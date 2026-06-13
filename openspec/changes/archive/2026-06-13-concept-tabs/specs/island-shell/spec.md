## MODIFIED Requirements

### Requirement: Today 焦点布局与 Inbox 全量视图
展开态页签 SHALL 与五大概念一一对应，集合为：`Today · 任务 · 工作项 · 日历事件 · 信息 · Agent · Calendar`（外加设置 ⚙）。各页签承载：

- **Today**：今日聚合（问候统计 → AI 建议 → 已超期 → 今日任务 → Agent 待处理 → 活跃工作项 → 已完成折叠）
- **任务**（Todo）：全部未完成个人任务的纯列表，可完成
- **工作项**（WorkItem）：全部 Jira/GitHub 工作项，活跃与积压分组，只读跳转
- **日历事件**（CalendarEvent）：纯事件议程（会议/节假日），不含个人任务
- **信息**（Message + Mention）：邮件消息 + @我提及，内部分段
- **Agent**（AgentSession）：全部会话
- **Calendar**：事件 + 个人任务的合并时间线（later-into-calendar）

不再提供 `Later`(Inbox) 页签。页签栏 SHALL 横向可滚动，右端 ＋/↻/⚙ 图标固定不随滚动，且角标不被裁剪。

#### Scenario: 工作项有独立入口
- **WHEN** 切到「工作项」页签
- **THEN** 看到全部 Jira/GitHub（活跃在前、积压在后），无个人任务

#### Scenario: 任务纯列表
- **WHEN** 切到「任务」页签
- **THEN** 看到全部未完成个人任务，可勾选完成；无外部工单

#### Scenario: 日历事件与 Calendar 区分
- **WHEN** 切到「日历事件」页签
- **THEN** 只看到事件（会议/节假日），不含个人任务
- **AND WHEN** 切到「Calendar」页签
- **THEN** 看到事件与个人任务合并的时间线

#### Scenario: 无 Later 页签
- **WHEN** 浏览页签栏
- **THEN** 不存在「Later」页签；外部工单积压在「工作项」页签可见

#### Scenario: 页签栏横向滚动
- **WHEN** 页签数量超出可视宽度
- **THEN** 页签区横向滚动，右端 ＋/↻/⚙ 固定可见，未读角标不被裁
