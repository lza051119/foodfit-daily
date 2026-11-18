import Foundation

/// A date in the user's local journal. Traveling across time zones doesn't move saved entries.
struct LogDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static var today: LogDay { LogDay(.now) }

    init(_ date: Date, calendar: Calendar = LogDay.calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    func start(in calendar: Calendar = LogDay.calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func adding(_ days: Int, calendar: Calendar = LogDay.calendar) -> LogDay {
        let start = start(in: calendar)
        return LogDay(calendar.date(byAdding: .day, value: days, to: start) ?? start, calendar: calendar)
    }

    var week: [LogDay] {
        let calendar = Self.calendar
        let start = self.start(in: calendar)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let monday = LogDay(weekStart, calendar: calendar)
        return (0..<7).map { monday.adding($0, calendar: calendar) }
    }

    static func < (lhs: LogDay, rhs: LogDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var isoDate: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

enum MealKind: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "cup.and.saucer"
        }
    }

    static func suggested(at date: Date = .now) -> Self {
        switch LogDay.calendar.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

struct CalorieEstimate: Codable, Equatable, Sendable {
    let name: String
    let kcal: Int
    let low: Int
    let high: Int
    let assumptions: String
}

struct Meal: Codable, Equatable, Identifiable {
    var id = UUID()
    var day: LogDay
    var kind: MealKind
    var name: String
    var notes: String
    var kcal: Int
    var photoID: UUID?
    var referencePhotoIDs: [UUID]? = nil
    var estimate: CalorieEstimate?
    var createdAt = Date()

    var photoIDs: [UUID] {
        (photoID.map { [$0] } ?? []) + (referencePhotoIDs ?? [])
    }
}

enum EnergySource: String, Codable, Sendable {
    case health, screenshot, manual

    var title: String {
        switch self {
        case .health: "Apple 健康"
        case .screenshot: "健身截图"
        case .manual: "手动补录"
        }
    }
}

struct EnergyReading: Equatable, Sendable {
    let source: EnergySource
    let active: Int?
    let resting: Int?
    let total: Int?

    static func health(active: Int?, resting: Int?) -> EnergyReading? {
        guard active != nil || resting != nil else { return nil }
        let total = active.flatMap { moving in resting.map { moving + $0 } }
        return EnergyReading(source: .health, active: active, resting: resting, total: total)
    }
}

struct EnergyEntry: Codable, Equatable, Identifiable {
    var id: LogDay { day }
    let day: LogDay
    let active: Int?
    let total: Int?
    var photoID: UUID?

    var reading: EnergyReading {
        let resting = total.flatMap { allDay in active.map { allDay - $0 } }
        return EnergyReading(source: photoID == nil ? .manual : .screenshot,
                             active: active, resting: resting, total: total)
    }
}

struct DayBalance: Equatable {
    let intake: Int?
    let energy: EnergyReading?

    var deficit: Int? {
        guard let intake, let total = energy?.total else { return nil }
        return total - intake
    }
}

struct LiftSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var kg: Double?
    var groups: Int? = nil

    var groupCount: Int { groups ?? 1 }
}

struct Lift: Codable, Equatable, Identifiable {
    static let commonEquipment = [
        "坐姿推胸机", "高位下拉机", "坐姿划船机", "器械推肩", "腿举机", "腿屈伸机",
        "腿弯举机", "史密斯机", "绳索器", "杠铃", "蝴蝶机反向飞鸟", "哑铃推肩",
        "哑铃侧平举", "窄距下拉", "龙门架直臂下拉"
    ]

    static func catalogName(for name: String) -> String {
        name == "肩推机" ? "器械推肩" : name
    }

    var id = UUID()
    var name: String
    var plannedSets: Int?
    var plannedReps: String
    var cues: String
    var sets: [LiftSet]
}

struct StrengthSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var day: LogDay
    var title: String
    var plannedMinutes: Int?
    var notes: String
    var isComplete: Bool
    var lifts: [Lift]

    var setCount: Int { lifts.flatMap(\.sets).reduce(0) { $0 + $1.groupCount } }

    func copyPlan(to day: LogDay) -> StrengthSession {
        let plan = lifts.map {
            Lift(name: $0.name, plannedSets: $0.plannedSets, plannedReps: $0.plannedReps,
                 cues: $0.cues, sets: [])
        }
        return StrengthSession(day: day, title: title, plannedMinutes: plannedMinutes,
                               notes: notes, isComplete: false, lifts: plan)
    }
}

struct Journal: Codable, Equatable {
    static let maxDailyEnergy = 20_000

    var meals: [Meal] = []
    var energyEntries: [EnergyEntry] = []
    var sessions: [StrengthSession] = []
    var heightCM: Double?
    var weights: [WeightRecord]?
    var recaps: [DailyRecap]?

    func weight(on day: LogDay) -> Double? { weights?.first { $0.day == day }?.kg }

    func recap(on day: LogDay) -> DailyRecap? { recaps?.first { $0.day == day } }

    mutating func saveMeasurements(heightCM: Double?, kg: Double?, on day: LogDay) throws {
        if let heightCM, !((10...300).contains(heightCM)) { throw JournalIssue.invalidHeight }
        if let kg, !((1...700).contains(kg)) { throw JournalIssue.invalidWeight }
        self.heightCM = heightCM
        var entries = weights ?? []
        entries.removeAll { $0.day == day }
        if let kg { entries.append(WeightRecord(day: day, kg: kg)) }
        weights = entries.isEmpty ? nil : entries
    }

    mutating func save(_ recap: DailyRecap) throws {
        guard DailyRecap.isValid(recap.text) else { throw JournalIssue.invalidRecap }
        var entries = (recaps ?? []).filter { $0.day != recap.day }
        entries.append(recap)
        recaps = entries
    }

    func meals(on day: LogDay) -> [Meal] {
        meals.filter { $0.day == day }.sorted { $0.createdAt < $1.createdAt }
    }

    func energyEntry(on day: LogDay) -> EnergyEntry? {
        energyEntries.first { $0.day == day }
    }

    func balance(on day: LogDay, health: EnergyReading?) -> DayBalance {
        let entries = meals(on: day)
        let intake = entries.isEmpty ? nil : entries.reduce(0) { $0 + $1.kcal }
        return DayBalance(intake: intake, energy: energyEntry(on: day)?.reading ?? health)
    }

    func sessions(on day: LogDay) -> [StrengthSession] {
        sessions.filter { $0.day == day }
    }

    var photosInUse: Set<UUID> {
        Set(meals.flatMap(\.photoIDs) + energyEntries.compactMap(\.photoID))
    }

    mutating func save(_ meal: Meal) throws {
        guard (0...Self.maxDailyEnergy).contains(meal.kcal) else { throw JournalIssue.invalidIntake }
        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }
    }

    mutating func save(_ energy: EnergyEntry) throws {
        let values = [energy.active, energy.total].compactMap { $0 }
        guard !values.isEmpty, values.allSatisfy({ (0...Self.maxDailyEnergy).contains($0) }) else {
            throw JournalIssue.invalidEnergy
        }
        if let active = energy.active, let total = energy.total, active > total {
            throw JournalIssue.activeExceedsTotal
        }
        if let index = energyEntries.firstIndex(where: { $0.day == energy.day }) {
            energyEntries[index] = energy
        } else {
            energyEntries.append(energy)
        }
    }

    mutating func save(_ session: StrengthSession) throws {
        guard !session.title.trimmed.isEmpty else { throw JournalIssue.missingSessionTitle }
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
}

enum JournalIssue: LocalizedError {
    case invalidIntake, invalidEnergy, activeExceedsTotal
    case missingSessionTitle, loadFailed, writeFailed
    case invalidHeight, invalidWeight, invalidRecap

    var errorDescription: String? {
        switch self {
        case .invalidIntake: "请输入 0 到 20,000 之间的整数大卡。"
        case .invalidEnergy: "至少填写一项消耗，数值为 0 到 20,000 之间的整数大卡。"
        case .activeExceedsTotal: "活动消耗应小于或等于全天总消耗。"
        case .missingSessionTitle: "请填写训练名称，例如「腿部训练」。"
        case .invalidHeight: "请输入有效身高，单位厘米。"
        case .invalidWeight: "请输入有效体重，并检查所选单位。"
        case .invalidRecap: "请输入总结正文，最多 1,000 字。"
        case .loadFailed: "日记暂时无法读取。请解锁设备后重试。"
        case .writeFailed: "保存失败。请检查设备可用空间后重试。"
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
