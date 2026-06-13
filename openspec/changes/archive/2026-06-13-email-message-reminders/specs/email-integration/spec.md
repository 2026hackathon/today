## ADDED Requirements

### Requirement: 邮件来源识别
邮件拉取层 SHALL 依据发件域与已知邮件头判定来源并归类为 `slack` / `jira` / `email` 三类之一：Slack 通知（如 `*.slack.com` 发件域或 Slack `List-ID`）归 `slack`；Jira 通知（如 `*.atlassian.net` 发件域或 Jira 通知头/正文 issue 链接）归 `jira`；其余一律归 `email`。识别不确定时 SHALL 安全降级为 `email`，不得因识别失败而丢弃邮件。

#### Scenario: Slack 通知邮件
- **WHEN** 收到发件域为 `*.slack.com` 的邮件
- **THEN** 生成的 Message.source 为 `slack`

#### Scenario: Jira 通知邮件
- **WHEN** 收到来自 `*.atlassian.net` 且正文含 `browse/{KEY}` 的邮件
- **THEN** Message.source 为 `jira`

#### Scenario: 普通邮件兜底
- **WHEN** 邮件来源无法判定为 slack 或 jira
- **THEN** Message.source 为 `email`，邮件不被丢弃

### Requirement: 链接归一
每条 Message SHALL 携带一个可点击的 `link: URL`，按来源归一：`slack` → 邮件内 Slack 深链（`https://*.slack.com/archives/...`）；`jira` → 对应 issue 链接（`{baseURL}/browse/{KEY}`）；`email` 或上述深链缺失时 → 统一邮件链接（优先 `message://<Message-ID>` 唤起本地邮件客户端，无法构造时回退 webmail/原始链接）。

#### Scenario: Slack 深链可用
- **WHEN** Slack 通知邮件正文含 archives 深链
- **THEN** Message.link 指向该 Slack 深链

#### Scenario: 深链缺失降级
- **WHEN** 邮件无可提取的来源深链
- **THEN** Message.link 为该邮件的邮件链接（message:// 或 webmail）

### Requirement: 邮件转 Message 与去重
拉取层 SHALL 将每封纳入的邮件转换为一条 Message（含 summary 占位/待 AI 填充、source、link、receivedAt、sender、rawSubject），并以邮件 `Message-ID` 为去重键：同一 `Message-ID` 重复拉取 SHALL NOT 产生重复 Message，且已存在 Message 的「已处理」状态 SHALL 被保留。

#### Scenario: 重复拉取不重复入库
- **WHEN** 轮询再次返回一封已入库的邮件（相同 Message-ID）
- **THEN** 不新增 Message，已有的 processed 状态保持不变

### Requirement: 发送 AI 前的隐私预处理
将邮件交给 AI 生成一句话提醒之前，系统 SHALL 在本地完成隐私处理：按发件域/邮件头预过滤明显噪音（营销、纯系统通知）不入库或不送 LLM；正文 SHALL 截断到上限（约 1.5k 字）并剥离签名与引用历史后再发送。无 AI Key 时 SHALL NOT 将正文出网。

#### Scenario: 正文截断与剥离
- **WHEN** 一封含长引用历史与签名的邮件被解析
- **THEN** 发送 LLM 的内容已截断且不含签名/引用历史

#### Scenario: 无 Key 不出网
- **WHEN** 未配置 AI Key
- **THEN** 不向远程 LLM 发送任何邮件正文，summary 走本地规则化生成
