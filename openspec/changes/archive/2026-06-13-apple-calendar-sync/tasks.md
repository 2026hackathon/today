## 1. 协议与常量（Foundation）

- [x] 1.1 在 `CalendarService.swift` 中将 `CalendarService` 协议的 `fetchTodayMeetings()` 替换为 `fetchMeetings(in range: ClosedRange<Date>) async throws -> [Meeting]`
- [x] 1.2 为协议添加 `fetchTodayMeetings()` 默认扩展实现，内部调用 `fetchMeetings(in: .today)`
- [x] 1.3 在 `CalendarService.swift` 中定义同步窗口常量 `static let syncDaysPast = 29` 和 `static let syncDaysFuture = 6`
- [x] 1.4 添加 `ClosedRange<Date>` 的 `.today` 便捷扩展（`startOfDay(today)...startOfDay(today+1)`）

## 2. EventKitCalendarService 实现

- [x] 2.1 重写 `fetchTodayMeetings()` 为 `fetchMeetings(in range: ClosedRange<Date>)`，使用 `range.lowerBound`/`range.upperBound` 替换硬编码的今天日期
- [x] 2.2 提醒事项查询使用同一 `range` 参数（`predicateForIncompleteReminders(withDueDateStarting: range.lowerBound, ending: range.upperBound, ...)`）
- [x] 2.3 验证 `swift build` 编译通过

## 3. MockCalendarService 实现

- [x] 3.1 重写 `MockCalendarService` 实现 `fetchMeetings(in range:)` 方法，生成覆盖请求范围的演示数据（每天 1-2 场会议）
- [x] 3.2 验证 `swift build` 编译通过

## 4. AppStore 数据层

- [x] 4.1 新增 `meetingsByDate: [(date: Date, meetings: [Meeting])]` 计算属性，按 `Calendar.startOfDay` 分组并按日期升序排列
- [x] 4.2 确认 `replaceMeetings()` 全量替换逻辑无需修改（已有行为满足多日场景）
- [x] 4.3 确认 `todayMeetings` 计算属性保留不变
- [x] 4.4 在 `resetDemoData()` 中添加 `UserDefaults.standard.removeObject(forKey: "calendarInitialSyncCompleted")`

## 5. AppDelegate 同步流程

- [x] 5.1 新增 `private var calendarSyncRange: ClosedRange<Date>` 计算属性，使用 `CalendarService.syncDaysPast`/`syncDaysFuture` 构建 `[today-29天, today+6天]`
- [x] 5.2 修改 `refreshCalendarMeetings()` 使用 `calendarSyncRange` 调用 `fetchMeetings(in:)` 替换 `fetchTodayMeetings()`
- [x] 5.3 修改 `syncExternalSources()` 中日历部分使用 `calendarSyncRange`
- [x] 5.4 在 `requestCalendarAccess()` 权限授予后添加首次同步检查：读 `calendarInitialSyncCompleted`，若为 `false` 则执行首次同步并在成功后设为 `true`
- [x] 5.5 修改 Layer 2 定时轮询使用 `fetchMeetings(in:)` + `calendarSyncRange`
- [x] 5.6 验证 `swift build` 编译通过

## 6. CalendarPanel UI 多日视图

- [x] 6.1 将 `timelineBody` 从单日列表改为按 `store.meetingsByDate` 分组的 ScrollView，使用 `ForEach` 遍历日期段落
- [x] 6.2 添加日期段落标题组件：今日显示「今天 M月d日」，昨天显示「昨天 M月d日」，其他日期显示「M月d日 周X」
- [x] 6.3 今日段落使用正常样式，过去日期段落文字和卡片设置 `opacity(0.5)`
- [x] 6.4 会议列表复用现有 `TimelineRow`，保持卡片样式不变
- [x] 6.5 添加 `ScrollViewReader` 使面板打开时自动滚动到今日段落位置
- [x] 6.6 更新空态文案：从「今日暂无会议」改为「暂无会议」
- [x] 6.7 更新会议计数显示：从「今日 X 场会议」改为「近 30 天 X 场会议」或移除
- [x] 6.8 验证 `swift build` 编译通过

## 7. 集成验证

- [x] 7.1 完整构建验证：`swift build` 无错误无警告
- [ ] 7.2 验证首次同步流程：重置演示数据 → 启动 → 授权 → 确认 30 天数据加载
- [ ] 7.3 验证日常同步：确认 Layer 1（事件驱动）/Layer 2（15分钟轮询）/Layer 3（面板展开刷新）均使用新范围
- [ ] 7.4 验证 CalendarPanel 多日视图：确认日期分组正确、今日高亮、过去降权、滚动到今日
