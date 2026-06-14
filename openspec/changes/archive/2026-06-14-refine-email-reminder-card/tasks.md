## 1. 标题取用邮件主题

- [x] 1.1 在 `MessageInboxPanel.swift` 行视图中计算标题 `title = message.rawSubject?.trimmed.nonEmpty ?? message.summary`，将 `Text(message.summary)`（约 137 行）改为展示该标题
- [x] 1.2 确认行内 strikethrough/lineLimit/titleColor 等修饰仍作用在新标题上，已处理转灰行为不变

## 2. AI 提醒归位到降落通知卡

- [x] 2.1 在 `MessageLandedCard.swift` 的 `summaryBlock` 中以邮件主题为标题（`rawSubject` 缺失回退 `summary`），用 `DS.Fonts.cardTitle`
- [x] 2.2 在标题下方新增一行展示 AI 一句话提醒 `message.summary`（次级字色/字号，如 `DS.Colors.text2`），主题已等于 summary（无主题回退）时不重复展示
- [x] 2.3 保留 sender 行、lineLimit 截断与卡片节奏不变

## 3. 完成圈改为绿色对勾态

- [x] 3.1 给 `PanelCheckCircle`（`TodayPanel.swift`）新增 `isDone: Bool` 入参
- [x] 3.2 在 `overlay {}` 内按态渲染：未完成 `Circle().strokeBorder`；已完成 `Circle().fill(绿)` + `Image(systemName: "checkmark")`（白色/对比色），不用 `if cond { self.x() } else { self }` 包宿主
- [x] 3.3 绿色走 `DS.*` 令牌；若 `DesignTokens.swift` 无合适绿色则新增 `DS.Colors.success`（一处，遵守 DS 守则）
- [x] 3.4 在 `MessageInboxPanel.swift:133` 调用处传入 `isDone: processed`，移除对完成圈的 `.opacity(processed ? 0.4 : 1)` 弱化

## 4. AI 建议 prompt 增补约束

- [x] 4.1 在 `AIService.swift` 的 `analyzeEmails` system 文案中追加约束：无实质内容时仅朴素概括，不臆造截止时间/单号/行动项，不输出「查看…」「了解…」等空泛建议
- [x] 4.2 确认 JSON 输出结构与字段（importance/suggestion/valuable）不变，规则化兜底 `EmailSummary.suggestion` 无需改动

## 5. 验证

- [x] 5.1 `cd MiniNotch && swift build` 通过
- [x] 5.2 `swift run` 冒烟：通过 Debug 菜单触发新邮件降落卡，确认卡片为「主题标题 + AI 提醒行」
- [x] 5.3 在消息页签确认行标题为邮件主题；点击完成后空心圈变为绿色对勾圈，再次点击幂等不报错
