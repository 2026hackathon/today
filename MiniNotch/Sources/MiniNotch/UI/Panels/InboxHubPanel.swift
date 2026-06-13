import SwiftUI

// ============================================================
// InboxHubPanel —— 「收件 Inbox」tab：邮件消息 + @我提及 合并。
// 顶部一个分段切换（消息 / 提及），各带未读计数；下方渲染对应内容。
// 内容来自 MessageInboxPanel（消息，owner 队友）与 MentionsContent（提及）。
// 纯内容视图，外层 TodayPanel 已套 PanelTabBar + PanelScrollView。
// ============================================================

struct InboxHubPanel: View {
    @EnvironmentObject var store: AppStore

    enum Segment { case messages, mentions }
    @State private var segment: Segment = .messages

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            segmentBar
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)

            switch segment {
            case .messages: MessageInboxPanel()
            case .mentions: MentionsContent()
            }
        }
    }

    private var segmentBar: some View {
        HStack(spacing: 6) {
            segButton("Email", count: store.unprocessedMessageCount, active: segment == .messages) {
                segment = .messages
            }
            segButton("Mentions", count: store.unreadMentions.count, active: segment == .mentions) {
                segment = .mentions
            }
            Spacer()
        }
    }

    private func segButton(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(DS.Fonts.button)
                    .foregroundStyle(active ? DS.Colors.text1 : DS.Colors.text3)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? DS.Colors.text1 : DS.Colors.text3)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16)
                        .background(
                            (active ? DS.Colors.accent.opacity(0.25) : DS.Colors.surface2),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .buttonStyle(.plain)
    }
}
