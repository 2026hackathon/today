## ADDED Requirements

### Requirement: Message 数据模型与持久化
框架 SHALL 定义独立的 `Message` 模型（不复用 `Todo`），字段含 `id / summary（一句话提醒）/ source（slack|jira|email）/ link / receivedAt / processedAt? / sender? / rawSubject?`。Message 集合 SHALL 由 `AppStore` 作为单一数据源持有，并持久化到 `~/Library/Application Support/MiniNotch/messages.json`，应用启动恢复、文件缺失时按空集处理、写入失败不崩溃。

#### Scenario: 重启不丢消息
- **WHEN** 收到若干消息后退出并重启应用
- **THEN** 消息列表与各自的已处理状态从 messages.json 恢复

#### Scenario: 旧版本无消息文件
- **WHEN** 升级后首次启动且无 messages.json
- **THEN** 消息列表为空集，不报错、不影响既有 todos/meetings 数据

### Requirement: 消息页签列表与排序
「消息」页签 SHALL 展示全部已收消息，按 `receivedAt` 倒序排列，可同时容纳多条；每条展示一句话 summary、来源标识与时间。

#### Scenario: 多条消息按时间倒序
- **WHEN** 切换到「消息」页签且已有多条消息
- **THEN** 最新收到的消息排在最上方

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
