## Context

现有拉取链路（探查结论）：
- `RealEmailService.fetchNewMessages()`（`Services/EmailService.swift:302-342`）调用 `IMAPConnection.searchUnseen()`（`UID SEARCH UNSEEN`，无时间窗），取 `uids.suffix(maxFetch)`，`maxFetch = 20`。
- `GraphEmailService.fetchNewMessages()`（`Services/GraphEmailService.swift:15-66`）用 `$filter=isRead eq false`、`$top=20`、`$orderby=receivedDateTime desc`。
- `AppDelegate.syncEmail()`（`AppDelegate.swift:640-661`）做来源识别 + 链接归一 + 隐私预处理 → `Message-ID` 跨源去重 → AI 分析（importance + ≤20 字 suggestion）→ 转 Message → `store.addMessages()`。
- 噪音过滤在 `EmailPreprocess`（`EmailService.swift:114-162`）：营销域、自动通知、跨 tab 覆盖。
- AI 分析在 `AIService`（importance + suggestion），无 Key 时 `EmailHeuristics` 启发式兜底。
- 数据模型 `Message`（`Core/Models.swift:430-475`）：`messageId` 去重键、`receivedAt`、`processedAt`（nil=未读/未处理）。无独立 `status`/`updatedAt` 字段。

约束：拉取层是「不可信外部输入 → 安全降级」原则；无 AI Key 时正文不得出网；改动需对 Gmail(IMAP) 与 O365(Graph) 两 provider 一致。

## Goals / Non-Goals

**Goals:**
- 把拉取纳入条件收敛为：未读 + 最近 3 天 + 增量/状态变化/他人回复。
- 已读邮件一律过滤。
- 在硬过滤之后增加 AI 价值过滤关卡，低价值邮件不入库。
- 完整保留既有过滤（来源识别、噪音域/自动通知、跨 tab、Message-ID 去重、隐私预处理）。

**Non-Goals:**
- 不引入服务端会话线程模型（不解析完整 thread 树）；「他人回复/状态变化」用「未读 + 时间窗 + 新到达 + Message-ID 去重」近似。
- 不改 Message 数据模型字段（不新增 `status`/`updatedAt`）。
- 不改轮询周期与提醒 UI。
- 不接真实 IMAP 账户类型确认之外的新 provider。

## Decisions

**D1：时间窗 = 拉取查询层下推，而非本地后过滤。**
IMAP 用 `UID SEARCH UNSEEN SINCE <date>`（`SINCE` 取日期粒度，按 3 天前的日期），Graph 在 `$filter` 加 `receivedDateTime ge <ISO8601>`。理由：减少传输与解析量，比拉回 20 封再丢弃更省；`SINCE` 是 RFC3501 标准搜索键，gmail IMAP 支持。
- 备选：拉回后本地按 `receivedAt` 过滤——实现简单但浪费带宽且受 `maxFetch` 截断影响（可能 20 封全是旧的，反而漏掉新的）。否决。
- 注意 `SINCE` 是日期（非时刻）粒度，会多带回当天更早的，本地再按精确时间戳收一刀，保证「最近 3 天」语义。

**D2：「增量/状态变化/他人回复」用现有去重 + 未读近似，不建线程模型。**
新增邮件 = `Message-ID` 未入库（已有逻辑）；他人回复 = 新到达的未读邮件（回复在 IMAP/Graph 表现为新消息）；状态变化在无 thread 模型下退化为「未读 + 时间窗内的新到达」。理由：避免引入 thread 解析复杂度，且当前 Message 模型本就以单封邮件为粒度。
- 备选：解析 `In-Reply-To`/`References` 头构建会话——能更精确区分「他人回复 vs 自己发的」，但需要拉取已读/已发邮件来还原线程，与「已读过滤/只拉未读」目标冲突。本期否决，列入 Open Questions。

**D3：AI 价值过滤合并进既有 AI 分析请求，而非新增一次调用。**
在 `AIService` 现有「importance + suggestion」schema 上扩展一个布尔/枚举字段（如 `valuable` 或复用 `importance == low` 的下沉判定 + 显式 `drop` 标记），同一次请求返回。理由：复用已做隐私截断/剥离的正文，零额外网络往返与出网风险。
- 备选：独立的「价值分类」调用——更解耦但翻倍延迟与成本。否决。
- 无 Key：`EmailHeuristics` 增补价值判定（沿用其 lowWords/营销特征），不出网。

**D4：AI 价值过滤位置在硬过滤之后、`addMessages` 之前。**
管线顺序：来源识别 → 噪音/自动通知/跨 tab 过滤 → 时间窗+未读+去重 → 隐私预处理 → **AI 价值过滤** → 转 Message → 入库。理由：先用便宜的规则过滤掉绝大多数噪音，AI 只评估「规则放过但可能仍低价值」的少数，省钱且语义清晰（AI 是最后一道而非第一道）。

## Risks / Trade-offs

- [3 天窗口可能漏掉重要旧未读] → 这是显式产品取舍（聚焦增量）；3 天为可配置常量，必要时调参。
- [`SINCE` 日期粒度导致窗口偏宽] → 本地按精确时间戳二次过滤兜底。
- [无 thread 模型，"他人回复 vs 自己回复" 区分有限] → 只拉未读天然偏向他人发来的；自己发出的通常已读或在已发件箱，不在 INBOX 未读集合内，影响小。列 Open Questions。
- [AI 误杀有价值邮件] → 价值过滤仅作用于「规则已放过」的邮件，且降级路径用保守启发式（默认保留，只过滤强特征低价值）；宁可放过不可错杀。
- [Graph `receivedDateTime ge` 与 IMAP `SINCE` 语义不完全一致] → 各 provider 内分别本地二次过滤，对齐到统一「最近 3 天」判定函数。

## Open Questions

- 是否需要把 3 天窗口、AI 价值过滤开关暴露到 Settings？（当前按常量实现，后续可加。）
- 是否在后续迭代解析 `In-Reply-To`/`References` 以精确实现「他人回复/状态变化」线程语义？
- 「价值不高」的判定标准是否需用户可调（保留/激进两档）？
