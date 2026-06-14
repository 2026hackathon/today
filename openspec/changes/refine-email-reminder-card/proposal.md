## Why

当前邮件提醒把 AI 生成的「一句话建议」当作条目标题展示，用户在收件列表里看不到邮件的真实主题，且 AI 在缺乏实质内容时也会硬挤出一句空泛建议。同时已完成邮件仍是灰色空心圈，缺少明确的「已勾选」正反馈。这一轮收敛把「真实主题」与「AI 提醒」各归其位，并补齐完成态视觉。

## What Changes

- 邮件条目（消息列表行 + 降落通知卡）的**标题直接取用邮件主题**（`Message.rawSubject`），主题缺失时回退到既有 summary。
- **AI 一句话提醒**（`Message.summary`）从「列表标题」位置移到**新邮件降落通知卡**中，作为主题下方的提醒行展示。
- 修改邮件 AI 一句话建议的 prompt，新增约束：**没有真实数据支撑时不要硬给无用建议**（宁可输出最朴素的要点概括，也不臆造行动项）。
- 已完成（`processedAt != nil`）邮件的**空心圈改为打勾的小绿圈**，未完成仍为空心圈。

## Capabilities

### New Capabilities
<!-- 无新增能力，均为既有能力的需求调整 -->

### Modified Capabilities
- `message-inbox`: 列表行标题改用邮件主题；已完成项的完成圈改为绿色对勾。
- `island-shell`: 新邮件降落通知卡以邮件主题为标题，并在其下展示 AI 一句话提醒。
- `ai-pipeline`: 邮件一句话建议 prompt 新增「无真实数据支撑不臆造无用建议」约束。

## Impact

- `UI/Panels/MessageInboxPanel.swift`：行标题取 `rawSubject`；完成圈传入已处理态。
- `UI/Panels/TodayPanel.swift`：`PanelCheckCircle` 支持已完成态渲染绿色对勾。
- `UI/Cards/MessageLandedCard.swift`：summaryBlock 改为「主题为标题 + AI 提醒行」。
- `Services/AIService.swift`：`analyzeEmails` 的 system prompt 增补约束。
- `Services/EmailService.swift`：规则化兜底标题逻辑保持（主题优先）。
- 数据模型 `Message` 字段不变（复用现有 `rawSubject` / `summary`）。
