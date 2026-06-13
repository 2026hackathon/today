## Why

上线后的两点体验微调：① 无固定时间的本地任务目前不显示完成圈（只能删除），但用户同样需要勾掉它们——「无截止 ≠ 不可完成」；② 日历列表里已完成项的绿色对勾圆圈在本轮被放大到 16pt，显得过重，回到此前 11pt 的小巧样式更克制。

## What Changes

- 无固定时间（无截止）的本地自定义任务 SHALL 也可点击完成（不再显示静态小点）。「静态小点」仅保留给**未来截止**的本地任务。
- 日历/任务行**已完成**状态的绿色对勾改回小尺寸（约 11pt，沿用前一版本样式），不再用 16pt 大圆。

## Capabilities

### New Capabilities
<!-- 无 -->

### Modified Capabilities
- `apple-calendar-integration`: 调整「完成与删除的可用性」——无截止本地任务纳入可完成；已完成对勾恢复小尺寸样式。

## Impact

- 代码：`Core/AppStore.swift`（`canComplete` 对无截止本地任务返回 true）；`UI/Panels/TodayPanel.swift`（`PersonalTodoRow` 与 `MeetingRow` 已完成对勾尺寸 16 → 11）。
- 无数据/接口变化；纯交互与视觉微调。
