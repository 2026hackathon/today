## Why

灵动岛的「+」快速录入与截图/贴图识图，应作为用户自己的私有待办空间：创建的日程/提醒只属于灵动岛，不应擅自写进系统苹果日历、污染用户跨设备的真实日历。另一方面，从苹果同步进来的日程/提醒/会议是「真实数据」，在灵动岛完成时应尽量回写苹果保持一致。同时「Later」与「Calendar」两个页签职责重叠：个人任务散落在 Later、日历项在 Calendar，用户要在两处找同一批待办。本次明确「创建只在本地、Apple 来源完成尽量回写」的同步边界，并把个人任务统一收敛到 Calendar 页签。

## What Changes

- **灵动岛创建项仅本地**：「+」快速录入（⌘N，含贴图）与 F2 截图识图创建的日程/提醒/任务 SHALL 只存在于灵动岛本地，**不写入**苹果日历/提醒事项。（移除初版「录入即写入苹果日历」方向，不再提供 `createEvent`/`createReminder` 写入能力。）
- **同步边界**：仅苹果来源（`.calendar`）的项参与回写——
  - 提醒事项（EKReminder）完成 → 原生回写 `isCompleted`（沿用现有能力）；
  - 日历事件/会议（EKEvent）完成 → **仅本地标记完成，不回写**（EventKit 无事件完成字段）。
- **录入意图分类**：AI 解析输出保留「日程 / 提醒 / 纯任务」意图（kind），但仅用于**本地**展示与提醒强度（如提前量），不决定是否写苹果。
- **截图保留与关联**：截图/贴图识图创建的本地项 SHALL 保留原图并关联到对应任务（沿用既有 `screenshotPath`）。
- **BREAKING**（行为）：「Later」(Inbox) 页签不再展示个人任务，个人任务完全并入 Calendar 页签时间线；Later 仅保留 Jira 等外部来源待办。
- Calendar 页签 SHALL 在苹果来源日历事件/提醒之外，按时间点同时渲染本地个人任务，形成统一时间线视图。

## Capabilities

### New Capabilities
<!-- 无全新能力；均为对现有 capability 的需求级修改。 -->

### Modified Capabilities
- `apple-calendar-integration`: 明确同步边界——灵动岛创建项不写入苹果日历；苹果来源事件完成仅本地、提醒完成沿用原生回写。Calendar 页签展示范围扩展为「苹果来源日历事件/提醒 + 本地个人任务」统一时间线。
- `ai-pipeline`: `parseScreenshot` / `parseQuickInput` 的 TodoDraft 输出新增「日程 vs 提醒 vs 纯任务」意图字段，仅用于本地分类与提醒强度。
- `todo-data`: 「Inbox（全部任务）」分组不再包含个人任务，个人任务改由 Calendar 页签承载；派生集合与计数相应调整。
- `capture`: 截图/贴图识图解析成功后，原图 SHALL 保留并关联到创建的本地任务。

## Impact

- 代码：
  - `Services/AIService.swift` + `Models.swift`（`TodoDraft` 增加 kind/意图字段；Mock 与 OpenAI 实现产出该字段；不新增日历写入方法）
  - `Core/AppStore.swift`（`inboxTodos` 排除个人任务；完成路径维持「仅 `.calendar` 提醒回写、事件本地完成」）
  - `UI/Panels/CalendarPanel.swift`（时间线纳入本地个人任务）、`UI/Panels/InboxPanel.swift`（移除个人任务区段）
  - `UI/Cards/QuickInputCard.swift`（提交链路保持仅本地）
- 依赖：仅用到既有 EventKit 读取与提醒完成/Snooze 回写，**不新增写事件能力**；无苹果数据时仅本地运行。
- 数据：既有 `Todo.screenshotPath` 复用，无需新增模型字段（除 kind）；`mergeCalendarTodos()` 行为不变。
