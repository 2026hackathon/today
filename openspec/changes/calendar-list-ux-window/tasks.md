## 1. 弹窗打开时抑制自动收起

- [x] 1.1 `AppStore` 新增 `@Published var dialogPresentedCount = 0`（计数标志），并在 `dismiss()`/`reset` 路径不强行重置（由视图对称增减管理）
- [x] 1.2 `IslandRootView.handleHover` 移出收起分支的 guard 增加 `store.dialogPresentedCount == 0`
- [x] 1.3 `PersonalTodoRow` 的 `confirmationDialog` 用 `isPresented` 的 `onChange` 在打开 `+1` / 关闭 `-1`（保证任何关闭路径都减计数）
- [x] 1.4 `MeetingRow` 的 `confirmationDialog` 做同样的 `+1/-1` 处理

## 2. 删除按钮悬停热区覆盖整行

- [x] 2.1 `PersonalTodoRow` 在 `.background(...)` 之后、`.onHover` 之前加 `.contentShape(Rectangle())`，使整行（含右侧空白）可悬停
- [x] 2.2 `MeetingRow` 加同样的整行 `.contentShape(Rectangle())`
- [x] 2.3 验证完成圈/缩略图/删除按钮等行内控件点击不受 contentShape 影响（子按钮在容器之上层，contentShape 仅补空白热区，与既有 `TaskRow` 写法一致）

## 3. 日历列表时间窗（昨天 ~ 未来 15 天）

- [x] 3.1 `CalendarPanel.dayGroups` 计算 `today / yesterday / windowEnd(today+15)` 边界
- [x] 3.2 Meeting 仅纳入 `startOfDay ∈ [today, windowEnd]`（昨天不含会议）
- [x] 3.3 有截止 Todo：`day == yesterday` 仅 `!isCompleted` 纳入；`day ∈ [today, windowEnd]` 全纳入；窗口外丢弃
- [x] 3.4 无截止 Todo 仍归今天分组，不受昨天口径影响
- [x] 3.5 `overviewRow` 计数改为从过滤后的 `groups` 统计，与可见数据一致

## 4. 验证

- [x] 4.1 `swift build` 通过
- [ ] 4.2 运行验证：打开删除确认弹窗、鼠标移向按钮，island 不收起；取消/删除后恢复收起
- [ ] 4.3 运行验证：行空白处悬停即出现删除按钮
- [ ] 4.4 运行验证：日历页签从昨天段开始、止于 +15 天；昨天只剩未完成自定义任务
