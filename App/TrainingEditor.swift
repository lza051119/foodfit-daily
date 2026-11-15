import SwiftUI
import UIKit

@MainActor
struct TrainingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store
    let original: StrengthSession?
    let onSave: (LogDay) -> Void
    @State private var date: Date
    @State private var title: String
    @State private var minutes: String
    @State private var notes: String
    @State private var complete: Bool
    @State private var lifts: [LiftDraft]
    @State private var issue: String?
    @State private var confirmDelete = false

    init(day: LogDay, original: StrengthSession?, onSave: @escaping (LogDay) -> Void) {
        self.original = original
        self.onSave = onSave
        _date = State(initialValue: (original?.day ?? day).start())
        _title = State(initialValue: original?.title ?? "")
        _minutes = State(initialValue: original?.plannedMinutes.map { String($0) } ?? "")
        _notes = State(initialValue: original?.notes ?? "")
        _complete = State(initialValue: original?.isComplete ?? false)
        _lifts = State(initialValue: original?.lifts.map { LiftDraft($0) } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日程") {
                    DatePicker("训练日期", selection: $date, displayedComponents: .date)
                    TextField("训练名称（选填）", text: $title)
                    if original == nil, title.trimmed.isEmpty {
                        Menu("按部位填写名称") {
                            ForEach(["胸部", "背部", "腿部", "肩部", "手臂", "全身"], id: \.self) { muscle in
                                Button(muscle) { title = muscle + "训练" }
                            }
                        }
                    }
                    LabeledContent("计划时长（分钟）") {
                        TextField("选填", text: $minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("计划时长（分钟）")
                    }
                    Toggle("标记已完成", isOn: $complete)
                    TextField("训练小结", text: $notes, axis: .vertical).lineLimit(2...4)
                    if original == nil, lifts.isEmpty, !recentPlans.isEmpty {
                        copyMenu
                    }
                }

                ForEach($lifts) { lift in liftSection(lift) }

                Section {
                    Menu {
                        ForEach(Lift.commonEquipment, id: \.self) { equipment in
                            Button(equipment) { lifts.append(LiftDraft(name: equipment)) }
                        }
                        Button("自定义动作") { lifts.append(LiftDraft()) }
                    } label: {
                        Label("添加动作", systemImage: "plus.circle")
                    }
                } footer: {
                    if lifts.isEmpty { Text("选一个常用器械，或添加自己的动作。") }
                }

                if original != nil {
                    Section { Button("删除日程", role: .destructive) { confirmDelete = true } }
                }
            }
            .fitForm()
            .navigationTitle(original == nil ? "排力量训练" : "编辑力量训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .confirmationDialog("删除这个训练日程和实做记录？", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("删除", role: .destructive, action: delete)
            }
            .journalEditAlert($issue)
        }
    }

    private var recentPlans: [StrengthSession] {
        Array(store.journal.sessions.filter { !$0.lifts.isEmpty }
            .sorted { $0.day > $1.day }.prefix(10))
    }

    private var copyMenu: some View {
        Menu("从最近的日程复制动作") {
            ForEach(recentPlans) { session in
                Button("\(session.title) · \(session.day.shortDate)") {
                    let plan = session.copyPlan(to: LogDay(date))
                    if title.trimmed.isEmpty { title = plan.title }
                    if minutes.trimmed.isEmpty { minutes = plan.plannedMinutes.map { String($0) } ?? "" }
                    lifts = plan.lifts.map { LiftDraft($0) }
                }
            }
        }
    }

    private func liftSection(_ lift: Binding<LiftDraft>) -> some View {
        let draft = lift.wrappedValue
        let number = (lifts.firstIndex { $0.id == draft.id } ?? 0) + 1
        return Section {
            TextField("动作名称，例如腿举", text: lift.name)
            LabeledContent("计划组数") {
                TextField("选填", text: lift.plannedSets)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("计划组数")
            }
            TextField("每组目标次数，例如 8–12", text: lift.plannedReps)
            TextField("器械设置和动作要点", text: lift.cues, axis: .vertical).lineLimit(2...4)
            if !draft.sets.isEmpty {
                Text("实做组次").font(.subheadline.weight(.semibold)).foregroundStyle(FitTheme.accent)
            }
            ForEach(lift.sets) { (set: Binding<SetDraft>) in
                setRow(set, in: lift)
            }
            Button {
                let previous = lift.wrappedValue.sets.last
                lift.wrappedValue.sets.append(SetDraft(reps: previous?.reps ?? "", kg: previous?.kg ?? ""))
            } label: {
                Label("加一行组次", systemImage: "plus.circle")
            }
            Button("移除这个动作", role: .destructive) { lifts.removeAll { $0.id == draft.id } }
        } header: {
            Text(draft.name.trimmed.isEmpty ? "动作 \(number)" : "动作 \(number) · \(draft.name.trimmed)")
        }
    }

    private func setRow(_ set: Binding<SetDraft>, in lift: Binding<LiftDraft>) -> some View {
        let id = set.wrappedValue.id
        let index = (lift.wrappedValue.sets.firstIndex { $0.id == id } ?? 0) + 1
        return HStack(alignment: .bottom, spacing: 8) {
            setField("组数", text: set.groups, line: index, keyboard: .numberPad)
            setField("重量 kg", text: set.kg, line: index, keyboard: .decimalPad)
            setField("每组次数", text: set.reps, line: index, keyboard: .numberPad)
            Button(role: .destructive) {
                lift.wrappedValue.sets.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("移除第 \(index) 行")
        }
    }

    private func setField(_ label: String, text: Binding<String>, line: Int, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(FitTheme.muted)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .accessibilityLabel("第 \(line) 行\(label)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        do {
            let duration = Int(minutes.trimmed)
            guard minutes.trimmed.isEmpty || duration.map({ (1...600).contains($0) }) == true else {
                throw TrainingInputIssue(message: "计划时长请输入 1 到 600 之间的整数分钟。")
            }
            let name = title.trimmed.isEmpty ? "力量训练" : title.trimmed
            let session = StrengthSession(id: original?.id ?? UUID(), day: LogDay(date), title: name,
                                          plannedMinutes: duration, notes: notes.trimmed,
                                          isComplete: complete, lifts: try lifts.map { try $0.record() })
            try store.saveSession(session)
            onSave(session.day)
            dismiss()
        } catch {
            issue = error.localizedDescription
        }
    }

    private func delete() {
        guard let original else { return }
        do {
            try store.deleteSession(original)
            dismiss()
        } catch {
            issue = error.localizedDescription
        }
    }
}

private struct LiftDraft: Identifiable {
    var id: UUID
    var name: String
    var plannedSets: String
    var plannedReps: String
    var cues: String
    var sets: [SetDraft]

    init(_ lift: Lift? = nil, name: String = "") {
        id = lift?.id ?? UUID()
        self.name = lift?.name ?? name
        plannedSets = lift?.plannedSets.map { String($0) } ?? ""
        plannedReps = lift?.plannedReps ?? ""
        cues = lift?.cues ?? ""
        sets = lift?.sets.map { SetDraft($0) } ?? []
    }

    func record() throws -> Lift {
        guard !name.trimmed.isEmpty else { throw TrainingInputIssue(message: "请填写每个动作的名称。") }
        let planCount = Int(plannedSets.trimmed)
        guard plannedSets.trimmed.isEmpty || planCount.map({ (1...100).contains($0) }) == true else {
            throw TrainingInputIssue(message: "「\(name)」的计划组数请输入 1 到 100 的整数。")
        }

        let realSets = try sets.enumerated().map { index, set in
            try set.record(label: "「\(name)」第 \(index + 1) 行")
        }
        return Lift(id: id, name: name.trimmed, plannedSets: planCount, plannedReps: plannedReps.trimmed,
                    cues: cues.trimmed, sets: realSets)
    }
}

struct SetDraft: Identifiable {
    var id = UUID()
    var reps: String
    var kg: String
    var groups = "1"

    init(id: UUID = UUID(), reps: String = "", kg: String = "", groups: String = "1") {
        self.id = id
        self.reps = reps
        self.kg = kg
        self.groups = groups
    }

    init(_ stored: LiftSet) {
        self.init(id: stored.id, reps: String(stored.reps), kg: stored.kg.map { String($0) } ?? "",
                  groups: String(stored.groupCount))
    }

    func record(label: String) throws -> LiftSet {
        guard let groupCount = Int(groups.trimmed), (1...100).contains(groupCount) else {
            throw TrainingInputIssue(message: "\(label)的组数请输入 1 到 100 的整数。")
        }
        guard let count = Int(reps.trimmed), (1...999).contains(count) else {
            throw TrainingInputIssue(message: "请填写\(label)的每组次数。")
        }
        let weight = Double(kg.trimmed.replacingOccurrences(of: ",", with: "."))
        guard kg.trimmed.isEmpty || weight.map({ (0...2_000).contains($0) }) == true else {
            throw TrainingInputIssue(message: "\(label)的重量请填写有效公斤数。")
        }
        return LiftSet(id: id, reps: count, kg: weight, groups: groupCount == 1 ? nil : groupCount)
    }
}

private struct TrainingInputIssue: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
