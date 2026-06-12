# todo-data

Todo / Meeting 数据模型、CRUD、分组与持久化。Owner: B。

## ADDED Requirements

### Requirement: 单一数据源 AppStore
所有 UI SHALL 通过 `AppStore`（ObservableObject）读写数据；AppStore SHALL 提供 Todo 的创建 / 编辑 / 完成 / 删除 / Snooze 与 Meeting 的替换式同步。

#### Scenario: 完成一个 Todo
- **WHEN** 调用 `store.complete(todo)`
- **THEN** todo.completedAt 置为当前时间、列表计数即时更新、触发持久化、若今日全部完成则切换 celebrate 状态

### Requirement: 三大分组
展开态数据 SHALL 按 个人 Todo / Jira Tickets / 今日会议 三组提供，组内按 紧急度 × 临近度 排序。

#### Scenario: Jira todo 归组
- **WHEN** todo.source == .jira
- **THEN** 它出现在 Jira Tickets 组且展示 jiraKey 与状态标签

### Requirement: JSON 本地持久化
数据 SHALL 持久化到 `~/Library/Application Support/MiniNotch/`（todos.json / meetings.json / settings.json），应用启动时恢复，写入失败不崩溃。

#### Scenario: 重启不丢数据
- **WHEN** 创建 todo 后退出并重启应用
- **THEN** todo 仍在列表中

### Requirement: 内置演示数据
首次启动（无持久化文件）SHALL 注入与 prototype.html 一致的演示数据（5 个人 todo + 3 Jira + 2 会议）。

#### Scenario: 首次启动
- **WHEN** 持久化目录为空时启动
- **THEN** island 显示 compact normal 态、计数为未完成演示任务数
