## Context

现有链路：`QuickInputCard`（⌘N，含剪贴板贴图）与 F2 截图 → `AIService.parseQuickInput/parseScreenshot` → `TodoDraft` → `AppStore` 落本地 Todo。`EventKitCalendarService` 已做**读**（fetchMeetings）与**提醒完成/Snooze 回写**（setReminderCompleted / setReminderDue），不会新建任何日历项——这正符合本次「创建仅本地」的方向。`mergeCalendarTodos()` 把 EventKit 的 Meeting 按 `eventIdentifier` upsert 成 `.calendar` 来源 Todo。

「Later」(`.inbox` 页签) 通过 `inboxTodos` 派生集合展示「今日焦点之外的全部 pending todo」，个人任务与 Jira 混排。「Calendar」(`.calendar` 页签) 当前只渲染 EventKit 来源的 `meetingsByDate`。

本次方向（经确认）：**灵动岛创建的日程/提醒/任务只在本地，不写苹果**；**苹果来源项的完成尽量回写**（提醒原生回写、事件仅本地）；个人任务从 Later 收敛进 Calendar 时间线。

## Goals / Non-Goals

**Goals:**
- 「+」/识图创建的项一律仅本地，不调用任何苹果写入；保留 kind 用于本地分类与提醒强度。
- 同步边界清晰：仅 `.calendar` 来源参与回写——提醒完成→EventKit；事件完成→本地。
- 截图/贴图原图保留并关联到本地任务。
- Later 不再含个人任务；个人任务进入 Calendar 统一时间线。

**Non-Goals:**
- 不新增 `createEvent`/`createReminder` 等苹果写入能力（初版方向已撤销）。
- 不把本地优先级映射进苹果日历（事件无原生优先级字段，且本地项本就不写苹果）。
- 不改 F2/F3 热键、截图采集、晨晚报、邮件提醒等既有能力。
- 不为日历事件伪造「完成」状态（不改标题、不删除事件）。

## Decisions

### D1：draft 携带 `kind`，仅用于本地分类
为 `TodoDraft` 增加意图字段（`enum DraftKind { case event, reminder, task }`）。`parseQuickInput`/`parseScreenshot` 产出该字段：有明确时间点的会议/约会→`.event`；有截止的待办→`.reminder`；无时间/纯笔记→`.task`。kind **不**触发任何苹果写入，只影响本地展示分组与提醒强度（如 `.event`/`.reminder` 用不同默认提前量）。Mock 用现有启发式，OpenAI 在 JSON schema 增 `kind` 字段，缺省回退 `.task`。

### D2：同步边界——只读 + 仅来源回写
- **创建**：所有灵动岛创建项 source 为本地（screenshot/manual 等），落本地 Todo，不触苹果。
- **完成回写**：仅当 `source == .calendar`（来自苹果同步）时——
  - 该项是提醒（`Meeting.isReminder` / 对应 EKReminder）→ 调既有 `onReminderCompletionChanged` → `setReminderCompleted` 回写（沿用现状）；
  - 该项是日历事件 → 仅置本地 `completedAt`，**不**调用任何 EventKit 写入（EventKit 的 EKEvent 无 isCompleted；不改标题、不删事件以免破坏用户日历）。
- Snooze/改期回写仍只对提醒生效（既有 `onReminderSnoozed`）。

*备选*：给事件标题加 ✅ 前缀或删除事件以表达完成。否决（经用户确认）——会修改/破坏用户真实日历，风险高。

### D3：Later → Calendar 收敛
- `inboxTodos` 过滤掉个人来源（仅保留 Jira/外部），Later 页签个人任务区段移除。
- `CalendarPanel` 时间线在 `meetingsByDate` 基础上并入本地个人任务：有 dueDate 的按日期/时间归入对应分组，无时间的归入当天「无固定时间」区，复用日期分组与完成标识渲染。
*备选*：把个人任务也写成日历项再统一展示。否决——与「创建仅本地」方向冲突，且会污染系统日历。

### D4：截图保留与关联（本地）
沿用既有：F2/贴图保存到 `Persistence.screenshotsDir`，路径写入 `TodoDraft.screenshotPath` → `Todo.screenshotPath`。本次只需确保卡片/详情有「查看原图」入口，文件缺失时降级提示，不崩溃。因创建项不再变成 `.calendar`，无需考虑「关联随同步丢失」的问题——关联始终在本地 Todo 上。

## Risks / Trade-offs

- [用户期望「事件完成也回写苹果」未被满足] → EventKit 不支持事件完成状态；已与用户确认仅本地完成。UI 上事件完成仍有对勾反馈，仅不跨设备同步。
- [本地完成与苹果重复展示] → 苹果来源事件本地完成后仍存在于苹果日历，下次同步仍会拉回；`mergeCalendarTodos()` 须保留本地 `completedAt`，不被同步覆盖（既有 upsert 已保留本地完成状态，需回归验证）。
- [Calendar 页签信息过载] → 个人无时间任务集中在「无固定时间」分隔区，避免淹没真实日程。
- [截图文件被清理后悬空] → 打开前校验存在性，缺失时降级「原图已不可用」，不崩溃。

## Open Questions

- 个人任务在 Calendar 时间线是否允许「加入会议」类操作？（默认否，仅展示 + 完成/Snooze）
- `.task`（无时间）个人任务在 Calendar 页签固定落「无固定时间」区——确认采用。
