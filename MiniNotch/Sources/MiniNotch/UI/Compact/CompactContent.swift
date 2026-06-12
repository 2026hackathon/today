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
            switch state {
            case .idle:
                compactIcon("tray", color: DS.Colors.text3)
                countText("0", color: DS.Colors.text3)
            case .near:
                compactIcon("clock", color: DS.Colors.text2)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            case .urgent:
                BlinkingIcon(systemName: "exclamationmark.triangle", color: DS.Colors.alert)
                countText("\(store.todayFocusCount)", color: DS.Colors.alert)
            case .aiWorking:
                PulsingSparkleIcon()
                Text("AI")
                    .font(DS.Fonts.compactSide.weight(.bold))
                    .foregroundStyle(DS.Colors.accent)
            case .justCompleted:
                compactIcon("checkmark", color: DS.Colors.success)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            case .celebrate:
                compactIcon("crown.fill", color: DS.Colors.gold)
                countText("0", color: DS.Colors.text1)
            default: // .normal 及兜底
                compactIcon("tray", color: DS.Colors.text2)
                countText("\(store.todayFocusCount)", color: DS.Colors.text1)
            }
        }
    }

    // MARK: - 右翼（上下文）

    @ViewBuilder
    private var rightContent: some View {
        switch state {
        case .idle, .celebrate:
            sideText("清空", color: DS.Colors.text3)
        case .near:
            sideText("\(minutesToNextDue) 分钟", color: DS.Colors.text2)
        case .urgent:
            sideText(isOverdue ? "已超时" : "\(minutesToNextDue) 分钟", color: DS.Colors.alert)
        case .aiWorking:
            BouncingDots()
        case .justCompleted:
            sideText("−1 完成", color: DS.Colors.text2)
        default: // .normal 及兜底
            if let due = store.nextDue {
                sideText("下个 \(due.dsHHmm)", color: DS.Colors.text2)
            } else {
                sideText("今日", color: DS.Colors.text2)
            }
        }
    }

    // MARK: - 派生

    /// 距最近截止的分钟数（向上取整，不小于 0）
    private var minutesToNextDue: Int {
        guard let due = store.nextDue else { return 0 }
        return max(0, Int((due.timeIntervalSinceNow / 60).rounded(.up)))
    }

    private var isOverdue: Bool {
        guard let due = store.nextDue else { return false }
        return due.timeIntervalSinceNow <= 0
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

// MARK: - 动画小组件（prototype: anim-blink / anim-sparkle / anim-walk）

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
