# apple-calendar-integration Specification

## Purpose
通过 EventKit 接入苹果日历与提醒事项：权限管理、日程/提醒拉取与映射、日历页签展示、完成状态与今日任务联动。
## Requirements
### Requirement: EventKit 权限请求
EventKitCalendarService SHALL 在首次拉取会议时调用 `requestFullAccessToEvents()`；用户拒绝时 SHALL 抛出 `.accessDenied`。

#### Scenario: 用户授权
- **WHEN** 用户首次触发日历拉取且系统弹窗授权
- **THEN** 用户点击「允许」后成功拉取今日会议

#### Scenario: 用户拒绝
- **WHEN** 用户在系统弹窗点击「不允许」
- **THEN** 抛出 `CalendarServiceError.accessDenied`，AppDelegate 降级到 Mock

### Requirement: 今日事件拉取
EventKitCalendarService.fetchMeetings(in:) SHALL 查询指定日期范围内所有 EKEvent，映射为 Meeting 并按 start 升序返回。日期范围由调用方指定（默认同步窗口为今天 00:00 ~ 未来 15 天，不含历史）。提醒事项 SHALL 查询同一范围内的未完成提醒。

#### Scenario: 拉取 30 天窗口的多场会议
- **WHEN** 调用 `fetchMeetings(in: [6月1日, 6月18日])` 且日历含该范围内 10 场会议
- **THEN** 返回 10 个 Meeting，按 start 升序排列

#### Scenario: 拉取单日会议（兼容旧调用）
- **WHEN** 调用 `fetchTodayMeetings()` 便捷方法
- **THEN** 内部调用 `fetchMeetings(in: [今日00:00, 今日24:00])`，返回今日会议

#### Scenario: 指定范围内无事件
- **WHEN** 指定日期范围内日历中无任何事件
- **THEN** 返回空数组

#### Scenario: 提醒事项纳入结果
- **WHEN** 指定日期范围内存在未完成的提醒事项
- **THEN** 提醒事项以 `isReminder: true` 的 Meeting 形式包含在返回结果中

### Requirement: 会议链接提取
EKEvent→Meeting 映射 SHALL 复用 `extractMeetingLink`（已实现，从 notes/location/url 提取 6 大平台链接）。此行为不变。

#### Scenario: 事件备注含 Zoom 链接
- **WHEN** EKEvent.notes 包含 "https://zoom.us/j/123456"
- **THEN** Meeting.link = URL, Meeting.platform = .zoom

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

### Requirement: 日历服务动态装配
AppDelegate SHALL 根据 EventKit 权限状态选择 CalendarService：有完整权限用 EventKitCalendarService，否则降级到 MockCalendarService。动态装配逻辑 SHALL 在每次同步调用时重新判定（不缓存服务实例）。

#### Scenario: 首次启动有权限
- **WHEN** EventKit 权限为 fullAccess
- **THEN** 装配 EventKitCalendarService，同步拉取 30 天窗口内的真实会议

#### Scenario: 权限被拒降级
- **WHEN** EventKit 权限为 denied
- **THEN** 装配 MockCalendarService，同步拉取演示数据

### Requirement: 稳定事件标识
EKEvent/EKReminder → Meeting 映射 SHALL 携带稳定标识：日历事件取 `EKEvent.eventIdentifier`，提醒事项取 `EKReminder.calendarItemIdentifier`，存入 `Meeting.eventIdentifier`（可选字段，旧 meetings.json 解码兼容）。该标识 SHALL 作为 `.calendar` 任务合并与完成状态匹配的键。

#### Scenario: 事件映射携带标识
- **WHEN** 拉取到一个 EKEvent
- **THEN** 生成的 Meeting.eventIdentifier 等于该事件的 eventIdentifier，跨同步周期保持稳定

#### Scenario: 旧数据解码兼容
- **WHEN** 用不含 eventIdentifier 字段的旧 meetings.json 启动
- **THEN** 解码成功，eventIdentifier 为 nil，不崩溃

### Requirement: 同步窗口
日历同步范围 SHALL 为今天 00:00 起至未来 15 天（不含历史）；日历页签与今日任务合并均以该窗口为数据源。该未来上界 SHALL 与日历页签展示窗的未来上界（today+15）对齐，确保 +8 ~ +15 天的苹果事件/提醒能被拉取并展示。

#### Scenario: 历史日程不展示
- **WHEN** 日历中存在昨天及更早的事件
- **THEN** 同步结果不含历史日程，日历页签从「今天」段开始展示

#### Scenario: 未来 15 天内的苹果日程可见
- **WHEN** 苹果日历/提醒中存在今天之后第 8 ~ 15 天的事件或提醒
- **THEN** 同步结果包含这些条目，日历页签在对应日期段展示，不再因同步窗过窄而缺失

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
- **THEN** 同步结果与当前状态一致（已完成提醒带完成态保留、本地任务不复活），UI 无抖动

### Requirement: 日历页签完成标识
CalendarPanel 的日程/提醒行 SHALL 根据完成状态渲染：已完成时左侧状态点替换为绿色 `checkmark.circle.fill` 小图标，标题加删除线并降低不透明度。完成状态由 AppStore 派生方法判定：提醒以 `Meeting.isCompleted` 为准，日历事件按 `calendarEventId == Meeting.eventIdentifier` 匹配今日 `.calendar` 任务，视图层不重复实现查找。

#### Scenario: 完成后日历页签显示对勾
- **WHEN** 用户在「今日任务」完成「评审会」后切到日历页签
- **THEN** 「评审会」行左侧显示绿色对勾小图标，标题删除线弱化，行仍保留在时间线中

#### Scenario: 未完成事件样式不变
- **WHEN** 某事件对应任务未完成（或无对应任务，如非当天事件）
- **THEN** 行样式与现状一致（状态点/铃铛 + 正常标题）

### Requirement: CalendarService 协议扩展
CalendarService 协议 SHALL 新增 `fetchMeetings(in: ClosedRange<Date>)` 方法作为主查询接口。原 `fetchTodayMeetings()` SHALL 保留为便捷方法（默认实现调用 `fetchMeetings(in: .today)`），所有调用方 SHALL 迁移至新方法。

#### Scenario: EventKit 实现支持日期范围
- **WHEN** 调用 `eventKitCalendarService.fetchMeetings(in: range)`
- **THEN** 使用 `eventStore.predicateForEvents(withStart: range.lowerBound, end: range.upperBound, calendars: nil)` 查询

#### Scenario: Mock 实现支持日期范围
- **WHEN** 调用 `mockCalendarService.fetchMeetings(in: range)`
- **THEN** 返回范围固定的演示数据（每天 1-2 场会议，覆盖请求的日期范围）

### Requirement: AppStore 多日会议计算属性
AppStore SHALL 新增 `meetingsByDate: [(date: Date, meetings: [Meeting])]` 计算属性，将 `meetings` 数组按 `Calendar.startOfDay` 分组并按日期升序排列，供 CalendarPanel 消费。`todayMeetings` 计算属性 SHALL 保留不变。

#### Scenario: 按日期分组
- **WHEN** `meetings` 包含 6月10日 2 场 + 6月12日 3 场会议
- **THEN** `meetingsByDate` 返回 `[(6月10日, [2场]), (6月12日, [3场])]`，按日期升序

#### Scenario: 空数组分组
- **WHEN** `meetings` 为空
- **THEN** `meetingsByDate` 返回空数组

### Requirement: 同步范围常量
系统 SHALL 在 `CalendarService` 集中定义同步窗口常量 `CalendarSyncConfig.syncDaysFuture = 15`（不含历史，无独立 past 常量）。`CalendarSyncConfig.defaultRange()` SHALL 据此构建同步日期范围，AppDelegate 的初始 / 周期 / 事件驱动同步均调用该便捷方法。

#### Scenario: 构建同步日期范围
- **WHEN** AppDelegate 需要执行日历同步
- **THEN** `defaultRange()` 返回 `[Calendar.startOfDay(today), Calendar.startOfDay(today) + (syncDaysFuture + 1) 天)`，即今天 00:00 起、含未来 15 天

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


### Requirement: 日历页签展示时间窗
日历页签 SHALL 仅展示「昨天 00:00 ~ 今天 +15 天」窗口内的数据；窗口外（前天及更早、+15 天之后）的日程/提醒/任务 SHALL NOT 出现在时间线。该窗口是日历页签的展示过滤（作用于 `meetingsByDate` 与 `calendarPersonalTodos` 的合并结果），不改变后台同步深度。窗口内分日期口径区分：
- **昨天**分组 SHALL 仅展示本地自定义且**未完成**的任务（`source` 非 Jira/GitHub 且非 `.calendar`，且 `isCompleted == false`）；苹果来源的日程/会议/提醒与已完成的本地任务 SHALL NOT 出现在昨天分组。
- **今天及未来 15 天**照旧展示全部（苹果日程/会议/提醒 + 本地任务，含已完成的删除线项）。
- 无固定时间（无截止）的本地任务仍归入今天分组，不受昨天口径影响。

#### Scenario: 历史与远期被过滤
- **WHEN** 日历中存在前天的会议或 +16 天后的日程
- **THEN** 这些项不出现在日历页签时间线

#### Scenario: 昨天只剩未完成自定义任务
- **WHEN** 昨天既有一个苹果会议、一个已完成的本地任务，又有一个未完成的本地自定义任务
- **THEN** 昨天分组仅显示那个未完成的本地自定义任务，会议与已完成任务都不显示

#### Scenario: 今天及未来正常全量
- **WHEN** 今天和未来 10 天内有苹果日程与已完成的本地任务
- **THEN** 它们均正常显示在对应日期分组（已完成项带删除线保留）

### Requirement: 行操作悬停热区覆盖整行
日历页签时间线的任务行（`PersonalTodoRow`）与会议行（`MeetingRow`）SHALL 以整行矩形（含标题右侧空白、缩略图与行尾区域）作为悬停热区，使删除按钮在鼠标位于该行任意位置时即出现，而非仅在文字上方。

#### Scenario: 空白处悬停也显示删除按钮
- **WHEN** 鼠标悬停在某行标题右侧的空白区域（非文字上）
- **THEN** 该行高亮且删除按钮出现，可直接点击删除
