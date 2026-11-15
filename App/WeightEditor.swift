import SwiftUI

@MainActor
struct WeightEditor: View {
    private enum Unit: String, CaseIterable {
        case jin = "斤"
        case kg = "kg"

        var factor: Double { self == .jin ? 2 : 1 }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(JournalStore.self) private var store

    let day: LogDay
    @State private var height: String
    @State private var weight: String
    @State private var unit: Unit = .jin
    @State private var issue: String?

    init(day: LogDay, journal: Journal) {
        self.day = day
        _height = State(initialValue: journal.heightCM.map { String($0) } ?? "")
        _weight = State(initialValue: journal.weight(on: day).map { String($0 * Unit.jin.factor) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("记录日期", value: "\(day.year)年\(day.heading)")
                    LabeledContent("体重") {
                        TextField("选填", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("体重")
                    }
                    Picker("体重单位", selection: $unit) {
                        ForEach(Unit.allCases, id: \.self) { item in Text(item.rawValue).tag(item) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("这一天")
                } footer: {
                    Text("同一天保留一条记录。清空体重后保存可移除当天记录。")
                }

                Section("身体资料") {
                    LabeledContent("身高（厘米）") {
                        TextField("选填", text: $height)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("身高厘米")
                    }
                }

                let recent = (store.journal.weights ?? []).sorted { $0.day > $1.day }.prefix(7)
                if !recent.isEmpty {
                    Section("最近记录") {
                        ForEach(recent) { item in
                            LabeledContent(item.day.isoDate,
                                           value: "\(Self.display(item.kg * unit.factor)) \(unit.rawValue)")
                        }
                    }
                }
            }
            .fitForm()
            .navigationTitle("记体重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onChange(of: unit) { old, new in
                if let value = decimal(weight) { weight = Self.display(value / old.factor * new.factor) }
            }
            .journalEditAlert($issue)
        }
    }

    private static func display(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US")))
    }

    private func decimal(_ value: String) -> Double? {
        guard let number = Double(value.trimmed.replacingOccurrences(of: ",", with: ".")),
              number.isFinite else { return nil }
        return number
    }

    private func save() {
        let cm = decimal(height)
        let kg = decimal(weight).map { $0 / unit.factor }
        guard height.trimmed.isEmpty || cm != nil else { issue = JournalIssue.invalidHeight.localizedDescription; return }
        guard weight.trimmed.isEmpty || kg != nil else { issue = JournalIssue.invalidWeight.localizedDescription; return }
        do {
            try store.saveMeasurements(heightCM: cm, kg: kg, day: day)
            dismiss()
        } catch {
            issue = error.localizedDescription
        }
    }
}
