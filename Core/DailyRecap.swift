import Foundation

struct WeightRecord: Codable, Equatable, Identifiable {
    var id: LogDay { day }
    let day: LogDay
    let kg: Double
}

struct DailyRecap: Codable, Equatable {
    let day: LogDay
    let text: String

    static func isValid(_ text: String) -> Bool {
        (1...1_000).contains(text.trimmed.count) && text.utf8.count <= 12_000
    }
}

/// Explicit export fields for DeepSeek. HealthKit, body measurements and photos stay on-device.
struct DailyRecapInput: Encodable, Equatable {
    struct MealReading: Encodable, Equatable {
        let kind: String
        let kcal: Int
        let estimated: Bool
    }

    struct TrainingReading: Encodable, Equatable {
        let exercise: String
        let sets: [SetReading]
    }

    struct SetReading: Encodable, Equatable {
        let groups: Int
        let reps: Int
        let kg: Double?
    }

    let date: String
    let meals: [MealReading]
    let intake: Int?
    let active: Int?
    let total: Int?
    let deficit: Int?
    let training: [TrainingReading]

    var hasData: Bool { !meals.isEmpty || active != nil || total != nil || !training.isEmpty }

    init(journal: Journal, day: LogDay) {
        date = day.isoDate
        meals = journal.meals(on: day).map { MealReading(kind: $0.kind.title, kcal: $0.kcal, estimated: $0.estimate != nil) }
        let balance = journal.balance(on: day, health: nil)
        intake = balance.intake
        active = balance.energy?.active
        total = balance.energy?.total
        deficit = balance.deficit
        training = journal.sessions(on: day).flatMap(\.lifts).compactMap { lift in
            guard !lift.sets.isEmpty else { return nil }
            return TrainingReading(exercise: String(lift.name.prefix(100)), sets: lift.sets.map {
                SetReading(groups: $0.groupCount, reps: $0.reps, kg: $0.kg)
            })
        }
    }
}
