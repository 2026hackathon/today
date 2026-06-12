# island-shell (delta)

## ADDED Requirements

### Requirement: Today 焦点布局与 Inbox 全量视图
Today 面板 SHALL 按 问候统计 → 今日日程 → 已超期（红色高亮）→ 今日任务 → 已完成折叠 → AI 建议 的顺序渲染；Inbox tab SHALL 展示全部未完成任务（个人/Jira 分组）。

#### Scenario: 日程置顶
- **WHEN** 打开 Today 面板
- **THEN** 今日会议在最上方，已超期紧随其后，空段自动隐藏

#### Scenario: Inbox 查看存货
- **WHEN** 切到 Inbox tab
- **THEN** 看到未来截止任务与 To Do 状态 Jira 的完整列表
