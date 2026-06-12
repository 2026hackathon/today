# integrations (delta)

## ADDED Requirements

### Requirement: Jira 真实拉取与装配降级
`RealJiraService` SHALL 调用 Jira Cloud `GET /rest/api/3/search/jql`（JQL: `assignee=currentUser() AND statusCategory != Done ORDER BY updated DESC`，fields: summary,status,priority,duedate，Basic Auth email:apiToken）。轮询装配 SHALL 按设置动态选择：`jiraBaseURL`/`jiraEmail`/`jiraAPIToken` 三项齐全时用 Real，任一为空回退 Mock，设置变更后下个轮询周期即生效。

#### Scenario: 配置齐全拉取真实 ticket
- **WHEN** 设置面板填好 Jira URL/Email/Token 且凭证有效
- **THEN** 60s 内「Jira Tickets」分组出现真实指派的未完成 ticket，优先级映射（Highest/High→高，Medium→中，其余→低），点击编号跳转 `{baseURL}/browse/{key}`

#### Scenario: 凭证错误或网络失败
- **WHEN** API 返回非 2xx 或请求抛错
- **THEN** 本轮静默跳过（NSLog 记录），列表保持上次数据，不弹任何错误 UI

#### Scenario: 清空配置回退 Mock
- **WHEN** 用户清空任一 Jira 配置项
- **THEN** 下个轮询周期起回到 Mock 演示数据，Debug「模拟 Jira 新分配」仍可用
