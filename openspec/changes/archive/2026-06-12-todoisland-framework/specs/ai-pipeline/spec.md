# ai-pipeline

AI 解析链路协议与 Mock。Owner: B（替换 Mock 为真实 LLM 调用）。

## ADDED Requirements

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
