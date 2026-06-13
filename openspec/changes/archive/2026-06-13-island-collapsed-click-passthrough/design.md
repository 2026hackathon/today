## Context

`AppDelegate.showPanel()` 创建一个固定 680×660 的 `NotchPanel`（为容纳最大展开态 460×540 + glow 溢光留边），并把铺满整窗的 `NSHostingView(IslandRootView)` 设为 contentView。`NotchPanel` 不忽略鼠标事件（需要接收岛体点击/悬停/输入），因此整窗范围内的点击都会经由 hosting view 的 `hitTest` 路由。

compact 态下岛体只渲染顶部居中约 200×32 一小块（`IslandRootView` 用 `.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)` 把岛体顶居中铺在大窗里），但 hosting view 仍覆盖整窗。落在岛体下方透明区的 `mouseDown` 被 hosting view 命中后由窗口消费，**不会下传到下方应用**——这就是"收缩时下方一片区域点不动"的根因。

约束：`NotchPanel` 必须保持 nonactivating、可成 key（输入框粘贴）、覆盖全屏与所有 Space；命中行为不能破坏悬停展开、卡片交互、展开面板内部控件点击，也不能破坏既有"点其他应用失焦收起"。岛体顶部居中、随形态形变（尺寸实时变化）。

## Goals / Non-Goals

**Goals:**
- compact / 卡片 / 展开各态下，只有岛体当前实际渲染矩形接收点击，其余透明区点击穿透到下方应用。
- 命中矩形随形态实时变化，覆盖当前可见岛体。
- 复用既有失焦收起：穿透后点击落到下方应用，全局监听自然触发回落。

**Non-Goals:**
- 不做逐像素 alpha 命中（NotchShape 圆角处的极小三角差异忽略，用矩形 + hit-slop 近似）。
- 不改窗口尺寸/位置策略（仍固定大窗，不随形态 resize 窗口——避免动画期间反复 setFrame 抖动）。
- 不改任何视觉、动画、状态机、glow/阴影逻辑。

## Decisions

### D1：穿透型 hosting view + 共享命中区域对象，而非动态 resize 窗口
新增 `PassthroughHostingView<Content>: NSHostingView<Content>`，持有一个轻量引用对象 `IslandHitRegion`（`var islandSize: CGSize?`）。`hitTest(_:)` 读取该尺寸，按"顶部居中"几何算出岛体在 hosting view 坐标系下的矩形（含 hit-slop），点落在矩形外直接返回 `nil`（放行穿透），矩形内交给 `super.hitTest` 做 SwiftUI 内部命中。

- 选它而非「随形态 resize 面板窗口」：窗口在弹簧动画期间高度连续变化，每帧 `setFrame` 会与 SwiftUI 内部形变动画打架、易抖动，且全屏/多 Space 下 setFrame 代价高。固定大窗 + 裁剪命中范围把"视觉形变"与"窗口尺寸"解耦，最稳。
- 选它而非「逐像素透明命中」：实现复杂、需读 backing store，圆角处收益微乎其微。矩形 + 6pt slop 已覆盖用户感知到的"可点区域"。
- `islandSize == nil`（尚未实测）时回退 `super.hitTest`，即维持现有"整窗捕获"行为，保证启动首帧不会误穿透。

### D2：命中尺寸由 `IslandRootView` 实测上报
岛体壳体那层已是显式 `.frame(width: geo.width, height: shellHeight)`。新增一个 `PreferenceKey`（`IslandShellSizeKey`）在壳体层用 `GeometryReader` 背景上报真实尺寸，`.onPreferenceChange` 里写入注入的 `IslandHitRegion.islandSize`。上报真实渲染尺寸 → 卡片/展开态自动覆盖全部内容，无需为每种态单独配置。

- 为何用壳体层尺寸而非内容自然高度：壳体 `.frame(height: shellHeight)` 正是窗口里实际画出黑岛的范围，命中区与可见区一一对应。
- 写外部对象属于视图更新副作用 → 放在 `onPreferenceChange`（已在主 actor、值变才触发），不在 body 求值期写。

### D3：坐标换算
hosting view 非 flipped（AppKit 左下原点）。岛体顶部贴窗口顶（`bounds.maxY`），水平居中（`.top` Alignment = 水平 center）。命中矩形：
`x = bounds.midX - (w+2·slop)/2`，`y = bounds.maxY - (h+2·slop)`，`width = w+2·slop`，`height = h+2·slop`。
contentView 在 borderless 面板里填满窗口、frame 原点 (0,0)，故传入 `hitTest` 的 superview 坐标点与 bounds 坐标一致，无需额外换算。

## Risks / Trade-offs

- [展开面板贴近窗口边缘的控件被 slop 外裁掉] → 命中矩形用壳体实测尺寸（已含面板全部宽高）再外扩 slop，只会比可见区更大不会更小，不会裁掉控件。
- [动画期间命中区滞后于视觉一帧/两帧] → onPreferenceChange 跟随形变更新，滞后在弹簧动画中不可感知；且 compact↔展开 由悬停/点击岛体触发，触发点本就在命中区内。
- [`islandSize` 首帧为 nil 时整窗捕获] → 仅持续到首次实测（启动即测得 compact 尺寸，<1 帧），可接受；这是"安全侧"回退（宁可暂时多捕获，不误穿透）。
- [穿透后点击落到下方应用会激活它] → 正是 spec 期望（失焦收起）；compact 态 `isDismissable` 为否，不会有副作用。

## Migration Plan

纯增量、无数据/接口变更。改 3 个文件即可，回滚 = 还原 `showPanel()` 用回普通 `NSHostingView`。验证走 `swift build` + `swift run`，用 Debug 菜单逐态确认岛体可点、下方透明区可穿透。
