## 1. Draft 意图字段（ai-pipeline，仅本地）

- [x] 1.1 在 `Models.swift` 的 `TodoDraft` 增加 `kind`（`enum DraftKind { case event, reminder, task }`），默认 `.task`，补充编解码/初始化与 `toTodo()` 透传
- [x] 1.2 `AIService.swift` Mock：在 `parseQuickInput`/`parseScreenshot` 启发式中产出 `kind`（具体时间点→event，截止/前→reminder，无时间→task）
- [x] 1.3 `AIService.swift` OpenAI：JSON schema 增加 `kind` 字段并解析回填，缺省回退 `.task`
- [x] 1.4 kind 仅影响本地：按 kind 设默认提前量/展示分组，确认**不触发任何苹果写入**

## 2. 同步边界（AppStore / AppDelegate）

- [x] 2.1 确认创建链路（QuickInputCard 提交、F2/贴图 draft 提交）只落本地 Todo，无任何 EventKit 写入调用
- [x] 2.2 完成路径：仅 `source == .calendar` 且为提醒（isReminder）时调 `onReminderCompletionChanged` → `setReminderCompleted`（沿用现状）
- [x] 2.3 完成路径：`source == .calendar` 且为日历事件时仅置本地 `completedAt`，不调用任何 EventKit 写入（不改标题、不删事件）
- [x] 2.4 校验 `mergeCalendarTodos()` upsert 保留本地 `completedAt`，事件本地完成状态不被下一轮同步覆盖
- [x] 2.5 移除初版遗留的 createEvent/createReminder/优先级映射等写入设想（若已落代码则回退）

## 3. Later → Calendar 收敛（todo-data + UI）

- [x] 3.1 `AppStore.inboxTodos` 过滤掉个人来源，仅保留 Jira/外部来源待办
- [x] 3.2 `InboxPanel.swift` 移除个人任务区段，仅渲染外部来源；标题/计数随之调整
- [x] 3.3 `CalendarPanel.swift` 时间线并入本地个人任务：有 dueDate 的按日期/时间归入对应分组，无时间的归入当天「无固定时间」区
- [x] 3.4 复用日期分组 + 完成标识渲染个人任务行（完成/Snooze 沿用现有交互），过去段落降权、空态文案更新
- [x] 3.5 校验 compact 态焦点计数仍与「已超期 + 今日任务」一致

## 4. 截图关联与查看（capture）

- [x] 4.1 确认 F2/贴图原图保留到 `screenshots/` 且路径贯穿 draft → 本地 todo（现状校验）
- [x] 4.2 卡片/任务详情提供「查看原图」入口，读取 `screenshotPath` 展示
- [x] 4.3 `screenshotPath` 文件缺失时降级提示「原图已不可用」，不崩溃

## 5. 回归与验收

- [x] 5.1 三类输入（事件/提醒/纯任务）端到端：均只落本地，苹果日历/提醒事项无新增条目（代码核验：无 create* 写入路径）
- [x] 5.2 苹果来源提醒完成 → 回写系统；苹果来源事件完成 → 仅本地、苹果日历不变（代码核验：complete() 仅对提醒回写）
- [x] 5.3 事件本地完成后再同步，完成状态保留不被覆盖（代码核验：mergeCalendarTodos 只置位不清除）
- [x] 5.4 截图项的 `screenshotPath` 可查看，缺失降级正常（ScreenshotThumb 缺失占位）
- [x] 5.5 Later 页签无个人任务、Calendar 页签个人任务正确归位（inboxTodos 仅外部 + CalendarPanel 并入）
- [x] 5.6 `openspec validate later-into-calendar` 通过；`swift build` 成功（Build complete, 无报错）

## 6. 完成可用性 + 删除（含苹果同步删除）

- [x] 6.1 `CalendarService` 协议加 `deleteCalendarItem(identifier:)`；`EventKitCalendarService` 实现（先 event 后 reminder 的 `remove`），Mock 空操作
- [x] 6.2 `AppStore` 加 `onCalendarItemDeleted` 回调；`AppDelegate` 接线到 `deleteCalendarItem`
- [x] 6.3 `AppStore.canComplete(_:)`：本地自定义任务（今天/超期）+ 苹果提醒为 true；苹果事件、未来/无截止本地、Jira/GitHub 为 false
- [x] 6.4 `AppStore.canDelete(_:)`：本地任务 + 苹果来源为 true；Jira/GitHub 为 false。`delete(_:)` 对 `.calendar` 项调用 `onCalendarItemDeleted` + 清本地镜像；加 `deleteMeeting(_:)` 供 MeetingRow
- [x] 6.5 `PersonalTodoRow`：完成圈按 `canComplete` 显隐（不可完成显占位点）；加删除按钮（`canDelete`），苹果同步项删除前确认
- [x] 6.6 `MeetingRow`：加删除按钮，苹果项删除前确认，调用 `deleteMeeting`
- [x] 6.7 `swift build` 成功 + `openspec validate` 通过
