## Why

任务来源已覆盖 Jira / 日历 / 截图 / GitHub，但**邮件**这一最高频的工作输入仍游离在外：重要邮件（Slack 通知、Jira 通知、同事来信）只能去邮箱里翻，既打断专注又容易漏。用户需要把邮件像「分配到我的 Jira」一样自动降落到灵动岛上——AI 提炼成一句话提醒、带上可直达的链接，并在一个独立的「消息」页签里集中收口与处理。

## What Changes

- **接入邮件并 AI 提炼**：新增 `EmailService`，拉取收件箱邮件，经 AI 生成**一句话提醒**（who + 要点 + 可选时间），先用 Mock 跑通，真实接入走 IMAP + 应用密码（Network 框架手写 IMAPS，无第三方依赖）。
- **送 AI 前代码预过滤**：用启发式规则先丢弃营销/退订/纯通知类无效邮件，再交 AI，省 token 且不刷屏。
- **AI 重要级别 + ≤20 字建议**：AI 对每封邮件给出重要级别（high/medium/low）与一句话行动建议（≤20 字，硬截断保底）；不同级别在提醒卡与消息行用不同样式（红/蓝/灰）呈现。
- **来源识别与链接**：识别邮件来源——来自 Slack 的附 Slack 深链、来自 Jira 的附 Jira 链接、其余统一附邮件原文链接（`message://` / webmail）。
- **多条并发提醒**：邮件到达时沿用「分配到我的 Jira」的降落卡样式与时间展示，且**支持同时展示多条**提醒卡（现状偏单条/串行）。
- **新增「消息」页签**：收到的邮件消息统一进入新的消息页签；列表按时间排序，可同时容纳多条。
- **已处理态与交互**：消息页签中**未处理为白色、已处理为灰色**；每条可「点击完成」或「点击跳转链接」，**两种操作都标记为已处理**。

## Capabilities

### New Capabilities
- `email-integration`: `EmailService` 协议、邮件拉取与去重、来源识别（slack/jira/其他）与链接归一、AI 一句话提醒生成、Mock + 真实（IMAP）装配降级。
- `message-inbox`: 「消息」页签的数据模型与持久化、未处理/已处理（白/灰）状态机、点击完成与点击跳转两条「转已处理」路径、多条并发展示与排序。

### Modified Capabilities
- `integrations`: 新增 `EmailService` 协议条目及 `MockEmailService` 联调要求，纳入现有「协议 + Mock + 真实装配降级」模式。
- `ai-pipeline`: 新增「邮件 → 一句话提醒」解析能力（输入邮件元数据/正文，输出一句话摘要 + 可选时间/链接），含降级与隐私截断约束。
- `island-shell`: 消息降落通知卡沿用 Jira 通知卡样式与时间展示并扩展为**可同时呈现多条**；`PanelTab` 新增「消息」页签入口。

## Impact

- **新增代码**：`Services/EmailService.swift`（协议 + Mock + Real-IMAP）、消息页签 UI（`UI/Panels/MessageInboxPanel`）、`Message` 数据模型与持久化（`messages.json`）。
- **修改代码**：`AppStore`（消息集合的增/改/标记已处理）、`AppDelegate`（EmailService 装配与轮询）、`AIService`（新增邮件解析方法）、`Models.swift`（`Message` 模型、来源枚举、链接字段）、提醒卡/灵动岛路由（多条并发 + 新页签入口）、`AppSettings`（邮件凭据，密码建议入 Keychain）。
- **依赖**：真实接入需 IMAP 客户端库（如 MailCore2 / Postal）；AI 解析复用现有 OpenAI 兼容通道。
- **隐私/安全**：邮件正文较敏感——发送 LLM 前做本地预过滤与正文截断/剥离签名；邮箱密码持久化建议从明文 settings.json 升级到 Keychain。
