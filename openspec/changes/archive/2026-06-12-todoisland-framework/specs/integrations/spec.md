# integrations

Jira / Apple 日历 / 推送集成协议与 mock。Owner: C。

## ADDED Requirements

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
