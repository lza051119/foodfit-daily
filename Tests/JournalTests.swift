import Foundation
import XCTest
@testable import FoodFitCore

final class JournalTests: XCTestCase {
    private let day = LogDay(Date(timeIntervalSince1970: 1_800_000_000))

    func testBalanceUsesTotalAndKeepsMissingIntakeUnknown() throws {
        var journal = Journal()
        let health = EnergyReading.health(active: 580, resting: 1_655)
        XCTAssertEqual(health?.total, 2_235)
        XCTAssertNil(journal.balance(on: day, health: health).intake)
        XCTAssertNil(journal.balance(on: day, health: health).deficit)

        try journal.save(Meal(day: day, kind: .breakfast, name: "水", notes: "", kcal: 0))
        try journal.save(Meal(day: day, kind: .lunch, name: "午餐", notes: "", kcal: 735))
        try journal.save(Meal(day: day.adding(1), kind: .dinner, name: "次日餐", notes: "", kcal: 620))
        let balance = journal.balance(on: day, health: health)
        XCTAssertEqual(balance.intake, 735)
        XCTAssertEqual(balance.deficit, 1_500)

        let activeOnly = EnergyReading.health(active: 580, resting: nil)
        XCTAssertEqual(activeOnly?.active, 580)
        XCTAssertNil(journal.balance(on: day, health: activeOnly).deficit)
    }

    func testDailyOverrideReplacesSourceAndRejectsInvalidTotals() throws {
        var journal = Journal()
        try journal.save(Meal(day: day, kind: .lunch, name: "午餐", notes: "", kcal: 735))
        let health = EnergyReading.health(active: 580, resting: 1_655)
        try journal.save(EnergyEntry(day: day, active: 610, total: nil))
        XCTAssertEqual(journal.balance(on: day, health: health).energy?.source, .manual)
        XCTAssertNil(journal.balance(on: day, health: health).deficit)

        let screenshot = EnergyEntry(day: day, active: 610, total: 2_215, photoID: UUID())
        try journal.save(screenshot)
        XCTAssertEqual(journal.energyEntries.count, 1)
        XCTAssertEqual(journal.balance(on: day, health: health).energy?.resting, 1_605)
        XCTAssertEqual(journal.balance(on: day, health: health).energy?.source, .screenshot)
        XCTAssertEqual(journal.balance(on: day, health: health).deficit, 1_480)

        XCTAssertThrowsError(try journal.save(EnergyEntry(day: day, active: 900, total: 880)))
        XCTAssertThrowsError(try journal.save(EnergyEntry(day: day, active: nil, total: nil)))
        XCTAssertEqual(journal.energyEntry(on: day), screenshot)
        journal.energyEntries.removeAll()
        XCTAssertEqual(journal.balance(on: day, health: health).deficit, 1_500)
    }

    func testStrengthSessionCompletionAndReuse() throws {
        var journal = Journal()
        let lift = Lift(name: "腿举", plannedSets: 3, plannedReps: "8–12", cues: "靠背第 2 档",
                        sets: [LiftSet(reps: 9, kg: 37.5, groups: 4), LiftSet(reps: 6, kg: 40)])
        var session = StrengthSession(day: day, title: "腿部训练", plannedMinutes: 42,
                                      notes: "", isComplete: false, lifts: [lift])
        try journal.save(session)
        session.isComplete = true
        try journal.save(session)
        XCTAssertEqual(journal.sessions.count, 1)
        XCTAssertTrue(journal.sessions(on: day).first?.isComplete == true)
        XCTAssertEqual(journal.sessions(on: day).first?.setCount, 5)

        let copy = session.copyPlan(to: day.adding(3))
        XCTAssertNotEqual(copy.id, session.id)
        XCTAssertNotEqual(copy.lifts.first?.id, lift.id)
        XCTAssertEqual(copy.lifts.first?.cues, lift.cues)
        XCTAssertEqual(copy.lifts.first?.plannedReps, lift.plannedReps)
        XCTAssertEqual(copy.setCount, 0)
        XCTAssertFalse(copy.isComplete)
        try journal.save(copy)
        XCTAssertEqual(journal.sessions(on: day.adding(3)), [copy])
        XCTAssertEqual(journal.sessions.count, 2)
    }

    func testStrengthSessionLoadsAnArchiveWithTheOldCourseField() throws {
        let lift = Lift(name: "高位下拉机", plannedSets: nil, plannedReps: "", cues: "",
                        sets: [LiftSet(reps: 10, kg: 32.5)])
        let session = StrengthSession(day: day, title: "背部训练", plannedMinutes: 60, notes: "",
                                      isComplete: true, lifts: [lift])
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        archive["coachLesson"] = 1
        let legacy = try JSONSerialization.data(withJSONObject: archive)
        XCTAssertEqual(try JSONDecoder().decode(StrengthSession.self, from: legacy), session)
    }

    func testArchiveRoundTripAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JournalDisk(directory: directory)
        XCTAssertEqual(try disk.load(), Journal())

        let image = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let photo = try disk.savePhoto(image)
        let orphan = try disk.savePhoto(Data([1]))
        var journal = Journal()
        try journal.save(Meal(day: day, kind: .dinner, name: "晚餐", notes: "半碗饭", kcal: 540, photoID: photo))
        try journal.save(EnergyEntry(day: day, active: 432, total: 1_992))
        try journal.save(StrengthSession(day: day, title: "胸部训练", plannedMinutes: 45,
                                         notes: "练习器械设置", isComplete: true, lifts: []))
        try disk.save(journal)
        let restored = try disk.load()
        XCTAssertEqual(restored, journal)
        XCTAssertEqual(restored.meals.first?.photoIDs, [photo])
        disk.removeUnreferencedPhotos(keeping: restored.photosInUse)
        XCTAssertEqual(disk.photo(photo), image)
        XCTAssertNil(disk.photo(orphan))

        try Data("truncated".utf8).write(to: directory.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(disk.photo(photo), image)
    }

    func testMealPhotoOrderingAndCleanup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JournalDisk(directory: directory)
        let meal = Meal(day: day, kind: .dinner, name: "鸡腿饭", notes: "", kcal: 620)
        let original = MealPhotoDraft(data: Data([1]))
        let reference = MealPhotoDraft(data: Data([2]))
        let saved = try disk.saveMeal(meal, photos: [original, reference], in: Journal())
        let stored = try XCTUnwrap(try disk.load().meals.first)
        let primaryID = try XCTUnwrap(stored.photoID)
        let referenceID = try XCTUnwrap(stored.referencePhotoIDs?.first)
        XCTAssertEqual(stored.photoIDs, [primaryID, referenceID])
        disk.removeUnreferencedPhotos(keeping: saved.photosInUse)
        XCTAssertEqual(disk.photo(primaryID), original.data)
        XCTAssertEqual(disk.photo(referenceID), reference.data)

        let first = MealPhotoDraft(id: primaryID, data: original.data)
        let second = MealPhotoDraft(id: referenceID, data: reference.data)
        let reordered = try disk.saveMeal(stored, photos: [second, first], in: saved)
        XCTAssertEqual(reordered.meals.first?.photoIDs, [referenceID, primaryID])
        let edited = try disk.saveMeal(stored, photos: [second], in: reordered)
        XCTAssertNil(edited.meals.first?.referencePhotoIDs)
        XCTAssertNil(disk.photo(primaryID))
        XCTAssertEqual(disk.photo(referenceID), reference.data)
        XCTAssertEqual(try disk.load(), edited)

        try disk.save(Journal(), replacing: edited)
        XCTAssertNil(disk.photo(referenceID))
    }

    func testFailedMealSaveKeepsExistingPhotosAndCleansNewFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = JournalDisk(directory: directory)
        var meal = Meal(day: day, kind: .dinner, name: "鸡腿饭", notes: "", kcal: 620)
        let original = MealPhotoDraft(data: Data([1]))
        let saved = try disk.saveMeal(meal, photos: [original], in: Journal())
        let originalID = try XCTUnwrap(saved.meals.first?.photoID)
        meal.kcal = -1
        XCTAssertThrowsError(try disk.saveMeal(meal, photos: [MealPhotoDraft(data: Data([2]))], in: saved))
        XCTAssertEqual(try disk.load(), saved)
        XCTAssertEqual(disk.photo(originalID), original.data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:
            directory.appendingPathComponent("photos").path), ["\(originalID.uuidString).jpg"])
    }

    func testExerciseCatalogContainsSpecificMoves() {
        let moves = ["蝴蝶机反向飞鸟", "哑铃推肩", "哑铃侧平举", "器械推肩", "窄距下拉", "龙门架直臂下拉"]
        XCTAssertTrue(Set(moves).isSubset(of: Set(Lift.commonEquipment)))
        XCTAssertFalse(Lift.commonEquipment.contains("哑铃"))
        XCTAssertFalse(Lift.commonEquipment.contains("肩推机"))
        XCTAssertEqual(Lift.catalogName(for: "肩推机"), "器械推肩")
    }

    func testDiaryAdvancesByLocalCalendarDayAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let today = LogDay(start, calendar: calendar)
        let tomorrow = today.adding(1, calendar: calendar)
        XCTAssertEqual(tomorrow.day, 9)
        XCTAssertEqual(tomorrow.start(in: calendar).timeIntervalSince(start), 23 * 60 * 60)
    }
}
