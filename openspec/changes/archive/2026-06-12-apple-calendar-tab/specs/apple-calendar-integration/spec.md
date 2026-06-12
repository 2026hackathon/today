## ADDED Requirements

### Requirement: EventKit 权限请求
EventKitCalendarService SHALL 在首次拉取会议时调用 `requestFullAccessToEvents()`；用户拒绝时 SHALL 抛出 `.accessDenied`。

#### Scenario: 用户授权
- **WHEN** 用户首次触发日历拉取且系统弹窗授权
- **THEN** 用户点击「允许」后成功拉取今日会议

#### Scenario: 用户拒绝
- **WHEN** 用户在系统弹窗点击「不允许」
- **THEN** 抛出 `CalendarServiceError.accessDenied`，AppDelegate 降级到 Mock

### Requirement: 今日事件拉取
EventKitCalendarService.fetchTodayMeetings SHALL 查询今日 00:00~24:00 范围内所有 EKEvent，映射为 Meeting 并按 start 升序返回。

#### Scenario: 今日有多场会议
- **WHEN** 日历含 3 场今日会议（9:00、14:00、16:00）
- **THEN** 返回 3 个 Meeting，按 start 升序排列

#### Scenario: 今日无会议
- **WHEN** 日历中没有今日事件
- **THEN** 返回空数组

### Requirement: 会议链接提取
EKEvent→Meeting 映射 SHALL 复用 `extractMeetingLink`（已实现，从 notes/location/url 提取 6 大平台链接）。

#### Scenario: 事件备注含 Zoom 链接
- **WHEN** EKEvent.notes 包含 "https://zoom.us/j/123456"
- **THEN** Meeting.link = URL, Meeting.platform = .zoom

### Requirement: 日历独立页签
PanelTab SHALL 新增 `.calendar` case；CalendarPanel 展示今日会议时间线视图，含时间轴、会议卡片、平台标识、加入会议按钮。

#### Scenario: 切换到日历页签
- **WHEN** 用户点击 Tab Bar 的「日历」
- **THEN** 内容区切换到 CalendarPanel，显示今日所有会议

#### Scenario: 日历页签空态
- **WHEN** 今日无会议
- **THEN** 显示「今日暂无会议」空态

### Requirement: 日历服务动态装配
AppDelegate SHALL 根据 EventKit 权限状态选择 CalendarService：有完整权限用 EventKitCalendarService，否则降级到 MockCalendarService。

#### Scenario: 首次启动有权限
- **WHEN** EventKit 权限为 fullAccess
- **THEN** 装配 EventKitCalendarService，轮询拉取真实会议

#### Scenario: 权限被拒降级
- **WHEN** EventKit 权限为 denied
- **THEN** 装配 MockCalendarService，轮询拉取演示数据
