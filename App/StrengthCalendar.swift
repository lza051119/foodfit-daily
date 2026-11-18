import SwiftUI

@MainActor
struct StrengthCalendar: View {
    private struct Edit: Identifiable {
        let id = UUID()
        let day: LogDay
        let session: StrengthSession?
    }

    @Environment(JournalStore.self) private var store
    @Binding var day: LogDay
    let today: LogDay
    @State private var edit: Edit?
    @State private var catalogOpen = false
    @State private var quickEntry: (liftID: UUID, request: UUID)?
    @State private var willAddCustom = false
    @State private var customName = ""
    @State private var issue: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text("训练记录")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button { edit = Edit(day: day, session: nil) } label: {
                        Label("排训练", systemImage: "plus")
                    }
                    .buttonStyle(FitActionStyle(prominent: true))
                    .disabled(store.hasLoadError)
                }

                if store.hasLoadError { JournalLoadProblem() }
                calendar
                schedule
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
        }
        .background(FitTheme.canvas.ignoresSafeArea())
        .foregroundStyle(FitTheme.ink)
        .onChange(of: day) { _, _ in
            catalogOpen = false
            quickEntry = nil
        }
        .journalEditAlert($issue)
        .sheet(item: $edit) { edit in
            TrainingEditor(day: edit.day, original: edit.session, onSave: { day = $0 })
        }
    }

    private var calendar: some View {
        let week = day.week
        let label = "\(week[0].shortDate) – \(week[6].shortDate)"
        return VStack(spacing: 10) {
            DateStrip(day: $day, step: 7, title: label)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ForEach(week, id: \.self) { date in weekCell(date) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
                    ForEach(week, id: \.self) { date in weekCell(date) }
                }
            }
        }
    }

    private func weekCell(_ date: LogDay) -> some View {
        let sessions = store.journal.sessions(on: date)
        let selected = day == date
        let allDone = !sessions.isEmpty && sessions.allSatisfy(\.isComplete)
        let foreground = selected ? Color.white : FitTheme.ink
        let status = sessions.isEmpty ? "暂无安排" : (allDone ? "训练已完成" : "已排训练")
        return Button { day = date } label: {
            VStack(spacing: 3) {
                Text(date == today ? "今" : date.weekday)
                    .font(.caption2.weight(.semibold))
                Text(String(date.day))
                    .font(FitTheme.number(18, relativeTo: .subheadline))
                ZStack {
                    Color.clear
                    if allDone {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                    } else if !sessions.isEmpty {
                        Circle().fill(selected ? FitTheme.citrus : FitTheme.accent).frame(width: 4, height: 4)
                    }
                }
                .frame(width: 10, height: 9)
                .accessibilityHidden(true)
            }
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 68)
            .foregroundStyle(foreground)
            .background(selected ? FitTheme.hero : FitTheme.paper, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.heading)，\(status)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var schedule: some View {
        let sessions = store.journal.sessions(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("训练动作").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { catalogOpen.toggle() } label: {
                    Label(catalogOpen ? "收起器械" : "添加器械", systemImage: catalogOpen ? "chevron.up" : "plus")
                }
                .buttonStyle(FitActionStyle(prominent: true))
                .disabled(store.hasLoadError)
            }
            if catalogOpen { equipmentPicker }
            if sessions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell")
                        .font(.headline)
                        .foregroundStyle(FitTheme.accent)
                        .frame(width: 46, height: 46)
                        .background(FitTheme.soft, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("这天还没安排力量训练").font(.subheadline.weight(.semibold))
                        Text("选一个器械后即可填写组数、重量和每组次数。")
                            .font(.footnote).foregroundStyle(FitTheme.muted)
                    }
                }
                .fitPanel()
            } else {
                ForEach(sessions) { session in
                    Button { edit = Edit(day: day, session: session) } label: {
                        sessionRow(session)
                            .fitPanel()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(session.lifts) { lift in
                        QuickStrengthEntry(sessionID: session.id, lift: lift,
                                           editRequest: quickEntry?.liftID == lift.id ? quickEntry?.request : nil)
                    }
                }
            }
        }
    }

    private var equipmentPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Lift.commonEquipment, id: \.self) { name in
                    Button { addLift(name) } label: {
                        VStack(spacing: 5) {
                            EquipmentThumbnail(name: name).frame(height: 104)
                            Text(name).font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(7)
                        .background(FitTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            if willAddCustom {
                TextField("动作名称", text: $customName).textFieldStyle(.roundedBorder)
                Button("添加动作") { addLift(customName) }.buttonStyle(FitActionStyle())
                    .disabled(customName.trimmed.isEmpty)
            } else {
                Button("自定义动作") { willAddCustom = true }.buttonStyle(FitActionStyle())
            }
        }
        .fitPanel()
    }

    private func addLift(_ input: String) {
        let name = Lift.catalogName(for: input.trimmed)
        guard !name.isEmpty else { return }
        let sessions = store.journal.sessions(on: day)
        if let existing = sessions.flatMap(\.lifts).first(where: { Lift.catalogName(for: $0.name) == name }) {
            quickEntry = (existing.id, UUID())
            catalogOpen = false
            return
        }
        let lift = Lift(name: name, plannedSets: nil, plannedReps: "", cues: "", sets: [])
        var session = sessions.first ?? StrengthSession(day: day, title: "力量训练", plannedMinutes: nil,
                                                        notes: "", isComplete: false, lifts: [])
        session.lifts.append(lift)
        do {
            try store.saveSession(session)
            quickEntry = (lift.id, UUID())
            catalogOpen = false
            willAddCustom = false
            customName = ""
        } catch { issue = error.localizedDescription }
    }

    private func sessionRow(_ session: StrengthSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title).font(.headline)
                if !session.lifts.isEmpty {
                    Text(session.lifts.map(\.name).joined(separator: "、"))
                        .font(.footnote).foregroundStyle(FitTheme.muted).lineLimit(2)
                }
                let detail = [
                    session.plannedMinutes.map { "计划 \($0) 分钟" },
                    session.setCount > 0 ? "已记 \(session.setCount) 组" : nil
                ].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(FitTheme.muted)
                }
            }
            Spacer(minLength: 0)
            Label(session.isComplete ? "已完成" : "编辑训练",
                  systemImage: session.isComplete ? "checkmark.circle.fill" : "pencil")
                .font(.caption.weight(.medium))
                .foregroundStyle(FitTheme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}
