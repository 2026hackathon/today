# Proposal: review-fixes-batch1

## Why

全量代码审查（3 agent + 人工复核）发现 24 条真实问题，用户确认修复其中 10 条：两条可造成不可逆数据丢失（#1 配置编辑窗口 prune 误删、#4 Todo 解码无兼容层）、两条核心交互正确性（#7 草稿串卡、#8 编辑中被收卡）及若干同步/提醒语义缺陷。

## What Changes

- #1 未配置外部源仅在启动后首次同步清空（清历史数据），运行期未配置跳过同步——堵住设置编辑窗口期误删
- #2 首轮静默基线改为「成功同步后才建立」，失败不置位；手动刷新共享同一基线，先于轮询也不会全量误报
- #4 `Todo` 增加向后兼容解码（逐字段 decodeIfPresent + 默认值），新增字段不再清空 todos.json
- #7 newTask/batch 路由按 draft id 绑定视图身份，连续触发不串草稿
- #8 卡片自动收回在 菜单打开（NSMenu 全局跟踪通知）/ 输入聚焦 / 用户点击过卡片 时解除
- #9 `isOverdue` 以 `snoozedUntil ?? dueDate` 为锚（snooze 后回「今日任务」）；调度器 snooze 到点后走标准分级管线（恢复过期 5 分钟重复）
- #10 `nextDue` 过滤非活跃 Jira，与 `overdueTodos` 口径一致（消除「compact 红色但面板无超期」）
- #11 到期提醒/晚报不抢占输入态（quickInput/newTask/batch）；晚报未弹出不消耗当日标记
- #12 NSMenu 跟踪期间挂起悬停收起与倒计时（Debug 菜单/右键菜单/卡内 Menu 不再塌面板）
- #13 crownedToday 跨天自动失效；justCompleted 闪光定时器校验状态后才回落

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `reminders`: snooze 到点后的分级语义明确化
- `todo-data`: isOverdue 锚点含 snooze；解码兼容性要求

## Impact

Models / AppStore / AppDelegate / IslandRootView / NewTaskCard / ReminderScheduler
