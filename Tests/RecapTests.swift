import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import FoodFitCore

final class RecapTests: XCTestCase {
    func testExistingJournalCanSaveAndReplaceDailyWeightsAndRecaps() throws {
        let encoded = Data(#"{"meals":[],"energyEntries":[],"sessions":[]}"#.utf8)
        var journal = try JSONDecoder().decode(Journal.self, from: encoded)
        let day = LogDay.today
        XCTAssertNil(journal.heightCM)
        XCTAssertNil(journal.weight(on: day))
        try journal.saveMeasurements(heightCM: 168, kg: 70.5, on: day)
        try journal.saveMeasurements(heightCM: 168, kg: 70, on: day)
        try journal.saveMeasurements(heightCM: 168, kg: 69, on: day.adding(1))
        XCTAssertThrowsError(try journal.saveMeasurements(heightCM: .nan, kg: 69, on: day))
        XCTAssertEqual(journal.weights?.count, 2)
        XCTAssertEqual(journal.weight(on: day), 70)
        try journal.save(DailyRecap(day: day, text: "已记一餐。"))
        try journal.save(DailyRecap(day: day, text: "已记两餐。"))
        let roundTrip = try JSONDecoder().decode(Journal.self, from: JSONEncoder().encode(journal))
        XCTAssertEqual(journal, roundTrip)
        XCTAssertEqual(roundTrip.recaps?.count, 1)
        XCTAssertEqual(roundTrip.recap(on: day)?.text, "已记两餐。")
    }

    func testDailyAdviceUsesRecordedMeasurementsAndSevenDaysOfHistory() throws {
        let day = LogDay.today
        var journal = Journal()
        XCTAssertFalse(DailyRecapInput(journal: journal, day: day).hasData)
        try journal.saveMeasurements(heightCM: nil, kg: 86, on: day)
        let weightOnly = DailyRecapInput(journal: journal, day: day)
        XCTAssertTrue(weightOnly.hasData)
        XCTAssertNil(weightOnly.heightCM)
        try journal.saveMeasurements(heightCM: 177, kg: 86, on: day)
        try journal.saveMeasurements(heightCM: 177, kg: 87, on: day.adding(-7))
        try journal.saveMeasurements(heightCM: 177, kg: 88, on: day.adding(-8))
        try journal.save(Meal(day: day, kind: .lunch, name: "鸡腿饭", notes: "private note",
                              kcal: 670, photoID: UUID()))
        try journal.save(EnergyEntry(day: day, active: 510, total: 2_030, photoID: UUID()))
        let exercise = Lift(name: "腿举机", plannedSets: nil, plannedReps: "", cues: "private cues",
                            sets: [LiftSet(reps: 12, kg: 40, groups: 3)])
        try journal.save(StrengthSession(day: day, title: "腿部", plannedMinutes: nil, notes: "private training note",
                                         isComplete: true, lifts: [exercise]))
        try journal.save(Meal(day: day.adding(1), kind: .snack, name: "another day", notes: "",
                              kcal: 550, photoID: nil))
        let dayBefore = day.adding(-1)
        let syncedWorkout = DailyRecapInput.WorkoutReading(name: "快走", minutes: 20, activeKcal: 95)
        let health: [LogDay: DailyRecapInput.HealthReading] = [
            day: .init(energy: .health(active: 900, resting: 1_600), workouts: [syncedWorkout]),
            dayBefore: .init(energy: .health(active: 450, resting: 1_550), workouts: [])
        ]
        let input = DailyRecapInput(journal: journal, day: day, health: health)
        XCTAssertTrue(input.isToday)
        XCTAssertEqual(input.current.weightKg, 86)
        XCTAssertEqual(input.heightCM, 177)
        XCTAssertEqual(input.goalWeightKg, 72.5)
        XCTAssertEqual(input.current.meals.first?.name, "鸡腿饭")
        XCTAssertEqual(input.current.intake, 670)
        XCTAssertEqual(input.current.deficit, 1_360)
        XCTAssertEqual(input.current.energySource, .screenshot)
        XCTAssertEqual(input.current.training.first?.sets.first?.groups, 3)
        XCTAssertEqual(input.current.workouts, [syncedWorkout])
        XCTAssertEqual(input.history.map(\.date), [day.adding(-7).isoDate, dayBefore.isoDate])
        XCTAssertEqual(input.history.first?.weightKg, 87)
        XCTAssertNil(input.history.last?.weightKg)
        XCTAssertEqual(input.history.last?.total, 2_000)
        XCTAssertEqual(input.history.last?.energySource, .health)

        let customPrompt = "优先围绕晚餐和步行给建议。"
        let request = try DeepSeekRequest.makeRecap(key: "fixture-token", input: input, prompt: customPrompt)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let instructions = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(instructions.hasPrefix(customPrompt))
        XCTAssertTrue(instructions.contains(#"{"recap":"建议正文"}"#))
        let exported = try XCTUnwrap(messages.last?["content"] as? String)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
        XCTAssertEqual(payload["goalWeightKg"] as? Double, 72.5)
        for excluded in ["private note", "photoID", "private cues", "private training note", "fixture-token", "another day"] {
            XCTAssertFalse(exported.contains(excluded), excluded)
        }
    }

    func testEmptyRecapPromptUsesDefaultAndOmittedMeasurementsStayUnknown() throws {
        let day = LogDay.today
        var journal = Journal()
        try journal.save(EnergyEntry(day: day, active: 250, total: nil, photoID: nil))
        let input = DailyRecapInput(journal: journal, day: day)
        let request = try DeepSeekRequest.makeRecap(key: "fixture-token", input: input, prompt: " \n ")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertTrue(try XCTUnwrap(messages.first?["content"] as? String).hasPrefix(DeepSeekRequest.recapPrompt))
        let exported = try XCTUnwrap(messages.last?["content"] as? String)
        let data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
        let current = try XCTUnwrap(data["current"] as? [String: Any])
        XCTAssertNil(data["heightCM"])
        XCTAssertNil(current["weightKg"])
        XCTAssertNil(current["deficit"])
    }
}
