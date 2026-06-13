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
    @State private var editingField: EditField?
    @State private var aiExpanded = false
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

    // MARK: - meta 徽章行（点 badge → 下方展开可选 chip）
    // 用自绘 Button 而非 SwiftUI Menu —— Menu 在非激活的 accessory NSPanel 里不渲染标签

    private enum EditField { case priority, time, lead }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // 优先级 badge 走统一红绿灯色（高红/中橙/低灰），与全 app 一致
                badge(.priority, text: "\(edited.priority.label)优先级",
                      fg: DS.priorityTagFG(edited.priority), bg: DS.priorityTagBG(edited.priority))
                // 显示具体时间点（始终带时间，远日期也不省略）
                badge(.time, text: edited.dueDate.map(dueBadgeLabel) ?? "无截止")
                // 提前提醒：仅在有截止时间时可设（无截止 → 提醒无意义，隐藏）
                if edited.dueDate != nil {
                    badge(.lead, text: Self.leadLabel(edited.reminderLeadMinutes ?? edited.kind.defaultLeadMinutes))
                }
            }
            if let f = editingField {
                optionRow(for: f)
            }
        }
        .padding(.bottom, 12)
    }

    private func badge(_ field: EditField, text: String,
                       fg: Color = DS.Colors.text2, bg: Color = DS.Colors.surface1) -> some View {
        Button {
            store.cardHeld = true
            withAnimation(.easeOut(duration: 0.15)) {
                editingField = (editingField == field) ? nil : field
            }
        } label: {
            metaBadge(text, fg: fg, bg: bg)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func optionRow(for field: EditField) -> some View {
        switch field {
        case .priority:
            HStack(spacing: 6) {
                ForEach(Priority.allCases, id: \.self) { p in
                    optionChip(p.label, selected: edited.priority == p) { edited.priority = p }
                }
            }
        case .lead:
            HStack(spacing: 6) {
                ForEach([0, 5, 15, 30, 60, 120], id: \.self) { m in
                    optionChip(Self.leadChip(m),
                               selected: (edited.reminderLeadMinutes ?? edited.kind.defaultLeadMinutes) == m) {
                        edited.reminderLeadMinutes = m
                    }
                }
            }
        case .time:
            timeEditor
        }
    }

    /// 时间编辑器：快捷预设 + DS 风格日期/时间步进器（不用原生 DatePicker，匹配暗色 UI）
    private var timeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                optionChip("今晚", selected: false) { edited.dueDate = Self.todayAt(hour: 18) }
                optionChip("明早", selected: false) { edited.dueDate = Self.tomorrowAt(hour: 9) }
                optionChip("周五", selected: false) { edited.dueDate = Self.nextFriday() }
                optionChip("无", selected: edited.dueDate == nil) { edited.dueDate = nil }
            }
            if edited.dueDate != nil {
                stepper(label: "日期", value: dueDateLabel,
                        dec: { shiftDue(days: -1) }, inc: { shiftDue(days: 1) })
                stepper(label: "时间", value: dueTimeLabel,
                        dec: { shiftDue(minutes: -30) }, inc: { shiftDue(minutes: 30) })
            }
        }
    }

    /// DS 风格步进器：◀ 值 ▶（保持展开，连续微调）
    private func stepper(label: String, value: String,
                         dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.text3)
                .frame(width: 30, alignment: .leading)
            stepBtn("chevron.left", dec)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.Colors.text1)
                .frame(minWidth: 96)
            stepBtn("chevron.right", inc)
        }
    }

    private func stepBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { store.cardHeld = true; action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.text2)
                .frame(width: 26, height: 24)
                .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func shiftDue(days: Int = 0, minutes: Int = 0) {
        let base = edited.dueDate ?? Self.todayAt(hour: 18)
        let cal = Calendar.current
        edited.dueDate = cal.date(byAdding: DateComponents(day: days, minute: minutes), to: base) ?? base
    }

    /// 日期标签：今天/明天/周X + M/d
    private var dueDateLabel: String {
        guard let due = edited.dueDate else { return "—" }
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        if cal.isDateInToday(due) { f.dateFormat = "'今天' M/d"; return f.string(from: due) }
        if cal.isDateInTomorrow(due) { f.dateFormat = "'明天' M/d"; return f.string(from: due) }
        f.dateFormat = "EEE M/d"; return f.string(from: due)
    }

    private var dueTimeLabel: String {
        edited.dueDate.map(PanelFormat.hm) ?? "—"
    }

    /// 时间 badge 文案：始终带时间（今天/明天 HH:mm；本周 周X HH:mm；更远 M/d HH:mm）
    private func dueBadgeLabel(_ due: Date) -> String {
        let cal = Calendar.current
        let t = PanelFormat.hm(due)
        if cal.isDateInToday(due) { return "今天 \(t)" }
        if cal.isDateInTomorrow(due) { return "明天 \(t)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: due)).day ?? 0
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = (2...6).contains(days) ? "EEE HH:mm" : "M/d HH:mm"
        return f.string(from: due)
    }

    private func optionChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.15)) { editingField = nil }
        } label: {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? DS.Colors.text1 : DS.Colors.text2)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(selected ? DS.Colors.accentSoft : DS.Colors.surface1,
                           in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    /// 提前量 → 文案（nil/0 → 「准点提醒」）
    static func leadLabel(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "准点提醒" }
        if m >= 60 { return m % 60 == 0 ? "提前 \(m / 60) 小时" : "提前 \(m) 分钟" }
        return "提前 \(m) 分钟"
    }

    /// 提前量 → 短 chip 文案
    static func leadChip(_ minutes: Int) -> String {
        guard minutes > 0 else { return "准点" }
        return minutes >= 60 ? "\(minutes / 60)小时" : "\(minutes)分"
    }

    private func metaBadge(_ text: String, fg: Color = DS.Colors.text2, bg: Color = DS.Colors.surface1) -> some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .opacity(0.5)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(bg, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - AI 解释行（外框 [AI] chip + 文案）

    private func aiRow(_ text: String) -> some View {
        Button {
            store.cardHeld = true
            withAnimation(.easeOut(duration: 0.18)) { aiExpanded.toggle() }
        } label: {
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
                    .lineLimit(aiExpanded ? nil : 2)            // 默认 2 行，展开看全文
                    .fixedSize(horizontal: false, vertical: true) // 强制竖向撑开（多行文字标准解）
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: aiExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Colors.text3)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)   // 关键：Button 自身撑满，才会给 label 传有限宽度
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
