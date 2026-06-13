## ADDED Requirements

### Requirement: 日历与提醒同步为今日任务
AppStore SHALL 在每次日历同步（replaceMeetings）后，将当天的日历事件与提醒事项合并为 `.calendar` 来源的 Todo（`dueDate` = 事件开始时间，`calendarEventId` = EventKit 稳定标识）。合并 SHALL 满足：

- **Upsert**：按 `calendarEventId` 匹配已有任务，存在则更新标题/时间（保留 `completedAt`、`snoozedUntil` 等本地状态），不存在则新增
- **不复活**：已完成（`completedAt != nil`）的 `.calendar` 任务在后续同步中 SHALL NOT 被清除完成态，prune 时 SHALL 跳过
- **Prune**：当天范围内、`.calendar` 来源、未完成、且本次同步未出现的任务 SHALL 删除

#### Scenario: 当天日程出现在今日任务
- **WHEN** 日历有今天 14:00 的事件「评审会」且提醒事项有今天 18:00 的「交周报」
- **THEN** 「今日任务」出现两条 `.calendar` 来源任务，按时间排在对应位置，可点击完成

#### Scenario: 重复同步不产生重复任务
- **WHEN** 同一事件在 15 分钟轮询中被连续拉取多次
- **THEN** 列表中始终只有一条对应任务（按 calendarEventId upsert）

#### Scenario: 事件标题在日历中被修改
- **WHEN** 用户在系统日历中将「评审会」改名为「设计评审」
- **THEN** 下次同步后任务标题更新为「设计评审」，完成/snooze 状态保留

#### Scenario: 事件被从日历删除
- **WHEN** 用户在系统日历删除当天某事件且对应任务未完成
- **THEN** 下次同步后该任务从列表中移除

#### Scenario: 已完成任务不复活
- **WHEN** 某日历事件任务已完成，且该事件仍存在于日历中被再次同步
- **THEN** 任务保持完成态，不重新出现在「今日任务」

### Requirement: 日历任务完成后不再显示
`.calendar` 来源任务完成后 SHALL 与普通任务一致：从「今日任务」消失、进入「已完成」折叠区、参与当日全部完成的 celebrate 判定；若该任务来自提醒事项，AppStore SHALL 触发 EventKit 完成回写。

#### Scenario: 点击完成日程任务
- **WHEN** 用户在「今日任务」点击完成「评审会」
- **THEN** 该项立即从「今日任务」消失，出现在「已完成」折叠区，compact 态计数减一

#### Scenario: 完成提醒事项任务
- **WHEN** 用户点击完成来自提醒事项的任务
- **THEN** 本地完成态立即生效，并异步将对应 EKReminder 标记为已完成

## MODIFIED Requirements

### Requirement: 三大分组
分组依据 SHALL 从「来源」改为「时间相关性」（本 requirement 被今日焦点派生取代，来源仅作行内标识）。AppStore SHALL 提供以下派生集合，Today 面板按 已超期 → 今日任务 → 已完成 顺序展示（原「今日日程」独立区段移除，当天日程与提醒以 `.calendar` 任务形式进入「今日任务」）：

- **已超期**：截止时间已过的未完成任务；个人来源全部计入，Jira 仅活跃状态（非 To Do/Done/Cancelled）计入
- **今日任务**：① 今天截止（含 snoozedUntil 今天到点）的任务与当天日历/提醒派生的 `.calendar` 任务按时间排序；② 活跃状态 Jira；③ 无截止时间的非 Jira 任务（含全天事件/无时间提醒）按优先级排序，置于「无固定时间」细分隔线下
- **Inbox（全部任务）**：其余未完成任务（未来截止 + To Do 状态 Jira），按 个人/Jira 分组、截止时间排序

#### Scenario: 活跃 Jira 进入今日任务
- **WHEN** Jira ticket 状态为 In Progress / In Review 等活跃状态
- **THEN** 它出现在「今日任务」，To Do 状态的 ticket 只出现在 Inbox

#### Scenario: 无截止时间的提醒事项
- **WHEN** 个人任务（含提醒事项同步）无截止时间
- **THEN** 显示在「今日任务」的「无固定时间」分隔线下，按优先级排序，不触发提醒、不进已超期

#### Scenario: 收缩态计数一致
- **WHEN** Today 面板显示 N 项焦点（已超期 + 今日任务）
- **THEN** compact 态数字与 N 一致

#### Scenario: 今日日程区段不再单独展示
- **WHEN** 当天存在日历事件
- **THEN** Today 面板不再渲染「今日日程」独立区段，事件以可完成任务出现在「今日任务」中；顶部摘要的「N 场会议」计数保留
