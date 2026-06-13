## 1. WorkItem 模型（Models.swift）

- [x] 1.1 新增 `WorkItemSource { case jira, github }` 与 `struct WorkItem`（key/title/source/status/statusCategory/assigner/storyPoints/url/priority/updatedAt/draft），含 `storyPointsLabel`、活跃判断辅助
- [x] 1.2 `WorkItem` 逐字段 `decodeIfPresent` 向后兼容解码
- [x] 1.3 `Todo` 移除 `jiraKey/jiraURL/jiraStatus/jiraStatusCategory/jiraAssigner/storyPoints` 字段及其 init/解码/`storyPointsLabel`
- [x] 1.4 `TodoSource` 移除 `.jira/.github`（保留 screenshot/manual/calendar），同步 label/图标/配色分支

## 2. Store 派生与合并（AppStore.swift）

- [x] 2.1 新增 `@Published workItems: [WorkItem]`（落 `workItems.json`）
- [x] 2.2 派生 `activeWorkItems` / `inboxWorkItems`（活跃判断迁到 WorkItem）
- [x] 2.3 删除 `isActiveJira/isExternal/todayExternalTodos/readOnlySources` 等 Todo 外部特判；`overdueTodos/todayTimed/todayUntimed/inboxTodos/personalTodos` 回归纯个人任务
- [x] 2.4 `todayFocusCount` = 个人焦点 + `activeWorkItems.count`；compact 打钩判定仅看个人可动手任务
- [x] 2.5 `mergeExternalTodos`→`mergeWorkItems(_:source:notify:prune:)`，按 key upsert/prune + 降落通知
- [x] 2.6 启动加载：`todos.json` 中 `.jira/.github` 旧记录在解码后剔除（迁移）；演示数据移除 `.jira` 条目
- [x] 2.7 `canComplete/canDelete` 不再引用 isExternal（个人任务规则不变）

## 3. 服务（JiraService / GitHubService）

- [x] 3.1 `JiraService.fetchAssignedTickets()` 返回 `[WorkItem]`；Real + Mock 改造
- [x] 3.2 `GitHubService.fetchMyPullRequests()` 返回 `[WorkItem]`；Real + Mock 改造
- [x] 3.3 `AppDelegate` 装配：轮询结果走 `mergeWorkItems`；`onWorkItemLanded` 接线降落卡

## 4. UI

- [x] 4.1 `JiraTodoRow` → `WorkItemRow`（吃 `WorkItem`，品牌图标 jira/github、status/SP/assigner、跳转）
- [x] 4.2 TodayPanel：「Jira · GitHub」分组改为「工作项」读 `activeWorkItems`；greeting 可加「N 个工作项」
- [x] 4.3 InboxPanel(Later)：改读 `inboxWorkItems`
- [x] 4.4 `IslandState.jiraLanded` 关联 `WorkItem`；`JiraLandedCard` 适配

## 5. 验收

- [x] 5.1 `cd MiniNotch && swift build -c release` 通过
- [x] 5.2 打包签名重启冒烟：Today 工作项分组、Later 工作项、降落卡、跳转均正常
- [x] 5.3 旧 `todos.json` 含 jira 记录时启动不崩、被迁移剔除
- [x] 5.4 `openspec validate workitem-extraction` 通过
