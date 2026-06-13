# message-inbox Specification

## Purpose
TBD - created by archiving change email-message-reminders. Update Purpose after archive.
## Requirements
### Requirement: Message 数据模型与持久化
框架 SHALL 定义独立的 `Message` 模型（不复用 `Todo`），字段含 `id / summary（一句话提醒）/ source（slack|jira|email）/ link / receivedAt / processedAt? / sender? / rawSubject?`。Message 集合 SHALL 由 `AppStore` 作为单一数据源持有，并持久化到 `~/Library/Application Support/MiniNotch/messages.json`，应用启动恢复、文件缺失时按空集处理、写入失败不崩溃。

#### Scenario: 重启不丢消息
- **WHEN** 收到若干消息后退出并重启应用
- **THEN** 消息列表与各自的已处理状态从 messages.json 恢复

#### Scenario: 旧版本无消息文件
- **WHEN** 升级后首次启动且无 messages.json
- **THEN** 消息列表为空集，不报错、不影响既有 todos/meetings 数据

### Requirement: 消息页签列表与排序
「消息」页签 SHALL 将邮件按**自然天（收件日 `receivedAt` 所在的日历日）分组**展示：每组以一个组头标注该天日期，组内列出当天的邮件。未处理邮件与「已处理」折叠区内的邮件各自独立分组。

分组与排序 SHALL 满足：
- 分组之间按日期**倒序**：最近的一天在最上方。
- 组内邮件按 `receivedAt` **倒序**：当天最新收到的在该组最上方。
- 未处理区与已处理区各自 SHALL 最多展示**最近 3 天**（按存在邮件的日历日计，从最新一天起取 3 天）的分组；更早的日期不展示。

每条邮件 SHALL 展示一句话 summary、来源标识、重要级别，以及该邮件的**收件时间**（见「行内时间等于真实收件时间」要求）。

#### Scenario: 同一天的邮件归入同一组
- **WHEN** 切换到「消息」页签且某天收到多封邮件
- **THEN** 这些邮件归入该天的同一分组，组头标注该天日期

#### Scenario: 分组按天倒序、组内按时间倒序
- **WHEN** 列表中存在跨多天的邮件
- **THEN** 最近的一天分组排在最上方，且每组内最新收到的邮件排在该组最上方

#### Scenario: 未处理最多显示最近 3 天
- **WHEN** 未处理邮件分布在 4 个或更多不同的收件日
- **THEN** 仅展示最近 3 个收件日的分组，更早日期的未处理邮件不展示

#### Scenario: 已处理最多显示最近 3 天
- **WHEN** 已处理邮件分布在 4 个或更多不同的收件日
- **THEN** 「已处理」折叠区仅展示最近 3 个收件日的分组，更早的不展示

### Requirement: 未处理与已处理视觉态
未处理（`processedAt == nil`）消息 SHALL 以白色/常规字色渲染；已处理（`processedAt != nil`）消息 SHALL 以灰色弱化渲染。

#### Scenario: 未处理为白
- **WHEN** 一条消息 processedAt 为空
- **THEN** 该条以白色/常规态显示

#### Scenario: 已处理转灰
- **WHEN** 一条消息被标记已处理
- **THEN** 该条立即转为灰色弱化态

### Requirement: 完成与跳转均转已处理
消息条目 SHALL 提供两种交互：「点击完成」与「点击跳转链接」。两者 SHALL 都调用 `AppStore.markProcessed(_:)` 将该消息标记为已处理（记录 processedAt）；该操作 SHALL 幂等（重复标记不报错、时间不被重复刷新）。「跳转」SHALL 同时打开该消息的 `link`。

#### Scenario: 点击完成
- **WHEN** 用户点击某未处理消息的「完成」
- **THEN** 该消息 processedAt 置为当前时间并转灰，不打开链接

#### Scenario: 点击跳转
- **WHEN** 用户点击某未处理消息的链接
- **THEN** 系统打开该 link 且该消息被标记为已处理（转灰）

#### Scenario: 重复处理幂等
- **WHEN** 对一条已处理消息再次触发完成或跳转
- **THEN** 不报错，processedAt 不被重复刷新（跳转仍打开链接）

### Requirement: 重要级别与分级样式
Message SHALL 携带 AI 分析的重要级别 `importance`（high / medium / low）并持久化。消息行与降落通知卡 SHALL 按级别呈现不同样式：high 用警示红、medium 用强调蓝、low 用弱化灰；级别 SHALL 以标签文案（重要 / 一般 / 次要）与配色同时体现。已处理消息的级别样式 SHALL 统一弱化为灰，不与未处理项争夺注意力。

#### Scenario: 重要邮件红色强调
- **WHEN** 一条未处理消息 importance 为 high
- **THEN** 其消息行级别竖条/标签与降落卡级别标签、倒计时条均用警示红

#### Scenario: 已处理弱化
- **WHEN** 一条 high 消息被标记已处理
- **THEN** 其级别样式转为灰色弱化（不再红色强调）

### Requirement: 行内时间等于真实收件时间
消息行展示的时间 SHALL 等于该邮件的真实收件时间（`receivedAt`），以 24 小时制「HH:mm」呈现，与邮箱中的收件时间一致；SHALL NOT 使用面向截止日的相对文案（如「今晚」「明天」「周X」）来替代收件时间。组头承载日期信息，行内只承载该邮件当天的具体时刻。

#### Scenario: 行内显示真实收件时刻
- **WHEN** 一封邮件的 `receivedAt` 为某日 09:07
- **THEN** 其消息行的时间显示为「09:07」，与邮箱收件时间一致

#### Scenario: 不使用截止日相对文案
- **WHEN** 一封邮件于今天傍晚之后收到
- **THEN** 其行内时间显示为对应的「HH:mm」，而非「今晚」等相对文案

### Requirement: 未读计数文案为「x 条未读邮件」
「消息」页签头部的未读计数文案 SHALL 为「x 条未读邮件」（x 为未处理邮件数）；当无未处理邮件时沿用既有的清空态文案。

#### Scenario: 存在未读邮件
- **WHEN** 有 3 封未处理邮件
- **THEN** 页签头部显示「3 条未读邮件」

#### Scenario: 无未读邮件
- **WHEN** 没有未处理邮件
- **THEN** 页签头部显示既有的清空态文案（如「消息已清空」）

