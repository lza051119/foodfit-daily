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

    func testDeepSeekRecapExportsOnlySelectedManualEntries() throws {
        let day = LogDay.today
        var journal = Journal()
        XCTAssertFalse(DailyRecapInput(journal: journal, day: day).hasData)
        try journal.saveMeasurements(heightCM: 168, kg: 70.5, on: day)
        try journal.save(Meal(day: day, kind: .lunch, name: "private meal label", notes: "private note",
                              kcal: 670, photoID: UUID()))
        try journal.save(EnergyEntry(day: day, active: 510, total: 2_030, photoID: UUID()))
        let exercise = Lift(name: "腿举机", plannedSets: nil, plannedReps: "", cues: "private cues",
                            sets: [LiftSet(reps: 12, kg: 40, groups: 3)])
        try journal.save(StrengthSession(day: day, title: "腿部", plannedMinutes: nil, notes: "private training note",
                                         isComplete: true, lifts: [exercise]))
        try journal.save(Meal(day: day.adding(1), kind: .snack, name: "another day", notes: "",
                              kcal: 550, photoID: nil))
        let input = DailyRecapInput(journal: journal, day: day)
        XCTAssertEqual(input.intake, 670)
        XCTAssertEqual(input.deficit, 1_360)
        XCTAssertEqual(input.training.first?.sets.first?.groups, 3)
        let request = try DeepSeekRequest.makeRecap(key: "fixture-token", input: input)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let exported = try XCTUnwrap(messages.last?["content"] as? String)
        for excluded in ["private meal", "private note", "photoID", "height", "70.5", "168", "private cues", "fixture-token", "550"] {
            XCTAssertFalse(exported.contains(excluded), excluded)
        }
    }
}
