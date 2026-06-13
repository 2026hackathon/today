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
EventKitCalendarService.fetchMeetings(in:) SHALL 查询指定日期范围内所有 EKEvent，映射为 Meeting 并按 start 升序返回。日期范围由调用方指定（默认同步窗口为 today-29 天 ~ today+6 天）。提醒事项 SHALL 查询同一范围内的未完成提醒。

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
PanelTab SHALL 保持 `.calendar` case；CalendarPanel SHALL 展示按日期分组的多日会议视图，包含日期段落标题、会议时间线、平台标识、加入会议按钮。今日段落 SHALL 高亮显示，过去日期段落 SHALL 降低不透明度。空日期 SHALL 不显示。

#### Scenario: 切换到日历页签查看多日日程
- **WHEN** 用户点击 Tab Bar 的「日历」
- **THEN** CalendarPanel 显示 30 天窗口内有事件的所有日期分组，今日段落自动滚动至可见区域

#### Scenario: 日历页签空态
- **WHEN** 30 天窗口内无任何会议
- **THEN** 显示「暂无会议」空态，副标题提示「苹果日历中的会议会显示在这里」

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
系统 SHALL 定义日历同步窗口常量 `calendarSyncDaysPast = 29` 和 `calendarSyncDaysFuture = 6`，由 AppDelegate 在构建同步日期范围时使用。常量 SHALL 集中在 `CalendarService` 或 `AppSettings` 中定义。

#### Scenario: 构建同步日期范围
- **WHEN** AppDelegate 需要执行日历同步
- **THEN** 构建 `ClosedRange<Date>` 为 `[Calendar.startOfDay(today - 29天), Calendar.startOfDay(today + 7天)]`（含 today 共 36 天）

