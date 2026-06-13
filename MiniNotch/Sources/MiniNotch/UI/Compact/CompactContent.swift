import SwiftUI

// ============================================================
// CompactContent —— 收缩态左右内容。
// 对应 prototype.html STATES: idle / normal / near / urgent /
// ai / done1（+ celebrate 皇冠变体）。
// 中央被硬件摄像头占据，内容分居左右两翼（各约 75pt）。
// ============================================================

struct CompactContent: View {
    let state: IslandState      // 只会收到 compact 类 state
    let notchWidth: CGFloat     // 硬件刘海宽度，中央这一段禁止放内容
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            leftContent
            Spacer(minLength: notchWidth)
            rightContent
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 左翼（图标 + 数字）

    @ViewBuilder
    private var leftContent: some View {
        HStack(spacing: 6) {
            todoLeftContent
            // agent 徽章（Claude Code + opencode 汇总）：运行中 ⚙ + 等待确认 🔔 并排，
            // 铃铛紧贴活动 session 右侧（用户指定布局，agent-session spec）
            if store.activeAgentCount > 0 {
                AgentBadge(
                    systemName: "cpu",
                    count: store.activeAgentCount,
                    color: DS.Colors.accent,
                    pulsing: true
                )
            }
            if store.waitingAgentCount > 0 {
                AgentBadge(
                    systemName: "bell.badge.fill",
                    count: store.waitingAgentCount,
                    color: DS.Colors.warning,
                    pulsing: true
                )
            }
            // 提前准备徽章（prep-reminder-card spec）：高优先级 prep 收起后常驻，
            // 点击重开 prep 卡；任务临近/完成时自动清除
            if store.hasPrepBadge {
                AgentBadge(
                    systemName: "hourglass",
                    count: store.prepBadgeCount,
                    color: DS.Colors.warning,
                    pulsing: true
                )
                .contentShape(Rectangle())
                .onTapGesture { store.reopenPrep() }
            }
        }
    }

    @ViewBuilder
    private var todoLeftContent: some View {
        HStack(spacing: 6) {
            switch state {
            case .idle:
                // 左翼维持「清单 + 今日总数」（含只读 ticket，与面板口径一致）；
                // "做完了"的打钩放右翼（用户指定布局）。统一亮白，与 normal 一致
                compactIcon("list.bullet", color: DS.Colors.text1)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            case .near:
                // 提前 1h 档：弱脉冲（F-04 动效分级）
                SoftPulseIcon(systemName: "clock.fill", color: DS.Colors.text2)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            case .urgent:
                // 15min 内 = 预警橙；已过期才转红（F-04：中=橙色脉冲，极强=红持续闪烁）
                BlinkingIcon(systemName: "exclamationmark.triangle.fill", color: urgentColor)
                countText("\(store.todayFocusCount)", color: urgentColor)
            case .aiWorking:
                PulsingSparkleIcon()
                Text("AI")
                    .font(DS.Fonts.compactSide.weight(.bold))
                    .foregroundStyle(DS.Colors.accent)
            case .justCompleted:
                compactIcon("checkmark.circle.fill", color: DS.Colors.success)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            case .celebrate:
                compactIcon("crown.fill", color: DS.Colors.gold)
                countText("0", color: DS.Colors.text1)
            default: // .normal 及兜底：清单 + 今日焦点数，亮白（与 agent 蓝/铃铛橙区分）
                compactIcon("list.bullet", color: DS.Colors.text1)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            }
        }
    }

    // MARK: - 右翼（上下文）

    @ViewBuilder
    private var rightContent: some View {
        // 右翼回归 todo 上下文；agent 徽章统一放左翼（铃铛紧贴活动 session）
        switch state {
        case .idle:
            // 今日可动手的事清零 → 右翼绿色打钩（用户指定放这一侧）
            compactIcon("checkmark.circle.fill", color: DS.Colors.success)
        case .celebrate:
            sideText("Clear", color: DS.Colors.text3)
        case .near:
            sideText("\(minutesToNextDue) min", color: DS.Colors.text2)
        case .urgent:
            sideText(isOverdue ? "Overdue" : "\(minutesToNextDue) min", color: urgentColor)
        case .aiWorking:
            BouncingDots()
        case .justCompleted:
            sideText("−1 done", color: DS.Colors.text2)
        default: // .normal 及兜底
            // 今日还有定时项 → 下一个截止时间；今日的提醒/会议都清空了 →
            // 不再向前看「明天 / Next 周一」(用户指定:今天的都完成了就别提示明天)，
            // 改用图标表达「今日日程已清空」
            if let due = store.todayNextDue {
                sideText("Next \(due.dsHHmm)", color: DS.Colors.text2)
            } else {
                compactIcon("calendar.badge.checkmark", color: DS.Colors.success)
            }
        }
    }

    // MARK: - 派生

    /// 距今日最近截止的分钟数（向上取整，不小于 0）
    private var minutesToNextDue: Int {
        guard let due = store.todayNextDue else { return 0 }
        return max(0, Int((due.timeIntervalSinceNow / 60).rounded(.up)))
    }

    private var isOverdue: Bool {
        guard let due = store.todayNextDue else { return false }
        return due.timeIntervalSinceNow <= 0
    }

    /// urgent 态配色：到期前 15min 预警橙，已过期红（F-04 分级）
    private var urgentColor: Color {
        isOverdue ? DS.Colors.alert : DS.Colors.warning
    }

    // MARK: - 小构件

    private func compactIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }

    private func countText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DS.Fonts.compactCount)
            .foregroundStyle(color)
    }

    private func sideText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DS.Fonts.compactSide)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Agent 会话徽章（图标 + 计数，可选弱脉冲）

private struct AgentBadge: View {
    let systemName: String
    let count: Int
    let color: Color
    var pulsing = false
    @State private var dimmed = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(DS.Fonts.compactCount)
        }
        .foregroundStyle(color)
        .opacity(dimmed ? 0.5 : 1)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
    }
}

// MARK: - 动画小组件（prototype: anim-blink / anim-sparkle / anim-walk）

/// near 态弱脉冲：透明度 0.55–1 缓慢呼吸（F-04「提前 1h：弱（脉冲）」）
private struct SoftPulseIcon: View {
    let systemName: String
    let color: Color
    @State private var dimmed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .opacity(dimmed ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

/// urgent 态 0.9s 闪烁（prototype urgentPulse 0.9s）
private struct BlinkingIcon: View {
    let systemName: String
    let color: Color
    @State private var dimmed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

/// aiWorking 态 sparkles 微动画
private struct PulsingSparkleIcon: View {
    @State private var up = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.Colors.accent)
            .scaleEffect(up ? 1.12 : 0.86)
            .opacity(up ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}

/// aiWorking 态右翼三个点点跳动
private struct BouncingDots: View {
    @State private var up = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(DS.Colors.accent)
                    .frame(width: 3, height: 3)
                    .offset(y: up ? -2 : 2)
                    .animation(
                        .easeInOut(duration: 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: up
                    )
            }
        }
        .onAppear { up = true }
    }
}

// MARK: - 截止时间显示格式（全 UI 模块共享，只在此处定义一次）

extension Date {
    /// 今天 →「今晚 18:00」/「HH:mm」；明天 →「明天」；
    /// 2-6 天 →「周X」；更远 →「M/d」；已过去的日期同样落到 M/d。
    var dsShortLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            let hour = cal.component(.hour, from: self)
            return hour >= 17 ? "今晚 \(dsHHmm)" : dsHHmm
        }
        if cal.isDateInTomorrow(self) { return "明天" }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: Date()),
            to: cal.startOfDay(for: self)
        ).day ?? 0
        if (2...6).contains(days) {
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            return names[cal.component(.weekday, from: self) - 1]
        }
        let comps = cal.dateComponents([.month, .day], from: self)
        return "\(comps.month ?? 1)/\(comps.day ?? 1)"
    }

    /// 24 小时制「HH:mm」
    var dsHHmm: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
