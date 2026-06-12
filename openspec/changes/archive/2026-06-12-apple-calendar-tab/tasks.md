## 1. Model & State

- [x] 1.1 `PanelTab` 枚举新增 `case calendar = "日历"`（IslandState.swift）
- [x] 1.2 `PanelTabBar.visibleTabs` 更新为 `[.today, .calendar, .inbox, .favorites]`（TodayPanel.swift）

## 2. EventKit 真实实现

- [x] 2.1 实现 `EventKitCalendarService.fetchTodayMeetings()`：requestFullAccess → predicate → events → Meeting 映射（CalendarService.swift）
- [x] 2.2 Info.plist 添加 `NSCalendarsFullAccessUsageDescription`

## 3. CalendarPanel 视图

- [x] 3.1 将 `MeetingRow` 从 `private` 改为 `internal`（TodayPanel.swift）
- [x] 3.2 新建 `CalendarPanel.swift`：日期标题 + 时间线会议列表 + 空态
- [x] 3.3 `IslandRootView.content` 路由 `.expanded(.calendar)` → CalendarPanel

## 4. AppDelegate 动态装配

- [x] 4.1 新增 `currentCalendarService()` 方法（类似 `currentJiraService()` 模式）：按 EventKit 权限动态返回真/Mock
- [x] 4.2 轮询任务改用 `currentCalendarService()` 替代固定 `calendarService`

## 5. Verify

- [x] 5.1 编译通过，无 warning
- [ ] 5.2 展开面板 → Tab Bar 出现「日历」页签（需手动验证）
- [ ] 5.3 点击「日历」→ CalendarPanel 展示今日会议（或空态）（需手动验证）
