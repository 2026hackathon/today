import AppKit
import SwiftUI

// ============================================================
// MessageInboxPanel —— 「消息」页签（message-inbox spec）。
// 邮件提炼的一句话提醒，按接收时间倒序：
//   未处理 = 白色/常规；已处理 = 灰色弱化。
//   每条「点击完成」或「点击跳转」——两者都标记已处理（markProcessed 幂等）。
// 嵌在 TodayPanel 的 ScrollView 内（tab == .messages 时渲染）。
// ============================================================

struct MessageInboxPanel: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 12)

            if store.messages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.Colors.text3)
                    Text("还没有收到消息")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text3)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            }

            ForEach(store.sortedMessages) { message in
                MessageRow(message: message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        let unread = store.unprocessedMessageCount
        return unread > 0 ? "\(unread) 条未处理消息" : "消息已清空"
    }
}

// MARK: - 消息行

private struct MessageRow: View {
    let message: Message
    @EnvironmentObject var store: AppStore
    @State private var hovering = false

    private var processed: Bool { message.isProcessed }
    /// 未处理白、已处理灰（message-inbox spec）
    private var titleColor: Color { processed ? DS.Colors.text3 : DS.Colors.text1 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 完成圈：点击 = 标记已处理（不打开链接）
            PanelCheckCircle(action: { store.markProcessed(message) })
                .opacity(processed ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.summary)
                    .font(DS.Fonts.todoTitle)
                    .foregroundStyle(titleColor)
                    .strikethrough(processed, color: DS.Colors.text3)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: message.source.iconSymbol).font(.system(size: 8))
                        Text(message.source.label)
                    }
                    .dsTag(processed ? DS.Colors.text3 : DS.messageColor(message.source),
                           bg: DS.Colors.surface1)
                    if let sender = message.sender {
                        Text(sender)
                            .font(DS.Fonts.meta)
                            .foregroundStyle(DS.Colors.text3)
                    }
                    Text(message.receivedAt.dsShortLabel)
                        .font(DS.Fonts.meta)
                        .foregroundStyle(DS.Colors.text3)
                }
            }
            Spacer(minLength: 0)
            // 跳转：打开链接 + 标记已处理（message-inbox spec：跳转即已处理）
            if message.link != nil {
                Button(action: openAndProcess) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(processed ? DS.Colors.text3 : DS.Colors.accent)
                        .opacity(hovering || !processed ? 1 : 0.4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .onHover { hovering = $0 }
    }

    private func openAndProcess() {
        if let url = message.link { NSWorkspace.shared.open(url) }
        store.markProcessed(message)
    }
}
