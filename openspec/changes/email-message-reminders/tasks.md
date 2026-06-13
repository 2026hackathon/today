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

- [x] 7.1 ~~引入 IMAP 客户端库~~ → 改为用 Network 框架手写最小 IMAPS（无第三方依赖，沿用项目手写网络层风格）
- [x] 7.2 实现 `RealEmailService` + `IMAPConnection`：IMAPS(TLS) 登录→SELECT INBOX→UID SEARCH UNSEEN→逐封 FETCH(头+正文片段)，含轻量 RFC2047 解码；失败抛错由装配层静默跳过
- [x] 7.3 `AppDelegate.currentEmailService()` 按 host/账号/应用密码三项齐全切 Real、任一为空回退 Mock，设置变更下轮生效
- [x] 7.4 邮箱密码读写封装并接入 Keychain（`Keychain` helper + `AppStore.emailAppPassword` 计算属性；settings.json 不再含密码）；设置面板新增「邮件接入（IMAP）」配置区（主机/账号/应用密码 + 测试连接）

## 8. 联调与验证

- [x] 8.1 `swift build` 通过，Mock 模式下「消息」页签与降落卡可演示
- [ ] 8.2 验证白/灰态、完成与跳转两条路径均转已处理且幂等（待运行交互观察）
- [ ] 8.3 验证多条并发降落卡不丢失、不抢占输入态、首轮静默（待运行交互观察）
- [ ] 8.4 真实 IMAP 凭据下拉取真实邮件、来源/链接识别正确、失败静默降级（待真实邮箱凭据）

## 9. 重要级别分析与分级样式（ai-pipeline / message-inbox / island-shell 增量）

- [x] 9.1 `MessageImportance` 模型 + `Message.importance` 字段 + 持久化（向后兼容解码）
- [x] 9.2 送 AI 前用代码过滤无效/噪音邮件（`EmailPreprocess.isNoise` 强化，Mock 与 Real 服务层均应用）
- [x] 9.3 `AIService.analyzeEmails`：重要级别 + ≤20 字一句话建议（Mock 规则化 + OpenAI 批量 JSON + `EmailSummary.clamp` 硬截断保底）
- [x] 9.4 分级样式：降落卡（级别标签 + 倒计时条配色）与消息行（左侧级别竖条 + 级别标签）按 high/medium/low 区分
- [x] 9.5 验证：Mock 下重要级别区分、summary ≤20 字、无效邮件过滤均生效（runtime 已确认）

## 10. O365 OAuth2 接入（IMAP 基础认证已被禁用，实测 "NO AUTHENTICATE failed."）

- [x] 10.1 `MicrosoftOAuth`：OAuth2 设备码流程（复用公开 client ID，无需注册 Azure 应用/回调）+ refresh token 续期；refresh token 存 Keychain，access token 内存缓存
- [x] 10.2 `IMAPConnection.authenticateXOAUTH2`：SASL XOAUTH2（`user=…^Aauth=Bearer <token>^A^A`），处理 "+" 错误质询避免挂起
- [x] 10.3 `RealEmailService.Auth`（password / oauth token provider）；`AppDelegate.currentEmailService` 已登录走 OAuth、否则应用密码、再否则 Mock
- [x] 10.4 设置面板「用 Microsoft 登录」行：设备码登录（自动开浏览器+复制代码）+ 已登录/退出 + 测试连接走 OAuth
- [x] 10.5 真实 O365 账号验证（部分）：设备码登录 + refresh token 存 Keychain + XOAUTH2 **认证已被服务器接受**（"User is authenticated…"）。
- [ ] 10.6 拉取真实邮件：被邮箱 **IMAP 协议禁用**挡住（服务器返回 "User is authenticated but not connected."）。需在 Exchange 启用 IMAP（OWA 自助或 IT `Set-CASMailbox -ImapEnabled $true`）；若无法启用则改走 Microsoft Graph（需带 Mail.Read 的 client ID）。

## 11. Gmail OAuth 接入 + 多账号（email-google-oauth）

- [x] 11.1 `GoogleOAuth`：授权码 + PKCE + 本地回环(NWListener) 流程，复用 Thunderbird 公开 Google client；refresh token 入 Keychain、Gmail 地址入 UserDefaults
- [x] 11.2 Gmail 拉信复用 IMAPConnection.authenticateXOAUTH2（imap.gmail.com:993 + Google token）
- [x] 11.3 多账号：`currentEmailServices()` 同时聚合 O365(Graph) + Gmail(IMAP XOAUTH2) + 其它 IMAP(应用密码)，syncEmail 跨来源按 messageId 去重后汇入消息
- [x] 11.4 设置面板「Gmail 登录」行（用 Google 登录 / 已登录:邮箱 / 退出）；测试连接覆盖所有已接入来源
- [ ] 11.5 真实 Gmail 账号验证：Google 登录成功 + 测试连接拉到真实未读（待用户实测）
