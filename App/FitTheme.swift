import SwiftUI
import UIKit

enum FitTheme {
    static let canvas = adaptive(0xF7F7F0, dark: 0x141916)
    static let paper = adaptive(0xFFFEFA, dark: 0x202922)
    static let ink = adaptive(0x1D3028, dark: 0xF1F5EF)
    static let muted = adaptive(0x536459, dark: 0xB4C5B8)
    static let accent = adaptive(0x266044, dark: 0xA7D6B9)
    static let soft = adaptive(0xE7EEE4, dark: 0x2C3A31)
    static let line = adaptive(0xE2E7DD, dark: 0x39443D)

    static let hero = Color(uiColor: rgb(0x173B2E))
    static let heroMuted = Color(uiColor: rgb(0xC3D9C9))
    static let citrus = Color(uiColor: rgb(0xF3CF88))

    static func number(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        Font.custom("Geist-Regular", size: size, relativeTo: style).weight(.semibold).monospacedDigit()
    }

    private static func adaptive(_ light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) })
    }

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }
}

extension View {
    func fitPanel(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FitTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(FitTheme.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    func fitForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background(FitTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
    }

    func journalEditAlert(_ message: Binding<String?>) -> some View {
        alert("请检查记录", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("知道了", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

struct FitActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : FitTheme.accent)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(prominent ? FitTheme.hero : FitTheme.soft, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct InlineProblem: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct JournalLoadProblem: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InlineProblem(message: JournalIssue.loadFailed.localizedDescription)
            Button("重新读取") { store.reload() }
                .buttonStyle(FitActionStyle())
        }
        .fitPanel()
    }
}

extension LogDay {
    var weekday: String {
        let index = Self.calendar.component(.weekday, from: start()) - 1
        return ["日", "一", "二", "三", "四", "五", "六"][index]
    }

    var heading: String { "\(month)月\(day)日 · 周\(weekday)" }
    var shortDate: String { "\(month)/\(day)" }
}

struct DateStrip: View {
    @Binding var day: LogDay
    var step = 1
    var lastDay: LogDay? = nil
    let title: String
    @State private var chooseDate = false

    var body: some View {
        HStack(spacing: 3) {
            arrow("chevron.left", label: step == 1 ? "前一天" : "上一周", offset: -step)

            Button { chooseDate = true } label: {
                Label(title, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开日历选日期")

            arrow("chevron.right", label: step == 1 ? "后一天" : "下一周", offset: step)
                .disabled(lastDay.map { day.adding(step) > $0 } ?? false)
                .opacity((lastDay.map { day.adding(step) > $0 } ?? false) ? 0.35 : 1)
        }
        .foregroundStyle(FitTheme.accent)
        .background(FitTheme.soft, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $chooseDate) {
            DateChooser(day: $day, lastDay: lastDay)
        }
    }

    private func arrow(_ icon: String, label: String, offset: Int) -> some View {
        Button { day = day.adding(offset) } label: {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct DateChooser: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var day: LogDay
    let lastDay: LogDay?
    @State private var selection: Date

    init(day: Binding<LogDay>, lastDay: LogDay?) {
        _day = day
        self.lastDay = lastDay
        _selection = State(initialValue: day.wrappedValue.start())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let lastDay {
                        DatePicker("日期", selection: $selection, in: ...lastDay.adding(1).start().addingTimeInterval(-1),
                                   displayedComponents: .date)
                    } else {
                        DatePicker("日期", selection: $selection, displayedComponents: .date)
                    }
                }
                .datePickerStyle(.graphical)
                .padding()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        day = LogDay(selection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(440), .large])
    }
}
