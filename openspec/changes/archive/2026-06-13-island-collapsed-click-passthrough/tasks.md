## 1. 穿透命中基础设施（NotchPanel.swift）

- [x] 1.1 新增 `IslandHitRegion` 引用对象，持有 `var islandSize: CGSize?`（岛体当前渲染尺寸，nil = 未实测）
- [x] 1.2 新增 `PassthroughHostingView<Content: View>: NSHostingView<Content>`，注入 `IslandHitRegion`；重写 `hitTest(_:)`：`islandSize` 为 nil 时回退 `super.hitTest`，否则按"顶部居中 + hit-slop(6pt)"算命中矩形，点在矩形外返回 `nil`（穿透），矩形内交 `super.hitTest`

## 2. 上报岛体尺寸（Island/IslandRootView.swift）

- [x] 2.1 新增 `IslandShellSizeKey: PreferenceKey`（reduce 取最新非零值）
- [x] 2.2 给 `IslandRootView` 增加注入的 `IslandHitRegion`，在壳体显式 `.frame(width: geo.width, height: shellHeight)` 层用 `GeometryReader` 背景上报真实尺寸
- [x] 2.3 `.onPreferenceChange(IslandShellSizeKey.self)` 中（主 actor）写入 `hitRegion.islandSize`

## 3. 装配（AppDelegate.swift）

- [x] 3.1 `showPanel()` 创建共享 `IslandHitRegion`，传入 `IslandRootView`
- [x] 3.2 contentView 改用 `PassthroughHostingView(rootView: root, hitRegion:)` 替代普通 `NSHostingView`

## 4. 验证

- [x] 4.1 `cd MiniNotch && swift build` 通过 + `swift run` 启动冒烟（面板就位、无崩溃）
- [x] 4.2 compact 态下点击岛体下方透明区 → 穿透到下方应用/桌面正常生效（人工点测通过）
- [x] 4.3 悬停展开 / 各卡片态（Debug 菜单逐态）→ 岛体本体与面板内部控件照常可点（人工点测通过）
- [x] 4.4 展开/卡片态点击岛体外透明区 → 穿透激活下方应用并触发失焦收起回落 compact（人工点测通过）
