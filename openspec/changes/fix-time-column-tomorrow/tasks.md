## 1. 修正时间轨格式化

- [x] 1.1 在 `TodayPanel.swift` 的 `PersonalTodoRow.timeLabel(_:)`（约 335–338 行）去掉 `isDateInToday` 分叉与 `dsShortLabel`，统一返回 `PanelFormat.hm(due)`，并更新该函数注释为「时间轨只承载时刻，日期交给分组段头」。
- [x] 1.2 确认 `timeTrack`（约 318–333 行）在 `effectiveDue == nil` 时仍走 `Color.clear` 留空占位分支，无需改动「为空」一侧。

## 2. 验证

- [x] 2.1 `swift build`（或项目既有构建命令）通过，无新增警告/错误。
- [x] 2.2 复现截图场景：非当天（明天）有时刻的个人任务行时间轨显示具体 `HH:mm`，不再出现「明天 / 周X / M/d」。
- [x] 2.3 回归确认：当天项仍显 `HH:mm`、无截止项时间轨留空、日历/提醒行（`MeetingRow`）不受影响；`dsShortLabel` 在 HoverPreview / QuickInputCard / BatchCard / MentionsPanel / PrepReminderCard 处文案不变。
