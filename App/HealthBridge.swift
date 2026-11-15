import Foundation
import HealthKit

struct AppleWorkout: Identifiable, Sendable {
    let id: UUID
    let title: String
    let start: Date
    let minutes: Int
    let activeKcal: Int?
}

struct HealthDay: Sendable {
    let day: LogDay
    let energy: EnergyReading?
    let workouts: [AppleWorkout]
    let readFailed: Bool
}

@MainActor
final class HealthBridge {
    private lazy var store = HKHealthStore()
    private let active = HKQuantityType(.activeEnergyBurned)
    private let resting = HKQuantityType(.basalEnergyBurned)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        let types: Set<HKObjectType> = [active, resting, HKObjectType.workoutType()]
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func read(_ day: LogDay) async -> HealthDay {
        let start = day.start()
        let end = min(Date(), day.adding(1).start())
        guard isAvailable, end > start else {
            return HealthDay(day: day, energy: nil, workouts: [], readFailed: false)
        }

        async let moving = energy(active, start: start, end: end)
        async let basal = energy(resting, start: start, end: end)
        async let exercises = workouts(start: start, end: end)
        let (activeResult, restingResult, workoutResult) = await (moving, basal, exercises)
        let reading = EnergyReading.health(active: activeResult.value, resting: restingResult.value)
        return HealthDay(day: day, energy: reading, workouts: workoutResult.value,
                         readFailed: activeResult.failed || restingResult.failed || workoutResult.failed)
    }

    private func energy(_ type: HKQuantityType, start: Date, end: Date) async -> (value: Int?, failed: Bool) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let buckets = try await query.result(for: store)
            return (wholeKcal(buckets.statistics(for: start)?.sumQuantity()), false)
        } catch {
            return (nil, (error as? HKError)?.code != .errorNoData)
        }
    }

    private func workouts(start: Date, end: Date) async -> (value: [AppleWorkout], failed: Bool) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .reverse)])
        do {
            let results = try await query.result(for: store)
            let items = results.filter { $0.startDate >= start && $0.startDate < end }.map { workout in
                AppleWorkout(id: workout.uuid, title: workoutName(workout.workoutActivityType),
                             start: workout.startDate, minutes: Int((workout.duration / 60).rounded()),
                             activeKcal: wholeKcal(workout.statistics(for: active)?.sumQuantity()))
            }
            return (items, false)
        } catch {
            return ([], (error as? HKError)?.code != .errorNoData)
        }
    }

    private func wholeKcal(_ quantity: HKQuantity?) -> Int? {
        guard let value = quantity?.doubleValue(for: .kilocalorie()), value.isFinite,
              (0...Double(Journal.maxDailyEnergy)).contains(value) else { return nil }
        return Int(value.rounded())
    }

    private func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "传统力量训练"
        case .functionalStrengthTraining: "功能性力量训练"
        case .running: "跑步"
        case .walking: "步行"
        case .hiking: "徒步"
        case .cycling: "骑行"
        case .elliptical: "椭圆机"
        case .stairClimbing, .stairs: "爬楼"
        case .rowing: "划船"
        case .coreTraining: "核心训练"
        case .highIntensityIntervalTraining: "高强度间歇训练"
        case .yoga: "瑜伽"
        case .swimming: "游泳"
        default: "体能训练"
        }
    }
}
