# Proposal: today-focus-redesign

## Why

接入真实 Jira（几十条 ticket）和日历后，Today 面板按「来源」分组（个人/Jira/会议）越来越复杂——每多一种数据源就多一个分组，且大量非今日内容淹没真正要关注的事。Today 应只回答「我今天要关注什么」。

## What Changes

- Today 面板从「来源分组」改为「时间相关性」结构：**今日日程 → 已超期 → 今日任务 → 已完成**，来源退化为行尾小图标
- 今日任务进入规则：今天截止（含 Snooze 今天到点）/ 无截止的个人任务（按优先级垫底）/ 活跃状态 Jira（非 To Do、非 Done、非 Cancelled）
- 已超期独立红色段：个人任务全部计入；Jira 仅活跃状态计入（避免陈年 To Do 噪音）
- 非今日内容（未来截止 + To Do 状态 Jira）挪进 **Inbox tab**（从占位变为「全部任务」视图）
- compact 收缩态计数对齐为「今日焦点数」（已超期 + 今日任务），与面板一致

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `todo-data`: 「三大分组」requirement 改为「今日焦点筛选 + Inbox 全量」派生规则
- `island-shell`: Today/Inbox 面板布局 requirement 更新

## Impact

- `Core/AppStore.swift`: 新增 overdue/todayTasks/inbox 派生属性，pendingCount 语义调整
- `UI/Panels/TodayPanel.swift`: 重构布局
- `UI/Panels/InboxPanel.swift`: 新建
