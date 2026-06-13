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
展开态页签 SHALL 与五大概念一一对应，集合为：`Today · 任务 · 工作项 · 日历事件 · 信息 · Agent · Calendar`（外加设置 ⚙）。各页签承载：

- **Today**：今日聚合（问候统计 → AI 建议 → 已超期 → 今日任务 → Agent 待处理 → 活跃工作项 → 已完成折叠）
- **任务**（Todo）：全部未完成个人任务的纯列表，可完成
- **工作项**（WorkItem）：全部 Jira/GitHub 工作项，活跃与积压分组，只读跳转
- **日历事件**（CalendarEvent）：纯事件议程（会议/节假日），不含个人任务
- **信息**（Message + Mention）：邮件消息 + @我提及，内部分段
- **Agent**（AgentSession）：全部会话
- **Calendar**：事件 + 个人任务的合并时间线（later-into-calendar）

不再提供 `Later`(Inbox) 页签。页签栏 SHALL 横向可滚动，右端 ＋/↻/⚙ 图标固定不随滚动，且角标不被裁剪。

#### Scenario: 工作项有独立入口
- **WHEN** 切到「工作项」页签
- **THEN** 看到全部 Jira/GitHub（活跃在前、积压在后），无个人任务

#### Scenario: 任务纯列表
- **WHEN** 切到「任务」页签
- **THEN** 看到全部未完成个人任务，可勾选完成；无外部工单

#### Scenario: 日历事件与 Calendar 区分
- **WHEN** 切到「日历事件」页签
- **THEN** 只看到事件（会议/节假日），不含个人任务
- **AND WHEN** 切到「Calendar」页签
- **THEN** 看到事件与个人任务合并的时间线

#### Scenario: 无 Later 页签
- **WHEN** 浏览页签栏
- **THEN** 不存在「Later」页签；外部工单积压在「工作项」页签可见

#### Scenario: 页签栏横向滚动
- **WHEN** 页签数量超出可视宽度
- **THEN** 页签区横向滚动，右端 ＋/↻/⚙ 固定可见，未读角标不被裁

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

### Requirement: 消息降落通知卡（多条并发）
轮询发现新消息且 island 处于 compact 态时，island SHALL 弹出通知卡，沿用「Jira 新分配通知卡」的样式与时间展示（展示一句话 summary、来源标识、接收时间），无需用户操作，倒计时（约 5s）结束后播放「收入灵动岛」动效并回落。与 Jira 单卡不同，消息通知卡 SHALL 支持**同时呈现多条**：同一轮到达多条或倒计时期间又到新消息时，SHALL 以队列依次呈现或聚合为「N 条新消息」卡，而非互相覆盖丢失。悬停 SHALL 暂停倒计时；点击卡片 SHALL 打开该消息 `link` 并标记已处理。新消息到达不得抢占输入态（快速新建 / 任务降落 / 批量卡进行中时顺延），应用启动后首轮同步 SHALL NOT 弹卡。

#### Scenario: 单条新消息弹卡并自动收回
- **WHEN** 轮询发现 1 条新消息且当前为 compact 态
- **THEN** 通知卡浮起（含 summary/来源/时间），约 5s 后内容收入岛体并回落 compact

#### Scenario: 多条新消息并发
- **WHEN** 同一轮到达 ≥2 条新消息
- **THEN** 多条以队列依次呈现或聚合为「N 条新消息」卡，无消息被覆盖丢失

#### Scenario: 点击通知卡跳转并处理
- **WHEN** 用户点击消息通知卡
- **THEN** 打开该消息 link 且该消息被标记已处理

#### Scenario: 不打断当前操作
- **WHEN** 新消息到达时用户正处于展开态/其他卡片态/输入态
- **THEN** 不弹卡，消息静默入库，待回到 compact 态后顺延呈现

#### Scenario: 首轮同步静默
- **WHEN** 应用启动后第一次邮件同步
- **THEN** 不弹通知卡（避免把初始全量当成新消息）

### Requirement: 「消息」页签入口
`PanelTab` SHALL 新增 `messages`（显示名「消息」）页签；展开态 SHALL 提供切换入口，切到该页签时渲染消息列表（详见 message-inbox 能力）。

#### Scenario: 切换到消息页签
- **WHEN** 用户在展开态点击「消息」页签
- **THEN** 面板渲染消息列表（多条、白/灰态、可完成/跳转）

