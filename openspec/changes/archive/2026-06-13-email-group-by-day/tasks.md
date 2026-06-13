## 1. 数据层：按天分组派生属性

- [x] 1.1 在 `AppStore` 新增 `pendingMessagesByDay: [(day: Date, messages: [Message])]`：对未处理消息按 `Calendar.startOfDay(receivedAt)` 分组，组按日期倒序、组内按 `receivedAt` 倒序，并 `prefix(3)` 取最近 3 个收件日（参考既有 `meetingsByDate`）
- [x] 1.2 在 `AppStore` 新增 `processedMessagesByDay`，逻辑同上但作用于已处理消息
- [x] 1.3 自测：构造跨 4+ 天的未处理 / 已处理样本，确认各自只剩最近 3 天且排序为天倒序、组内时间倒序

## 2. 时间显示格式

- [x] 2.1 新增组头日期格式（如 `Date.dsDayHeader`：今天→「今天」、昨天→「昨天」、更早→「M/d」），不改动既有 `dsShortLabel`
- [x] 2.2 将 `MessageRow` 行内时间由 `message.receivedAt.dsShortLabel` 改为 `message.receivedAt.dsHHmm`，确保显示真实收件时刻

## 3. 面板渲染：分组视图

- [x] 3.1 `MessageInboxPanel` 未处理区改为遍历 `store.pendingMessagesByDay`，每组渲染一个日期组头 + 组内 `MessageRow` 列表
- [x] 3.2 「已处理」折叠区改为遍历 `store.processedMessagesByDay`，同样按天分组带组头；折叠计数仍反映展示范围
- [x] 3.3 实现日期组头视图（沿用 `DS.Colors.text3` / `DS.Fonts.meta` 等既有样式），与「已处理」折叠头风格协调
- [x] 3.4 处理空态：无任何消息时仍显示既有「还没有收到消息」占位

## 4. 文案

- [x] 4.1 将 `headline` 中「\(unread) 条未处理消息」改为「\(unread) 条未读邮件」，清空态文案保持不变

## 5. 验证

- [x] 5.1 编译通过，切换到「消息」页签人工核对：分组按天、最近 3 天、最新在最上、行内时间为 HH:mm 且与邮箱一致、头部显示「x 条未读邮件」
- [x] 5.2 标记某条为已处理后，确认它从未处理分组移除并出现在已处理区对应日期组，3 天裁剪在两区独立生效
