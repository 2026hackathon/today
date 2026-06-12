# integrations (delta)

## ADDED Requirements

### Requirement: Jira 同步镜像清理
Jira 同步 SHALL 使列表镜像「当前 assign 给我的未完成 ticket」：本地未完成的 Jira todo 若 key 不在本次完整拉取结果中 SHALL 被移除；本地已完成的保留。RealJiraService SHALL 按 nextPageToken 分页拉全后再清理。

#### Scenario: ticket 被转走
- **WHEN** ticket 在 Jira 中改派他人或关闭，下一轮同步（≤60s）或手动刷新后
- **THEN** 该 ticket 从 Today/Inbox 列表消失

#### Scenario: Debug 模拟不清真实数据
- **WHEN** 使用 Debug「模拟 Jira 新分配」（Mock 数据）
- **THEN** 真实 ticket 不被清除（prune 关闭）
