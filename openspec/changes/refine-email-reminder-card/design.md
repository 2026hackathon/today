## Context

邮件提醒链路现状（已落地）：
- `Message` 模型已含 `rawSubject`（邮件原始主题）与 `summary`（AI 一句话建议，≤20 字），二者并存。
- 但 UI 把 `summary` 当作条目标题：`MessageInboxPanel.swift:137` 与 `MessageLandedCard.swift:74` 都显示 `message.summary`，`rawSubject` 几乎不露出。
- AI 建议 prompt 在 `AIService.swift`（`OpenAIChatAIService.analyzeEmails`，约 559-573 行）已要求 ≤20 字、去寒暄、带关键对象，但未禁止「无实质内容时臆造行动项」。
- 完成圈 `PanelCheckCircle`（`TodayPanel.swift:764-781`）只画 `Circle().strokeBorder`，不区分已处理态；`MessageInboxPanel.swift:133` 用 `.opacity(processed ? 0.4 : 1)` 弱化表示完成。

本次为纯 UI/prompt 收敛，不改数据模型、不改持久化、不改服务装配。

## Goals / Non-Goals

**Goals:**
- 邮件主题（`rawSubject`）成为条目标题，AI 一句话提醒（`summary`）归位到降落通知卡。
- prompt 增补「无真实数据不臆造无用建议」约束。
- 已完成完成圈呈现填充绿色对勾，提供明确正反馈。

**Non-Goals:**
- 不改 `Message` 字段或 messages.json 结构。
- 不改邮件抓取 / 同步 / 去重逻辑。
- 不引入新设计令牌之外的颜色（若 `DS` 无合适绿色则新增一个令牌，沿用既有命名规范）。

## Decisions

**1. 标题取 `rawSubject`，缺失回退 `summary`。**
邮件主题可能为空（少数邮件无主题）。在 UI 层统一一个取值：`title = rawSubject?.nonEmpty ?? summary`。放在视图内计算，不污染模型。备选：在写入时把 subject 拷进 summary——否决，会丢失 AI 提醒原值且破坏 summary 语义。

**2. AI 提醒只在降落卡露出，列表行不再以提醒为主体。**
满足需求②「AI 提醒放在弹窗卡中」。列表行主体改为主题；列表行原 `summary` 位置让给主题，AI 提醒不再在行内重复展示（保持行紧凑、避免与卡片信息冗余）。降落卡 `summaryBlock` 改为：主题为标题（`DS.Fonts.cardTitle`）+ 下方一行 AI 提醒（次级字色/字号）。

**3. 完成圈用「态驱动」单一组件，避免身份不稳。**
给 `PanelCheckCircle` 增加 `isDone: Bool` 入参，在同一 `Button`/`overlay` 内按态切换：未完成 `Circle().strokeBorder`，已完成 `Circle().fill(绿)` + `Image(systemName: "checkmark")`。按编码守则，条件渲染放进 `overlay {}` 内部，不用 `if cond { self.x() } else { self }` 包宿主。绿色用 `DS.*` 令牌（如 `DS.Colors.success`，缺失则新增）。`MessageInboxPanel` 调用处去掉原 `.opacity(processed ? 0.4 : 1)` 对完成圈的弱化（绿勾本身即正反馈），传入 `isDone: processed`。

**4. prompt 增补约束，不改 JSON 结构与字段。**
在 `analyzeEmails` 的 system 文案里追加一句：无实质内容时仅朴素概括、不臆造截止/单号/行动项、不输出空泛建议。规则化兜底（`EmailSummary.suggestion`）天然只用主题+发件人，已符合约束，无需改。

## Risks / Trade-offs

- [列表行不再显示 AI 提醒，信息密度下降] → 提醒已在降落卡完整呈现，且主题本身信息量更高；符合需求拆分意图。
- [`DS` 可能无现成绿色令牌] → 若无则新增 `DS.Colors.success`（一处），遵守「颜色一律走 DS」守则，不散落裸色值。
- [主题过长撑爆行/卡] → 沿用既有 `lineLimit`（行 2 行、卡 3 行）截断，不额外处理。

## Open Questions

- 无（已确认复用现有字段与组件，范围明确）。
