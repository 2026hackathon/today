## ADDED Requirements

### Requirement: 邮件一句话提醒生成
`AIService` SHALL 新增「邮件 → 一句话提醒」能力（async throws），输入为经隐私预处理的邮件摘要信息（发件人 / 主题 / 截断后的正文），输出一句话提醒（who + 要点 + 可选时间），长度 SHALL ≤ 1 句。一次轮询返回多封邮件时 SHALL 支持批量解析以节省 token。`MockAIService`/未配置 Key 时 SHALL 走本地规则化摘要（如发件人 + 主题）兜底，永不失败、且不出网。

#### Scenario: 邮件生成一句话
- **WHEN** 传入一封经预处理的邮件
- **THEN** 返回一条 ≤1 句的提醒文案，写入对应 Message.summary

#### Scenario: 批量解析
- **WHEN** 一次轮询返回多封新邮件
- **THEN** 合并为批量调用生成各自的一句话提醒

#### Scenario: 无 Key 规则化兜底
- **WHEN** 未配置 AI Key
- **THEN** summary 由本地规则（发件人 + 主题）生成，不向远程 LLM 发送正文
