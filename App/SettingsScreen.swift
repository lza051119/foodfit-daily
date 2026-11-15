import SwiftUI

@MainActor
struct SettingsScreen: View {
    @Binding var readHealth: Bool
    let health: HealthBridge
    @AppStorage("deepseek.allowMeal") private var allowMeal = false
    @AppStorage(DailyRecapPreferences.consentKey) private var allowRecap = false
    @State private var waiting = false
    @State private var issue: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if readHealth {
                        Label("已开启自动读取", systemImage: "checkmark.circle")
                            .foregroundStyle(FitTheme.accent)
                        Button("停用本应用读取") { readHealth = false }
                    } else if health.isAvailable {
                        Button { Task { await connect() } } label: {
                            Label("连接 Apple 健康", systemImage: "heart.text.clipboard")
                        }
                        .disabled(waiting)
                    } else {
                        Label("此设备无法读取健康数据", systemImage: "heart.slash")
                    }
                    if waiting { ProgressView("等待授权…") }
                    if let issue { InlineProblem(message: issue) }
                } header: {
                    Text("Apple 健康")
                } footer: {
                    Text("读取活动能量、静息能量和体能训练。可在 iPhone「健康 → 头像 → App 与服务」检查和更改访问权限。")
                }

                DeepSeekSettingsSection()

                Section("隐私与数据") {
                    Text("日记、照片、身高和体重保存在这台设备。健身截图在设备上识别。")
                        .foregroundStyle(FitTheme.muted)
                    Text("Apple 健康读数用于日记和每日长图。经你确认后，消耗和训练汇总也可用于 DeepSeek 建议。")
                        .foregroundStyle(FitTheme.muted)
                    if allowMeal || allowRecap {
                        Button("撤销 DeepSeek 发送授权") {
                            allowMeal = false
                            allowRecap = false
                        }
                    }
                    if let target = Bundle.main.object(forInfoDictionaryKey: "FoodFitPrivacyPolicyURL") as? String,
                       let url = URL(string: target), url.scheme == "https", url.host != nil {
                        Link("隐私政策", destination: url)
                    }
                }
            }
            .fitForm()
            .navigationTitle("设置")
        }
    }

    private func connect() async {
        waiting = true
        issue = nil
        defer { waiting = false }
        do {
            try await health.requestAccess()
            readHealth = true
        } catch {
            let detail = error.localizedDescription
            if detail.localizedCaseInsensitiveContains("com.apple.developer.healthkit") {
                issue = "当前安装的签名缺少 HealthKit 权限。请用启用 HealthKit 的 Xcode 工程重新安装。"
            } else {
                issue = "未能发起健康授权。\(detail)"
            }
        }
    }
}

struct DeepSeekSettingsSection: View {
    @AppStorage(DailyRecapPreferences.promptKey) private var recapPrompt = DeepSeekRequest.recapPrompt
    @State private var input = ""
    @State private var hasKey = false
    @State private var issue: String?
    @State private var confirmRemoval = false
    @State private var checking = false
    @State private var connection: String?

    var body: some View {
        Section {
            LabeledContent("API Key", value: hasKey ? "已保存" : "未配置")
            SecureField(hasKey ? "粘贴新密钥以替换" : "粘贴 DeepSeek API Key", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
            Button("保存密钥") { save() }
                .disabled(input.trimmed.isEmpty || checking)
            if hasKey {
                Button("测试连接") { Task { await check() } }.disabled(checking)
                if checking { ProgressView("正在检查…") }
                if let connection { Text(connection).font(.footnote).foregroundStyle(FitTheme.accent) }
                Button("移除密钥", role: .destructive) { confirmRemoval = true }
                    .disabled(checking)
            }
            if let issue { InlineProblem(message: issue) }
            DisclosureGroup("查看餐食估算提示词") {
                Text(DeepSeekRequest.estimatePrompt).font(.footnote).textSelection(.enabled)
            }
            DisclosureGroup("编辑日总结提示词") {
                TextEditor(text: $recapPrompt)
                    .font(.callout)
                    .frame(minHeight: 180)
                    .accessibilityLabel("日总结提示词")
                Button("恢复默认提示词") { recapPrompt = DeepSeekRequest.recapPrompt }
                    .disabled(recapPrompt == DeepSeekRequest.recapPrompt)
                Text("修改自动保存，下次生成建议时使用。留空时用默认提示词。")
                    .font(.footnote).foregroundStyle(FitTheme.muted)
            }
        } header: {
            Text("DeepSeek")
        } footer: {
            Text("密钥存入设备钥匙串。点击估算时，这餐的照片和食物描述会发送到 DeepSeek，调用使用你的账户额度。")
        }
        .task { read() }
        .confirmationDialog("移除 DeepSeek API Key？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("移除", role: .destructive) { remove() }
        }
    }

    private func read() {
        do {
            hasKey = try DeepSeekKey.load() != nil
            issue = nil
            connection = nil
        } catch {
            issue = error.localizedDescription
        }
    }

    private func save() {
        do {
            try DeepSeekKey.save(input)
            input = ""
            read()
        } catch {
            issue = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try DeepSeekKey.remove()
            input = ""
            read()
        } catch {
            issue = error.localizedDescription
        }
    }

    private func check() async {
        checking = true
        issue = nil
        connection = nil
        defer { checking = false }
        do {
            try await DeepSeekService.checkConnection()
            connection = "密钥可访问 deepseek-flash。"
        } catch { issue = error.localizedDescription }
    }
}
