## Context

灵动岛面板（`NotchPanel`）在 `.statusBar` 层级，靠两条路径收起：
1. **失焦收起**（`AppDelegate`）：全局鼠标按下（点本 App 之外）+ `NSWorkspace.didActivateApplicationNotification`（⌘Tab/Spotlight 等）→ `dismissOnFocusLoss()` → `store.dismiss()`。
2. **悬停移出收起**（`IslandRootView.handleHover`）：鼠标移出 0.2s 后 `store.dismiss()`，已有 `isMenuTracking`、`dialogPresentedCount` 两个抑制条件。

最初用系统「预览」打开截图，有两个硬伤：「预览」普通窗口压在岛下层看不到；拉起外部 App 抢前台触发失焦收起。曾尝试用「外部 App 激活时不收、本 App 重新激活时解除」抑制，但解除依赖本 App 重新激活，时机不可靠、容易卡在展开态。

## Goals / Non-Goals

**Goals:**
- 大图盖在灵动岛**上层**显示。
- 大图尺寸舒适（卡片式，不铺满、不放大超原图）。
- 看图期间灵动岛**保持不动**，看完关闭后**确定性**恢复正常收起。

**Non-Goals:**
- 不改截图存取、AI 链路、数据模型。
- 不改正常的失焦/悬停收起逻辑（仅在「查看器打开」窗口内豁免）。

## Decisions

**D1：应用内浮层窗口而非系统「预览」。** 新增 `ScreenshotViewerWindowController`（仿 `CelebrationWindowController`）：透明 `NSPanel`，`level = .statusBar + 2` 确保盖在岛上层；`nonactivatingPanel` + `orderFrontRegardless` 不抢外部 App 前台；`ignoresMouseEvents = false` 以接收翻页/关闭点击。全程在本 App 内，从根上消除「外部 App 抢焦」这一收起诱因。

**D2：抑制态绑定查看器生命周期，而非外部 App 激活。** `AppStore.screenshotViewerOpen` 由 `show(onWillOpen:)` 在弹出**前同步**置 `true`（早于 0.2s 悬停收起计时），由 `close()` 淡出完成后的 `onDidClose` 置 `false`。开/关都由查看器自身驱动 → 确定性，不会卡住。两条收起路径都追加 `!screenshotViewerOpen` 守卫。

**D3：大图舒适尺寸。** 用 `GeometryReader` 拿容器尺寸，显示尺寸 = 原图按 `min(屏宽*0.72/W, 屏高*0.72/H, 1)` 缩放——`min(.., 1)` 保证不放大超过原图；圆角 + 描边 + 阴影成卡片，暗背景 0.62。

**D4：关闭后回到原页签。** 关闭只清抑制态、不强制收起；岛仍是打开前的展开态，用户回到原面板，后续按正常悬停规则收起（与面板「停在原地直到下次移出」一致）。

## Risks / Trade-offs

- [关闭查看器后鼠标若不在岛上，岛维持展开直到下次 hover-out] → 与普通面板行为一致（停在上次上下文），可接受；不强制收起以免打断用户。
- [`@Sendable` 动画完成回调里捕获非 Sendable 局部闭包导致数据竞争编译错误] → 关闭回调存为 `@MainActor` 控制器属性 `onDidClose`，在 `MainActor.assumeIsolated` 内从 `self` 读取并调用，不捕获局部。
- [Esc 关闭] → 本地 + 全局 keyDown 监听双保险（本 App 非前台时全局兜底），关闭时移除。
