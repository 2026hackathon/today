## 1. 数据模型与标识

- [x] 1.1 `Core/Models.swift`：`Meeting` 新增可选字段 `eventIdentifier: String?`；`Todo` 新增可选字段 `calendarEventId: String?`（解码缺失取 nil，验证旧 JSON 兼容）
- [x] 1.2 `Services/CalendarService.swift`：EKEvent 映射填入 `ev.eventIdentifier`，`mapReminders` 填入 `reminder.calendarItemIdentifier`

## 2. 日历/提醒 → 任务合并

- [x] 2.1 `Core/AppStore.swift`：新增 `mergeCalendarTodos(from meetings: [Meeting])` —— 当天 Meeting 映射为 `.calendar` Todo 草稿（dueDate = start，全天/无时间项 dueDate 置 nil），按 `calendarEventId` upsert（保留 completedAt/snoozedUntil），prune 跳过已完成项
- [x] 2.2 在 `replaceMeetings` 后（或 AppDelegate 同步链路中）调用 2.1 的合并，覆盖三层同步入口（EKEventStoreChanged / 15min 轮询 / 面板打开）
- [x] 2.3 验证幂等：连续两次同步不重复、不复活已完成项；日历删除事件后未完成任务被 prune

## 3. 完成动作与提醒回写

- [x] 3.1 `CalendarService` 协议新增 `completeReminder(identifier: String) async throws`；EventKit 实现用 `calendarItem(withIdentifier:)` 置 `isCompleted = true` 并 save；Mock 实现空操作
- [x] 3.2 `AppStore.complete(todo)`：`.calendar` 来源且为提醒事项时异步触发回写，失败仅 NSLog 不回滚本地完成态（需要区分事件/提醒：Todo 草稿映射时打 tag 或字段标记）

## 4. Today 面板

- [x] 4.1 `UI/Panels/TodayPanel.swift`：移除「今日日程」独立区段（保留顶部摘要「N 场会议」计数）
- [x] 4.2 确认 `.calendar` 任务走 `PersonalTodoRow` 可完成行（来源色橙色标识），有时间项按时间排入「今日任务」，无时间项落「无固定时间」分区
- [x] 4.3 验证完成后行为：从「今日任务」消失、进「已完成」折叠区、compact 计数与 celebrate 判定一致

## 5. 日历页签完成图标

- [x] 5.1 `Core/AppStore.swift`：新增派生方法 `isMeetingCompleted(_ meeting: Meeting) -> Bool`（按 `calendarEventId == eventIdentifier` 匹配已完成 `.calendar` 任务）
- [x] 5.2 `MeetingRow`（TodayPanel.swift）：新增 `isCompleted` 入参，已完成时左侧状态点替换为绿色 `checkmark.circle.fill`，标题删除线 + 降低不透明度
- [x] 5.3 `UI/Panels/CalendarPanel.swift`：DateSection 调用处传入 `store.isMeetingCompleted(meeting)`

## 6. 实施中修订（用户反馈）

- [x] 6.0.1 同步窗口改为 [今天 00:00, +7 天]（`CalendarSyncConfig`），日历页签不再展示历史日程
- [x] 6.0.2 双谓词拉取提醒（未完成按 due 窗口 + 已完成按完成时间窗口），`Meeting.isCompleted` 携带 EventKit 完成态——完成回写后日历页签该行保留并打勾
- [x] 6.0.3 合并时外部已完成提醒单向同步进本地任务（置 completedAt，无对应任务不新建）；`isMeetingCompleted` 对提醒以 Meeting.isCompleted 为准
- [x] 6.0.4 回写改双向 `setReminderCompleted(identifier:completed:)`：撤销完成回写取消，避免被下一轮合并翻回

## 7. 验收

- [x] 7.1 `swift build` 通过；旧 todos.json / meetings.json 启动无崩溃
- [ ] 7.2 端到端验证：今日日历事件与提醒出现在「今日任务」→ 点击完成消失 → 日历页签该行显示对勾 → Apple 提醒事项 App 中对应提醒已勾选
- [ ] 7.3 回写触发的 EKEventStoreChanged 同步收敛，无重复任务、无 UI 抖动
