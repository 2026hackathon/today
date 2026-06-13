## Context

「消息」页签（`MessageInboxPanel`）目前把 `store.sortedMessages`（按 `receivedAt` 倒序的扁平数组）拆成未处理 / 已处理两段渲染，无任何分组。行内时间复用了为「截止日」设计的 `Date.dsShortLabel`（输出「今晚 / 明天 / 周X / M/d」），对「过去收到的邮件」语义不符，且与邮箱真实收件时刻对不上。

`Message` 已带权威的 `receivedAt`（IMAP RFC2822 / Graph ISO8601 解析，抓取层无需改动）。代码库已有按天分组的成熟范式 `AppStore.meetingsByDate`（用 `Calendar.startOfDay` + `Dictionary(grouping:)`），可直接借鉴。

## Goals / Non-Goals

**Goals:**
- 未处理与已处理两区各自按收件自然天分组，组头标日期。
- 每区最多展示最近 3 个「有邮件的收件日」的分组。
- 分组间按天倒序、组内按 `receivedAt` 倒序。
- 行内时间显示真实收件时刻「HH:mm」。
- 头部计数文案改为「x 条未读邮件」。

**Non-Goals:**
- 不改 `Message` 模型字段与 `messages.json` 持久化格式。
- 不改邮件抓取 / 收件时间解析逻辑。
- 不引入分页、虚拟滚动或「加载更多」历史。
- 不改 Slack/Jira 等非邮件来源的处理流程（分组按 `receivedAt` 统一适用）。

## Decisions

**1. 分组逻辑放在 `AppStore` 的派生属性，而非 View 内。**
新增形如 `pendingMessagesByDay` / `processedMessagesByDay` 的计算属性，返回 `[(day: Date, messages: [Message])]`，与既有 `meetingsByDate` 风格一致，便于复用与测试。View 只负责渲染。
- 备选：在 View 内即时分组。否决——逻辑（含 3 天裁剪）放数据层更内聚，且与项目既有模式统一。

**2. 「最近 3 天」= 有邮件的收件日的前 3 个，而非日历上的 today/昨天/前天。**
先按 `startOfDay(receivedAt)` 分组，组按日期倒序排序后 `prefix(3)`。这样即便中间某天没有邮件，仍能稳定展示「最近三个有内容的日期」，避免出现空组或因跨日空档而少于预期的展示。
- 备选：硬过滤 `today / today-1 / today-2` 三个日历日。否决——会在无邮件的日期产生空洞，信息密度更低，也不符合「显示最近 3 天的邮件」的直觉。

**3. 行内时间改用 `Date.dsHHmm`，组头日期用单独的格式。**
行内复用既有 `dsHHmm`（24 小时制 HH:mm）即满足「与收件时间相同」。组头日期格式：今天→「今天」、昨天→「昨天」、更早→「M/d」(可附周几)。新增一个轻量 `Date.dsDayHeader` 扩展或在 View 内局部格式化，不污染 `dsShortLabel`（后者仍服务截止日场景）。
- 备选：直接复用 `dsShortLabel` 做组头。否决——其「今晚/明天/周X」面向未来截止日，对过去的收件日语义错乱。

**4. 头部文案直接改字面量。** `headline` 中 `"\(unread) 条未处理消息"` → `"\(unread) 条未读邮件"`，清空态文案不变。

## Risks / Trade-offs

- [更早邮件被隐藏，用户可能找不到旧邮件] → 这是本次明确诉求（最多 3 天）；已处理区仍折叠保留同样的 3 天范围。若后续需要可加「查看更多」，本次不做。
- [非邮件来源（Slack/Jira）也会被按天分组并受 3 天裁剪] → 与「消息」页签统一行为一致，符合按 `receivedAt` 倒序的既有语义；可接受。
- [3 天裁剪基于"有邮件的天"而非日历天] → 需在 spec 场景中讲清，避免实现者误用日历日硬过滤；已在 specs 写明。

## Migration Plan

纯前端展示改动，无数据迁移。直接修改 `MessageInboxPanel` 与 `AppStore` 派生属性即可，旧 `messages.json` 完全兼容。回滚即还原这两个文件。
