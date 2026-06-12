import SwiftUI

// ============================================================
// SettingsPanel —— 设置面板（prototype `settings` 状态，460×540）。
// 四个卡片：API 配置 / 快捷键 / 第三方集成 / 提醒与外观。
// store.settings 是 @Published var，直接 $store.settings.* 绑定，改动即持久化。
// ============================================================

struct SettingsPanel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            PanelTabBar(current: .settings)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    apiSection
                    hotkeySection
                    integrationSection
                    reminderSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - API 配置

    private var apiSection: some View {
        SettingsSection(label: "API 配置") {
            SettingsRow(label: "AI API Key") {
                SettingsInputField(placeholder: "Azure Key", text: $store.settings.aiAPIKey, secure: true)
            }
            // 端点/模型固定在 AIDefaults（团队共用 Azure 资源），UI 不暴露
            SettingsRow(label: "模型") {
                Text("\(AIDefaults.model)（内置）· 未配置 Key 时用 Mock")
                    .font(DS.Fonts.compactSide)
                    .foregroundStyle(DS.Colors.text3)
            }
        }
    }

    // MARK: - 快捷键（只读展示）

    private var hotkeySection: some View {
        SettingsSection(label: "快捷键") {
            SettingsRow(label: "截图 → Todo") { SettingsValueText("F2") }
            SettingsRow(label: "截图收藏") { SettingsValueText("F3") }
            SettingsRow(label: "快速新建") { SettingsValueText("⌘N") }
            SettingsRow(label: "展开/收起") { SettingsValueText("⌘⇧L") }
        }
    }

    // MARK: - 第三方集成

    private var jiraConfigured: Bool {
        !store.settings.jiraBaseURL.isEmpty
            && !store.settings.jiraEmail.isEmpty
            && !store.settings.jiraAPIToken.isEmpty
    }

    private var integrationSection: some View {
        SettingsSection(label: "第三方集成") {
            SettingsRow(label: "Jira") { SettingsStatusText(configured: jiraConfigured) }
            SettingsRow(label: "URL") {
                SettingsInputField(placeholder: "https://xx.atlassian.net", text: $store.settings.jiraBaseURL)
            }
            SettingsRow(label: "Email") {
                SettingsInputField(placeholder: "you@example.com", text: $store.settings.jiraEmail)
            }
            SettingsRow(label: "Token") {
                SettingsInputField(placeholder: "API Token", text: $store.settings.jiraAPIToken, secure: true)
            }
            JiraConnectionTestRow()

            SettingsCardDivider()

            SettingsRow(label: "飞书 Webhook") {
                SettingsStatusText(configured: !store.settings.feishuWebhook.isEmpty)
            }
            SettingsRow(label: "URL") {
                SettingsInputField(placeholder: "https://open.feishu.cn/...", text: $store.settings.feishuWebhook)
            }

            SettingsCardDivider()

            SettingsRow(label: "Bark Token") {
                SettingsStatusText(configured: !store.settings.barkToken.isEmpty)
            }
            SettingsRow(label: "Token") {
                SettingsInputField(placeholder: "Bark Token", text: $store.settings.barkToken)
            }
        }
    }

    // MARK: - 提醒与外观

    private var reminderSection: some View {
        SettingsSection(label: "提醒与外观") {
            SettingsRow(label: "勿扰开始") {
                SettingsHourStepper(hour: $store.settings.quietHourStart)
            }
            SettingsRow(label: "勿扰结束") {
                SettingsHourStepper(hour: $store.settings.quietHourEnd)
            }
            SettingsRow(label: "晚报时间") {
                SettingsHourStepper(hour: $store.settings.eveningReportHour)
            }
            SettingsRow(label: "动效") {
                Toggle("", isOn: $store.settings.effectsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(DS.Colors.accent)
            }
        }
    }
}

// MARK: - 设置卡片（settings-label + settings-card）

private struct SettingsSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(DS.Fonts.sectionTitle)
                .foregroundStyle(DS.Colors.text3)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        }
    }
}

// MARK: - 设置行（label 左 + 控件右）

private struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label)
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
            Spacer(minLength: 8)
            trailing
        }
    }
}

// MARK: - 只读 value（mono）

private struct SettingsValueText: View {
    let value: String
    init(_ value: String) { self.value = value }

    var body: some View {
        Text(value)
            .font(DS.Fonts.compactSide)
            .foregroundStyle(DS.Colors.text3)
    }
}

// MARK: - Jira 测试连接行（结果就地反馈：成功显示 ticket 数，失败显示原因）

private struct JiraConnectionTestRow: View {
    @EnvironmentObject var store: AppStore

    private enum TestState: Equatable {
        case idle, testing
        case success(Int)
        case failure(String)
    }
    @State private var state: TestState = .idle

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case .idle:
                Spacer()
            case .testing:
                ProgressView()
                    .controlSize(.small)
                Spacer()
            case .success(let count):
                Text("✓ 连接正常 · \(count) 个指派 ticket")
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.success)
                Spacer(minLength: 8)
            case .failure(let message):
                Text("✗ \(message)")
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.alert)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
            }

            Button {
                runTest()
            } label: {
                Text(state == .testing ? "测试中…" : "测试连接")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(state == .testing)
        }
    }

    private func runTest() {
        state = .testing
        let settings = store.settings
        Task { @MainActor in
            do {
                let service = RealJiraService(
                    baseURL: settings.jiraBaseURL,
                    email: settings.jiraEmail,
                    apiToken: settings.jiraAPIToken
                )
                let tickets = try await service.fetchAssignedTickets()
                state = .success(tickets.count)
            } catch JiraServiceError.notConfigured {
                state = .failure("请先填写 URL / Email / Token")
            } catch JiraServiceError.http(let code) {
                state = .failure(code == 401 || code == 403
                    ? "认证失败 (\(code))，检查 Email/Token"
                    : "请求失败 HTTP \(code)，检查 URL")
            } catch {
                state = .failure("网络错误：\(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 已配置/未配置 状态文字

private struct SettingsStatusText: View {
    let configured: Bool

    var body: some View {
        Text(configured ? "已配置" : "未配置")
            .font(DS.Fonts.meta)
            .foregroundStyle(configured ? DS.Colors.success : DS.Colors.text3)
    }
}

// MARK: - 输入框（settings-input：surface1 + border + mono 11pt，宽 180）

private struct SettingsInputField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text)
            } else {
                TextField("", text: $text)
            }
        }
        .textFieldStyle(.plain)
        .focused($focused)
        .font(DS.Fonts.compactSide)
        .foregroundStyle(DS.Colors.text1)
        .padding(.horizontal, 9)
        .frame(width: 180, height: 24)
        // 自绘占位符：.plain 样式下 prompt 的颜色样式不生效，黑底上看不清，
        // 改为文字为空时自己叠一层（颜色完全走 DS token）
        .overlay(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(DS.Fonts.compactSide)
                    .foregroundStyle(DS.Colors.text3)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }
        }
        .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.s)
                .strokeBorder(focused ? DS.Colors.accent : DS.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - 小时 Stepper（0-23，显示 "HH:00" mono）

private struct SettingsHourStepper: View {
    @Binding var hour: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d:00", hour))
                .font(DS.Fonts.compactSide)
                .foregroundStyle(DS.Colors.text1)
            Stepper("", value: $hour, in: 0...23)
                .labelsHidden()
                .controlSize(.mini)
        }
    }
}

// MARK: - 卡片内分隔线

private struct SettingsCardDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Colors.border)
            .frame(height: 1)
    }
}
