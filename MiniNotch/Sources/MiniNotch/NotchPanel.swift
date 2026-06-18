import AppKit
import SwiftUI

/// 灵动岛当前可交互区域 —— 由 `IslandRootView` 实测壳体尺寸后写入，
/// 供 `PassthroughHostingView` 在命中测试时把"岛体之外的透明区"放行给下方应用。
final class IslandHitRegion {
    var islandSize: CGSize?
    /// 最近一次有效壳体尺寸；首帧未实测时用于估算命中区（避免整窗误挡）
    private(set) var lastKnownSize = CGSize(width: 350, height: 40)

    var effectiveSize: CGSize {
        if let s = islandSize, s.width > 0, s.height > 0 { return s }
        return lastKnownSize
    }

    func update(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        islandSize = size
        lastKnownSize = size
    }

    init() {}
}

/// 穿透型 hosting view —— 面板固定为可容纳最大展开态的大窗，但只有岛体当前
/// 实际渲染所覆盖的矩形接收点击，其余透明区域返回 nil 让点击穿透到下方应用。
/// （island-shell spec：不打扰的窗口行为 —— 透明区点击穿透）
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    private let hitSlopX: CGFloat = 6
    private let hitSlopTop: CGFloat = 4
    /// 辉光向下溢出，底部不加容差，避免挡下方 IDE tab / 工具栏
    private let hitSlopBottom: CGFloat = 0

    private let hitRegion: IslandHitRegion

    init(rootView: Content, hitRegion: IslandHitRegion) {
        self.hitRegion = hitRegion
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required init(rootView: Content) {
        fatalError("use init(rootView:hitRegion:)")
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let size = hitRegion.effectiveSize
        let w = size.width + hitSlopX * 2
        let h = size.height + hitSlopTop + hitSlopBottom
        let x = bounds.midX - w / 2
        // NSHostingView 为 flipped 坐标（原点在左上）；岛体 alignment: .top → y 从 0 向下
        let y = isFlipped ? bounds.minY : (bounds.maxY - h)
        let islandRect = NSRect(x: x, y: y, width: w, height: h)
        guard islandRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

/// 不抢焦点的悬浮窗口 —— Vibe Island / Boring Notch 这类应用的核心。
///
/// 关键点：
/// 1. `nonactivatingPanel`：点击面板不会激活 App、不抢编辑器焦点
/// 2. `canBecomeKey = true` + `canBecomeMain = false`：仍能接收键盘事件
/// 3. `collectionBehavior`：在所有 Space 显示，包括全屏 App 上方
/// 4. `level = .statusBar`：层级高于普通窗口，能盖在刘海上方
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        // 岛体永远是深色 UI——强制窗口深色外观，让原生控件（DatePicker / Toggle /
        // Stepper / Menu）也渲染深色变体，否则浅色模式下会冒出白底控件（如编辑卡的日期选择器白框）。
        self.appearance = NSAppearance(named: .darkAqua)

        // 在所有 Space 显示 + 覆盖全屏窗口
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// accessory 应用没有主菜单，⌘V/⌘C 等编辑快捷键没有 Edit 菜单可分发，
    /// 系统会直接丢弃 —— 这里手动路由给响应链，面板里的输入框才能粘贴/复制
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if modifiers == .command {
            switch key {
            case "v": if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "c": if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "x": if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a": if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z": if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default: break
            }
        } else if modifiers == [.command, .shift], key == "z" {
            if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
