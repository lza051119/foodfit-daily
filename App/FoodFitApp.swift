import SwiftUI

@main @MainActor
struct FoodFitApp: App {
    @State private var store = JournalStore()

    var body: some Scene {
        WindowGroup {
            MainTabs()
                .environment(store)
                .environment(\.calendar, LogDay.calendar)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .tint(FitTheme.accent)
        }
    }
}

@MainActor
private struct MainTabs: View {
    private enum Tab: Hashable { case journal, strength, settings }

    @Environment(\.scenePhase) private var phase
    @Environment(JournalStore.self) private var store
    @AppStorage("useAppleHealth") private var readHealth = false
    @State private var selected: Tab = .journal
    @State private var today = LogDay.today
    @State private var logDay = LogDay.today
    @State private var strengthDay = LogDay.today
    @State private var health = HealthBridge()

    var body: some View {
        TabView(selection: $selected) {
            JournalHome(day: $logDay, today: today, readHealth: readHealth, health: health,
                        openSettings: { selected = .settings }, openStrength: showStrength)
                .tabItem { Label("饮食消耗", systemImage: "list.bullet.rectangle") }
                .tag(Tab.journal)

            StrengthCalendar(day: $strengthDay, today: today)
                .tabItem { Label("训练记录", systemImage: "dumbbell") }
                .tag(Tab.strength)

            SettingsScreen(readHealth: $readHealth, health: health)
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .onChange(of: phase) { _, state in
            guard state == .active else { return }
            let current = LogDay.today
            if logDay == today || logDay > current { logDay = current }
            if strengthDay == today { strengthDay = current }
            today = current
            if store.hasLoadError { store.reload() }
        }
    }

    private func showStrength() {
        strengthDay = logDay
        selected = .strength
    }
}
