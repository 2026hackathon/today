## 1. 应用内查看器窗口

- [x] 1.1 新增 `ScreenshotViewerWindowController`（仿 `CelebrationWindowController`）：透明 `NSPanel`，`level = .statusBar + 2` 盖在岛上层，`nonactivatingPanel` + `orderFrontRegardless` 不抢前台，`ignoresMouseEvents = false`
- [x] 1.2 `show(paths:onWillOpen:onDidClose:)`：过滤不存在的文件，弹出前同步调 `onWillOpen`，淡出关闭后调 `onDidClose`；Esc 本地+全局监听关闭，重入先拆旧窗
- [x] 1.3 `ScreenshotViewerView`：暗背景点击关闭、大图卡片、✕ 关闭、多张翻页 + `N/M` 计数

## 2. 大图舒适尺寸

- [x] 2.1 `GeometryReader` 取容器尺寸，显示尺寸 = 原图按 `min(屏宽*0.72/W, 屏高*0.72/H, 1)` 缩放（不放大超原图），圆角+描边+阴影成卡片

## 3. 看图模态抑制收起

- [x] 3.1 `AppStore` 新增 `@Published var screenshotViewerOpen`
- [x] 3.2 `ScreenshotViewer.open(_:store:)` 改为打开浮层窗口，onWillOpen 置 `true`、onDidClose 置 `false`；小相机/缩略图调用点传入 `store`（`ScreenshotThumb` 注入 `@EnvironmentObject store`）
- [x] 3.3 `AppDelegate.dismissOnFocusLoss()` 与 `IslandRootView` 悬停移出收起判定追加 `!store.screenshotViewerOpen`

## 4. 验证

- [x] 4.1 `swift build` 通过（修掉 `@Sendable` 完成回调捕获非 Sendable 局部闭包的数据竞争错误：改为从 `@MainActor` 控制器属性读回调）
- [ ] 4.2 运行 App：点小相机/缩略图 → 大图盖在岛上层、舒适尺寸、岛保持不动（待手动确认）
- [ ] 4.3 关闭查看器（背景/✕/Esc）→ 回到原页签、恢复正常收起；多张图可翻页（待手动确认）
