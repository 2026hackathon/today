## Why

灵动岛面板是一个固定 680×660 的悬浮窗口，`NSHostingView` 铺满整窗。收缩（compact）态下岛体只占顶部居中一小块，但其**下方一大片透明区域**（约等于提醒卡展开时占的高度）仍归属 hosting view，会把落在那里的鼠标点击全部吞掉——点不到下方的应用窗口/桌面。用户反馈"灵动岛收缩时下方一块区域鼠标无法点击"即源于此。

## What Changes

- 面板对**非岛体可交互区域的点击实施穿透**：收缩 / 卡片 / 展开各态下，只有岛体当前实际渲染所覆盖的矩形接收鼠标事件，其余透明区域的点击放行给下方应用。
- 引入一个承载岛体当前命中区域尺寸的轻量共享对象，由 `IslandRootView` 实测上报、由面板的 hosting view 在 `hitTest` 中读取裁剪命中范围。
- 透明区放行后，点击岛体之外区域天然走"失焦收起"路径（点到其他应用 → 全局监听 → 展开/卡片态回落 compact），与既有窗口行为一致，不需额外逻辑。

## Capabilities

### New Capabilities
<!-- 无新增能力 -->

### Modified Capabilities
- `island-shell`: 「不打扰的窗口行为」要求新增"透明区域点击穿透"约束——岛体之外的窗口区域 SHALL NOT 拦截鼠标点击。

## Impact

- 代码：`NotchPanel.swift`（新增穿透 hosting view + 命中区域对象）、`AppDelegate.swift`（`showPanel()` 改用穿透 hosting view 并注入命中区域）、`Island/IslandRootView.swift`（实测并上报岛体当前尺寸）。
- 共享契约：触及 `Island/IslandRootView.swift` 与窗口装配点，按编码守则需走 openspec change（本变更）。
- 无 API / 依赖变更，无数据迁移。仅改变鼠标命中行为；视觉、动画、状态机不变。
