## Context

MiniNotch 已有一套成熟的「来源接入」范式：每个外部来源是一个 `@MainActor protocol`（如 `JiraService.fetchAssignedTickets()`），配 `MockXxx` 与 `RealXxx` 两个实现，在 `AppDelegate.makeServices()` 按 `settings` 凭据是否齐全动态选择，`wireServices()` 挂轮询任务（Jira 60s），结果经 `AppStore.mergeXxx(_:)` 替换式合并入单一数据源。UI 由 `IslandState` 状态机驱动，多页签由 `PanelTab` 枚举（today/calendar/inbox/favorites/settings）路由。

本变更要在此范式下接入「邮件」这一新来源，但它有两点与现有来源不同：

1. 邮件产出的不是「任务」，而是**一句话提醒消息**——有独立的「已处理/未处理」生命周期，不应混入 `Todo` 的完成语义。
2. 用户要一个**独立的「消息」页签**集中收口，并要求**同时展示多条**降落提醒卡（现有卡片态偏单条串行）。

约束：Swift 6 / SwiftUI / SPM；AI 走现有 OpenAI 兼容通道；先 Mock 跑通、真实接入走 IMAP + 应用密码；邮件正文敏感。

## Goals / Non-Goals

**Goals:**
- 以最小侵入复用现有「协议 + Mock + Real + 装配降级 + 轮询合并」范式接入邮件。
- 邮件经 AI 提炼为一句话提醒，识别来源（slack/jira/其他）并归一为可点击链接。
- 新增「消息」页签：未处理白、已处理灰；点击完成或点击跳转**任一**都转为已处理。
- 到达时沿用 Jira 降落卡样式与时间展示，支持**多条并发**提醒。
- Mock 实现保证 UI 可独立联调，无需真实邮箱。

**Non-Goals:**
- 不做邮件全文阅读器/回复/发信（仅"提醒 + 跳转"）。
- 不做多账号管理（首版单账号）。
- 不实现 OAuth（Gmail/Graph）——本期只做 IMAP + 应用密码；OAuth 留作后续。
- 不改动 `Todo` 的完成/超期/提醒分级语义。

## Decisions

### D1: 新增独立 `Message` 模型，而非复用 `Todo`
邮件消息有自己的状态机（unprocessed/processed）与展示位（消息页签），与 `Todo` 的 completed/overdue/snooze 语义不同。强行复用 `Todo` 会污染既有派生分组（已超期/今日任务/Inbox）与提醒调度。
- **方案**：新增 `struct Message: Identifiable, Codable, Sendable`，字段含 `id / summary(一句话) / source(MessageSource) / link(URL) / receivedAt / processedAt / rawSubject? / sender?`。`MessageSource` 枚举：`slack / jira / email`。
- **持久化**：新增 `messages.json`（沿用 `Persistence` JSON 范式），`AppStore` 增 `@Published var messages: [Message]` 及 `addMessages / markProcessed(_:)`。
- **替代方案**：给 `Todo` 加 `isMessage` 标记并复用 —— 否决，语义耦合、回归风险大。

### D2: `EmailService` 协议沿用 Jira 范式
```swift
@MainActor protocol EmailService: AnyObject {
    func fetchNewMessages() async throws -> [Message]
}
```
- `MockEmailService`：返回 3 条演示消息（slack/jira/普通邮件各一），保证页签与降落卡可独立开发。
- `RealEmailService`：IMAP + 应用密码（IMAP 库如 MailCore2/Postal），拉取近 N 封未读，去重键用邮件 `Message-ID`。
- 装配：`AppDelegate` 按 `settings.emailImapHost/emailAddress/emailAppPassword` 齐全→Real，否则 Mock；轮询周期 60s（与 Jira 对齐），结果 `store.addMessages(_:)`（按 `Message-ID`/`id` 去重，已处理的保留状态）。
- **替代方案**：直接读 Apple Mail —— 否决，macOS 无稳定公开 API。

### D3: 来源识别与链接归一在「拉取层」完成
邮件 → 来源判定优先级：① 发件域/已知头（`*.slack.com`、Slack `List-ID` → slack；`*.atlassian.net`/Jira 通知头 → jira）；② 否则归 `email`。链接归一：
- slack → 邮件内的 Slack 深链（`https://...slack.com/archives/...`，无则降级邮件链接）；
- jira → 提取 `browse/{KEY}` 或通知里的 issue 链接；
- 其他 → 统一邮件链接（优先 `message://<Message-ID>` 唤起本地邮件，webmail 兜底）。
- **理由**：UI/消息模型只认 `link: URL`，来源差异在服务层吸收，下游不分叉。

### D4: AI「邮件 → 一句话提醒」复用现有 AIService，前置隐私处理
`AIService` 新增 `func summarizeEmail(_ input: EmailDigestInput) async throws -> String`（who + 要点 +可选时间，≤1 句）。
- **隐私**：发送 LLM 前——本地预过滤明显噪音（营销/系统通知按头/域跳过）、正文截断（如前 ~1.5k 字）、剥离签名与引用历史；Mock/无 Key 时退回规则化摘要（取 subject + sender）。
- **批量**：一次轮询多封时合并为一次批量调用省 token（参照截图批量 ≥3 的处理）。

### D5: 多条并发降落提醒——以队列驱动卡片态，复用 Jira 蓝色 Touchdown
新消息到达时播放与「分配到我的 Jira」一致的降落卡（样式 + 显示时间）。现有卡片态偏单条，故：
- `AppStore` 维护**待展示提醒队列**，`IslandState` 的提醒卡态支持承载多条（或顺序快速出列），compact 角标显示未处理消息数。
- 不抢占输入态（沿用 reminders spec 既有保护：快速新建/降落/批量卡进行时顺延）。

### D6: 「消息」页签与已处理态
`PanelTab` 新增 `case messages = "消息"`。新增 `MessageInboxPanel`：
- 列表按 `receivedAt` 倒序，未处理 `processedAt == nil` 渲染白底/常规字色，已处理渲染灰字弱化。
- 每条两个交互：**点击完成**（标记已处理）/ **点击跳转**（打开 `link` 并标记已处理）——二者都调用 `store.markProcessed(message)`，幂等。

### D7: 凭据存储
首版 Mock-first 不阻塞；真实接入时邮箱密码**应入 Keychain**（优于现有 settings.json 明文）。本期至少把邮件密码字段读写封装，留 Keychain 接入点。

## Risks / Trade-offs

- **邮件正文泄露给 LLM** → D4 的本地预过滤 + 截断 + 剥离签名；无 Key 走规则化摘要不出网。
- **IMAP 库引入新依赖、企业邮箱协议差异（O365 可能需 Graph）** → 先 Mock 解耦；Real 失败按 Jira 范式静默跳过、保留上次数据、不弹错误 UI。
- **来源/链接识别不准（误判 slack/jira）** → 识别失败安全降级为 `email` + 邮件链接，不丢消息。
- **多条并发卡片刷屏打扰** → 走提醒队列 + 勿扰时段 + 不抢占输入态；超量时合并为「N 条新消息」聚合卡。
- **消息与 Jira/日历任务语义混淆** → D1 独立 `Message` 模型，物理隔离。

## Migration Plan

1. 加 `Message`/`MessageSource` 模型 + `messages.json` 持久化 + `AppStore` 集合与方法（向后兼容，旧 json 无该文件即空集）。
2. `EmailService` 协议 + `MockEmailService`；`AppDelegate` 装配 + 轮询（默认 Mock，无需凭据即可演示）。
3. 「消息」页签 UI + 白/灰态 + 两条「转已处理」路径。
4. 降落提醒多条并发 + AI 一句话解析。
5. `RealEmailService`（IMAP）+ 来源/链接识别 + 邮件密码 Keychain。
- **回滚**：删除 `messages.json` 不影响既有 Todo 数据；装配处改回不挂 EmailService 即停用。

## Open Questions

- 企业邮箱 `xm.wonder.com` 实际是 O365 / Google Workspace / 自建 IMAP？决定真实接入是否需在后续加 Graph/Gmail 分支（本期仍以 IMAP 为准）。
- 一句话提醒是否需要可点开看「原邮件摘要/正文片段」，还是只保留 subject + 跳转？
- 已处理消息是否需要定期清理/归档上限（避免 messages.json 无限增长）？
