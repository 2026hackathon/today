## ADDED Requirements

### Requirement: 邮件拉取的纳入条件（时间窗 + 未读 + 增量/变化/回复）
拉取层 SHALL 仅纳入**同时满足**以下全部硬条件的邮件，其余一律不纳入（不入库、不送 AI）：

1. **未读**：邮件当前为未读状态。
2. **最近 3 天**：邮件的最后更新时间（IMAP 的 INTERNALDATE / `Date` 头，Graph 的 `receivedDateTime`，取可得的最新者）落在「当前时间往前 3 天」窗口内。
3. **属于增量/变化/回复之一**：邮件为本地从未入库的**新增邮件**；或所属会话的**最新状态发生变化**；或会话内**他人有新回复**（即新到达、非自己发出的回复）。

这三类「增量/变化/回复」语义在 provider 能力允许范围内表达：对仅支持「未读 + 时间窗」的 provider（如基础 IMAP），未读 + 最近 3 天即作为「增量/变化/回复」的近似实现，仍以 `Message-ID` 去重保证不重复入库。各 provider 的查询 SHALL 表达上述条件：Gmail(IMAP) 用 `UID SEARCH UNSEEN SINCE <3天前日期>`；O365(Graph) 用 `$filter=isRead eq false and receivedDateTime ge <3天前ISO时间>` 并按 `receivedDateTime desc` 排序。`maxFetch` 上限保留。

#### Scenario: 最近 3 天的未读新邮件被纳入
- **WHEN** 收到一封未读、最后更新时间在 3 天内、且本地从未入库的邮件
- **THEN** 该邮件进入候选并继续后续来源识别/隐私预处理/AI 流程

#### Scenario: 超过 3 天的未读邮件被排除
- **WHEN** 一封未读邮件的最后更新时间早于当前时间 3 天
- **THEN** 该邮件不被纳入，不入库、不送 AI

#### Scenario: 会话内他人新回复被纳入
- **WHEN** 某会话在 3 天内收到一封他人发来的新回复且为未读
- **THEN** 该回复作为新到达邮件被纳入候选

#### Scenario: Gmail IMAP 查询带时间窗
- **WHEN** 通过 imap.gmail.com 拉取
- **THEN** 搜索条件为 `UNSEEN` 且带 `SINCE <3天前>`，而非无时间窗的全部未读

#### Scenario: O365 Graph 查询带时间窗
- **WHEN** 通过 Graph 拉取
- **THEN** `$filter` 同时包含 `isRead eq false` 与 `receivedDateTime ge <3天前ISO>`，并按 `receivedDateTime desc` 排序

### Requirement: 已读邮件 SHALL 被过滤
拉取层 SHALL NOT 纳入任何已读邮件。已读邮件不入库、不占提醒位、不发送给 AI。已入库 Message 的「已处理」状态不受影响（按既有 `Message-ID` 去重规则保留）。

#### Scenario: 已读邮件不入库
- **WHEN** 拉取时遇到一封已读邮件（即使在 3 天内）
- **THEN** 不生成 Message，不发送给 AI

#### Scenario: 邮件被标记已读后不再重复带入
- **WHEN** 一封原本未入库的邮件已在邮箱中被读过
- **THEN** 后续轮询不会因它仍在时间窗内而将其纳入

### Requirement: AI 价值过滤
通过全部硬过滤（来源识别、噪音域/自动通知过滤、跨 tab 去重、时间窗/未读/增量条件）的候选邮件，在转为可见 Message 之前 SHALL 再经过一道**价值识别**：系统判定该邮件是否「价值不高」，价值不高者 SHALL 被过滤掉，不入库、不占提醒位。

配置 AI Key 时，价值判定由 AI 完成（可与既有 importance + suggestion 分析合并到同一次请求，复用已截断/剥离的隐私安全正文，不额外出网正文）。未配置 AI Key 时 SHALL 降级为本地启发式价值判定，且 SHALL NOT 将正文出网。此关卡叠加在既有规则化噪音过滤之上，既有过滤条件全部保留。

#### Scenario: AI 判定低价值邮件被过滤
- **WHEN** 一封通过硬过滤的邮件被 AI 判定为「价值不高」
- **THEN** 不生成可见 Message，不占提醒位

#### Scenario: AI 判定有价值邮件入库
- **WHEN** 一封通过硬过滤的邮件被 AI 判定为有价值
- **THEN** 生成 Message 并带 importance 与一句话 suggestion

#### Scenario: 无 AI Key 时本地降级且不出网
- **WHEN** 未配置 AI Key
- **THEN** 价值判定走本地启发式，不向远程 LLM 发送任何邮件正文

#### Scenario: 既有噪音过滤仍生效
- **WHEN** 一封营销/纯系统通知邮件进入拉取
- **THEN** 仍先被既有发件域/关键字噪音过滤拦下，不依赖 AI 价值过滤这一关
