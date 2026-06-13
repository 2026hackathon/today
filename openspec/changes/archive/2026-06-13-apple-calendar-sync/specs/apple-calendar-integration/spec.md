## MODIFIED Requirements

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

### Requirement: 会议链接提取
EKEvent→Meeting 映射 SHALL 复用 `extractMeetingLink`（已实现，从 notes/location/url 提取 6 大平台链接）。此行为不变。

#### Scenario: 事件备注含 Zoom 链接
- **WHEN** EKEvent.notes 包含 "https://zoom.us/j/123456"
- **THEN** Meeting.link = URL, Meeting.platform = .zoom

## ADDED Requirements

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
