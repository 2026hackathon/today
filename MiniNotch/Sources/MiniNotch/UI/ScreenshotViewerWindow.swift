import AppKit
import SwiftUI

// ============================================================
// 截图大图查看器 —— 岛内点击小相机/缩略图后，在「灵动岛上层」弹出原图。
//
// 为什么用独立窗口而非系统「预览」：
// - 灵动岛面板在 .statusBar 层级，系统「预览」是普通窗口只能压在岛下面，
//   且拉起外部 App 会抢前台 → 触发失焦收起，看完还得重新展开。
// - 这里用一个层级高于岛（.statusBar + N）的透明面板把大图盖在岛上层，
//   全程在本 App 内，不抢外部 App 前台。
//
// 交互（友好）：
// - 大图按舒适尺寸居中成卡片（最多屏幕 ~72%，不放大超过原图），不再铺满全屏。
// - 看图当作一次「聚焦模态」：打开期间灵动岛保持不动（不自动收起），
//   关闭后恢复正常悬停收起 —— 由 onWillOpen/onDidClose 回调驱动 store 标志，
//   生命周期完全可控（不会像拉起外部 App 那样卡住）。
// - 点暗背景 / ✕ / Esc 关闭；多张图带左右翻页与计数。
// ============================================================

@MainActor
final class ScreenshotViewerWindowController {
    static let shared = ScreenshotViewerWindowController()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onDidClose: (() -> Void)?

    private init() {}

    /// 在灵动岛上层弹出大图。过滤掉已不存在的文件；无可看的文件则不弹（也不触发回调）。
    /// - Parameters:
    ///   - onWillOpen: 真正弹出前同步回调（置「看图中」标志，让岛先别收）
    ///   - onDidClose: 关闭后回调（清标志，恢复正常收起）
    func show(paths: [String], onWillOpen: () -> Void = {}, onDidClose: @escaping () -> Void = {}) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        teardown() // 重入：先拆旧窗（不触发上一次的 onDidClose，避免标志被错误清除）
        onWillOpen()
        self.onDidClose = onDidClose

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // 高于灵动岛（NotchPanel 用 .statusBar）一档，确保盖在岛上层
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false        // 需要接收点击（翻页/关闭）
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.contentView = NSHostingView(
            rootView: ScreenshotViewerView(paths: existing) { [weak self] in self?.close() }
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()            // 显示但不激活 App、不抢前台
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        installKeyMonitors()
    }

    func close() {
        removeKeyMonitors()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // completion 在主线程回调，跳回 MainActor 拆窗并通知（从 self 读回调，
            // 避免把非 Sendable 的局部闭包捕获进 @Sendable completionHandler）
            MainActor.assumeIsolated {
                guard let self else { return }
                self.teardown()
                let done = self.onDidClose
                self.onDidClose = nil
                done?()
            }
        })
    }

    // MARK: - 私有

    /// Esc 关闭：本 App 非前台时全局监听兜底，前台时本地监听并吞掉事件。
    private func installKeyMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = esc
            MainActor.assumeIsolated { self?.close() }
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.close() }
        }
    }

    private func removeKeyMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
    }

    private func teardown() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

// MARK: - 查看器内容视图

/// 暗背景 + 居中大图卡片（舒适尺寸，不铺满全屏），多张图带左右翻页与计数；点背景/✕ 关闭。
struct ScreenshotViewerView: View {
    let paths: [String]
    let onClose: () -> Void

    @State private var index = 0
    @State private var appeared = false

    private var currentImage: NSImage? {
        guard paths.indices.contains(index) else { return nil }
        return NSImage(contentsOfFile: paths[index])
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 暗背景：点击关闭
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onClose() }

                // 大图卡片：限制在屏幕 ~72% 内、不放大超过原图，点击不关闭
                if let img = currentImage {
                    let size = displaySize(for: img, in: proxy.size)
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 28, y: 12)
                        .contentShape(Rectangle())
                        .onTapGesture {} // 阻止落到背景关闭
                }

                // 翻页（多张）
                if paths.count > 1 {
                    HStack {
                        pageButton(systemName: "chevron.left") { step(-1) }
                        Spacer()
                        pageButton(systemName: "chevron.right") { step(1) }
                    }
                    .padding(.horizontal, 24)
                }

                // 关闭按钮（右上）+ 计数（底部，多张）
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.5), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if paths.count > 1 {
                        Text("\(index + 1) / \(paths.count)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                .padding(22)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.18)) { appeared = true } }
    }

    /// 在容器内按 ~72% 适配，且不放大超过原图自然尺寸
    private func displaySize(for image: NSImage, in container: CGSize) -> CGSize {
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return .zero }
        let maxW = container.width * 0.72
        let maxH = container.height * 0.72
        let scale = min(maxW / natural.width, maxH / natural.height, 1) // min(.., 1) → 不放大
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    private func step(_ delta: Int) {
        let n = paths.count
        guard n > 0 else { return }
        index = ((index + delta) % n + n) % n
    }

    private func pageButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
