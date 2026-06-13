## 1. Gmail/IMAP 链接生成（EmailService.swift）

- [x] 1.1 在 `EmailClassifier` 增加 Gmail 原邮件链接生成：去除 Message-ID 外层 `<>` 后整体百分号编码，拼出 `https://mail.google.com/mail/u/0/#search/rfc822msgid:<encoded>`；Message-ID 为空时返回 nil
- [x] 1.2 给 `normalizedLink` / `mailLink` 增加 provider/host 参数：`host == imap.gmail.com` 走 1.1 的 Gmail 链接；否则才回退 `message://<Message-ID>`
- [x] 1.3 移除 `email` 来源在 `mailLink` 中「回退正文第一个 http 链接」的逻辑（`slack`/`jira` 的 `deepLink` 提取保持不变）
- [x] 1.4 在 `RealEmailService.fetchNewMessages` 调用 `normalizedLink` 处传入 `host`

## 2. O365(Graph) 链接契约确认

- [x] 2.1 确认 `GraphEmailService` 对 `email` 来源用 `webLink`（现状），保持不变；补一行注释说明这是「原邮箱链接」契约

## 3. 验证

- [x] 3.1 `swift build` 通过
- [x] 3.2 Gmail：拉取一封含 Message-ID 的 `email` 邮件，确认 `Message.link` 为 `rfc822msgid` 链接、非 `message://`、非正文 http
- [x] 3.3 O365：拉取一封 `email` 邮件确认 `Message.link == webLink`
- [x] 3.4 Slack/Jira 邮件确认深链行为未变
- [x] 3.5 `openspec validate email-link-use-original-url` 通过
