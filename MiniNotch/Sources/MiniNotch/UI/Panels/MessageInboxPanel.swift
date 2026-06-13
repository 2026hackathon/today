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
    @State private var showProcessed = false

    /// 未处理在上（按时间倒序），已处理收进底部折叠区
    private var pending: [Message] { store.sortedMessages.filter { !$0.isProcessed } }
    private var processed: [Message] { store.sortedMessages.filter { $0.isProcessed } }

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

            ForEach(pending) { message in
                MessageRow(message: message)
            }

            if !processed.isEmpty {
                processedFold
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 已处理折叠（与 Today「已完成」一致）：默认收起，点开看历史
    private var processedFold: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(IslandAnimation.spring) { showProcessed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showProcessed ? "▾" : "▸")
                    Text("已处理 (\(processed.count))")
                }
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if showProcessed {
                ForEach(processed) { message in
                    MessageRow(message: message)
                }
            }
        }
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
    /// 分级样式主色（已处理统一灰）
    private var levelColor: Color { processed ? DS.Colors.text3 : DS.importanceColor(message.importance) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左侧分级竖条：重要红 / 一般蓝 / 次要灰（已处理转灰）
            RoundedRectangle(cornerRadius: 1.5)
                .fill(levelColor.opacity(processed ? 0.3 : 0.9))
                .frame(width: 3)
                .padding(.vertical, 1)

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
                    // 重要级别标签（分级样式）
                    Text(message.importance.label)
                        .dsTag(levelColor, bg: processed ? DS.Colors.surface1 : levelColor.opacity(0.14))
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
