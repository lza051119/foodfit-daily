import SwiftUI

@MainActor
struct MealEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    @AppStorage("deepseek.allowMeal") private var allowMeal = false
    let day: LogDay
    let original: Meal?
    @State private var kind: MealKind
    @State private var name: String
    @State private var notes: String
    @State private var kcal: String
    @State private var photos: [MealPhotoDraft]
    @State private var estimate: CalorieEstimate?
    @State private var appliedEstimate: CalorieEstimate?
    @State private var loadingPhoto = false
    @State private var estimateTask: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var estimateIssue: String?
    @State private var saveIssue: String?
    @State private var configureKey = false
    @State private var confirmDelete = false
    @State private var confirmSend = false

    init(day: LogDay, original: Meal?, originalPhotos: [MealPhotoDraft]) {
        self.day = day
        self.original = original
        _kind = State(initialValue: original?.kind ?? (day == .today ? .suggested() : .lunch))
        _name = State(initialValue: original?.name ?? "")
        _notes = State(initialValue: original?.notes ?? "")
        _kcal = State(initialValue: original.map { String($0.kcal) } ?? "")
        _photos = State(initialValue: originalPhotos)
        _estimate = State(initialValue: original?.estimate)
        _appliedEstimate = State(initialValue: original?.estimate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("这餐吃了什么") {
                    LabeledContent("日期", value: day.heading)
                    Picker("餐次", selection: $kind) {
                        ForEach(MealKind.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    TextField("名称，例如鸡腿饭", text: $name)
                    LabeledContent("摄入大卡") {
                        TextField("填写大卡", text: $kcal)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("摄入大卡")
                    }
                }

                Section {
                    MealPhotoField(photos: $photos, isLoading: $loadingPhoto)
                } header: {
                    Text("餐食照片")
                } footer: {
                    Text("用实拍作主图，外卖截图或营养表可作为辅助图。")
                }

                Section {
                    TextField("补充份量和做法，例如半碗饭、鸡皮没吃", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                    if estimateTask != nil {
                        ProgressView("估算中…")
                        Button("取消估算") { cancelEstimate() }
                    } else {
                        Button(action: estimateTapped) {
                            Label("用 DeepSeek 估算", systemImage: "sparkles")
                        }
                        .disabled(loadingPhoto)
                    }
                    if let estimate { estimateResult(estimate) }
                    if let estimateIssue { InlineProblem(message: estimateIssue) }
                } header: {
                    Text("热量估算")
                } footer: {
                    Text("估算会把这餐的主图、辅助图和描述发送到 DeepSeek。结果可核对、修改后再保存。")
                }

                if original != nil {
                    Section {
                        Button("删除这餐", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .fitForm()
            .navigationTitle(original == nil ? "记一餐" : "编辑饮食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(loadingPhoto)
                }
            }
            .confirmationDialog("删除这餐记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive, action: delete)
            }
            .confirmationDialog("发送这餐给 DeepSeek？", isPresented: $confirmSend, titleVisibility: .visible) {
                Button("同意并估算") { allowMeal = true; startEstimate() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("发送这餐的文字、主图及已添加的辅助图，用于估算大卡。")
            }
            .journalEditAlert($saveIssue)
            .sheet(isPresented: $configureKey) { keySettings }
            .onChange(of: photos.map(\.id)) { _, _ in inputsChanged() }
            .onChange(of: name) { _, _ in inputsChanged() }
            .onChange(of: notes) { _, _ in inputsChanged() }
            .onDisappear { cancelEstimate() }
        }
    }

    private func estimateResult(_ estimate: CalorieEstimate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(estimate.name) · 约 \(estimate.kcal) 大卡").font(.headline)
            Text("估算范围 \(estimate.low)–\(estimate.high) 大卡")
                .font(.subheadline).foregroundStyle(FitTheme.accent)
            Text(estimate.assumptions).font(.footnote).foregroundStyle(FitTheme.muted)
            Button("填入 \(estimate.kcal) 大卡") {
                kcal = String(estimate.kcal)
                appliedEstimate = estimate
                saveIssue = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private var keySettings: some View {
        NavigationStack {
            Form { DeepSeekSettingsSection() }
                .fitForm()
                .navigationTitle("DeepSeek 设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { configureKey = false } }
                }
        }
    }

    private func startEstimate() {
        guard estimateTask == nil else { return }
        let text = [name.trimmed, notes.trimmed].filter { !$0.isEmpty }.joined(separator: "\n")
        let mainPhoto = photos.first?.data
        let references = photos.dropFirst().compactMap(\.data)
        guard !text.isEmpty || mainPhoto != nil || !references.isEmpty else {
            estimateIssue = DeepSeekIssue.noInput.localizedDescription
            return
        }

        estimateIssue = nil
        let id = UUID()
        requestID = id
        estimateTask = Task {
            defer {
                if requestID == id {
                    requestID = nil
                    estimateTask = nil
                }
            }
            do {
                let result = try await DeepSeekService.estimate(notes: text, photo: mainPhoto, referencePhotos: references)
                if requestID == id, !Task.isCancelled { estimate = result }
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                if (error as? DeepSeekIssue) == .noKey {
                    configureKey = true
                } else {
                    estimateIssue = error.localizedDescription
                }
            }
        }
    }

    private func estimateTapped() {
        guard photos.contains(where: { $0.data != nil }) || !name.trimmed.isEmpty || !notes.trimmed.isEmpty else {
            estimateIssue = DeepSeekIssue.noInput.localizedDescription
            return
        }
        if allowMeal { startEstimate() } else { confirmSend = true }
    }

    private func cancelEstimate() {
        requestID = nil
        estimateTask?.cancel()
        estimateTask = nil
    }

    private func inputsChanged() {
        cancelEstimate()
        if estimate != nil { estimateIssue = "餐食信息已经更新，请重新估算或核对已填写的大卡。" }
        estimate = nil
        appliedEstimate = nil
    }

    private func save() {
        guard let value = Int(kcal.trimmed), (0...Journal.maxDailyEnergy).contains(value) else {
            saveIssue = JournalIssue.invalidIntake.localizedDescription
            return
        }
        let used = appliedEstimate.flatMap { $0.kcal == value ? $0 : nil }
        let title = name.trimmed.isEmpty ? (used?.name ?? kind.title) : name.trimmed
        let meal = Meal(id: original?.id ?? UUID(), day: day, kind: kind, name: title, notes: notes.trimmed,
                        kcal: value, estimate: used,
                        createdAt: original?.createdAt ?? .now)
        do {
            try store.saveMeal(meal, photos: photos)
            dismiss()
        } catch {
            saveIssue = error.localizedDescription
        }
    }

    private func delete() {
        guard let original else { return }
        do {
            try store.deleteMeal(original)
            dismiss()
        } catch {
            saveIssue = error.localizedDescription
        }
    }
}
