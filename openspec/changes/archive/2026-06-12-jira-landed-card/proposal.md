# Proposal: jira-landed-card

## Why

新 Jira ticket 分配目前只有蓝色涟漪一闪，用户感知不到具体内容。需要一张「任务降落」通知卡：展示 ticket 信息、倒计时后自动收入灵动岛——这是 PRD F-07/F-12 的 Demo 高光时刻（「同事现场分配，刘海立刻通知」）。

## What Changes

- `IslandState` 新增 `jiraLanded(todo:, moreCount:)` 卡片态
- 新建 `JiraLandedCard`：样式对齐 NewTaskCard，但**无需用户操作**——展示 ticket 信息 + 倒计时进度条，倒计时结束播放「收入灵动岛」动效（内容向上缩入 + 岛体弹簧回缩）
- 悬停暂停倒计时；点击卡片跳转浏览器打开 ticket
- `mergeJiraTodos` 发现新 key 且 island 处于 compact 态时弹卡；同轮多条新分配显示「等 N 条」；应用启动后的首轮同步静默（避免初始全量误报）

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `island-shell`: 新增「Jira 新分配通知卡」requirement

## Impact

- `Island/IslandState.swift`（共享契约 +1 case）、`Core/AppStore.swift`、`AppDelegate.swift`
- 新建 `UI/Cards/JiraLandedCard.swift`、`Island/IslandRootView.swift` 路由 +1
