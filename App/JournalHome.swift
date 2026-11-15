import SwiftUI
import UIKit

@MainActor
struct JournalHome: View {
    private enum Editor: Identifiable {
        case meal(Meal?), energy, dailySummary, weight

        var id: String {
            switch self {
            case .meal(let meal): meal?.id.uuidString ?? "new-meal"
            case .energy: "energy"
            case .dailySummary: "daily-summary"
            case .weight: "weight"
            }
        }
    }

    private struct HealthRefresh: Hashable {
        let day: LogDay
        let enabled: Bool
        let active: Bool
    }

    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @Binding var day: LogDay
    let today: LogDay
    let readHealth: Bool
    let health: HealthBridge
    let openSettings: () -> Void
    let openStrength: () -> Void
    @State private var editor: Editor?
    @State private var snapshot: HealthDay?
    @State private var healthIsLoading = false
    @State private var refreshID = UUID()

    private var healthDay: HealthDay? {
        guard readHealth, snapshot?.day == day else { return nil }
        return snapshot
    }

    private var balance: DayBalance { store.journal.balance(on: day, health: healthDay?.energy) }
    private var entry: EnergyEntry? { store.journal.energyEntry(on: day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                DateStrip(day: $day, lastDay: today, title: day.heading)

                if store.hasLoadError { JournalLoadProblem() }

                VStack(spacing: 10) {
                    EnergyOverview(balance: balance, isToday: day == today)
                    energySourceRow
                }

                weightRow
                Button { editor = .dailySummary } label: {
                    Label("每日总结", systemImage: "photo")
                }
                .buttonStyle(FitActionStyle(prominent: true))
                .disabled(store.hasLoadError)

                mealList
                strengthLink
                if readHealth { workoutList }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .background(FitTheme.canvas.ignoresSafeArea())
        .foregroundStyle(FitTheme.ink)
        .refreshable { await reloadHealth() }
        .task(id: HealthRefresh(day: day, enabled: readHealth, active: phase == .active)) {
            if phase == .active { await reloadHealth() }
        }
        .sheet(item: $editor) { destination in
            switch destination {
            case .meal(let meal):
                MealEditor(day: day, original: meal, originalPhoto: store.photo(meal?.photoID))
            case .energy:
                EnergyEditor(day: day, original: entry, originalPhoto: store.photo(entry?.photoID))
            case .dailySummary:
                DailySummarySheet(day: day, balance: balance, meals: store.journal.meals(on: day),
                                  sessions: store.journal.sessions(on: day), workouts: healthDay?.workouts ?? [])
            case .weight:
                WeightEditor(day: day, journal: store.journal)
            }
        }
    }

    private var weightRow: some View {
        let weight = store.journal.weight(on: day)
        return Button { editor = .weight } label: {
            HStack(spacing: 11) {
                mealIcon("scalemass")
                VStack(alignment: .leading, spacing: 4) {
                    Text("当天体重").font(.headline)
                    if let weight {
                        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2))
                        Text("\((weight * 2).formatted(style)) 斤 · \(weight.formatted(style)) kg")
                            .font(.subheadline).foregroundStyle(FitTheme.muted)
                    } else {
                        Text("点此记录体重和身高").font(.subheadline).foregroundStyle(FitTheme.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(FitTheme.accent)
            }
            .fitPanel(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.hasLoadError)
        .accessibilityElement(children: .combine)
    }

    private var heading: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("食动日记", systemImage: "fork.knife")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FitTheme.accent)
                Text("饮食与消耗")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button { editor = .meal(nil) } label: {
                Label("记一餐", systemImage: "plus")
            }
            .buttonStyle(FitActionStyle(prominent: true))
            .disabled(store.hasLoadError)
        }
    }

    private var energySourceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                energySourceText
                Spacer(minLength: 10)
                energyButton
            }
            VStack(alignment: .leading, spacing: 8) {
                energySourceText
                energyButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 2)
    }

    private var energySourceText: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let reading = balance.energy {
                Label(reading.source.title, systemImage: reading.source == .health ? "heart.text.clipboard" : "doc.text")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FitTheme.accent)
                if reading.active != nil || reading.resting != nil {
                    Text([reading.active.map { "活动 \($0.formatted())" },
                          reading.resting.map { "静息 \($0.formatted())" }].compactMap { $0 }.joined(separator: " · ") + " 大卡")
                        .font(.caption)
                        .foregroundStyle(FitTheme.muted)
                }
            } else if healthIsLoading && readHealth {
                ProgressView("读取 Apple 健康…").font(.footnote)
            } else if readHealth {
                Button(action: openSettings) {
                    Label(healthDay?.readFailed == true ? "健康数据读取失败" : "暂无可读的健康能量",
                          systemImage: "heart.text.clipboard")
                        .font(.footnote)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FitTheme.accent)
                .accessibilityHint("前往设置检查健康权限")
            } else {
                Button(action: openSettings) {
                    Label("连接 Apple 健康", systemImage: "heart.text.clipboard")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FitTheme.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var energyButton: some View {
        Button { editor = .energy } label: {
            Label(entry == nil ? "补录消耗" : "编辑补录", systemImage: "square.and.pencil")
        }
        .buttonStyle(FitActionStyle())
        .disabled(store.hasLoadError)
    }

    private var mealList: some View {
        let meals = store.journal.meals(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("饮食").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if !meals.isEmpty {
                    Text("\(meals.count) 条记录").font(.footnote).foregroundStyle(FitTheme.muted)
                }
            }

            if meals.isEmpty {
                HStack(spacing: 12) {
                    mealIcon("fork.knife")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("这天还没记饮食").font(.subheadline.weight(.semibold))
                        Text("可以直接填大卡，也可以选照片估算。")
                            .font(.footnote).foregroundStyle(FitTheme.muted)
                    }
                }
                .fitPanel()
            } else {
                VStack(spacing: 0) {
                    ForEach(meals) { meal in
                        Button { editor = .meal(meal) } label: { mealRow(meal) }
                            .buttonStyle(.plain)
                        if meal.id != meals.last?.id { Divider().overlay(FitTheme.line) }
                    }
                }
                .fitPanel(padding: 12)
            }
        }
    }

    private func mealRow(_ meal: Meal) -> some View {
        HStack(spacing: 11) {
            if let data = store.photo(meal.photoID), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
            } else {
                mealIcon(meal.kind.icon)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(meal.kind.title + (meal.estimate == nil ? " · 手动" : " · AI 估算"))
                    .font(.caption)
                    .foregroundStyle(FitTheme.muted)
            }
            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(meal.kcal.formatted()).font(FitTheme.number(21, relativeTo: .headline))
                Text("大卡").font(.caption2).foregroundStyle(FitTheme.muted)
            }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(FitTheme.muted)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func mealIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(FitTheme.accent)
            .frame(width: 46, height: 46)
            .background(FitTheme.soft, in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }

    private var strengthLink: some View {
        let sessions = store.journal.sessions(on: day)
        return Button(action: openStrength) {
            HStack(spacing: 12) {
                mealIcon("dumbbell")
                VStack(alignment: .leading, spacing: 5) {
                    Text("训练记录").font(.headline)
                    if sessions.isEmpty {
                        Text("这天还没安排训练")
                            .font(.footnote).foregroundStyle(FitTheme.muted)
                    } else {
                        Text(sessions.map(\.title).joined(separator: "、"))
                            .font(.footnote).foregroundStyle(FitTheme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(FitTheme.accent)
            }
            .fitPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var workoutList: some View {
        let workouts = healthDay?.workouts ?? []
        return VStack(alignment: .leading, spacing: 12) {
            Text("Apple 体能训练").font(.headline).accessibilityAddTraits(.isHeader)
            if workouts.isEmpty {
                Text(healthIsLoading ? "读取中…" : "这天暂无可读取的体能训练")
                    .font(.footnote).foregroundStyle(FitTheme.muted)
            } else {
                ForEach(workouts) { workout in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(workout.title).font(.subheadline.weight(.semibold))
                            Text("\(workout.start.formatted(date: .omitted, time: .shortened)) · \(workout.minutes) 分钟")
                                .font(.caption).foregroundStyle(FitTheme.muted)
                        }
                        Spacer()
                        if let kcal = workout.activeKcal {
                            Text("活动 \(kcal.formatted()) 大卡").font(.footnote).foregroundStyle(FitTheme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .fitPanel()
    }

    private func reloadHealth() async {
        let id = UUID()
        refreshID = id
        guard readHealth, health.isAvailable else {
            snapshot = nil
            healthIsLoading = false
            return
        }

        let requested = day
        healthIsLoading = true
        let result = await health.read(requested)
        guard refreshID == id else { return }
        healthIsLoading = false
        if !Task.isCancelled, requested == day { snapshot = result }
    }
}

private struct EnergyOverview: View {
    let balance: DayBalance
    let isToday: Bool

    private var title: String {
        guard let deficit = balance.deficit else { return "估算热量缺口" }
        if deficit < 0 { return "估算热量盈余" }
        return "估算热量缺口"
    }

    private var hint: String {
        switch (balance.intake, balance.energy?.total) {
        case (nil, nil): "记下饮食和总消耗后，就能查看估算。"
        case (nil, _): "记下饮食后，就能查看估算。"
        case (_, nil): "需要全天总消耗才能计算缺口。"
        default:
            isToday && balance.energy?.source == .health
                ? "按已记饮食和截至当前的消耗估算。"
                : "按已记饮食和日记中的总消耗估算。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: "flame")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FitTheme.citrus)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(balance.deficit.map { abs($0).formatted() } ?? "—")
                    .font(FitTheme.number(49, relativeTo: .largeTitle))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .accessibilityLabel(balance.deficit.map { abs($0).formatted() } ?? "待计算")
                if balance.deficit != nil {
                    Text("大卡").font(.subheadline).foregroundStyle(FitTheme.heroMuted)
                }
            }
            .accessibilityElement(children: .combine)

            Text(hint).font(.footnote).foregroundStyle(FitTheme.heroMuted)
            Rectangle().fill(.white.opacity(0.19)).frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    metric("已记摄入", balance.intake)
                    Spacer(minLength: 0)
                    metric("总消耗", balance.energy?.total)
                }
                VStack(alignment: .leading, spacing: 12) {
                    metric("已记摄入", balance.intake)
                    metric("总消耗", balance.energy?.total)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                FitTheme.hero
                ForEach(0..<3) { ring in
                    Circle().strokeBorder(FitTheme.heroMuted.opacity(0.12), lineWidth: 1)
                        .frame(width: CGFloat(114 + ring * 29), height: CGFloat(114 + ring * 29))
                        .offset(x: CGFloat(36 + ring * 15), y: CGFloat(-35 - ring * 15))
                }
            }
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func metric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(FitTheme.heroMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value?.formatted() ?? "—").font(FitTheme.number(24, relativeTo: .title3))
                    .accessibilityLabel(value?.formatted() ?? "暂无记录")
                if value != nil { Text("大卡").font(.caption).foregroundStyle(FitTheme.heroMuted) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
