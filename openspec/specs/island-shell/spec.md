# island-shell Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: 状态机驱动的形态切换
灵动岛 SHALL 由唯一的 `IslandState` 决定几何尺寸与内容，状态间切换 SHALL 使用统一弹簧动画（response 0.45 / damping 0.72）。

#### Scenario: 收缩态自动派生
- **WHEN** 数据变化（todo 数、最近截止时间、AI 是否工作中）
- **THEN** compact 态在 idle / normal / near / urgent / aiWorking 间自动切换，无需手动指定

#### Scenario: 事件触发卡片态
- **WHEN** AI 解析完成 / 提醒到期 / 用户按 ⌘N
- **THEN** island 切换到对应卡片态（newTask / reminder / quickInput），完成或超时后回到 compact 态

### Requirement: 不打扰的窗口行为
island 窗口 SHALL 不抢焦点、不占 Dock、覆盖全屏应用、在所有 Space 显示（沿用 NotchPanel 既有行为）。

#### Scenario: 全屏应用上方可见
- **WHEN** 用户在任意全屏应用中
- **THEN** island 仍然吸附刘海位置可见、可交互

### Requirement: 悬停直接展开
island SHALL 在悬停 compact 态时直接展开完整面板（无中间预览态，点击可跳过悬停延迟立即展开），鼠标移出、esc 或失去焦点（点击其他应用 / ⌘Tab 切走）SHALL 收起所有非 compact 态。

#### Scenario: 悬停展开
- **WHEN** 鼠标悬停 compact 态 ≥ 0.25s（防路过误触发）
- **THEN** 壳体从刘海向下弹性拉伸，直接展开完整 Today 面板，内容延迟淡入；移出 0.2s 后收回

#### Scenario: 失焦收起
- **WHEN** island 处于展开/卡片态，用户点击其他应用窗口或通过 ⌘Tab 等方式激活其他应用
- **THEN** island 回落到 compact 态

### Requirement: Debug 状态菜单
菜单栏 SHALL 提供 Debug 子菜单，可手动触发全部 island 状态（联调与 Demo 兜底用）。

#### Scenario: 手动触发任意状态
- **WHEN** 在菜单栏选择某个状态
- **THEN** island 立即切换到该状态并使用演示数据渲染

### Requirement: Today 焦点布局与 Inbox 全量视图
Today 面板 SHALL 按 问候统计 → 今日日程 → 已超期（红色高亮）→ 今日任务 → 已完成折叠 → AI 建议 的顺序渲染；Inbox tab SHALL 展示全部未完成任务（个人/Jira 分组）。

#### Scenario: 日程置顶
- **WHEN** 打开 Today 面板
- **THEN** 今日会议在最上方，已超期紧随其后，空段自动隐藏

#### Scenario: Inbox 查看存货
- **WHEN** 切到 Inbox tab
- **THEN** 看到未来截止任务与 To Do 状态 Jira 的完整列表

### Requirement: Jira 新分配通知卡
轮询发现新分配的 Jira ticket 且 island 处于 compact 态时，island SHALL 弹出通知卡展示 ticket（key/标题/优先级/状态），无需用户操作，倒计时（约 5s）结束后 SHALL 播放「收入灵动岛」动效并回落 compact 态；悬停 SHALL 暂停倒计时；点击卡片 SHALL 跳转浏览器打开 ticket。

#### Scenario: 新 ticket 弹卡并自动收回
- **WHEN** 轮询合并发现新 jiraKey 且当前为 compact 态
- **THEN** 通知卡浮起（蓝色 Touchdown 涟漪），5s 倒计时进度条走完后内容缩入岛体、岛体弹簧回缩，compact 计数已 +1

#### Scenario: 悬停暂停
- **WHEN** 倒计时期间鼠标悬停卡片
- **THEN** 倒计时暂停，移开后继续

#### Scenario: 不打断当前操作
- **WHEN** 新 ticket 到达时用户正在展开态/其他卡片态
- **THEN** 不弹卡，ticket 静默入库（涟漪仍播放）

#### Scenario: 首轮同步静默
- **WHEN** 应用启动后第一次 Jira 同步
- **THEN** 不弹通知卡（避免把初始全量当成新分配）

