## MODIFIED Requirements

### Requirement: 邮件重要级别分析与一句话建议长度约束
`AIService` 的邮件分析 SHALL 对每封邮件同时给出**重要级别**（high / medium / low）与**一句话行动建议**；建议长度 SHALL ≤ 20 个字，实现 SHALL 在写入前硬截断保底（即使模型超长也不超过 20 字）。批量分析返回 SHALL 与输入等长、按序一一对应；任一项缺失 SHALL 由规则化兜底补齐。未配置 Key 时重要级别 SHALL 由本地关键词启发式判定（紧急/截止/老板客户→high，知会/通知类→low，其余 medium），不出网。

建议 prompt SHALL 包含「无真实数据不臆造」约束：当邮件正文没有可支撑具体行动项的实质内容（如纯通知、自动回执、无明确诉求）时，模型 SHALL 仅朴素概括邮件要点，SHALL NOT 编造截止时间、单号、行动项或其他未在邮件中出现的信息，也 SHALL NOT 输出「查看…」「了解…」这类空泛无用的建议。

#### Scenario: 给出级别与 ≤20 字建议
- **WHEN** 分析一封明确要求今天反馈预算的邮件
- **THEN** 返回 importance ∈ {high,medium,low} 与一条 ≤20 字的建议，写入 Message.importance / Message.summary

#### Scenario: 建议超长硬截断
- **WHEN** 模型返回的建议超过 20 字
- **THEN** 实现在写入前硬截断到 ≤20 字

#### Scenario: 无实质内容不臆造建议
- **WHEN** 一封邮件正文为纯通知/自动回执、无明确诉求与可支撑数据
- **THEN** 建议仅朴素概括要点，不编造截止时间/单号/行动项，也不输出「查看…」「了解…」等空泛说法

#### Scenario: 未配置 Key 走规则化兜底
- **WHEN** 未配置 AI Key
- **THEN** 重要级别由本地关键词规则判定、建议由规则化生成，均不出网
