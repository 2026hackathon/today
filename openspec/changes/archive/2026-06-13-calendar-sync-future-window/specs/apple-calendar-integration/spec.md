## MODIFIED Requirements

### Requirement: 今日事件拉取
EventKitCalendarService.fetchMeetings(in:) SHALL 查询指定日期范围内所有 EKEvent，映射为 Meeting 并按 start 升序返回。日期范围由调用方指定（默认同步窗口为今天 00:00 ~ 未来 15 天，不含历史）。提醒事项 SHALL 查询同一范围内的未完成提醒。

#### Scenario: 拉取 30 天窗口的多场会议
- **WHEN** 调用 `fetchMeetings(in: [6月1日, 6月18日])` 且日历含该范围内 10 场会议
- **THEN** 返回 10 个 Meeting，按 start 升序排列

#### Scenario: 拉取单日会议（兼容旧调用）
- **WHEN** 调用 `fetchTodayMeetings()` 便捷方法
- **THEN** 内部调用 `fetchMeetings(in: [今日00:00, 今日24:00])`，返回今日会议

### Requirement: 同步窗口
日历同步范围 SHALL 为今天 00:00 起至未来 15 天（不含历史）；日历页签与今日任务合并均以该窗口为数据源。该未来上界 SHALL 与日历页签展示窗的未来上界（today+15）对齐，确保 +8 ~ +15 天的苹果事件/提醒能被拉取并展示。

#### Scenario: 历史日程不展示
- **WHEN** 日历中存在昨天及更早的事件
- **THEN** 同步结果不含历史日程，日历页签从「今天」段开始展示

#### Scenario: 未来 15 天内的苹果日程可见
- **WHEN** 苹果日历/提醒中存在今天之后第 8 ~ 15 天的事件或提醒
- **THEN** 同步结果包含这些条目，日历页签在对应日期段展示，不再因同步窗过窄而缺失

### Requirement: 同步范围常量
系统 SHALL 在 `CalendarService` 集中定义同步窗口常量 `CalendarSyncConfig.syncDaysFuture = 15`（不含历史，无独立 past 常量）。`CalendarSyncConfig.defaultRange()` SHALL 据此构建同步日期范围，AppDelegate 的初始 / 周期 / 事件驱动同步均调用该便捷方法。

#### Scenario: 构建同步日期范围
- **WHEN** AppDelegate 需要执行日历同步
- **THEN** `defaultRange()` 返回 `[Calendar.startOfDay(today), Calendar.startOfDay(today) + (syncDaysFuture + 1) 天)`，即今天 00:00 起、含未来 15 天
