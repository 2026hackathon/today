## ADDED Requirements

### Requirement: WorkItem 模型
系统 SHALL 提供独立于 `Todo` 的 `WorkItem` 值类型，表示来自外部系统、本地只读、由外部驱动状态的工作项（Jira ticket / GitHub PR）。`WorkItem` SHALL 至少包含：稳定标识 `key`（Jira issueKey / GitHub `repo#number`）、`title`、`source`（`jira`/`github`）、`status`（展示名）、`statusCategory`（机器值 new/indeterminate/done，用于活跃判断）、`assigner`、`storyPoints`、`url`、`priority`、`updatedAt`。`WorkItem` SHALL 提供逐字段 `decodeIfPresent` 的向后兼容解码。

#### Scenario: 工作项不可在 app 内完成
- **WHEN** 用户在任意面板看到一个 WorkItem 行
- **THEN** 不提供完成勾选/删除操作，仅提供跳转到外部链接

#### Scenario: 活跃判断以 statusCategory 为准
- **WHEN** WorkItem 的 `statusCategory == "indeterminate"`（Jira In Progress 类）或为 GitHub 待 review/已指派
- **THEN** 该工作项被视为「活跃」，进入今日焦点
- **AND WHEN** statusCategory 缺失时回退到 status 名称黑名单（to do/backlog/done/closed 等视为非活跃）

### Requirement: WorkItem 派生集合
`AppStore` SHALL 维护 `workItems: [WorkItem]` 单一数据源，并提供派生：`activeWorkItems`（活跃，进 Today）、`inboxWorkItems`（非活跃，进 Later/Inbox）。焦点计数 `todayFocusCount` SHALL 等于「个人今日任务 + activeWorkItems」之和；compact 态打钩判定 SHALL 仅看个人可动手任务，不被只读工作项阻塞。

#### Scenario: 活跃工作项进 Today
- **WHEN** 存在一个 In Progress 的 Jira 或待 review 的 GitHub PR
- **THEN** 它出现在 Today 的「工作项」分组，且计入 `todayFocusCount`

#### Scenario: 非活跃工作项进 Later
- **WHEN** 存在一个 To Do/Backlog 的 Jira
- **THEN** 它出现在 Later(Inbox) 页签，不计入今日焦点

#### Scenario: 工作项不阻塞今日清空
- **WHEN** 个人任务全部完成，仅剩活跃工作项
- **THEN** compact 态仍可进入清空/打钩态（只读工作项不算「可动手」）

### Requirement: WorkItem 轮询合并
`AppStore` SHALL 提供 `mergeWorkItems(_:source:notify:prune:)`，按 `key` upsert：已存在则更新 status/assigner 等可变字段，新出现则追加并（可选）播放降落卡；本轮未返回的同源工作项 SHALL 被 prune。新分配的工作项 SHALL 通过降落卡通知（携带 `WorkItem`）。

#### Scenario: 重复轮询不产生重复
- **WHEN** 连续两轮拉取返回相同 key 的工作项
- **THEN** 仅保留一条，字段更新为最新

#### Scenario: 工单消失即清理
- **WHEN** 某工作项在最新一轮拉取中不再返回（已 Done/取消指派）
- **THEN** 它从 `workItems` 中移除
