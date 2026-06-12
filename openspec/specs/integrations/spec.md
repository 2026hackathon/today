# integrations Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: JiraService 协议
框架 SHALL 定义 `JiraService.fetchAssignedTickets() -> [Todo]`；真实现轮询周期 60s；新 ticket SHALL 触发蓝色 Touchdown 动效。

#### Scenario: 新分配 ticket
- **WHEN** 轮询发现新 jiraKey
- **THEN** todo 加入 Jira 分组并播放蓝色任务降落动效

### Requirement: CalendarService 协议
框架 SHALL 定义 `CalendarService.fetchTodayMeetings() -> [Meeting]`；真实现基于 EventKit 拉取今日所有日历事件并提取会议链接（6 大平台）。

#### Scenario: 今日会议展示
- **WHEN** 日历中有今天的会议
- **THEN** 展开态「今日会议」分组按时间排序展示，含平台标识与「加入会议」跳转

### Requirement: PushService 协议
框架 SHALL 定义 `PushService.push(title:body:)`；默认 Noop 实现；真实现接飞书 webhook / Bark / ClawBot。

#### Scenario: 到期推送
- **WHEN** 提醒到期且配置了推送通道
- **THEN** 30s 内推送送达（由真实现保证）

### Requirement: Mock 数据联调
MockJiraService SHALL 返回 3 条演示 ticket，MockCalendarService SHALL 返回今日 2 场会议（与 prototype 一致），保证 UI 可独立开发。

#### Scenario: 无凭证启动
- **WHEN** 未配置 Jira/日历授权
- **THEN** 展开态三分组仍有内容可看（mock 数据）

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

### Requirement: Jira 同步镜像清理
Jira 同步 SHALL 使列表镜像「当前 assign 给我的未完成 ticket」：本地未完成的 Jira todo 若 key 不在本次完整拉取结果中 SHALL 被移除；本地已完成的保留。RealJiraService SHALL 按 nextPageToken 分页拉全后再清理。

#### Scenario: ticket 被转走
- **WHEN** ticket 在 Jira 中改派他人或关闭，下一轮同步（≤60s）或手动刷新后
- **THEN** 该 ticket 从 Today/Inbox 列表消失

#### Scenario: Debug 模拟不清真实数据
- **WHEN** 使用 Debug「模拟 Jira 新分配」（Mock 数据）
- **THEN** 真实 ticket 不被清除（prune 关闭）

### Requirement: GitHub PR 拉取与通知
`GitHubService` SHALL 通过 GitHub Search API 拉取待我 review（`review-requested:@me`）与指派给我（`assignee:@me`）的 open PR，按 PR URL 去重，映射为只读 todo（source=github，key=`repo#123`，作者作指派人，draft 降为低优先级）。同步 SHALL 复用外部镜像合并（按 github 来源清理），新 PR 且 compact 态 SHALL 弹通知卡（GitHub 紫）。Token 未配置时 SHALL 回退 Mock。

#### Scenario: 新 PR 请求我 review
- **WHEN** 同事在 PR 上 request 我 review，下一轮轮询后
- **THEN** 通知卡浮起（「新 PR 待处理」+ 作者 + repo#编号），倒计时后收入岛体，「今日任务」出现该 PR 行

#### Scenario: PR 合并或移除 review 请求
- **WHEN** PR 关闭/合并/取消 review 请求
- **THEN** 下一轮同步后该行消失（镜像清理，不影响 Jira 来源）

#### Scenario: 点击 PR 行
- **WHEN** 点击 PR 行任意位置
- **THEN** 浏览器打开 PR 页面（只读集成，不提供完成圈）

