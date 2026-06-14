# 邮件筛选逻辑

> 一封邮件从「拉取」到「入库弹卡」要过 **4 道关**：前 3 道是纯代码规则（不出网、省 token），第 4 道是 AI 价值判定。
> 筛选哲学：**代码层做「宁可错杀」的噪音/机器邮件清理 + 去重，AI 层做「宁可放过」的真人事务价值判定**（两处把握不准时都倾向保留）。

## 总览管线

```
拉取(IMAP/Graph)
  → ① 时间窗过滤(最近 3 天)
  → ② 代码硬过滤(噪音 / 自动通知 / 其他页签已覆盖)
  → ③ 去重(已知 messageId)
  → ④ AI 价值判定(valuable=false 丢弃)
  → 入库 + 弹提醒卡
```

代码位置：

| 关卡 | 实现 | 文件 |
| --- | --- | --- |
| ① 时间窗 | `EmailFetchWindow` | `Services/EmailService.swift` |
| ② 硬过滤 | `EmailPreprocess` / `EmailClassifier` | `Services/EmailService.swift` |
| ③ 去重 + ④ 调度 | `AppDelegate.syncEmail` | `AppDelegate.swift` |
| ④ AI prompt | `AIService.analyzeEmails` | `Services/AIService.swift` |
| 兜底（AI 不可用） | `EmailHeuristics` / `EmailSummary` | `Services/EmailService.swift` |

---

## ① 时间窗过滤 —— 只要最近 3 天的未读

`EmailFetchWindow`

- **服务端先收一刀**：IMAP 用 `UID SEARCH UNSEEN SINCE <dd-MMM-yyyy>`（日期粒度，略宽）；Graph 用 `receivedDateTime ge <ISO8601>`（精确）。
- **本地再收紧**：拉回后按 `cutoff = now - 3*86400` 精确时间戳二次过滤（日期不可解析时保留）。
- 每轮最多处理 **20 封**（`maxFetch`），防一次性拉爆。

---

## ② 代码硬过滤（送 AI 之前，三个 guard）

Mock 和真实现走同一套逻辑。任意一条命中即丢弃。

### a. `isNoise` —— 营销 / 系统噪音

- **域名含**：`newsletter` `noreply-marketing` `mailchimp` `sendgrid.net` `mailgun` `no-reply@` `donotreply`
- **主题含**：`unsubscribe` `退订` `促销` `newsletter` `广告` `verify your email` `验证码` `对账单` `账单通知` `daily digest`

### b. `isAutomatedNotification` —— 非真人自动通知（= 自动地址 OR 通知类主题）

**自动发件地址** `isAutomatedAddress`（最稳信号，看 `@` 前的 localpart）：

- 含特征词：`no-reply` `noreply` `notification` `notify` `mailer` `bounce` `automated` `newsletter` `digest` `marketing` `updates` `alerts` `account-security` 等
- 整段精确匹配：`team` `hello` `news` `info` `support` `notifications`（精确匹配避免误伤 `teamlead.li` 之类）

**通知类主题** `looksLikeNotificationSubject`：

- 英文：`digest` `weekly` `newsletter` `changelog` `release note` `product update` `activity in` `meeting notes` `invitation to` `security alert` `sign-in`
- 中文：`周报` `月报` `更新` `活动` `纪要` `邀请你加入` `受邀` `知会` `通知`

### c. `isCoveredByOtherTab` —— 已有专属页签，避免重复

- **Jira/Confluence** 通知（`atlassian.net`）→ 走 Mentions 页签
- **GitHub** 通知（`github.com`）→ 走 Today 的 Jira·GitHub 区

> 来源识别 `EmailClassifier.source` 会把邮件标记为 `slack / jira / email`（Slack/Jira 通知判定 + 深链归一），其中 `jira` 来源直接被 c 排除。

---

## ③ 去重

`AppDelegate.syncEmail`：与库内已有 `messageId` 比对 + 本轮内去重。**去重在 AI 之前**，避免对已知邮件重复打 LLM。首轮静默不弹卡（`emailBaselineSynced`）。

---

## ④ AI 价值判定（最后一关，硬过滤之后 / 入库之前）

`AIService.analyzeEmails` 一次调用批量分析，逐封返回 `importance / suggestion / valuable`，**`valuable=false` 的不入库、不占提醒位**。AI 不可用时回退本地启发式 `EmailHeuristics.isLowValue`。

### System Prompt（原文）

```
你是邮件提醒助手。逐封分析邮件并输出：importance（high=需我尽快行动/老板或客户催办/明确截止，medium=一般待办，low=仅知会/通知类），suggestion（用一句话客观摘要这封邮件的核心内容——说清这封邮件讲了什么事，带上关键对象：人名 / 单号 / 截止时间；去掉寒暄、签名、客套和无关细节。**20 个汉字以内**、不换行、不加引号、不要用「查看…」「了解…」这类空泛说法。只依据正文已有内容如实概括，不要臆造截止时间、单号、诉求或任何未在邮件中出现的信息），valuable（true=值得进收件箱提醒的真人事务或我必须知道的信息；false=价值不高、可忽略：纯营销/群发周知/自动回执/与我无关的抄送/重复或过期通知。把握不准时给 true）。只输出 JSON 对象：{"results": [{"index": 0, "importance": "high|medium|low", "suggestion": "...", "valuable": true}]}，index 与输入序号一致、覆盖全部邮件。只依据给定内容，不要臆造。
```

### 喂给模型的每封邮件格式

已经过隐私预处理（`EmailPreprocess.excerpt`：剥离签名/引用历史 + 正文截断到约 1500 字）：

```
[0] 来源:<slack/jira/邮件> 发件人:<name>
主题:<subject>
正文:<bodyExcerpt>
```

---

## 兜底：AI 不可用时的本地价值判定

`EmailHeuristics.isLowValue` —— 保守策略，默认保留：

- **高价值信号一票否决（保留）**：`紧急` `尽快` `立即` `今天` `截止` `deadline` `asap` `urgent` `请回复`，或重要发件人 `boss@` `ceo@` `client` `vip`
- 否则若主题仍像通知类（`looksLikeNotificationSubject`）→ 判为低价值丢弃

`EmailHeuristics.importance` —— 重要级别启发式：

- **high**：命中高价值词或重要发件人
- **low**：命中 `通知` `知会` `fyi` `仅供参考` `周报` `newsletter` `抄送`
- 其余 **medium**
