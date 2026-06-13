import AppKit
import SwiftUI

// ============================================================
// MessageLandedCard —— 新邮件消息降落通知卡（island-shell spec）。
// 沿用 JiraLandedCard 的样式与节奏：5s 倒计时 + 悬停暂停 + 收入灵动岛。
//   - 同轮多条新消息聚合为「N 条新消息」（moreCount）
//   - 点击卡片 → 打开链接并标记已处理（markProcessed），随后收回
// ============================================================

struct MessageLandedCard: View {
    let message: Message
    /// 同轮其余新消息数（>0 聚合显示「N 条新消息」）
    let moreCount: Int
    @EnvironmentObject var store: AppStore

    private static let duration: Double = 5.0

    @State private var remaining = MessageLandedCard.duration
    @State private var hovering = false
    @State private var collecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            summaryBlock
            metaRow
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, 36) // 摄像头区留位
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { countdownBar }
        .scaleEffect(collecting ? 0.05 : 1, anchor: .top)
        .opacity(collecting ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { openAndCollect() }
        .onHover { hovering = $0 }
        .task(id: message.id) { await runCountdown() }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: message.source.iconSymbol)
                .font(.system(size: 12))
                .foregroundStyle(sourceColor)
            Text("新消息 · \(message.source.label)")
                .font(DS.Fonts.meta.weight(.medium))
                .foregroundStyle(DS.Colors.text2)
            Spacer(minLength: 0)
            Text(message.receivedAt.dsHHmm)
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
        .padding(.bottom, 10)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sender = message.sender {
                Text(sender)
                    .font(DS.Fonts.compactSide.weight(.semibold))
                    .foregroundStyle(sourceColor)
            }
            Text(message.summary)
                .font(DS.Fonts.cardTitle)
                .foregroundStyle(DS.Colors.text1)
                .lineLimit(3)
        }
        .padding(.bottom, 10)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            if moreCount > 0 {
                Text("等 \(moreCount + 1) 条新消息")
                    .dsTag(DS.Colors.accent, bg: DS.Colors.accentSoft)
            }
            Spacer(minLength: 0)
            Text(message.link == nil ? "点击完成" : "点击查看")
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.bottom, 6)
    }

    private var countdownBar: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(sourceColor.opacity(0.8))
                .frame(width: geo.size.width * remaining / Self.duration, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }

    private var sourceColor: Color { DS.messageColor(message.source) }

    // MARK: - 倒计时与收回

    private func runCountdown() async {
        while remaining > 0 {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
            if !hovering {
                remaining = max(0, remaining - 0.05)
            }
        }
        await collect()
    }

    /// 点击 = 打开链接（有则）+ 标记已处理 + 收回（message-inbox spec：跳转即已处理）
    private func openAndCollect() {
        if let url = message.link {
            NSWorkspace.shared.open(url)
        }
        store.markProcessed(message)
        Task { await collect() }
    }

    private func collect() async {
        guard !collecting else { return }
        withAnimation(.easeIn(duration: 0.22)) { collecting = true }
        try? await Task.sleep(for: .milliseconds(220))
        // 倒计时期间状态可能已被其他事件抢占，只在仍是本卡时回落
        if case .messageLanded(let current, _) = store.islandState, current.id == message.id {
            store.dismiss()
        }
    }
}
