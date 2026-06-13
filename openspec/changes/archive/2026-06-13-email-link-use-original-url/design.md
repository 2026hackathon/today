## Context

每条 Message 携带一个可点击的 `link: URL`，UI（`MessageInboxPanel` 的 ↗ 按钮、`MessageLandedCard` 整卡点击）通过 `NSWorkspace.shared.open(link)` 打开。链接由拉取层生成：

- O365(Graph)：`GraphEmailService` 对 `email` 来源取 Graph 的 `webLink`（OWA 原邮件 web 链接）。✓ 已是原邮箱链接。
- Gmail(IMAP XOAUTH2)：`RealEmailService` 经 `EmailClassifier.normalizedLink` → `mailLink`，对 `email` 来源生成 `message://<Message-ID>`（唤起本地 Mail.app），无 Message-ID 时回退正文第一个 http 链接。✗ 不是原邮箱链接。

两个真实通道当前都在用：`AppDelegate.currentEmailServices()` 同时装配 `GraphEmailService()` 与 `RealEmailService(host: "imap.gmail.com", …)`。手动 IMAP+应用密码通道已停用。

## Goals / Non-Goals

**Goals:**
- `email` 来源的 link 一律指向「原邮箱网页端的那封原始邮件」，点开即原邮件。
- Gmail 用 `Message-ID` 生成 Gmail 网页端原邮件链接，替代 `message://`。
- O365 维持 `webLink`，把「email 用 webLink」明确为契约。

**Non-Goals:**
- 不改 `slack` / `jira` 来源的深链行为（仍优先正文深链）。
- 不改 UI 打开方式、不改去重/隐私预处理。
- 不为「通用 IMAP（非 Gmail/O365）」新增 webmail 推断；它继续走 `message://` 兜底（且该通道当前停用）。

## Decisions

### D1：Gmail 原邮件链接用 `rfc822msgid` 搜索 URL
Gmail 网页端打开某封原始邮件的标准方式是按 RFC822 Message-ID 搜索：
`https://mail.google.com/mail/u/0/#search/rfc822msgid:<percent-encoded Message-ID>`（Message-ID 去掉外层 `<>` 后整体 URL 编码）。这是 Gmail 暴露的、指向「邮箱里那封原始邮件」的 web 链接，符合「直接使用原邮箱的链接」。

- 备选：`message://`（现状）——唤起本地客户端而非邮箱，多数用户打不开，否决。
- 备选：用 IMAP UID 构造链接——UID 是会话内/邮箱内部标识，无稳定 web 入口，否决。

### D2：链接生成需要知道 provider（host）
`EmailClassifier.normalizedLink` / `mailLink` 当前只拿到 `source/body/messageId`，无法区分 Gmail vs 通用 IMAP。`RealEmailService` 持有 `host`，在调用处把 host（或一个 `provider` 枚举）传入，使 `host == imap.gmail.com` 时走 Gmail 链接、否则走 `message://` 兜底。Graph 路径不经过该函数，单独保留 `webLink`。

### D3：`email` 来源不再回退正文 http 链接
原 `mailLink` 在无 Message-ID 时回退正文第一个 http 链接——那是邮件正文里的任意外链，不是原邮件链接，与本次目标冲突。改为：能生成原邮箱链接就用，生成不了（如无 Message-ID 的通用 IMAP）才回退 `message://`；不再扫正文 http。`slack`/`jira` 的深链提取逻辑（`deepLink`）保留，不受影响。

## Risks / Trade-offs

- [Gmail 多账号 `u/0` 不一定对] → `#search/rfc822msgid:` 在登录的 Gmail 会按当前账号定位邮件；`u/0` 是常见默认，多账号下若不命中用户可切换账号，仍能打开原邮件。后续如需精确可用 `u/<email>`。优于现状（完全打不开）。
- [Message-ID 含特殊字符] → 去 `<>` 后做百分号编码（含 `@`、`+` 等），避免 URL 破损。
- [通用 IMAP 仍 `message://`] → 该通道当前停用，影响面为零；保留兜底不阻塞本次目标。

## Migration Plan

无数据迁移：link 在拉取时生成，下一轮 `syncEmail` 自然产出新链接。已入库的旧 `message://` 链接随其 Message 被处理/清理而消失，不需要回填。

## Open Questions

无。
