## Why

会议目前只显示在 Today 页签的一个 section 里，信息密度低且无法专注查看日程。EventKitCalendarService 已有骨架但未实现真实拉取。用户需要苹果日历的深度集成和独立页签，以便快速浏览全天会议。

## What Changes

- 实现 `EventKitCalendarService` 真实 EventKit 拉取（请求权限 → 谓词查询 → EKEvent→Meeting 映射）
- `PanelTab` 枚举新增 `.calendar` 页签
- 新建 `CalendarPanel` 视图，展示今日时间线形式的会议列表
- AppDelegate 动态装配：EventKit 有权限时用真服务，否则降级到 Mock
- Info.plist 添加 `NSCalendarsFullAccessUsageDescription`
- Today 页签中保留「今日会议」section（与日历页签共存）

## Capabilities

### New Capabilities
- `apple-calendar-integration`: EventKit 真实拉取今日会议 + 独立日历页签

### Modified Capabilities
- `integrations`: CalendarService 从 Mock 升级为动态装配（真/Mock 按权限降级）

## Impact

- `MiniNotch/Sources/MiniNotch/Services/CalendarService.swift`: 实现 EventKitCalendarService.fetchTodayMeetings
- `MiniNotch/Sources/MiniNotch/Island/IslandState.swift`: PanelTab 加 .calendar
- `MiniNotch/Sources/MiniNotch/UI/Panels/TodayPanel.swift`: 路由日历页签到 CalendarPanel
- 新建 `MiniNotch/Sources/MiniNotch/UI/Panels/CalendarPanel.swift`
- `MiniNotch/Sources/MiniNotch/AppDelegate.swift`: 动态装配日历服务
- `MiniNotch/Info.plist`: 加 NSCalendarsFullAccessUsageDescription
