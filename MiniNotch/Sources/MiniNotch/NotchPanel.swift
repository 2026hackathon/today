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
}
