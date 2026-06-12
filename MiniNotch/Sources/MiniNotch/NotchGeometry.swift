import AppKit

/// 刘海几何信息计算。
///
/// macOS 14+ 暴露了 `NSScreen.safeAreaInsets.top` —— 在带刘海的屏幕上等于刘海高度。
/// 屏幕上有刘海时，可视区域 `visibleFrame` 会扣掉刘海高度，
/// 我们用 `frame` 而不是 `visibleFrame` 来获取整块屏幕（含刘海）。
enum NotchGeometry {

    /// 真实刘海尺寸（来自实测 / Apple 设计文档）
    /// MacBook Pro 14"/16" M1+：约 200 × 32pt
    /// 没有刘海的屏幕回退一个伪刘海，便于在外接屏 / Intel Mac 上调试
    static let fallbackSize = CGSize(width: 200, height: 32)

    /// 计算面板应该出现的位置 —— 紧贴屏幕顶部、水平居中
    /// - Parameters:
    ///   - screen: 目标屏幕（通常是主屏）
    ///   - panelSize: 面板的展开尺寸
    /// - Returns: 面板的 origin（屏幕坐标系，左下角原点）
    static func panelFrame(on screen: NSScreen, panelSize: CGSize) -> NSRect {
        let screenFrame = screen.frame
        let x = screenFrame.midX - panelSize.width / 2
        // 顶部对齐：macOS 坐标系原点在左下，所以 y = 屏幕顶部 - 面板高度
        let y = screenFrame.maxY - panelSize.height
        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    /// 刘海实际尺寸
    static func notchSize(on screen: NSScreen) -> CGSize {
        let topInset = screen.safeAreaInsets.top
        if topInset > 0 {
            // 刘海宽度没有公开 API，常见值 ~200pt
            return CGSize(width: 200, height: topInset)
        }
        return fallbackSize
    }
}
