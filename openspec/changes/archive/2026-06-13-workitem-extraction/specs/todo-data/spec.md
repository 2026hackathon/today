## MODIFIED Requirements

### Requirement: 三大分组
`Todo` SHALL 仅表示个人待办（来源 `screenshot/manual/calendar`），不再承载外部工单。外部工单（Jira/GitHub）由独立的 `WorkItem`（见 `work-item` capability）承载，不再出现在任何 `Todo` 派生集合中。AppStore 的今日焦点派生 SHALL 调整为：

- **已超期**：截止已过的未完成个人任务（外部工单不计入超期）
- **今日任务**：① 今天截止（含 snoozedUntil 今天到点）的个人任务与当天 `.calendar` 任务按时间排序；② 无截止个人任务按优先级排在「无固定时间」下
- **工作项**：活跃工作项（`activeWorkItems`）作为独立只读分组在今日任务之后展示，不可完成
- **Inbox（Later）**：仅展示非活跃工作项（`inboxWorkItems`）；个人任务由 Calendar 页签承载（沿用 later-into-calendar），Later 不含个人任务

#### Scenario: Todo 不再含外部来源
- **WHEN** 遍历任意 `Todo` 派生集合（overdue/today/inbox/personal）
- **THEN** 不存在 `source == .jira` 或 `.github` 的项（该枚举值已移除）

#### Scenario: 焦点计数清晰相加
- **WHEN** Today 显示焦点数 N
- **THEN** N = 已超期个人任务 + 今日个人任务 + 活跃工作项，且与 compact 态数字一致

#### Scenario: 旧数据迁移
- **WHEN** 启动时 `todos.json` 含旧的 `.jira/.github` 记录（旧版本写入）
- **THEN** 这些记录在加载后被剔除，不进入 `todos`；外部工单由下一轮轮询重建为 `WorkItem`
