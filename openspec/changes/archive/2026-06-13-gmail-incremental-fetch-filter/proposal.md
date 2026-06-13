## Why

当前 Gmail/IMAP 拉取只用 `UID SEARCH UNSEEN` 取最近 20 封未读，没有时间窗约束，也无法表达「只要增量、状态变化、他人回复」的意图——历史久远的未读会被反复带进来，而真正值得提醒的新回复/状态变化没有被优先识别。同时噪音过滤仅靠发件域/关键字规则，价值不高的邮件仍会入库占用提醒位。我们需要把拉取条件收敛为「最近 3 天、未读、增量/有变化/有回复」，并在入库前用 AI 识别并过滤低价值邮件。

## What Changes

- 拉取条件收敛为一个明确集合：仅纳入**未读**、**最后更新时间在最近 3 天内**，且属于以下之一的邮件——**新增邮件** / **会话最新状态发生变化** / **他人有新回复**。
- **已读邮件 SHALL 被过滤**，不入库、不送 AI、不占提醒位。
- 在现有发件域/关键字噪音预过滤之上，新增 **AI 价值识别**：对通过硬过滤的候选邮件，由 AI 判定是否「价值不高」，价值不高者被过滤掉（无 AI Key 时降级为现有启发式，不出网）。
- **保留现有过滤条件**：来源识别（slack/jira/email）、噪音域/自动通知过滤、跨 tab 去重、Message-ID 去重、隐私预处理（正文截断/剥离签名引用）全部不变。
- 时间窗与「增量/变化/回复」语义对 Gmail(IMAP)、O365(Graph) 两个 provider 统一表达（IMAP 用 SINCE + UNSEEN，Graph 用 `isRead eq false` + `receivedDateTime` 时间窗 + 排序）。

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `email-integration`: 在「邮件转 Message 与去重」「发送 AI 前的隐私预处理」之外，新增/修改拉取层的纳入条件——时间窗（最近 3 天）、未读门槛、增量/状态变化/他人回复语义，以及 AI 价值过滤这道新关卡。

## Impact

- 代码：`Services/EmailService.swift`（`RealEmailService.fetchNewMessages` / `IMAPConnection.searchUnseen`：改为带 `SINCE` 的 UNSEEN 搜索）、`Services/GraphEmailService.swift`（Graph `$filter` 增加时间窗）、AI 价值过滤接入点（`AppDelegate.syncEmail` 处理管线 + `AIService`/`EmailHeuristics`）。
- 行为：进入 Messages tab 的邮件数量会减少（已读与低价值被剔除、超 3 天的不再带入）；提醒更聚焦增量与回复。
- 依赖：复用现有 AI 分析调用（importance + suggestion），价值判定可与之合并到同一次请求，避免额外网络往返。
