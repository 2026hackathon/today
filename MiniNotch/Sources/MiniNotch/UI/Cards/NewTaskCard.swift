import SwiftUI

// ============================================================
// NewTaskCard —— AI 识别到新任务的「任务降落卡」。
// 对应 prototype.html STATES.newtask。
// 草稿即编辑：标题可直接输入，徽章点击即改，无独立编辑模式。
// ============================================================

struct NewTaskCard: View {
    let draft: TodoDraft
    @EnvironmentObject var store: AppStore

    /// 可编辑副本（保存时以此为准）
    @State private var edited: TodoDraft
    @State private var titleHovered = false
    @FocusState private var titleFocused: Bool

    init(draft: TodoDraft) {
        self.draft = draft
        _edited = State(initialValue: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            titleField
            metaRow
            if let explanation = edited.aiExplanation, !explanation.isEmpty {
                aiRow(explanation)
            }
            actions
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    // MARK: - 头部（sparkles + 标签 + 来源 tag + 发丝分隔线）

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                Text("AI 识别到新任务")
                    .font(DS.Fonts.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.text2)
                Spacer()
                sourceTag
            }
            Rectangle()
                .fill(DS.Colors.border)
                .frame(height: 1)
        }
        .padding(.bottom, 10)
    }

    private var sourceTag: some View {
        HStack(spacing: 5) {
            Image(systemName: Self.sourceIcon(edited.source))
                .font(.system(size: 9))
                .foregroundStyle(DS.Colors.text3)
            Text(edited.source.label)
        }
        .font(DS.Fonts.tag)
        .foregroundStyle(DS.Colors.text3)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: 4))
    }

    private static func sourceIcon(_ source: TodoSource) -> String {
        switch source {
        case .screenshot: "camera"
        case .manual: "square.and.pencil"
        case .calendar: "calendar"
        }
    }

    // MARK: - 可编辑标题（hover/focus 才显出输入感）

    private var titleField: some View {
        TextField("任务标题…", text: $edited.title)
            .textFieldStyle(.plain)
            .font(DS.Fonts.cardTitle)
            .foregroundStyle(DS.Colors.text1)
            .focused($titleFocused)
            .onChange(of: titleFocused) { _, focused in
                // 开始输入标题 → 解除自动收回（review-fixes #8）
                if focused { store.cardHeld = true }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                (titleHovered || titleFocused) ? DS.Colors.surface1 : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .onHover { titleHovered = $0 }
            .padding(.bottom, 10)
    }

    // MARK: - meta 徽章行（点击修改优先级 / 时间）

    private var metaRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button("\(p.label)优先级") { edited.priority = p }
                }
            } label: {
                metaBadge("\(edited.priority.label)优先级", isAlert: edited.priority == .high)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Button("今晚 18:00") { edited.dueDate = Self.todayAt(hour: 18) }
                Button("明天 09:00") { edited.dueDate = Self.tomorrowAt(hour: 9) }
                Button("周五") { edited.dueDate = Self.nextFriday() }
                Button("无截止") { edited.dueDate = nil }
            } label: {
                metaBadge(edited.dueDate?.dsShortLabel ?? "无截止", isAlert: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // 提前提醒：仅在有截止时间时可设（无截止 → 提醒无意义，隐藏）
            if edited.dueDate != nil {
                Menu {
                    Button("提前 5 分钟") { edited.reminderLeadMinutes = 5 }
                    Button("提前 15 分钟") { edited.reminderLeadMinutes = 15 }
                    Button("提前 30 分钟") { edited.reminderLeadMinutes = 30 }
                    Button("提前 1 小时") { edited.reminderLeadMinutes = 60 }
                    Button("不提前") { edited.reminderLeadMinutes = 0 }
                } label: {
                    metaBadge(Self.leadLabel(edited.reminderLeadMinutes ?? edited.kind.defaultLeadMinutes), isAlert: false)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.bottom, 12)
    }

    /// 提前量 → 文案（nil/0 → 「准点提醒」）
    static func leadLabel(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "准点提醒" }
        if m >= 60 { return m % 60 == 0 ? "提前 \(m / 60) 小时" : "提前 \(m) 分钟" }
        return "提前 \(m) 分钟"
    }

    private func metaBadge(_ text: String, isAlert: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .opacity(0.5)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(isAlert ? DS.Colors.alert : DS.Colors.text2)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            isAlert ? DS.Colors.alertSoft : DS.Colors.surface1,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - AI 解释行（外框 [AI] chip + 文案）

    private func aiRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("AI")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(DS.Colors.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(DS.Colors.accent, lineWidth: 1)
                )
            Text(text)
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text2)
                .lineSpacing(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        .padding(.bottom, 14)
    }

    // MARK: - 操作（保存 / 忽略）

    private var actions: some View {
        // 主操作（保存）靠右：macOS 默认按钮在尾部，且与 EditTask/QuickInput 卡保持一致
        HStack(spacing: 6) {
            Button("忽略") { store.dismiss() }
                .buttonStyle(DSGhostButtonStyle())
            Button("保存") { save() }
                .buttonStyle(DSPrimaryButtonStyle())
        }
    }

    private func save() {
        var final = edited
        if final.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            final.title = draft.title    // 防止把标题清空后保存
        }
        store.add(final.toTodo())
        store.dismiss()
    }

    // MARK: - 快捷时间

    private static func todayAt(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func tomorrowAt(hour: Int) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func nextFriday() -> Date {
        let cal = Calendar.current
        return cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 18, minute: 0, weekday: 6),
            matchingPolicy: .nextTime
        ) ?? Date()
    }
}

// ============================================================
// 共享按钮样式（其他卡片复用）—— prototype .btn.primary / .btn.ghost
// ============================================================

/// 白底黑字主按钮（prototype: 纯黑岛上的白色填充）
struct DSPrimaryButtonStyle: ButtonStyle {
    /// false 时不撑满父容器（quickInput 的固定宽按钮）
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Fonts.button.weight(.semibold))
            .foregroundStyle(DS.Colors.islandBG)
            .padding(.horizontal, fullWidth ? 0 : 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 32)
            .background(
                DS.Colors.text1.opacity(configuration.isPressed ? 0.88 : 1),
                in: RoundedRectangle(cornerRadius: DS.Radius.s)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s))
    }
}

/// 透明 ghost 按钮
struct DSGhostButtonStyle: ButtonStyle {
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Fonts.button)
            .foregroundStyle(configuration.isPressed ? DS.Colors.text1 : DS.Colors.text2)
            .padding(.horizontal, fullWidth ? 0 : 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 32)
            .background(
                configuration.isPressed ? DS.Colors.surface1 : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.s)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s))
    }
}
