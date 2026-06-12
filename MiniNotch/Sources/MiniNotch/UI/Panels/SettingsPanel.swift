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
                SettingsInputField(placeholder: "sk-...", text: $store.settings.aiAPIKey, secure: true)
            }
            SettingsRow(label: "模型") {
                Text("未配置时使用 Mock 演示数据")
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
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .focused($focused)
        .font(DS.Fonts.compactSide)
        .foregroundStyle(DS.Colors.text1)
        .padding(.horizontal, 9)
        .frame(width: 180, height: 24)
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
