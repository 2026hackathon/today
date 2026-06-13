import AppKit
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
            PanelScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    apiSection
                    hotkeySection
                    integrationSection
                    emailSection
                    reminderSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
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

    // MARK: - 快捷键（可改键：点录制按下新组合，避免与其它软件冲突）

    private var hotkeySection: some View {
        SettingsSection(label: "全局快捷键") {
            SettingsRow(label: "截图 → Todo") {
                HotKeyRecorderField(config: $store.settings.todoHotKey, defaultConfig: .todoDefault)
            }
            SettingsRow(label: "截图收藏") {
                HotKeyRecorderField(config: $store.settings.favoriteHotKey, defaultConfig: .favoriteDefault)
            }
            SettingsRow(label: "语音速记") {
                HotKeyRecorderField(config: $store.settings.voiceHotKey, defaultConfig: .voiceDefault)
            }
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
            SettingsRow(label: "轮询间隔") {
                SettingsPollIntervalPicker(seconds: $store.settings.jiraPollSeconds)
            }
            JiraConnectionTestRow()

            SettingsCardDivider()

            SettingsRow(label: "GitHub") {
                SettingsStatusText(configured: !store.settings.githubToken.isEmpty)
            }
            SettingsRow(label: "Token") {
                SettingsInputField(placeholder: "PAT / gh auth token", text: $store.settings.githubToken, secure: true)
            }
        }
    }

    // MARK: - 邮件接入（IMAP）

    private var emailConfigured: Bool {
        // 任一来源接入即算已配置（O365/Gmail OAuth）。手动 IMAP+应用密码通道暂隐藏。
        MicrosoftOAuth.shared.isSignedIn || GoogleOAuth.shared.isSignedIn
    }

    private var emailSection: some View {
        SettingsSection(label: "邮件接入") {
            SettingsRow(label: "邮件") { SettingsStatusText(configured: emailConfigured) }

            // O365：OAuth2 设备码登录（IMAP 基础认证已被禁用 → 走 Graph）
            MicrosoftSignInRow()

            SettingsCardDivider()

            // Gmail：OAuth2 浏览器登录（底层走 imap.gmail.com + XOAUTH2）
            GoogleSignInRow()

            // ── 手动「IMAP + 应用密码」兜底通道暂隐藏（当前用不上；OAuth 已覆盖 O365/Gmail）──
            // 恢复时取消注释下方字段，并恢复 AppDelegate.currentEmailServices /
            // EmailConnectionTestRow 里对应的 .password 装配段。Gmail OAuth 不依赖这些字段。
            // SettingsCardDivider()
            // SettingsRow(label: "IMAP 主机") {
            //     SettingsInputField(placeholder: "imap.example.com:993", text: $store.settings.emailImapHost)
            // }
            // SettingsRow(label: "账号") {
            //     SettingsInputField(placeholder: "you@example.com", text: $store.settings.emailAddress)
            // }
            // SettingsRow(label: "应用密码") {
            //     SettingsInputField(
            //         placeholder: "Gmail 等的 App Password",
            //         text: Binding(get: { store.emailAppPassword },
            //                       set: { store.emailAppPassword = $0 }),
            //         secure: true
            //     )
            // }
            EmailConnectionTestRow()
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

// MARK: - 热键录制（点一下进入录制，按下新组合即写入；Esc 取消，可一键恢复默认）

private struct HotKeyRecorderField: View {
    @Binding var config: HotKeyConfig
    let defaultConfig: HotKeyConfig
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button { toggle() } label: {
                Text(recording ? "按下新组合…" : config.display)
                    .font(DS.Fonts.compactSide)
                    .foregroundStyle(recording ? DS.Colors.accent : (hovering ? DS.Colors.text1 : DS.Colors.text3))
                    .lineLimit(1)
                    .frame(minWidth: 64)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.s)
                            .strokeBorder(recording ? DS.Colors.accent : DS.Colors.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            if config != defaultConfig {
                Button { reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Colors.text3)
                }
                .buttonStyle(.plain)
                .help("恢复默认")
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggle() { recording ? stopRecording() : startRecording() }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc（无修饰）取消录制，不改键
            if event.keyCode == 53,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stopRecording()
                return nil
            }
            config = HotKeyConfig(
                keyCode: Int(event.keyCode),
                modifiers: Self.carbonModifiers(event.modifierFlags),
                keyLabel: Self.label(for: event)
            )
            stopRecording()
            return nil  // 吞掉事件，不让它继续派发到输入框
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func reset() {
        stopRecording()
        config = defaultConfig
    }

    /// NSEvent 修饰键 → Carbon 掩码（cmd 256 / shift 512 / option 2048 / control 4096）
    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= 256 }
        if flags.contains(.shift) { m |= 512 }
        if flags.contains(.option) { m |= 2048 }
        if flags.contains(.control) { m |= 4096 }
        return m
    }

    /// 基键的人类可读名：功能键/空格等查表，其余取 charactersIgnoringModifiers 大写
    private static func label(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        let chars = (event.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespaces)
        return chars.isEmpty ? "Key\(event.keyCode)" : chars.uppercased()
    }

    private static let specialKeys: [UInt16: String] = [
        0x31: "Space", 0x24: "Return", 0x30: "Tab", 0x33: "Delete",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
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

// MARK: - Microsoft 登录行（O365 OAuth2 设备码：浏览器登录一次，token 存 Keychain）

private struct MicrosoftSignInRow: View {
    // 观察常驻单例：轮询在单例里跑，面板收起再开仍能看到最新状态
    @ObservedObject private var oauth = MicrosoftOAuth.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Microsoft")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text2)
                Spacer(minLength: 8)
                if oauth.signedIn {
                    Text("已登录").font(DS.Fonts.meta).foregroundStyle(DS.Colors.success)
                    Button("退出") { oauth.signOut() }
                        .buttonStyle(.plain)
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.accent)
                } else {
                    // 始终可点：等待中再点 = 取消旧的、重新生成验证码
                    Button(oauth.pendingUserCode != nil ? "重新生成代码" : "授权") {
                        oauth.beginDeviceLogin()
                    }
                    .buttonStyle(.plain)
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.accent)
                }
            }
            if let code = oauth.pendingUserCode {
                Text("浏览器已打开，输入代码：\(code)（已复制）· 完成后稍候自动登录")
                    .font(DS.Fonts.meta)
                    .foregroundStyle(DS.Colors.accent)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else if let msg = oauth.errorMessage {
                Text("✗ \(msg)").font(DS.Fonts.meta).foregroundStyle(DS.Colors.alert).lineLimit(2)
            }
        }
    }
}

// MARK: - Google 登录行（Gmail OAuth：浏览器授权一次 → IMAP XOAUTH2）

private struct GoogleSignInRow: View {
    @ObservedObject private var oauth = GoogleOAuth.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gmail")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text2)
                Spacer(minLength: 8)
                if oauth.signedIn {
                    Text(oauth.accountEmail.isEmpty ? "已登录" : oauth.accountEmail)
                        .font(DS.Fonts.meta).foregroundStyle(DS.Colors.success).lineLimit(1)
                    Button("退出") { oauth.signOut() }
                        .buttonStyle(.plain).font(DS.Fonts.button).foregroundStyle(DS.Colors.accent)
                } else {
                    Button(oauth.waiting ? "授权中…" : "授权") { oauth.beginSignIn() }
                        .buttonStyle(.plain).font(DS.Fonts.button).foregroundStyle(DS.Colors.accent)
                }
            }
            if oauth.waiting {
                Text("浏览器已打开 Google 授权页，完成后自动登录…")
                    .font(DS.Fonts.meta).foregroundStyle(DS.Colors.accent).lineLimit(2)
            } else if let msg = oauth.errorMessage {
                Text("✗ \(msg)").font(DS.Fonts.meta).foregroundStyle(DS.Colors.alert).lineLimit(2)
            }
        }
    }
}

// MARK: - 邮件测试连接行（拉一次 IMAP，成功显示未读条数 / 失败显示原因）

private struct EmailConnectionTestRow: View {
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
                ProgressView().controlSize(.small)
                Spacer()
            case .success(let count):
                Text("✓ 连接正常 · \(count) 封新邮件")
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

            Button { runTest() } label: {
                Text(state == .testing ? "测试中…" : "测试连接")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.accent)
            }
            .buttonStyle(.plain)
            .disabled(state == .testing)
        }
    }

    private func runTest() {
        // 测试所有已接入来源：O365(Graph) + Gmail(IMAP XOAUTH2) + 其它 IMAP(应用密码)
        var services: [EmailService] = []
        if MicrosoftOAuth.shared.isSignedIn { services.append(GraphEmailService()) }
        if GoogleOAuth.shared.isSignedIn, !GoogleOAuth.shared.accountEmail.isEmpty {
            let email = GoogleOAuth.shared.accountEmail
            services.append(RealEmailService(host: "imap.gmail.com", email: email,
                                             auth: .oauth { try await GoogleOAuth.shared.validAccessToken() }))
        }
        // 手动「IMAP + 应用密码」兜底通道暂停用（恢复时取消注释，与 currentEmailServices 同步）
        // let host = store.settings.emailImapHost, email = store.settings.emailAddress, password = store.emailAppPassword
        // if !host.isEmpty, !email.isEmpty, !password.isEmpty, !AppDelegate.isOffice365IMAP(host) {
        //     services.append(RealEmailService(host: host, email: email, auth: .password(password)))
        // }
        guard !services.isEmpty else {
            state = .failure("请先用 Microsoft / Gmail 登录")
            return
        }
        state = .testing
        Task { @MainActor in
            var total = 0
            for service in services {
                do {
                    total += try await service.fetchNewMessages().count
                } catch let EmailServiceError.server(reason) {
                    NSLog("[EmailTest] server rejected: \(reason)")
                    state = .failure("服务器拒绝：\(reason)"); return
                } catch {
                    NSLog("[EmailTest] transport error: \(error)")
                    state = .failure("连不上：\(error.localizedDescription)"); return
                }
            }
            state = .success(total)
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

// MARK: - 轮询间隔选择（30s/1min/2min/5min 下拉）

private struct SettingsPollIntervalPicker: View {
    @Binding var seconds: Int
    @State private var hovering = false

    private static let options: [(value: Int, label: String)] = [
        (5, "5 秒"), (30, "30 秒"), (60, "1 分钟"), (120, "2 分钟"), (300, "5 分钟"),
    ]

    private var currentLabel: String {
        Self.options.first { $0.value == seconds }?.label ?? "\(seconds) 秒"
    }

    var body: some View {
        Menu {
            ForEach(Self.options, id: \.value) { option in
                Button {
                    seconds = option.value
                } label: {
                    if option.value == seconds {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentLabel)
                    .font(DS.Fonts.compactSide)
                    .foregroundStyle(hovering ? DS.Colors.text1 : DS.Colors.text3)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(DS.Colors.text3)
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}
