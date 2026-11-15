import Foundation

struct WeightRecord: Codable, Equatable, Identifiable {
    var id: LogDay { day }
    let day: LogDay
    let kg: Double

    static func label(for kg: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
        return "\((kg * 2).formatted(style)) 斤 · \(kg.formatted(style)) kg"
    }
}

struct DailyRecap: Codable, Equatable {
    let day: LogDay
    let text: String

    static func isValid(_ text: String) -> Bool {
        (1...1_000).contains(text.trimmed.count) && text.utf8.count <= 12_000
    }
}

/// The daily facts sent to DeepSeek after the user authorizes advice generation.
struct DailyRecapInput: Encodable, Equatable {
    static let recentDayCount = 7

    struct MealReading: Encodable, Equatable {
        let kind: String
        let name: String
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

    struct WorkoutReading: Encodable, Equatable {
        let name: String
        let minutes: Int
        let activeKcal: Int?
    }

    struct HealthReading {
        let energy: EnergyReading?
        let workouts: [WorkoutReading]
    }

    struct DayReading: Encodable, Equatable {
        let date: String
        let weightKg: Double?
        let meals: [MealReading]
        let intake: Int?
        let active: Int?
        let resting: Int?
        let total: Int?
        let deficit: Int?
        let energySource: EnergySource?
        let training: [TrainingReading]
        let workouts: [WorkoutReading]

        var hasData: Bool { weightKg != nil || intake != nil || energySource != nil || !training.isEmpty || !workouts.isEmpty }

        init(journal: Journal, day: LogDay, health: HealthReading?) {
            date = day.isoDate
            weightKg = journal.weight(on: day)
            meals = journal.meals(on: day).map {
                MealReading(kind: $0.kind.title, name: String($0.name.prefix(100)), kcal: $0.kcal, estimated: $0.estimate != nil)
            }
            let balance = journal.balance(on: day, health: health?.energy)
            intake = balance.intake
            active = balance.energy?.active
            resting = balance.energy?.resting
            total = balance.energy?.total
            deficit = balance.deficit
            energySource = balance.energy?.source
            workouts = health?.workouts ?? []
            training = journal.sessions(on: day).flatMap(\.lifts).compactMap { lift in
                guard !lift.sets.isEmpty else { return nil }
                return TrainingReading(exercise: String(lift.name.prefix(100)), sets: lift.sets.map {
                    SetReading(groups: $0.groupCount, reps: $0.reps, kg: $0.kg)
                })
            }
        }
    }

    let current: DayReading
    let history: [DayReading]
    let isToday: Bool
    let heightCM: Double?
    let goalWeightKg: Double = 72.5 // 145 斤

    var hasData: Bool { current.hasData || !history.isEmpty }

    init(journal: Journal, day: LogDay, health: [LogDay: HealthReading] = [:]) {
        current = DayReading(journal: journal, day: day, health: health[day])
        history = Self.previousDays(before: day).map { date in
            DayReading(journal: journal, day: date, health: health[date])
        }.filter(\.hasData)
        isToday = day == .today
        heightCM = journal.heightCM
    }

    static func previousDays(before day: LogDay) -> [LogDay] {
        (1...recentDayCount).reversed().map { day.adding(-$0) }
    }
}
