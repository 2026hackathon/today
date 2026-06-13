## Why

邮件消息的「外链按钮」对不同来源行为不一致：O365(Graph) 邮件用的是 `webLink`（OWA 原始链接，点开即原邮件），而 Gmail(IMAP) 邮件用的是构造出来的 `message://<Message-ID>`——它唤起的是本地 Mail.app（多数用户未配置），无法构造时还会回退到正文里随便抓到的第一个 http 链接。结果是「打开原邮件」常常打不开原邮件。用户要求：邮件外链按钮直接使用原邮箱的链接，点开就是邮箱里那封原始邮件。

## What Changes

- `email` 来源的 `Message.link` 统一改为**原邮箱中该封邮件的 web 链接**，点击即在邮箱网页端打开原始邮件：
  - O365(Graph)：使用 Graph 返回的 `webLink`（保持现状，明确为契约）。
  - Gmail(IMAP XOAUTH2)：用该邮件的 `Message-ID` 生成 Gmail 网页端原邮件链接（`https://mail.google.com/mail/u/0/#search/rfc822msgid:<Message-ID>`），不再使用 `message://`。
- 移除 `email` 来源对「正文里随便抓到的 http 链接」的兜底：邮件外链只指向原邮箱链接，抓不到时按来源决定（见 design）。
- `message://<Message-ID>` 仅作为「无已知 webmail 的通用 IMAP」最后兜底，不再是 Gmail/默认路径。
- `slack` / `jira` 来源的深链行为**不变**（仍优先正文深链）。

## Capabilities

### New Capabilities
<!-- 无新增能力 -->

### Modified Capabilities
- `email-integration`: 「链接归一」要求变更——`email` 来源的 link 由「优先 `message://` 唤起本地客户端」改为「原邮箱该邮件的 web 链接（Gmail rfc822msgid / O365 webLink）」。

## Impact

- `MiniNotch/Sources/MiniNotch/Services/EmailService.swift` — `EmailClassifier.normalizedLink` / `mailLink`（Gmail/IMAP 链接生成）。
- `MiniNotch/Sources/MiniNotch/Services/GraphEmailService.swift` — `webLink` 作为 email 原始链接的契约（确认/保持）。
- 调用方 `RealEmailService.fetchNewMessages`（imap.gmail.com 路径）需要把 host/provider 信息传入链接生成，以便区分 Gmail。
- UI 无需改动：`MessageInboxPanel` / `MessageLandedCard` 仍直接 `NSWorkspace.shared.open(message.link)`。
