## Context

- 日历事件与提醒事项由 `EventKitCalendarService.fetchMeetings(in:)` 拉取为 `Meeting`（提醒事项 `isReminder = true`），经 `AppStore.replaceMeetings` 替换式存入 `meetings.json`，仅在 Today 面板「今日日程」区段与 CalendarPanel 只读展示。
- `Meeting.id` 是每次拉取新生成的 UUID，没有携带 EventKit 标识，无法跨同步周期识别同一事件。
- `TodoSource` 已有 `.calendar` case（未使用）；`AppStore.mergeExternalTodos` 已实现按 key upsert + prune 的外部任务合并模式（Jira/GitHub 在用）。
- `AppStore.complete(todo)` 置 `completedAt`，列表派生集合自动把完成项移入「已完成」折叠区。
- 提醒事项同步只拉「未完成」（`predicateForIncompleteReminders`），无回写。

## Goals / Non-Goals

**Goals:**
- 当天的日历事件与提醒事项以 `.calendar` 来源 Todo 出现在「今日任务」，可勾选完成，完成后不再显示
- 提醒事项完成时回写 EventKit，保证 Apple 提醒事项 App 与本应用状态一致
- CalendarPanel 行根据完成状态显示小对勾图标
- 同步幂等：重复同步不产生重复任务，已完成项不复活，事件删除后任务被清理

**Non-Goals:**
- 不做日历事件（EKEvent）的回写（系统日历没有"完成"概念，完成态仅记录在本地 Todo）
- 不改变会议提醒/通知调度（ReminderScheduler 行为不变，`.calendar` 任务与普通任务同等参与提醒分级）
- 不支持非当天（未来/过去日）的事件转任务
- 不改 Inbox / Jira / GitHub 既有合并逻辑

## Decisions

### D1: 用稳定 EventKit 标识作为合并键
`Meeting` 新增 `eventIdentifier: String?`，映射时分别取 `EKEvent.eventIdentifier` 与 `EKReminder.calendarItemIdentifier`；`Todo` 新增 `calendarEventId: String?`。两者均为可选字段，`Codable` 解码旧 JSON 自动为 nil，无迁移成本。

备选：用「标题+开始时间」做模糊键 —— 否决，改标题/改时间会产生重复任务。

### D2: 复用 mergeExternalTodos 模式做 .calendar 合并
`replaceMeetings` 后追加一步：把当天 meetings 映射为 Todo 草稿（`title`、`dueDate = start`、`source: .calendar`、`calendarEventId`、`isReminder` 经 note/tag 区分），调用合并逻辑：

- **Upsert**：按 `calendarEventId` 匹配；存在则更新标题/时间（保留 `completedAt`/`snoozedUntil` 等本地状态），不存在则新增
- **不复活**：已完成（`completedAt != nil`）的项只更新元信息，不清除完成态。提醒事项完成回写后下次拉取自然不含该项，prune 时 SHALL 跳过已完成项（保留在「已完成」区直到当天结束）
- **Prune**：当天范围内、`.calendar` 来源、未完成、且本次同步未出现的任务删除（事件被用户从日历删除）

备选：直接在派生集合里把 Meeting 动态拼进「今日任务」（不落 Todo）—— 否决：完成态需要持久化、需要参与已完成分组/celebrate/提醒分级，复用 Todo 管线代价最小。

### D3: 提醒完成态双向回写 EventKit
`CalendarService` 协议新增 `setReminderCompleted(identifier:completed:) async throws`；EventKit 实现用 `eventStore.calendarItem(withIdentifier:)` 找到 EKReminder 写完成态并 save。`AppStore.complete/uncomplete` 检测到 `.calendar` 来源且为提醒事项时异步触发回写（撤销不回写会被下一轮合并按 EventKit 完成态翻回）；回写失败仅 NSLog，不回滚本地状态。

日历事件不回写（无完成语义），完成态只存在于本地 Todo。

### D3.5: 已完成提醒保留 + 外部完成同步进本地（实施中修订）
仅拉未完成提醒会让完成回写后整行从日历页签消失。改为双谓词拉取：未完成按 due 窗口 + 已完成按完成时间窗口（前移 30 天兜底提前勾掉的情况，due 仍限定同步范围），`Meeting.isCompleted` 携带 EventKit 完成态。合并时外部已完成的提醒单向同步进本地任务（置 completedAt；无对应任务不新建）；`isMeetingCompleted` 对提醒以 `Meeting.isCompleted` 为准，事件仍按今日任务匹配。

### D3.6: 同步窗口收紧（实施中修订）
窗口从 [-29 天, +6 天] 改为 [今天 00:00, +7 天]：日历页签只展示从今天开始的日程和提醒，历史数据随替换式同步自然清除。

### D4: CalendarPanel 完成图标按 calendarEventId 关联
`MeetingRow` 新增 `isCompleted: Bool` 入参；CalendarPanel/调用方用 `store.todos` 中匹配 `calendarEventId == meeting.eventIdentifier && isCompleted` 判定。已完成行：左侧状态点替换为绿色 `checkmark.circle.fill` 小图标，标题加删除线 + 降低不透明度。AppStore 提供 `isMeetingCompleted(_ meeting: Meeting) -> Bool` 派生方法，避免视图层重复查找逻辑。

### D5: 移除 Today 面板「今日日程」区段
日程项现以任务形式进入「今日任务」，原只读区段删除以避免重复。Today 面板顶部摘要中的「N 场会议」计数保留（数据仍来自 `todayMeetings`）。CalendarPanel 不变（仍展示完整 Meeting 时间线，叠加完成图标）。

备选：两处都显示 —— 否决，同一事件出现两次易混淆，且与用户诉求（在今日任务中管理）冲突。

### D6: 今日任务内的排序与展示
`.calendar` 任务带 `dueDate = 事件开始时间`，自然落入「今日任务（有时间）」按时间排序；全天事件/无时间提醒落入「无固定时间」细分区。行样式复用 `PersonalTodoRow`（可完成），来源色用既有 `DS.sourceColor(.calendar)`（橙色 #FF9500）标识。

## Risks / Trade-offs

- [EKEventStoreChanged 风暴：回写提醒会触发自身的变更通知，引发一轮多余同步] → 同步幂等（D2 upsert + 不复活）保证收敛；该轮同步结果无差异，不产生 UI 抖动
- [eventIdentifier 在日历账户变动后可能变化（EventKit 已知行为）] → 旧任务被 prune、新标识重建任务，完成态丢失；当天范围窗口小，影响可接受，hackathon 不做映射表
- [重复事件（recurring EKEvent）共享 eventIdentifier] → 同步范围仅当天，同一天同 identifier 多次出现的情况极少；如出现取首个，记入 Open Questions
- [meetings.json / todos.json 旧数据无新字段] → 字段全部可选，解码兼容；旧 `.calendar` 任务不存在（该来源此前未使用），无脏数据
- [用户在 Apple 提醒事项中外部完成提醒] → 下次同步拉不到该提醒，但本地任务未完成 → 会被 prune 删除而非标记完成；可接受（列表不再显示，与诉求一致）

## Open Questions

- 重复（recurring）日历事件同日多实例的合并键冲突 —— 实现时若遇到，键改为 `eventIdentifier + startDate` 组合
- 「已完成」折叠区中的当天日程任务是否随次日同步清理 —— 默认保留至次日被 prune（不在当天范围内），无需额外逻辑
