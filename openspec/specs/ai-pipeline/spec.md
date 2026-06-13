# ai-pipeline Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: AIService 协议
框架 SHALL 定义 `AIService` 协议：截图→TodoDraft 列表、自然语言→TodoDraft、晨报/晚报生成。所有方法 async throws。

#### Scenario: 截图解析单任务
- **WHEN** `parseScreenshot` 返回 1 个 draft
- **THEN** island 进入 newTask 卡片态，展示可编辑草稿（标题/优先级/截止时间/AI 解释）

#### Scenario: 批量识别
- **WHEN** `parseScreenshot` 返回 ≥3 个 draft
- **THEN** island 进入 batch 卡片态，逐项可勾选，默认全选

#### Scenario: 解析失败兜底
- **WHEN** AIService 抛出异常
- **THEN** island 红色短闪并提示「未识别到任务」，提供手动录入入口

### Requirement: 解析中流光反馈
AI 调用期间 island SHALL 处于 aiWorking 态并显示流光呼吸效果，调用结束立即停止。

#### Scenario: 感知 AI 工作
- **WHEN** AI 调用开始
- **THEN** compact 态变宽（340pt）且出现 SwiftGlow 流光，结束后恢复

### Requirement: Mock 实现保障演示
框架 SHALL 内置 `MockAIService`：固定延迟 ~1.2s，返回 PRD 演示用 draft（含紧急度与 AI 解释文案），永不失败。

#### Scenario: 无 API Key 也能跑 Demo
- **WHEN** 未配置任何 AI key
- **THEN** F2 截图链路仍可走通（使用 Mock 结果）

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

### Requirement: 邮件重要级别分析与一句话建议长度约束
`AIService` 的邮件分析 SHALL 对每封邮件同时给出**重要级别**（high / medium / low）与**一句话行动建议**；建议长度 SHALL ≤ 20 个字，实现 SHALL 在写入前硬截断保底（即使模型超长也不超过 20 字）。批量分析返回 SHALL 与输入等长、按序一一对应；任一项缺失 SHALL 由规则化兜底补齐。未配置 Key 时重要级别 SHALL 由本地关键词启发式判定（紧急/截止/老板客户→high，知会/通知类→low，其余 medium），不出网。

#### Scenario: 给出级别与 ≤20 字建议
- **WHEN** 传入一封经预处理的邮件
- **THEN** 返回 importance ∈ {high,medium,low} 与一条 ≤20 字的建议，写入 Message.importance / Message.summary

#### Scenario: 模型超长硬截断
- **WHEN** 模型返回的建议超过 20 字
- **THEN** 写入前截断到 ≤20 字（带省略号）

#### Scenario: 无 Key 启发式判级
- **WHEN** 未配置 AI Key
- **THEN** 重要级别由本地关键词规则判定、建议由规则化生成，均不出网

