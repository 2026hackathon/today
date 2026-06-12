# todo-data Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: 单一数据源 AppStore
所有 UI SHALL 通过 `AppStore`（ObservableObject）读写数据；AppStore SHALL 提供 Todo 的创建 / 编辑 / 完成 / 删除 / Snooze 与 Meeting 的替换式同步。

#### Scenario: 完成一个 Todo
- **WHEN** 调用 `store.complete(todo)`
- **THEN** todo.completedAt 置为当前时间、列表计数即时更新、触发持久化、若今日全部完成则切换 celebrate 状态

### Requirement: 三大分组
分组依据 SHALL 从「来源」改为「时间相关性」（本 requirement 被今日焦点派生取代，来源仅作行内标识）。AppStore SHALL 提供以下派生集合，Today 面板按 日程 → 已超期 → 今日任务 顺序展示：

- **今日日程**：今天的全部会议，按开始时间排序
- **已超期**：截止时间已过的未完成任务；个人来源全部计入，Jira 仅活跃状态（非 To Do/Done/Cancelled）计入
- **今日任务**：① 今天截止（含 snoozedUntil 今天到点）的任务按时间排序；② 活跃状态 Jira；③ 无截止时间的非 Jira 任务按优先级排序，置于「无固定时间」细分隔线下
- **Inbox（全部任务）**：其余未完成任务（未来截止 + To Do 状态 Jira），按 个人/Jira 分组、截止时间排序

#### Scenario: 活跃 Jira 进入今日任务
- **WHEN** Jira ticket 状态为 In Progress / In Review 等活跃状态
- **THEN** 它出现在「今日任务」，To Do 状态的 ticket 只出现在 Inbox

#### Scenario: 无截止时间的提醒事项
- **WHEN** 个人任务（含提醒事项同步）无截止时间
- **THEN** 显示在「今日任务」的「无固定时间」分隔线下，按优先级排序，不触发提醒、不进已超期

#### Scenario: 收缩态计数一致
- **WHEN** Today 面板显示 N 项焦点（已超期 + 今日任务）
- **THEN** compact 态数字与 N 一致

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

### Requirement: 超期锚点与解码兼容
任务的超期判定 SHALL 以 `snoozedUntil ?? dueDate` 为锚（snooze 到未来 → 不超期、回「今日任务」分组）；`Todo` 的持久化解码 SHALL 对缺失字段取默认值（向后兼容），新增模型字段不得导致历史 todos.json 解码失败。

#### Scenario: 超期任务 snooze 到今天下午
- **WHEN** 已超期任务被 snooze 到今天 15:00
- **THEN** 它离开「已超期」进入「今日任务」（按 15:00 排序），15:00 过后才重新计为超期

#### Scenario: 升级后打开旧数据
- **WHEN** 新版本给 Todo 增加了字段，用户用旧 todos.json 启动
- **THEN** 数据全部加载成功，新字段取默认值

