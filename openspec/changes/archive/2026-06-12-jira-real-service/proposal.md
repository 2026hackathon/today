# Proposal: jira-real-service

## Why

框架的 Jira 集成（F-12）目前只有 Mock。需要接真实 Jira Cloud API，让灵动岛展示真实指派的 ticket，并保留 Mock 作为 Demo 兜底（PRD 风险缓解要求）。

## What Changes

- 实现 `RealJiraService`：Jira Cloud `/rest/api/3/search/jql` 端点（旧 `/rest/api/3/search` 已被 Atlassian 下线）+ Basic Auth，issues → Todo 映射（含优先级/截止日期）
- AppDelegate 轮询装配改为**按配置动态选择**：settings 三项（baseURL/email/token）齐全 → Real，否则 → Mock；设置面板改完即生效（下个轮询周期），无需重启
- Mock 实例常驻保留（Debug 菜单「模拟 Jira 新分配」继续可用）

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `integrations`: 新增「Jira 真实拉取与装配降级」requirement（端点、字段映射、配置切换规则）

## Impact

- `Services/JiraService.swift`: RealJiraService 真实现
- `AppDelegate.swift`: 轮询处按配置选择服务
- 实测验证：wonder.atlassian.net 真实账号拉取成功
