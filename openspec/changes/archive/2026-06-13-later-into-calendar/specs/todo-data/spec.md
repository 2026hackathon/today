## MODIFIED Requirements

### Requirement: 三大分组
分组依据 SHALL 从「来源」改为「时间相关性」（本 requirement 被今日焦点派生取代，来源仅作行内标识）。AppStore SHALL 提供以下派生集合，Today 面板按 已超期 → 今日任务 → 已完成 顺序展示（原「今日日程」独立区段移除，当天日程与提醒以 `.calendar` 任务形式进入「今日任务」）：

- **已超期**：截止时间已过的未完成任务；个人来源全部计入，Jira 仅活跃状态（非 To Do/Done/Cancelled）计入
- **今日任务**：① 今天截止（含 snoozedUntil 今天到点）的任务与当天日历/提醒派生的 `.calendar` 任务按时间排序；② 活跃状态 Jira；③ 无截止时间的非 Jira 任务（含全天事件/无时间提醒）按优先级排序，置于「无固定时间」细分隔线下
- **Inbox（全部任务）**：`inboxTodos` SHALL 仅包含**非个人来源**的其余未完成任务（如 To Do 状态 Jira 等外部来源），按来源分组、截止时间排序；个人任务 SHALL NOT 出现在 Inbox/Later 页签，而是统一由 Calendar 页签时间线承载

#### Scenario: 活跃 Jira 进入今日任务
- **WHEN** Jira ticket 状态为 In Progress / In Review 等活跃状态
- **THEN** 它出现在「今日任务」，To Do 状态的 ticket 只出现在 Inbox

#### Scenario: 个人任务不再出现在 Later
- **WHEN** 存在一个未来截止的个人任务
- **THEN** 它不出现在 Inbox/Later 页签，而出现在 Calendar 页签对应日期的时间线中

#### Scenario: Later 仅保留外部来源
- **WHEN** Later 页签渲染
- **THEN** 仅展示 Jira 等外部来源待办，无个人任务区段

#### Scenario: 无截止时间的提醒事项
- **WHEN** 个人任务（含提醒事项同步）无截止时间
- **THEN** 显示在「今日任务」的「无固定时间」分隔线下，按优先级排序，不触发提醒、不进已超期

#### Scenario: 收缩态计数一致
- **WHEN** Today 面板显示 N 项焦点（已超期 + 今日任务）
- **THEN** compact 态数字与 N 一致

#### Scenario: 今日日程区段不再单独展示
- **WHEN** 当天存在日历事件
- **THEN** Today 面板不再渲染「今日日程」独立区段，事件以可完成任务出现在「今日任务」中；顶部摘要的「N 场会议」计数保留
