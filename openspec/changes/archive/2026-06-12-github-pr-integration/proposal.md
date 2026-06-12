# Proposal: github-pr-integration

## Why

研发的"待办"除了 Jira ticket 还有 GitHub PR（待我 review / 指派给我的）。PR 与 ticket 同构：外部只读、轮询镜像、新分配要通知——完全复用 Jira 链路即可低成本接入。

## What Changes

- `TodoSource` 新增 `github`；复用 Todo 的 ticket 字段（jiraKey="repo#123"、jiraStatus="待 Review"、jiraAssigner=PR 作者）
- 新建 `GitHubService`（protocol + Mock + Real）：GitHub Search API 拉取 `review-requested:@me` + `assignee:@me` 的 open PR，合并去重
- `AppStore.mergeJiraTodos` 泛化为 `mergeExternalTodos(source:)`（按来源镜像清理），Jira 包装器保留不破调用方
- 新 PR 复用 `jiraLanded` 通知卡（文案/图标/颜色按来源区分：GitHub 紫 `#8250DF` + pull 图标）
- GitHub PR 始终进「今日任务」（待 review 即当下要处理）；TaskRow 按来源路由到只读 ticket 行
- 设置页新增 GitHub Token；轮询间隔与 Jira 共用

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `integrations`: 新增 GitHub PR 拉取 requirement

## Impact

- Models/AppStore/IslandState 契约小幅扩展；Services/GitHubService.swift 新建
- AppDelegate 轮询与装配、SettingsPanel、JiraLandedCard、TodayPanel TaskRow
