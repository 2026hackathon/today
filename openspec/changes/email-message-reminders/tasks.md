## 1. 数据模型与持久化

- [x] 1.1 在 `Core/Models.swift` 新增 `Message` 结构（id/summary/source/link/receivedAt/processedAt?/sender?/rawSubject?）与 `MessageSource` 枚举（slack/jira/email，含 label）
- [x] 1.2 `Persistence` 增加 `messages.json` 的读写（缺文件→空集、写失败不崩溃）
- [x] 1.3 `AppStore` 新增 `@Published var messages: [Message]`，提供 `addMessages(_:)`（按 Message-ID/id 去重、保留已处理状态）与 `markProcessed(_:)`（幂等，置 processedAt）
- [x] 1.4 `AppSettings` 增加 `emailAddress / emailImapHost / emailAppPassword` 字段并接入持久化（向后兼容旧 settings.json）

## 2. EmailService 协议与 Mock（先跑通链路）

- [x] 2.1 新建 `Services/EmailService.swift`：定义 `@MainActor protocol EmailService { func fetchNewMessages() async throws -> [Message] }` 及 `EmailServiceError`
- [x] 2.2 实现 `MockEmailService`：返回 3 条演示消息（slack/jira/普通邮件各一，各带对应来源链接）
- [x] 2.3 `AppDelegate` 装配 EmailService（默认 Mock）并挂 60s 轮询任务，结果调用 `store.addMessages(_:)`

## 3. 消息页签 UI（message-inbox）

- [x] 3.1 `Island/IslandState.swift` 的 `PanelTab` 新增 `case messages = "消息"`，并接入展开态页签切换入口
- [x] 3.2 新建 `UI/Panels/MessageInboxPanel`：按 receivedAt 倒序渲染消息列表，展示 summary/来源标识/时间
- [x] 3.3 未处理白色/常规态、已处理灰色弱化态的样式区分
- [x] 3.4 每条提供「完成」与「跳转链接」两个交互；二者都调用 `store.markProcessed(_:)`，跳转额外 `NSWorkspace.open(link)`

## 4. AI 一句话提醒与隐私预处理（ai-pipeline + email-integration）

- [x] 4.1 `Services/AIService.swift` 协议新增邮件→一句话提醒方法（async throws，支持批量），`MockAIService` 给规则化兜底（发件人+主题）
- [x] 4.2 `OpenAIChatAIService` 实现真实邮件摘要调用；无 Key 时不出网、走规则化
- [x] 4.3 实现邮件预处理：发件域/头预过滤噪音、正文截断（~1.5k）、剥离签名与引用历史
- [x] 4.4 在拉取层把 AI summary 写入对应 Message.summary（批量解析）

## 5. 来源识别与链接归一（email-integration）

- [x] 5.1 实现来源判定：`*.slack.com`/Slack 头→slack，`*.atlassian.net`/issue 链接→jira，其余→email（不确定降级 email，不丢邮件）
- [x] 5.2 实现链接归一：slack 深链 / jira `browse/{KEY}` / 邮件链接（`message://<Message-ID>` 优先，webmail 兜底）

## 6. 多条并发降落通知卡（island-shell）

- [x] 6.1 新增消息通知卡片态，沿用 Jira 新分配通知卡样式（summary/来源/时间 + 蓝色 Touchdown + 约 5s 倒计时 + 悬停暂停）
- [x] 6.2 支持多条并发：队列依次呈现或聚合为「N 条新消息」卡，不互相覆盖
- [x] 6.3 复用既有保护：不抢占输入态、首轮同步静默、点击卡片打开 link 并标记已处理
- [x] 6.4 compact 角标计入未处理消息数

## 7. 真实接入（RealEmailService / IMAP）

- [ ] 7.1 引入 IMAP 客户端库（MailCore2 / Postal）到 `Package.swift`
- [ ] 7.2 实现 `RealEmailService`：IMAP+应用密码登录，拉取近 N 封未读→Message；失败本轮静默跳过保留上次数据
- [ ] 7.3 `AppDelegate` 装配按凭据齐全切 Real、任一为空回退 Mock，设置变更下轮生效
- [ ] 7.4 邮箱密码读写封装并接入 Keychain（替代 settings.json 明文）

## 8. 联调与验证

- [x] 8.1 `swift build` 通过，Mock 模式下「消息」页签与降落卡可演示
- [ ] 8.2 验证白/灰态、完成与跳转两条路径均转已处理且幂等
- [ ] 8.3 验证多条并发降落卡不丢失、不抢占输入态、首轮静默
- [ ] 8.4 真实 IMAP 凭据下拉取真实邮件、来源/链接识别正确、失败静默降级
