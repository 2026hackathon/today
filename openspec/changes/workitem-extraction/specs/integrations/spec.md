## MODIFIED Requirements

### Requirement: JiraService 协议
`JiraService.fetchAssignedTickets()` SHALL 返回 `[WorkItem]`（不再是 `[Todo]`），映射 issueKey→`key`、summary→`title`、status/statusCategory、priority、duedate→`updatedAt` 参考、assigner（changelog）、storyPoints（customfield_10025）。Mock 实现 SHALL 同步返回 `[WorkItem]` 供联调。

#### Scenario: Jira 拉取产出 WorkItem
- **WHEN** 调用 `fetchAssignedTickets()`
- **THEN** 返回的每个元素是 `WorkItem`（source `.jira`），含 key/status/statusCategory/assigner/storyPoints

### Requirement: GitHub PR 拉取与通知
`GitHubService.fetchMyPullRequests()` SHALL 返回 `[WorkItem]`（source `.github`），`key="repo#number"`、`status` 为「待 Review/已指派/Draft」、`assigner` 为 PR 作者、`url` 为 PR 页面。新 PR SHALL 通过降落卡通知（携带 `WorkItem`）。

#### Scenario: GitHub 拉取产出 WorkItem
- **WHEN** 调用 `fetchMyPullRequests()`
- **THEN** 返回 `WorkItem` 列表，key 形如 `repo#123`，可跳转 PR 页面

### Requirement: Jira 同步镜像清理
同步镜像清理 SHALL 以 `WorkItem.key` 为准对 `workItems` 做 upsert/prune（替代原先对 `todos` 按 `jiraKey` 的清理）：本轮未返回的同源工作项被移除，已存在的更新可变字段，新出现的追加。

#### Scenario: 同源 prune 不误伤
- **WHEN** Jira 轮询返回集合 A，GitHub 轮询返回集合 B
- **THEN** prune 仅作用于对应 source，互不影响
