## MODIFIED Requirements

### Requirement: 链接归一
每条 Message SHALL 携带一个可点击的 `link: URL`，按来源归一：`slack` → 邮件内 Slack 深链（`https://*.slack.com/archives/...`）；`jira` → 对应 issue 链接（`{baseURL}/browse/{KEY}`）；`email` → **原邮箱网页端中该封原始邮件的 web 链接**，点击即在邮箱打开原邮件。

`email` 来源的原邮箱链接按 provider 生成：
- O365(Graph)：使用 Graph 返回的 `webLink`（OWA 原邮件链接）。
- Gmail(IMAP)：使用该邮件 `Message-ID` 生成 Gmail 网页端原邮件链接 `https://mail.google.com/mail/u/0/#search/rfc822msgid:<percent-encoded Message-ID>`（Message-ID 去除外层 `<>` 后整体 URL 编码）。

`email` 来源 SHALL NOT 回退到邮件正文中提取的任意 http 链接；仅当 provider 无可用 web 邮箱链接（如无 Message-ID 的通用 IMAP）时，方可回退 `message://<Message-ID>` 作为最后兜底。`slack` / `jira` 的来源深链行为保持不变。

#### Scenario: Slack 深链可用
- **WHEN** Slack 通知邮件正文含 archives 深链
- **THEN** Message.link 指向该 Slack 深链

#### Scenario: O365 邮件用 webLink
- **WHEN** 通过 Graph 拉取到一封 `email` 来源的邮件且 Graph 返回 `webLink`
- **THEN** Message.link 为该 `webLink`（OWA 原邮件链接）

#### Scenario: Gmail 邮件用原邮箱 web 链接
- **WHEN** 通过 imap.gmail.com 拉取到一封 `email` 来源、含 Message-ID 的邮件
- **THEN** Message.link 为 `https://mail.google.com/mail/u/0/#search/rfc822msgid:<编码后的 Message-ID>`，点击在 Gmail 网页端打开该原邮件
- **AND** Message.link SHALL NOT 为 `message://` 或正文中提取的 http 链接

#### Scenario: 无 web 邮箱链接时兜底
- **WHEN** 一封 `email` 来源邮件来自既非 Gmail 也非 O365 的通用 IMAP，且无可用 web 邮箱链接
- **THEN** Message.link 回退为 `message://<Message-ID>`，且不扫描正文 http 链接
