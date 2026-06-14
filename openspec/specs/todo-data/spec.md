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
`Todo` SHALL 仅表示个人待办（来源 `screenshot/manual/calendar`），不再承载外部工单。外部工单（Jira/GitHub）由独立的 `WorkItem`（见 `work-item` capability）承载，不再出现在任何 `Todo` 派生集合中。AppStore 的今日焦点派生 SHALL 调整为：

- **已超期**：截止已过的未完成个人任务（外部工单不计入超期）
- **今日任务**：① 今天截止（含 snoozedUntil 今天到点）的个人任务与当天 `.calendar` 任务按时间排序；② 无截止个人任务按优先级排在「无固定时间」下
- **工作项**：活跃工作项（`activeWorkItems`）作为独立只读分组在今日任务之后展示，不可完成
- **Inbox（Later）**：仅展示非活跃工作项（`inboxWorkItems`）；个人任务由 Calendar 页签承载（沿用 later-into-calendar），Later 不含个人任务

#### Scenario: Todo 不再含外部来源
- **WHEN** 遍历任意 `Todo` 派生集合（overdue/today/inbox/personal）
- **THEN** 不存在 `source == .jira` 或 `.github` 的项（该枚举值已移除）

#### Scenario: 焦点计数清晰相加
- **WHEN** Today 显示焦点数 N
- **THEN** N = 已超期个人任务 + 今日个人任务 + 活跃工作项，且与 compact 态数字一致

#### Scenario: 旧数据迁移
- **WHEN** 启动时 `todos.json` 含旧的 `.jira/.github` 记录（旧版本写入）
- **THEN** 这些记录在加载后被剔除，不进入 `todos`；外部工单由下一轮轮询重建为 `WorkItem`

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

### Requirement: 日历与提醒同步为今日任务
AppStore SHALL 在每次日历同步（replaceMeetings）后，将当天的日历事件与提醒事项合并为 `.calendar` 来源的 Todo（`dueDate` = 事件开始时间，`calendarEventId` = EventKit 稳定标识）。合并 SHALL 满足：

- **Upsert**：按 `calendarEventId` 匹配已有任务，存在则更新标题/时间（保留 `completedAt`、`snoozedUntil` 等本地状态），不存在则新增；外部已完成的提醒不再新建任务
- **不复活**：已完成（`completedAt != nil`）的 `.calendar` 任务在后续同步中 SHALL NOT 被清除完成态，prune 时 SHALL 跳过
- **Prune**：当天范围内、`.calendar` 来源、未完成、且本次同步未出现的任务 SHALL 删除
- **外部完成同步**：提醒在 EventKit 中已完成且本地任务未完成时，SHALL 单向置为完成（EventKit 未完成不清本地完成态）

#### Scenario: 当天日程出现在今日任务
- **WHEN** 日历有今天 14:00 的事件「评审会」且提醒事项有今天 18:00 的「交周报」
- **THEN** 「今日任务」出现两条 `.calendar` 来源任务，按时间排在对应位置，可点击完成

#### Scenario: 重复同步不产生重复任务
- **WHEN** 同一事件在 15 分钟轮询中被连续拉取多次
- **THEN** 列表中始终只有一条对应任务（按 calendarEventId upsert）

#### Scenario: 事件标题在日历中被修改
- **WHEN** 用户在系统日历中将「评审会」改名为「设计评审」
- **THEN** 下次同步后任务标题更新为「设计评审」，完成/snooze 状态保留

#### Scenario: 事件被从日历删除
- **WHEN** 用户在系统日历删除当天某事件且对应任务未完成
- **THEN** 下次同步后该任务从列表中移除

#### Scenario: 已完成任务不复活
- **WHEN** 某日历事件任务已完成，且该事件仍存在于日历中被再次同步
- **THEN** 任务保持完成态，不重新出现在「今日任务」

#### Scenario: 外部勾选同步进本地
- **WHEN** 用户在 Apple 提醒事项 App 勾掉一条今天的提醒
- **THEN** 下次同步后对应本地任务置为完成；无对应本地任务时不新建

### Requirement: 日历任务完成后不再显示
`.calendar` 来源任务完成后 SHALL 与普通任务一致：从「今日任务」消失、进入「已完成」折叠区、参与当日全部完成的 celebrate 判定；若该任务来自提醒事项，AppStore SHALL 触发 EventKit 完成回写（撤销完成亦回写取消）。

#### Scenario: 点击完成日程任务
- **WHEN** 用户在「今日任务」点击完成「评审会」
- **THEN** 该项立即从「今日任务」消失，出现在「已完成」折叠区，compact 态计数减一

#### Scenario: 完成提醒事项任务
- **WHEN** 用户点击完成来自提醒事项的任务
- **THEN** 本地完成态立即生效，并异步将对应 EKReminder 标记为已完成

#### Scenario: 撤销完成提醒任务
- **WHEN** 用户在「已完成」折叠区撤销一条提醒任务
- **THEN** EventKit 中该提醒恢复未完成，任务回到「今日任务」且不被下一轮合并翻回

### Requirement: 今日任务展示会议标签与加入链接

Today 列表中 `.calendar` 来源的任务，若其对应会议（按 `Todo.calendarEventId` 匹配 `Meeting.eventIdentifier`）已检测到会议平台（`Meeting.platform`），任务行 SHALL 展示该平台标签（如「Zoom」「腾讯会议」）。若该会议带有加入链接（`Meeting.link`），任务行 SHALL 额外提供一键「加入会议」入口以打开该链接。

匹配 SHALL 优雅降级：当 `.calendar` 任务找不到对应会议、或对应会议无平台/无链接（如提醒事项、全天事件、无链接日程）时，任务行 SHALL 与现状完全一致渲染，不显示空标签或失效按钮。平台与链接 SHALL 复用既有提取结果（`CalendarService.extractMeetingLink`），本需求不改变日历同步与链接提取行为。

#### Scenario: 带平台与链接的日程在今日任务显示会议标签与加入入口
- **WHEN** 今天 14:00 的日历事件「评审会」notes 含 Zoom 链接，已同步为 `.calendar` 任务并出现在「今日任务」
- **THEN** 该任务行展示「Zoom」会议标签
- **AND** 该任务行提供「加入会议」入口，点击后打开该 Zoom 链接

#### Scenario: 仅有平台无链接时只显示标签
- **WHEN** 某 `.calendar` 任务对应会议检测到平台但 `Meeting.link` 为空
- **THEN** 任务行展示平台标签
- **AND** 任务行 SHALL NOT 显示「加入会议」入口

#### Scenario: 非会议的日历任务保持原样
- **WHEN** 一个 `.calendar` 来源任务对应的是提醒事项或无可识别平台的事件
- **THEN** 任务行不展示会议标签与加入入口，与未改动前的渲染一致

#### Scenario: 会议尚未同步或无 calendarEventId 时不报错
- **WHEN** 某 `.calendar` 任务的 `calendarEventId` 缺失，或对应会议尚未出现在已加载的 meetings 列表中
- **THEN** 行内会议查找返回空，任务行按现状渲染，不出现空标签

