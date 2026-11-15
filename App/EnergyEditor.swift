import SwiftUI

@MainActor
struct EnergyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    let day: LogDay
    let original: EnergyEntry?
    let originalPhoto: Data?
    @State private var active: String
    @State private var total: String
    @State private var photo: Data?
    @State private var readingPhoto = false
    @State private var recognition: Task<Void, Never>?
    @State private var recognitionID: UUID?
    @State private var ocrMessage: String?
    @State private var issue: String?
    @State private var confirmDelete = false

    init(day: LogDay, original: EnergyEntry?, originalPhoto: Data?) {
        self.day = day
        self.original = original
        self.originalPhoto = originalPhoto
        _active = State(initialValue: original?.active.map { String($0) } ?? "")
        _total = State(initialValue: original?.total.map { String($0) } ?? "")
        _photo = State(initialValue: originalPhoto)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("日期", value: day.heading)
                    energyField("活动消耗", input: $active)
                    energyField("全天总消耗", input: $total)
                } header: {
                    Text("消耗大卡")
                } footer: {
                    Text("全天总消耗包含活动和静息能量。保存后，这一天使用补录的数据。")
                }

                Section {
                    PhotoField(photo: $photo, isLoading: $readingPhoto, title: "选择健身截图", maxPixels: 2700)
                    if recognition != nil {
                        ProgressView("识别活动和总消耗…")
                    } else if let photo {
                        Button("重新识别截图") { recognize(photo) }
                            .disabled(readingPhoto)
                    }
                    if let ocrMessage {
                        Text(ocrMessage).font(.footnote).foregroundStyle(FitTheme.muted)
                    }
                } header: {
                    Text("从 Apple 健身补录")
                } footer: {
                    Text("选择「健身 → 摘要 → 活动圆环」里的当天详情截图。识别在设备上进行，保存前请核对日期和数字。")
                }

                if original != nil {
                    Section {
                        Button("移除当天补录", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("移除后，当天会显示可读取的 Apple 健康数据。")
                    }
                }
            }
            .fitForm()
            .navigationTitle("补录消耗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(readingPhoto || recognition != nil)
                }
            }
            .confirmationDialog("移除这一天的消耗补录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("移除", role: .destructive, action: delete)
            }
            .journalEditAlert($issue)
            .onChange(of: photo) { _, value in
                stopRecognition()
                ocrMessage = nil
                if let value { recognize(value) }
            }
            .onDisappear { stopRecognition() }
        }
    }

    private func energyField(_ name: String, input: Binding<String>) -> some View {
        LabeledContent(name) {
            TextField("大卡（选填）", text: input)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("\(name)大卡")
        }
    }

    private func recognize(_ image: Data) {
        stopRecognition()
        issue = nil
        ocrMessage = nil
        let id = UUID()
        let previousActive = active
        let previousTotal = total
        recognitionID = id
        recognition = Task {
            defer {
                if recognitionID == id {
                    recognitionID = nil
                    recognition = nil
                }
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ImageTools.readFitnessScreenshot(image)
                }.value
                guard recognitionID == id, !Task.isCancelled else { return }
                if let value = result.active, active == previousActive { active = String(value) }
                if let value = result.total, total == previousTotal { total = String(value) }
                if result.isWorkoutDetail {
                    ocrMessage = "这张看起来是单项训练详情，请选当天的活动圆环截图。"
                } else if result.active != nil || result.total != nil {
                    ocrMessage = "已提取能识别的数值，请核对截图日期、活动大卡和全天总大卡。"
                } else {
                    ocrMessage = "图片里没找到可确认的消耗大卡。可以更换截图或手动填入。"
                }
            } catch {
                if recognitionID == id, !Task.isCancelled {
                    ocrMessage = "截图识别失败，请更换截图或手动填入。"
                }
            }
        }
    }

    private func stopRecognition() {
        recognitionID = nil
        recognition?.cancel()
        recognition = nil
    }

    private func save() {
        let activity = Int(active.trimmed)
        let overall = Int(total.trimmed)
        guard (active.trimmed.isEmpty || activity != nil), (total.trimmed.isEmpty || overall != nil) else {
            issue = JournalIssue.invalidEnergy.localizedDescription
            return
        }
        do {
            let entry = EnergyEntry(day: day, active: activity, total: overall, photoID: original?.photoID)
            try store.saveEnergy(entry, photo: PhotoEdit(original: originalPhoto, current: photo))
            dismiss()
        } catch {
            issue = error.localizedDescription
        }
    }

    private func delete() {
        guard let original else { return }
        do {
            try store.deleteEnergy(original)
            dismiss()
        } catch {
            issue = error.localizedDescription
        }
    }
}
