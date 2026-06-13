## Why

从任务行点击「小相机」或行尾缩略图查看截图大图时，原先拉起系统「预览」：一是「预览」是普通窗口、只能压在 `.statusBar` 层级的灵动岛**下面**，看不到；二是拉起外部 App 抢占前台会触发失焦收起，把灵动岛收回 compact、丢失当前页签。需要一种「大图盖在岛上层、看图过程不打断岛」的友好查看方式。

## What Changes

- 截图查看改为**应用内浮层窗口**（层级高于灵动岛的 `.statusBar`），把大图盖在岛**上层**显示，不再拉起系统「预览」。
- 大图按**舒适尺寸**居中成卡片（最多屏幕 ~72%、不放大超过原图），不铺满全屏；多张图带左右翻页与 `N/M` 计数；点暗背景 / ✕ / Esc 关闭。
- 看图视为一次**聚焦模态**：打开期间灵动岛保持不动（不自动收起），关闭后恢复正常的悬停/失焦收起。抑制态绑定查看器自身的打开/关闭生命周期，确定性清除（不会卡住）。

## Capabilities

### New Capabilities
<!-- 无新增能力，行为归属现有 island-shell -->

### Modified Capabilities
- `island-shell`: 在「失焦收起 / 确认弹窗抑制收起」相邻语义上，新增一类抑制场景——岛内打开截图大图查看器（盖在岛上层的应用内模态）期间抑制自动收起（失焦与悬停移出两条路径），查看器关闭即恢复。

## Impact

- 新增 `ScreenshotViewerWindowController` + `ScreenshotViewerView`（应用内浮层窗口，`.statusBar + N` 层级，带 onWillOpen/onDidClose 生命周期回调）。
- `AppStore`：新增可观察标志 `screenshotViewerOpen`。
- `AppDelegate.dismissOnFocusLoss` 与 `IslandRootView` 悬停移出收起判定读取该标志。
- `TodayPanel`（`ScreenshotViewer.open` 及小相机/缩略图调用点）：改为打开浮层窗口并经回调置位/清除标志。
- 仅影响截图查看呈现与灵动岛收起时机，不改截图存取、AI 链路或数据模型。
