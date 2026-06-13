## MODIFIED Requirements

### Requirement: 完成与删除的可用性及删除回写
任务/会议行的「完成」(✓) 与「删除」操作 SHALL 按来源与时间相关性区分可用性：
- 「完成」(✓) SHALL 出现在：① 苹果来源项（`source == .calendar`）——其同步合并仅为**当天**项生成 `.calendar` todo，故均可完成：事件完成仅置本地 `completedAt`，提醒完成经 `onReminderCompletionChanged` 回写 `EKReminder.isCompleted`；② 本地自定义任务且截止今天、已超期、**或无固定时间（无截止）**。仅**未来截止**的本地任务、Jira/GitHub SHALL NOT 显示完成（显示静态小点）。
- 日历页签时间线里的 Meeting 行 SHALL 按日期区分：**今天及更早**的苹果项显示可点击完成圈；**未来**的苹果项显示静态小点（不可完成）。
- 已完成项 SHALL 保留在列表中以删除线弱化展示、**不隐藏**（本地任务与日历项一致），可再次点击撤销完成；已完成的绿色对勾 SHALL 使用小尺寸样式（约 11pt），不使用大圆。
- 「删除」SHALL 出现在本地任务与苹果来源项（事件/提醒）；Jira/GitHub 只读 SHALL NOT 可删除。
- 删除苹果来源项（`source == .calendar` 且有 `calendarEventId`，或带 `eventIdentifier` 的 Meeting）SHALL 经 CalendarService 从 EventKit 真删除对应 EKEvent / EKReminder，并移除本地镜像（meetings / `.calendar` todo）；删除本地任务仅移除本地，不触苹果。
- CalendarService SHALL 提供 `deleteCalendarItem(identifier:)`：按标识先查事件、再查提醒事项并 `remove`；找不到（已被外部删除）视为成功。`MockCalendarService` 为空操作。

#### Scenario: 无固定时间本地任务可完成
- **WHEN** 一个无截止时间的本地自定义任务
- **THEN** 该行显示可点击完成圈，可勾选完成（完成后保留并加删除线）

#### Scenario: 未来本地任务不可完成
- **WHEN** 一个本地自定义任务截止在明天
- **THEN** 该行显示静态小点而非完成(✓)圈，但显示删除按钮

#### Scenario: 已完成对勾为小尺寸
- **WHEN** 任意行（本地任务或日历项）处于已完成状态
- **THEN** 其绿色对勾以约 11pt 小尺寸渲染，并对标题加删除线，可点击撤销完成

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
