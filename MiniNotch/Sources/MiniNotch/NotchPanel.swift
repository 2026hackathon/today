import AppKit
import SwiftUI

/// 灵动岛当前可交互区域 —— 由 `IslandRootView` 实测壳体尺寸后写入，
/// 供 `PassthroughHostingView` 在命中测试时把"岛体之外的透明区"放行给下方应用。
/// `islandSize == nil` 表示尚未实测（启动首帧），命中测试回退为整窗捕获（安全侧）。
///
/// 注意：glow 溢光（SwiftGlow 的 Metal 层）本身不参与命中（`hitTest → nil` +
/// `allowsHitTesting(false)`），且 `islandSize` 在挂 glow 之前实测，所以发光态不会
/// 放大命中区。命中范围只跟随岛体壳体（含圆角）。
final class IslandHitRegion {
    var islandSize: CGSize?
    /// 壳体下沿圆角半径（compact 18 / 展开 24），用于把命中区收成与岛体同形的 NotchShape
    var cornerRadius: CGFloat = 0
    init() {}
}

/// 穿透型 hosting view —— 面板固定为可容纳最大展开态的大窗，但只有岛体当前
/// 实际渲染所覆盖的矩形接收点击，其余透明区域返回 nil 让点击穿透到下方应用。
/// （island-shell spec：不打扰的窗口行为 —— 透明区点击穿透）
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// 贴边命中容差：只向外放宽这么点，避免点岛体边缘差一两像素点不到。
    /// 必须保持小——它会把岛体下方/两侧的下层应用 UI 一并吞掉（之前 6pt 会在岛体
    /// 下沿额外留出 ~12pt 死区，挡住紧贴刘海的他应用按钮）。
    private let hitSlop: CGFloat = 2

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
        // 尚未实测尺寸 → 维持整窗捕获，绝不误穿透
        guard let size = hitRegion.islandSize else { return super.hitTest(point) }
        // 命中区按"可见岛体轮廓（NotchShape：上沿直角、下沿圆角）"裁剪，而不是外接矩形。
        // 这样圆角缺口、岛体下沿之外、以及 glow 光晕区都放行给下方应用，
        // 紧贴刘海的他应用 UI（标签栏 / 输入框 / 按钮）不再被吞。
        guard islandHitPath(islandSize: size).contains(point) else { return nil }
        return super.hitTest(point)
    }

    /// 与可见岛体同形的命中路径（hosting view 非 flipped，AppKit 左下原点 → 岛顶在 bounds.maxY）。
    /// 仅向外放宽 `hitSlop` 一点点容差；下沿两角按壳体圆角收成弧形。
    private func islandHitPath(islandSize size: CGSize) -> NSBezierPath {
        let left = bounds.midX - size.width / 2 - hitSlop
        let right = bounds.midX + size.width / 2 + hitSlop
        let top = bounds.maxY                              // 岛顶贴窗顶，不向屏幕外延伸
        let bottom = bounds.maxY - size.height - hitSlop
        let r = max(0, min(hitRegion.cornerRadius, (right - left) / 2, (top - bottom) / 2))

        let path = NSBezierPath()
        path.move(to: NSPoint(x: left, y: top))            // 左上（直角）
        path.line(to: NSPoint(x: right, y: top))           // 上沿 → 右上（直角）
        path.line(to: NSPoint(x: right, y: bottom + r))    // 右沿下行
        path.appendArc(withCenter: NSPoint(x: right - r, y: bottom + r),
                       radius: r, startAngle: 0, endAngle: -90, clockwise: true)   // 右下圆角
        path.line(to: NSPoint(x: left + r, y: bottom))     // 下沿
        path.appendArc(withCenter: NSPoint(x: left + r, y: bottom + r),
                       radius: r, startAngle: -90, endAngle: -180, clockwise: true) // 左下圆角
        path.close()
        return path
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
