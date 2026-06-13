import AppKit
import SwiftUI

// ============================================================
// MentionsContent —— @我提及内容（只读跳转），嵌在「收件 Inbox」tab 的分段里。
// 数据来自 MentionService（Jira 评论@我 + Confluence 页面@我）。
// 纯内容（无自带 tab bar / ScrollView），由 InboxHubPanel 包裹。
// ============================================================

struct MentionsContent: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        if store.unreadMentions.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(store.unreadMentions.count) 条未读提及")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
            ForEach(store.unreadMentions) { mention in
                MentionRow(mention: mention) {
                    store.markMentionRead(mention)   // 点开即已读，从未读列表消失
                    if let url = mention.url { NSWorkspace.shared.open(url) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "at")
                .font(.system(size: 24))
                .foregroundStyle(DS.Colors.text3)
            Text("没有未读的@我")
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text3)
            Text("Jira 评论、Confluence 页面里@你时会汇总到这里；点开即已读")
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text3)
        }
        .frame(maxWidth: .infinity, minHeight: 380)
    }
}

// MARK: - 提及行（来源图标 + 标题 + 上下文 → 整行点击跳转）

private struct MentionRow: View {
    let mention: Mention
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BrandIcon(brand: mention.source == .jira ? .jira : .confluence, size: 12)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(mention.title)
                    .font(DS.Fonts.todoTitle)
                    .foregroundStyle(DS.Colors.text1)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(mention.source == .jira ? "Jira" : "Confluence")
                        .dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
                    if let ctx = mention.context, !ctx.isEmpty {
                        Text(ctx).dsTag()
                    }
                    if let updated = mention.updated {
                        Text(updated.dsShortLabel)
                            .font(DS.Fonts.meta)
                            .foregroundStyle(DS.Colors.text3)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.text3)
                .opacity(hovering ? 1 : 0)
                .padding(.top, 2)
        }
        .padding(8)
        .background(hovering ? DS.Colors.surface1 : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
    }
}
