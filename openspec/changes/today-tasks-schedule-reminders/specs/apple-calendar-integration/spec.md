## ADDED Requirements

### Requirement: 稳定事件标识
EKEvent/EKReminder → Meeting 映射 SHALL 携带稳定标识：日历事件取 `EKEvent.eventIdentifier`，提醒事项取 `EKReminder.calendarItemIdentifier`，存入 `Meeting.eventIdentifier`（可选字段，旧 meetings.json 解码兼容）。该标识 SHALL 作为 `.calendar` 任务合并与完成状态匹配的键。

#### Scenario: 事件映射携带标识
- **WHEN** 拉取到一个 EKEvent
- **THEN** 生成的 Meeting.eventIdentifier 等于该事件的 eventIdentifier，跨同步周期保持稳定

#### Scenario: 旧数据解码兼容
- **WHEN** 用不含 eventIdentifier 字段的旧 meetings.json 启动
- **THEN** 解码成功，eventIdentifier 为 nil，不崩溃

### Requirement: 同步窗口
日历同步范围 SHALL 为今天 00:00 起至未来 7 天（不含历史）；日历页签与今日任务合并均以该窗口为数据源。

#### Scenario: 历史日程不展示
- **WHEN** 日历中存在昨天及更早的事件
- **THEN** 同步结果不含历史日程，日历页签从「今天」段开始展示

### Requirement: 已完成提醒保留
提醒事项拉取 SHALL 同时包含未完成（按 due 窗口）与已完成（按完成时间窗口，due 仍限定在同步范围内）的提醒，`Meeting.isCompleted` 携带 EventKit 完成态——已完成提醒的行保留在日历页签并打勾，而非消失。

#### Scenario: 完成回写后行保留
- **WHEN** 用户在今日任务完成一条提醒，回写触发重新同步
- **THEN** 该提醒仍出现在日历页签，isCompleted = true，行打勾

#### Scenario: 外部勾选同步进本地任务
- **WHEN** 用户在 Apple 提醒事项 App 勾掉一条今天的提醒
- **THEN** 下次同步后对应本地任务置为完成（单向：EventKit 未完成不清本地完成态）；无对应本地任务时不再新建

### Requirement: 提醒事项完成回写
CalendarService SHALL 提供 `setReminderCompleted(identifier:completed:)`：按 calendarItemIdentifier 查找 EKReminder，写入完成态并保存；完成与撤销完成均回写（撤销不回写会被下一轮合并按 EventKit 完成态翻回）。回写失败 SHALL 仅记录日志，不回滚本地状态。

#### Scenario: 回写成功
- **WHEN** 用户完成提醒事项任务且 EventKit 权限正常
- **THEN** Apple 提醒事项 App 中该提醒显示为已完成

#### Scenario: 回写失败降级
- **WHEN** 回写时提醒已被外部删除或保存抛错
- **THEN** 记录日志，本地任务保持完成态，不弹错误、不崩溃

#### Scenario: 撤销完成回写
- **WHEN** 用户在「已完成」折叠区撤销一条提醒任务
- **THEN** EventKit 中该提醒恢复为未完成，本地任务回到「今日任务」且不被合并翻回

#### Scenario: 回写触发的变更通知收敛
- **WHEN** 回写引发 EKEventStoreChanged 触发新一轮同步
- **THEN** 同步结果与当前状态一致（已完成提醒不在拉取结果中、本地任务不复活），UI 无抖动

### Requirement: 日历页签完成标识
CalendarPanel 的日程/提醒行 SHALL 根据对应 `.calendar` 任务的完成状态渲染：已完成时左侧状态点替换为绿色 `checkmark.circle.fill` 小图标，标题加删除线并降低不透明度。完成状态由 AppStore 派生方法按 `calendarEventId == Meeting.eventIdentifier` 匹配，视图层不重复实现查找。

#### Scenario: 完成后日历页签显示对勾
- **WHEN** 用户在「今日任务」完成「评审会」后切到日历页签
- **THEN** 「评审会」行左侧显示绿色对勾小图标，标题删除线弱化，行仍保留在时间线中

#### Scenario: 未完成事件样式不变
- **WHEN** 某事件对应任务未完成（或无对应任务，如非当天事件）
- **THEN** 行样式与现状一致（状态点/铃铛 + 正常标题）
