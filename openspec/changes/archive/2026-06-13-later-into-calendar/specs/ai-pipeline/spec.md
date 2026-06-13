## MODIFIED Requirements

### Requirement: AIService 协议
框架 SHALL 定义 `AIService` 协议：截图→TodoDraft 列表、自然语言→TodoDraft、晨报/晚报生成。所有方法 async throws。`TodoDraft` SHALL 携带「意图」字段 `kind`（`event` 带具体时间点的日程 / `reminder` 带截止的提醒 / `task` 无时间或纯笔记），仅用于**本地**分类与提醒强度（如不同默认提前量），**不**触发任何苹果日历写入。无明确时间的 draft SHALL 默认 `kind = task`。

#### Scenario: 截图解析单任务
- **WHEN** `parseScreenshot` 返回 1 个 draft
- **THEN** island 进入 newTask 卡片态，展示可编辑草稿（标题/优先级/截止时间/AI 解释/意图 kind）

#### Scenario: 带具体时间点判定为日程
- **WHEN** 输入「明天下午3点和张三开评审会」
- **THEN** 返回 draft 的 `kind = event`，含起止时间，仅创建本地日程（不写苹果日历）

#### Scenario: 带截止时间判定为提醒
- **WHEN** 输入「周五前交季度报告」
- **THEN** 返回 draft 的 `kind = reminder`，含 dueDate，仅创建本地提醒（不写苹果提醒事项）

#### Scenario: 无时间判定为纯任务
- **WHEN** 输入「整理桌面」无任何时间线索
- **THEN** 返回 draft 的 `kind = task`，仅落本地

#### Scenario: 批量识别
- **WHEN** `parseScreenshot` 返回 ≥3 个 draft
- **THEN** island 进入 batch 卡片态，逐项可勾选，默认全选，每项各自携带 kind

#### Scenario: 解析失败兜底
- **WHEN** AIService 抛出异常
- **THEN** island 红色短闪并提示「未识别到任务」，提供手动录入入口
