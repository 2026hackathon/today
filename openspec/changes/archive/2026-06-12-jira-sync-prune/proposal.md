# Proposal: jira-sync-prune

## Why

Jira 同步目前只增不删：ticket 被转走/关闭后仍留在本地列表（实测 MD-18101 已不归我但还在）。列表应忠实镜像「当前 assign 给我的未完成 ticket」。

## What Changes

- `mergeJiraTodos` 增加清理：本地未完成的 Jira todo，其 key 不在本次拉取结果中 → 移除（本地已标完成的保留，不影响「已完成」列表）
- `RealJiraService` 支持 nextPageToken 分页（最多 5 页/250 条），保证拉取完整后再清理，避免分页截断误删
- Debug「模拟 Jira 新分配」走 `prune: false`，Mock 数据不清掉真实 ticket

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `integrations`: Jira 同步 requirement 增加镜像清理行为

## Impact

- `Core/AppStore.swift` mergeJiraTodos、`Services/JiraService.swift` 分页、`AppDelegate` debug 调用
