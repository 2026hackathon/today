## Why

「提前提醒」= 提前准备，但现状下 lead（`.oneHour`）档触发时**没有任何主动提示**——只调 `refreshCompactState()` 让刘海颜色可能转 near，无卡、无声、无推送。用户在提前量那一刻其实感知不到「该准备了」。

同时不同优先级的事，提前准备的「打扰强度」应当不同：高优先级的准备是要你动手的、不该轻易溜走；中优先级只是告知一声。这正好契合 app 既有的隐含语法——**需要动手的卡常驻（如到期卡），纯告知的卡倒计时自动收回（如工单/消息降落卡）**。

## What Changes

- lead（`.oneHour`）档触发时，按优先级分级呈现「提前准备卡」`PrepReminderCard`：
  - **高优先级** SHALL 弹卡且**不自动消失**；用户点「知道了」或点外侧收起后，SHALL 在 compact 左翼留下一个**常驻提前准备徽章**（复用 AgentBadge 视觉），点徽章可重新展开卡片。
  - **中优先级** SHALL 弹卡并带底部倒计时条（~6s，悬停暂停），走完**完全收回**到 compact（不留徽章），靠 near 色被动留存感知。
  - **低优先级** SHALL 维持现状：不弹卡，仅刷新 compact 颜色。
- prep 卡 SHALL NOT 抢占输入态（快速新建 / 任务降落 / 批量卡），与到期卡一致。
- 提前准备徽章 SHALL 在以下任一情形**自动清除**（无需用户手动清）：对应任务进入 finalWindow（即 fifteenMin/due 提醒接管）、被完成、或被删除。即徽章「一直可见到真正到点为止」。
- 同一轮多条 lead 同时触发时 SHALL 聚合：先弹一张卡，其余进徽章，卡上以 `moreCount` 显示「还有 N 项要准备」。
- prep 卡的文案随 `kind` 区分（日程「去准备」/ 任务「该开始」），并展示距截止时间。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `island-shell`: 新增 `IslandState.prepReminder(todo:moreCount:)` 卡片态；compact 左翼新增「提前准备」常驻徽章（高优先级 lead 收起后留存，点击重开）。
- `reminders`: lead（提前量）档触发 SHALL 按优先级分级呈现 prep 卡（高常驻+徽章 / 中倒计时自收 / 低仅刷新颜色），并定义徽章的自动清除条件与输入态保护。

## Impact

- `Island/IslandState.swift`（共享契约）：新增 `case prepReminder(todo:moreCount:)`；`IslandGeometry` 补该态尺寸（沿用 reminder 卡 380 宽）。
- `Core/AppStore.swift`（共享契约）：新增瞬态 `prepPendingTodoIDs: Set<UUID>`（不持久化）+ 派生 `hasPrepBadge`/`prepBadgeCount`；新增 `presentPrep(_:moreCount:)`、`acknowledgePrep(_:)`（高：收卡留徽章）、`reopenPrep()`（点徽章重开）、`clearPrep(_:)`/`prunePrepBadges()`（自动清除）。
- `AppDelegate.swift`：`reminderScheduler.onFire` 的 `.oneHour` 分支改为按优先级 `presentPrep`；`.fifteenMin/.due/.overdue` 分支补 `store.clearPrep(todo)`（接管即清徽章）。
- `UI/Cards/PrepReminderCard.swift`（新建）：仿 `JiraLandedCard`，中=倒计时条自收、高=「知道了」按钮收成徽章。
- `UI/Compact/CompactContent.swift`：左翼增加 prep 徽章（在 agent 徽章旁），点击触发 `store.reopenPrep()`。
- 持久化不变（徽章为瞬态、不写盘）；旧数据无影响。
- 菜单栏 Debug 菜单加触发项（高/中 prep 卡）便于冒烟与 Demo。
