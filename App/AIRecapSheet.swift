import SwiftUI

@MainActor
struct AIRecapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    @AppStorage("deepseek.allowRecap") private var allowRecap = false
    let day: LogDay

    @State private var text: String
    @State private var working: String?
    @State private var message: String?
    @State private var problem: String?
    @State private var askToSend = false

    init(day: LogDay, saved: DailyRecap?) {
        self.day = day
        _text = State(initialValue: saved?.text ?? "")
    }

    private var input: DailyRecapInput { DailyRecapInput(journal: store.journal, day: day) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(day.isoDate).foregroundStyle(FitTheme.muted)
                    Button {
                        if allowRecap { generate() } else { askToSend = true }
                    } label: {
                        Label(text.trimmed.isEmpty ? "生成 AI 总结" : "重新生成", systemImage: "sparkles")
                    }
                    .disabled(!input.hasData || working != nil)
                    if !input.hasData {
                        Text(DeepSeekIssue.noRecapInput.localizedDescription).font(.footnote)
                    }
                    if let working { ProgressView(working) }
                    if let problem { InlineProblem(message: problem) }
                    if let message { Text(message).foregroundStyle(FitTheme.accent).font(.footnote) }
                } footer: {
                    Text("生成时发送当天记录的餐次与大卡、补录消耗和实际力量组次给 DeepSeek。")
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 158)
                        .accessibilityLabel("总结正文")
                        .disabled(working != nil)
                    Button("保存到长图") { saveDraft() }
                        .disabled(!DailyRecap.isValid(text) || working != nil)
                } header: {
                    Text("总结正文")
                } footer: {
                    Text("保存的文字会加在当天长图的末尾。")
                }
            }
            .fitForm()
            .navigationTitle("AI 日总结")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() }.disabled(working != nil) }
            }
            .confirmationDialog("发送日记摘要给 DeepSeek？", isPresented: $askToSend, titleVisibility: .visible) {
                Button("同意并生成") { allowRecap = true; generate() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("发送餐次与大卡、补录的消耗和力量组次。照片、身高、体重和 Apple 健康读取的数据保存在本机。")
            }
        }
        .interactiveDismissDisabled(working != nil)
    }

    private func generate() {
        guard working == nil else { return }
        let snapshot = input
        working = "正在生成…"
        problem = nil
        message = nil
        Task {
            defer { working = nil }
            do {
                text = try await DeepSeekService.recap(snapshot)
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
