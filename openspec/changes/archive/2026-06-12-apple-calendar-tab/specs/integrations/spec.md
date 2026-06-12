## MODIFIED Requirements

### Requirement: CalendarService 动态装配（替换原有 Mock 常驻）
CalendarService 装配 SHALL 由 AppDelegate 按 EventKit 权限动态选择，而非硬编码 Mock。原有 `MockCalendarService 常驻` 行为变更为「权限缺失时降级兜底」。

#### Scenario: 权限齐全用真服务
- **WHEN** EventKit fullAccess 已授予
- **THEN** 60min 轮询调用 EventKitCalendarService.fetchTodayMeetings，今日会议分组展示真实数据

#### Scenario: 权限缺失降级 Mock
- **WHEN** EventKit 权限未授予
- **THEN** 轮询回退到 MockCalendarService，行为与之前一致
