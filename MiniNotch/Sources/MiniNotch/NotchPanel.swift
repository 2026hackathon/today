import AppKit

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
