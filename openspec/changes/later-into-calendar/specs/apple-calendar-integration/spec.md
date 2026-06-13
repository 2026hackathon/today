## ADDED Requirements

### Requirement: 完成与删除的可用性及删除回写
任务/会议行的「完成」(✓) 与「删除」操作 SHALL 按来源与时间相关性区分可用性：
- 「完成」(✓) SHALL 出现在：① 苹果来源项（`source == .calendar`）——其同步合并仅为**当天**项生成 `.calendar` todo，故均可完成：事件完成仅置本地 `completedAt`，提醒完成经 `onReminderCompletionChanged` 回写 `EKReminder.isCompleted`；② 本地自定义任务且截止今天或已超期。未来截止 / 无截止的本地任务、Jira/GitHub SHALL NOT 显示完成。
- 日历页签时间线里的 Meeting 行 SHALL 按日期区分：**今天及更早**的苹果项显示可点击完成圈；**未来**的苹果项显示静态小点（不可完成）。
- 已完成项 SHALL 保留在列表中以删除线弱化展示、**不隐藏**（本地任务与日历项一致），可再次点击撤销完成。
- 「删除」SHALL 出现在本地任务与苹果来源项（事件/提醒）；Jira/GitHub 只读 SHALL NOT 可删除。
- 删除苹果来源项（`source == .calendar` 且有 `calendarEventId`，或带 `eventIdentifier` 的 Meeting）SHALL 经 CalendarService 从 EventKit 真删除对应 EKEvent / EKReminder，并移除本地镜像（meetings / `.calendar` todo）；删除本地任务仅移除本地，不触苹果。
- CalendarService SHALL 提供 `deleteCalendarItem(identifier:)`：按标识先查事件、再查提醒事项并 `remove`；找不到（已被外部删除）视为成功。`MockCalendarService` 为空操作。

#### Scenario: 未来本地任务不可完成
- **WHEN** 一个本地自定义任务截止在明天
- **THEN** 该行显示静态小点而非完成(✓)圈，但显示删除按钮

#### Scenario: 苹果事件可完成（本地）可删除
- **WHEN** 一个今天的苹果日历事件行
- **THEN** 显示可点击完成圈；完成仅置本地状态并加删除线，不改苹果事件；删除则从苹果日历移除该 EKEvent

#### Scenario: 苹果提醒可完成回写可删除
- **WHEN** 一个今天的苹果提醒事项行
- **THEN** 完成→回写 `EKReminder.isCompleted`；删除→从苹果提醒事项移除该 EKReminder

#### Scenario: 未来苹果项显示小点
- **WHEN** 日历时间线渲染一个明天或更晚的苹果日程/提醒
- **THEN** 该行显示静态小点，不可点击完成

#### Scenario: 已完成本地任务保留显示
- **WHEN** 在日历页签完成一个本地自定义任务
- **THEN** 该任务仍留在时间线对应日期，标题加删除线弱化，不消失

#### Scenario: 删除本地任务不触苹果
- **WHEN** 删除一个本地自定义任务
- **THEN** 仅本地移除，不调用任何 EventKit 写入

### Requirement: 同步边界——创建仅本地，仅来源项回写
灵动岛创建的日程/提醒/任务（「+」快速录入、F2 截图、贴图识图）SHALL 只落本地 Todo，**不得**写入苹果日历或提醒事项（不提供 createEvent/createReminder 之类的写入能力）。完成回写 SHALL 仅对 `source == .calendar`（苹果同步来源）的项生效，并按类型区分：
- 项为提醒事项（`Meeting.isReminder` 对应 EKReminder）时，完成 SHALL 经既有 `onReminderCompletionChanged` 回写 `EKReminder.isCompleted`；
- 项为日历事件（EKEvent）时，完成 SHALL 仅置本地 `completedAt`，**不得**调用任何 EventKit 写入（EventKit 无事件完成字段；不改标题、不删除事件）。

#### Scenario: 灵动岛创建项不写苹果
- **WHEN** 用户用「+」或识图创建一个带时间的日程
- **THEN** 仅创建本地 Todo，苹果日历/提醒事项中不出现任何新条目

#### Scenario: 苹果来源提醒完成回写
- **WHEN** 用户在灵动岛完成一个来自苹果的提醒事项（`.calendar` 且 isReminder）
- **THEN** 调用 `setReminderCompleted` 回写，系统提醒事项 App 中该项变为已完成

#### Scenario: 苹果来源事件完成仅本地
- **WHEN** 用户在灵动岛完成一个来自苹果的日历事件/会议
- **THEN** 本地标记完成并显示对勾，但不触发任何 EventKit 写入，苹果日历中的事件保持不变

#### Scenario: 事件本地完成状态不被同步覆盖
- **WHEN** 苹果来源事件本地完成后发生下一轮 `fetchMeetings` 同步
- **THEN** `mergeCalendarTodos()` 保留本地 `completedAt`，该事件仍显示为已完成

## MODIFIED Requirements

### Requirement: 日历独立页签
PanelTab SHALL 保持 `.calendar` case；CalendarPanel SHALL 展示按日期分组的多日时间线视图，包含日期段落标题、时间线、平台标识、加入会议按钮。时间线 SHALL 同时纳入苹果来源日历事件/提醒与**本地个人任务**：有截止时间的个人任务按 dueDate 归入对应日期分组并按时间排序；无固定时间的个人任务归入当天分组的「无固定时间」区。今日段落 SHALL 高亮显示，过去日期段落 SHALL 降低不透明度。空日期 SHALL 不显示。

#### Scenario: 切换到日历页签查看多日日程
- **WHEN** 用户点击 Tab Bar 的「日历」
- **THEN** CalendarPanel 显示窗口内有事件或个人任务的所有日期分组，今日段落自动滚动至可见区域

#### Scenario: 个人任务进入日历时间线
- **WHEN** 存在一个截止于明天 15:00 的本地个人任务
- **THEN** 该任务出现在 CalendarPanel 明天段落 15:00 时间点，与日历事件同线展示

#### Scenario: 无固定时间个人任务的落点
- **WHEN** 存在无截止时间的本地个人任务
- **THEN** 它显示在今天段落的「无固定时间」区，不占据具体时间点

#### Scenario: 日历页签空态
- **WHEN** 窗口内无任何会议且无个人任务
- **THEN** 显示空态，副标题提示日程与任务会显示在这里

#### Scenario: 过去日期段落视觉降权
- **WHEN** CalendarPanel 渲染昨天及更早的日期段落
- **THEN** 过去日期段落的文字和卡片使用降低的不透明度（opacity 0.5），今日段落正常显示
