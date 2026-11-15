import SwiftUI
import UIKit

@MainActor
struct QuickStrengthEntry: View {
    @Environment(JournalStore.self) private var store
    let sessionID: UUID
    let lift: Lift
    let editRequest: UUID?
    @State private var draft: SetDraft?
    @State private var issue: String?

    init(sessionID: UUID, lift: Lift, editRequest: UUID?) {
        self.sessionID = sessionID
        self.lift = lift
        self.editRequest = editRequest
        _draft = State(initialValue: editRequest.map { _ in Self.newDraft(for: lift) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lift.name).font(.headline)
                    if !lift.sets.isEmpty {
                        Text("已记 \(lift.sets.reduce(0) { $0 + $1.groupCount }) 组")
                            .font(.caption).foregroundStyle(FitTheme.muted)
                    }
                }
                Spacer()
                EquipmentThumbnail(name: lift.name).frame(width: 74, height: 65)
            }
            ForEach(lift.sets) { set in
                if let draft, draft.id == set.id {
                    editor(draft, stored: set)
                } else {
                    Button { draft = SetDraft(set) } label: {
                        HStack {
                            Text("\(set.groupCount) 组 × \(set.reps) 次")
                            Spacer()
                            Text(set.kg.map { "\($0.formatted()) kg" } ?? "自重")
                            Image(systemName: "pencil").font(.caption)
                        }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let draft {
                if !lift.sets.contains(where: { $0.id == draft.id }) { editor(draft, stored: nil) }
            } else {
                Button {
                    draft = Self.newDraft(for: lift)
                } label: {
                    Label("加一行组次", systemImage: "plus")
                }
                .buttonStyle(FitActionStyle())
            }
        }
        .fitPanel()
        .onChange(of: editRequest) { _, request in
            if request != nil && draft == nil { draft = Self.newDraft(for: lift) }
        }
        .journalEditAlert($issue)
    }

    private static func newDraft(for lift: Lift) -> SetDraft {
        SetDraft(kg: lift.sets.last?.kg.map { String($0) } ?? "")
    }

    private func editor(_ draft: SetDraft, stored: LiftSet?) -> some View {
        let remove: (() -> Void)? = stored.map { set in
            {
                if mutate({ $0.removeAll { $0.id == set.id } }) { self.draft = nil }
            }
        }
        return QuickGroupFields(initial: draft, save: { edited in
            let record = try edited.record(label: "「\(lift.name)」")
            if mutate({ sets in
                if let index = sets.firstIndex(where: { $0.id == record.id }) { sets[index] = record }
                else { sets.append(record) }
            }) { self.draft = nil }
        }, cancel: { self.draft = nil }, remove: remove)
        .id(draft.id)
    }

    private func mutate(_ change: (inout [LiftSet]) -> Void) -> Bool {
        guard var session = store.journal.sessions.first(where: { $0.id == sessionID }),
              let index = session.lifts.firstIndex(where: { $0.id == lift.id }) else { return false }
        change(&session.lifts[index].sets)
        do { try store.saveSession(session); return true }
        catch { issue = error.localizedDescription; return false }
    }
}

private struct QuickGroupFields: View {
    @State private var draft: SetDraft
    @State private var issue: String?
    private let save: (SetDraft) throws -> Void
    private let cancel: () -> Void
    private let remove: (() -> Void)?

    init(initial: SetDraft, save: @escaping (SetDraft) throws -> Void, cancel: @escaping () -> Void,
         remove: (() -> Void)?) {
        _draft = State(initialValue: initial)
        self.save = save
        self.cancel = cancel
        self.remove = remove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 7) {
                field("组数", text: $draft.groups, keyboard: .numberPad)
                field("重量 kg", text: $draft.kg, keyboard: .decimalPad)
                field("每组次数", text: $draft.reps, keyboard: .numberPad)
            }
            if let issue { InlineProblem(message: issue) }
            HStack {
                Button("取消", action: cancel).buttonStyle(FitActionStyle())
                if let remove { Button("移除", role: .destructive, action: remove).buttonStyle(FitActionStyle()) }
                Spacer()
                Button("保存这行") {
                    do { try save(draft) }
                    catch { issue = error.localizedDescription }
                }
                .buttonStyle(FitActionStyle(prominent: true))
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(FitTheme.muted)
            TextField(label, text: text).keyboardType(keyboard).textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct EquipmentThumbnail: View {
    let name: String
    private static let tiles: [String: UIImage] = {
        guard let url = Bundle.main.url(forResource: "equipment-atlas", withExtension: "png"),
              let atlas = UIImage(contentsOfFile: url.path)?.cgImage else { return [:] }
        let width = atlas.width / 4
        let height = atlas.height / 3
        return Dictionary(uniqueKeysWithValues: Lift.commonEquipment.enumerated().compactMap { index, name in
            let rect = CGRect(x: CGFloat(index % 4 * width), y: CGFloat(index / 4 * height),
                              width: CGFloat(width), height: CGFloat(height))
            return atlas.cropping(to: rect).map { (name, UIImage(cgImage: $0)) }
        })
    }()

    var body: some View {
        if let image = Self.tiles[name] {
            Image(uiImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("\(name)参考图")
        } else {
            Image(systemName: "dumbbell").foregroundStyle(FitTheme.accent).accessibilityHidden(true)
        }
    }
}
