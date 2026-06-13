## 1. 时间窗 + 未读拉取条件（provider 层）

- [x] 1.1 在 `Services/EmailService.swift` 新增一个统一的「最近 3 天起点」计算（常量 `recentDays = 3`，返回 3 天前 Date/日期），供 IMAP/Graph/本地二次过滤共用
- [x] 1.2 改 `IMAPConnection.searchUnseen()`（或新增 `searchUnseenSince(_:)`），把搜索条件改为 `UID SEARCH UNSEEN SINCE <3天前日期>`，日期按 IMAP 日期格式（`dd-MMM-yyyy`）格式化
- [x] 1.3 在 `RealEmailService.fetchNewMessages()` 调用新搜索，并对返回邮件按精确 `Date`/INTERNALDATE 做本地二次过滤（收紧 `SINCE` 的日期粒度到精确 3 天），保留 `suffix(maxFetch)`
- [x] 1.4 改 `GraphEmailService.fetchNewMessages()` 的 `$filter`，由 `isRead eq false` 改为 `isRead eq false and receivedDateTime ge <3天前ISO8601>`，保留 `$top` 与 `$orderby=receivedDateTime desc`

## 2. 已读过滤与增量/回复语义

- [x] 2.1 确认两个 provider 都不纳入已读邮件（IMAP 仅 UNSEEN；Graph `isRead eq false`），并在 `syncEmail` 管线前不会引入已读来源
- [x] 2.2 复用现有 `Message-ID` 去重保证「新增/他人回复」只入一次；确认已入库 Message 的 `processedAt` 状态在重复拉取时保留不变（`AppStore.addMessages` 仅 append 未知 messageId）

## 3. AI 价值过滤关卡

- [x] 3.1 在 `AIService` 邮件分析的请求 schema 上扩展价值判定字段（如 `valuable: bool` 或 `drop: bool`），与现有 importance + suggestion 合并到同一次请求，复用已截断/剥离的安全正文
- [x] 3.2 在 `EmailHeuristics` 增补无 Key 时的本地价值判定（沿用 lowWords/营销特征，保守：默认保留，仅过滤强特征低价值），确保不出网
- [x] 3.3 在 `AppDelegate.syncEmail()` 管线中，于硬过滤（来源识别/噪音/跨 tab/时间窗/去重）之后、`store.addMessages()` 之前接入价值过滤，丢弃被判定为低价值的候选

## 4. 验证

- [x] 4.1 验证：3 天内未读新邮件入库；超 3 天未读不入库；已读不入库（代码级：IMAP `UNSEEN SINCE` + 本地 `cutoff` 二次过滤；Graph `isRead eq false and receivedDateTime ge`。**未跑真实 Gmail/O365 账户端到端**——本会话无运行时环境）
- [x] 4.2 验证：营销/系统通知仍被既有噪音过滤拦下，不依赖 AI 价值过滤（`isNoise`/`isAutomatedNotification`/`isCoveredByOtherTab` 三道硬过滤在服务层保持不变，位于 AI 之前）
- [x] 4.3 验证：无 AI Key 时价值过滤走本地启发式且无正文出网（`MockAIService.analyzeEmails` 不联网；`syncEmail` 降级分支用 `EmailHeuristics.isLowValue`，无网络调用）
- [x] 4.4 验证：重复轮询不重复入库，已处理状态保留（`syncEmail` 按 `store.messages` messageId 去重 + `addMessages` 仅 append 未知 id）
- [x] 4.5 运行 `openspec validate gmail-incremental-fetch-filter` 通过（`swift build` 亦通过）
