## Context

三处问题各在不同层：
- **弹窗误收起**：`IslandRootView.handleHover(false)` 在移出 0.2s 后调用 `store.dismiss()`，guard 只排除 `isMenuTracking`（Debug/右键菜单）。SwiftUI `confirmationDialog` 是局部 `@State`，不进 island 状态机，移出收起照样触发，把弹窗一起关掉。
- **删除按钮热区**：`PersonalTodoRow` / `MeetingRow` 用 `.onHover` 驱动 `hovering`，但行只有 `.background(...)` 没有覆盖整行的 `.contentShape`，`Spacer` 撑出的空白区不参与命中测试，悬停只在文字/可见控件上生效。
- **时间窗**：`CalendarPanel.dayGroups` 直接消费 `store.meetingsByDate`（含 29 天历史）与 `store.calendarPersonalTodos`（无日期过滤），未做窗口裁剪，历史全量铺开。

## Goals / Non-Goals

**Goals:**
- 确认弹窗打开时不被悬停移出收起；关闭后恢复。
- 任务行/会议行整行可悬停触发删除按钮。
- 日历页签只显示「昨天 ~ 未来 15 天」，昨天仅留本地未完成自定义任务。

**Non-Goals:**
- 不改后台同步深度（`calendarSyncDaysPast/Future` 不动，避免牵动 `calendar-historical-sync` 的 30 天窗口约束）。展示窗只是过滤层。
- 不改 Today 焦点面板（仅日历页签）。
- 不为弹窗引入新的 island 状态机态——用一个轻量标志即可。

## Decisions

### 弹窗抑制：AppStore 计数标志 + handleHover guard
在 `AppStore` 加 `@Published var dialogPresentedCount = 0`（计数而非 bool，防多行弹窗并发置位互相覆盖）；`PersonalTodoRow`/`MeetingRow` 的 `confirmationDialog` 用 `isPresented` 绑定的 `onChange`（或在 `requestDelete`/按钮回调里）进出时 `+1/-1`。`handleHover` 移出分支 guard 增加 `store.dialogPresentedCount == 0`。
- **为何计数不用 bool**：日历页可见多行，理论上状态切换交错；计数对称增减更稳，归零才放行收起。
- **为何不复用 `cardHeld`**：`cardHeld` 语义是「编辑卡未保存」，`dismiss()` 里会被重置，语义不符；新标志独立清晰。
- **备选（否决）**：把确认做成 island 状态机的一态——改动大、过度设计，且 `confirmationDialog` 已够用。

### 热区：整行 contentShape
在两行的 `.background(...)` 之后、`.onHover` 之前加 `.contentShape(Rectangle())`（或 `RoundedRectangle`），让整行矩形参与命中测试。`TaskRow`（427 行附近）已有 `.contentShape`，对齐其写法即可。

### 时间窗：在 dayGroups 内裁剪 + 昨天特判
窗口边界在 `CalendarPanel.dayGroups` 计算：
```
today = startOfDay(now); yesterday = today - 1d; windowEnd = today + 15d
```
- Meeting：仅纳入 `startOfDay(meeting) ∈ [today, windowEnd]`（昨天不纳入会议）。
- Todo（来自 `calendarPersonalTodos`，已排除 Jira/GitHub/.calendar）：
  - 有 `effectiveDue`：`day = startOfDay(due)`；`day == yesterday` 时仅当 `!isCompleted` 纳入；`day ∈ [today, windowEnd]` 全纳入；否则丢弃。
  - 无截止：仍挂今天分组（不受昨天口径影响）。
- 分组排序后即得 `[昨天?, 今天, …, +15]`。
- **为何放在 dayGroups 而非 AppStore**：窗口是日历页签专属展示口径，Today 面板与其它消费方不应受影响；`calendarPersonalTodos`/`meetingsByDate` 保持「全量数据源」语义。

## Risks / Trade-offs

- [弹窗标志泄漏：弹窗异常关闭未减计数，导致 island 再也不自动收起] → 用 `confirmationDialog` 的 `isPresented` `onChange(false)` 统一归位，而非只在按钮回调里减；确保任何关闭路径都触发。
- [contentShape 吃掉行内子控件点击] → 用 `Rectangle` 作 contentShape 只扩大命中范围，子按钮（完成圈/缩略图/删除）仍在其上层，正常接收点击；与已存在的 `TaskRow` 写法一致，已验证可行。
- [未来 Apple 事件实际只同步到 +6 天，+15 上界对会议是空窗] → 可接受：需求本质是「收窄、去历史」，+15 是上界 cap；本地任务可达 +15。若后续要更深的未来会议，另开同步深度变更。

## Open Questions

无。
