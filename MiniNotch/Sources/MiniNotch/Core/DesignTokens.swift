import SwiftUI

// ============================================================
// 设计 tokens —— 数值一比一来自 prototype.html 的 :root。
// UI 一律引用这里，禁止散落魔法数字 / 裸 Color。
// ============================================================

enum DS {

    // MARK: - 颜色

    enum Colors {
        /// 岛体纯黑（和真刘海融为一体，绝不加透明度）
        static let islandBG = Color.black

        static let surface1 = Color.white.opacity(0.06)
        static let surface2 = Color.white.opacity(0.10)
        static let border = Color.white.opacity(0.08)

        static let text1 = Color(red: 0.96, green: 0.96, blue: 0.96)
        static let text2 = Color.white.opacity(0.62)
        static let text3 = Color.white.opacity(0.36)

        /// AI / 可交互提示（去饱和蓝，避免在纯黑岛里刺眼）
        static let accent = Color(red: 0x6A / 255, green: 0xA8 / 255, blue: 0xF5 / 255)
        static let accentSoft = accent.opacity(0.12)
        static let accentStrong = Color(red: 0x8F / 255, green: 0xC0 / 255, blue: 0xFF / 255)

        /// 仅用于 过期/阻塞
        static let alert = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x61 / 255)
        static let alertSoft = alert.opacity(0.13)
        /// 高优先级实心红 chip 底色：更深更饱和，白字才压得住，
        /// 与「中」的淡橙 tint 拉开「实心 vs 描边」的权重差
        static let alertSolid = Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x43 / 255)

        /// 到期前 15min 档预警橙（reminders spec：中强度，与过期红区分）
        static let warning = Color(red: 1.0, green: 0.62, blue: 0.29)
        /// 预警橙的淡底（优先级「中」chip、Snooze 再次提醒卡共用）
        static let warningSoft = warning.opacity(0.15)

        /// 仅用于完成确认
        static let success = Color(red: 0x4C / 255, green: 0xD2 / 255, blue: 0x7D / 255)

        /// 完成时的金色高光
        static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
        /// Snooze 后再次提醒的黄色系底色（reminders spec：与首次红色提醒视觉区分）
        static let goldSoft = gold.opacity(0.13)
    }

    // MARK: - 来源色（Touchdown 涟漪 / 来源标识）

    static func sourceColor(_ source: TodoSource) -> Color {
        switch source {
        case .screenshot: Color(red: 0xAF / 255, green: 0x52 / 255, blue: 0xDE / 255) // 紫
        case .manual: Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)      // 绿
        case .calendar: Color(red: 0xFF / 255, green: 0x95 / 255, blue: 0x00 / 255)    // 橙
        }
    }

    /// 工作项来源色（Jira 蓝 / GitHub PR 紫）
    static func workItemColor(_ source: WorkItemSource) -> Color {
        switch source {
        case .jira: Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0xFF / 255)        // 蓝
        case .github: Color(red: 0x82 / 255, green: 0x50 / 255, blue: 0xDF / 255)      // GitHub PR 紫
        }
    }

    /// 消息来源色（消息卡/页签来源标识）
    static func messageColor(_ source: MessageSource) -> Color {
        switch source {
        case .slack: Color(red: 0x61 / 255, green: 0x1F / 255, blue: 0x69 / 255)  // Slack aubergine
        case .jira: workItemColor(.jira)                                          // 复用 Jira 蓝
        case .email: Colors.accent
        }
    }

    /// 邮件重要级别色（提醒卡/消息行分级样式）：重要红 / 一般蓝 / 次要灰
    static func importanceColor(_ i: MessageImportance) -> Color {
        switch i {
        case .high: Colors.alert
        case .medium: Colors.accent
        case .low: Colors.text3
        }
    }

    // 优先级标签配色（红绿灯三档，全 app 唯一来源，改这里即处处生效）：
    // 高=白字实心红（最响，danger）/ 中=橙字淡橙底（描边感）/ 低=暗灰字淡底。
    // 「高」用实心填充与「中」的 tint 拉开权重差，小尺寸下也一眼可分。
    static func priorityTagFG(_ p: Priority) -> Color {
        switch p {
        case .high: .white
        case .medium: Colors.warning
        case .low: Colors.text3
        }
    }

    static func priorityTagBG(_ p: Priority) -> Color {
        switch p {
        case .high: Colors.alertSolid
        case .medium: Colors.warningSoft
        case .low: Colors.surface1
        }
    }

    // MARK: - 圆角

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
        /// 展开态岛体下沿圆角
        static let island: CGFloat = 24
        static let islandCompact: CGFloat = 18
    }

    // MARK: - 字体（SF Mono 数字 = prototype 的像素感）

    enum Fonts {
        static let compactCount = Font.system(size: 12, weight: .bold, design: .monospaced)
        static let compactSide = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let cardTitle = Font.system(size: 15, weight: .semibold)
        static let todoTitle = Font.system(size: 13, weight: .medium)
        static let meta = Font.system(size: 11)
        static let sectionTitle = Font.system(size: 10, weight: .semibold)
        static let tag = Font.system(size: 10, weight: .medium, design: .monospaced)
        static let button = Font.system(size: 12, weight: .medium)
    }
}

// MARK: - 通用小组件样式

extension View {
    /// prototype `.tag` 小徽章
    func dsTag(_ color: Color = DS.Colors.text3, bg: Color = DS.Colors.surface1) -> some View {
        self.font(DS.Fonts.tag)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(bg, in: RoundedRectangle(cornerRadius: 3))
    }
}
