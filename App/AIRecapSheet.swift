import SwiftUI

@MainActor
struct AIRecapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    @AppStorage(DailyRecapPreferences.consentKey) private var allowRecap = false
    @AppStorage(DailyRecapPreferences.promptKey) private var recapPrompt = DeepSeekRequest.recapPrompt
    let day: LogDay
    let health: HealthBridge?

    @State private var text: String
    @State private var working: String?
    @State private var message: String?
    @State private var problem: String?
    @State private var askToSend = false

    init(day: LogDay, health: HealthBridge?, saved: DailyRecap?) {
        self.day = day
        self.health = health
        _text = State(initialValue: saved?.text ?? "")
    }

    private var canGenerate: Bool {
        health != nil || DailyRecapInput(journal: store.journal, day: day).hasData
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(day.isoDate).foregroundStyle(FitTheme.muted)
                    Button {
                        if allowRecap { generate() } else { askToSend = true }
                    } label: {
                        Label(text.trimmed.isEmpty ? "生成减脂建议" : "重新生成建议", systemImage: "sparkles")
                    }
                    .disabled(!canGenerate || working != nil)
                    if !canGenerate {
                        Text(DeepSeekIssue.noRecapInput.localizedDescription).font(.footnote)
                    }
                    if let working { ProgressView(working) }
                    if let problem { InlineProblem(message: problem) }
                    if let message { Text(message).foregroundStyle(FitTheme.accent).font(.footnote) }
                } footer: {
                    Text("根据所选日和此前 \(DailyRecapInput.recentDayCount) 天的记录生成建议，目标体重 145 斤。")
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 158)
                        .accessibilityLabel("建议正文")
                        .disabled(working != nil)
                    Button("保存到长图") { saveDraft() }
                        .disabled(!DailyRecap.isValid(text) || working != nil)
                } header: {
                    Text("建议正文")
                } footer: {
                    Text("保存的文字会加在当天长图的末尾。")
                }
            }
            .fitForm()
            .navigationTitle("AI 减脂建议")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() }.disabled(working != nil) }
            }
            .confirmationDialog("发送日记摘要给 DeepSeek？", isPresented: $askToSend, titleVisibility: .visible) {
                Button("同意并生成") { allowRecap = true; generate() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("发送所选日及此前 \(DailyRecapInput.recentDayCount) 天的餐食名称和大卡、消耗、训练摘要、体重，以及已保存的身高。消耗和训练可包含 Apple 健康同步的汇总。")
            }
        }
        .interactiveDismissDisabled(working != nil)
    }

    private func generate() {
        guard working == nil else { return }
        let journal = store.journal
        let prompt = recapPrompt
        working = "正在生成…"
        problem = nil
        message = nil
        Task {
            defer { working = nil }
            do {
                var healthReadings: [LogDay: DailyRecapInput.HealthReading] = [:]
                if let health {
                    for date in [day] + DailyRecapInput.previousDays(before: day) {
                        try Task.checkCancellation()
                        let reading = await health.read(date)
                        healthReadings[date] = DailyRecapInput.HealthReading(
                            energy: reading.energy,
                            workouts: reading.workouts.map {
                                DailyRecapInput.WorkoutReading(name: $0.title, minutes: $0.minutes, activeKcal: $0.activeKcal)
                            }
                        )
                    }
                }
                let input = DailyRecapInput(journal: journal, day: day, health: healthReadings)
                text = try await DeepSeekService.recap(input, prompt: prompt)
                try store.saveRecap(DailyRecap(day: day, text: text))
                message = "已加到长图，正文可以编辑。"
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func saveDraft() {
        do {
            try store.saveRecap(DailyRecap(day: day, text: text.trimmed))
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }

}
