## 1. 无固定时间可完成

- [x] 1.1 `AppStore.canComplete(_:)`：本地任务无 `effectiveDue` 时返回 true（无截止可完成）；未来截止仍返回 false

## 2. 已完成对勾恢复小尺寸

- [x] 2.1 `PersonalTodoRow` 已完成分支 `checkmark.circle.fill` 字号 16 → 11
- [x] 2.2 `MeetingRow` 已完成分支 `checkmark.circle.fill` 字号 16 → 11

## 3. 验收

- [x] 3.1 无截止本地任务显示完成圈、可勾选；未来任务仍为小点
- [x] 3.2 已完成项对勾为小尺寸、标题删除线、可撤销
- [x] 3.3 `swift build` 成功 + `openspec validate calendar-complete-untimed` 通过
