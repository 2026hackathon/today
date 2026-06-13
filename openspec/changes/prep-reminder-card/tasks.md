## 1. 状态机契约

- [x] 1.1 `Island/IslandState.swift`：新增 `case prepReminder(todo: Todo, moreCount: Int)`；`isCompact` 保持 false（默认走 isDismissable）
- [x] 1.2 `IslandGeometry.geometry(for:)`：`.prepReminder` 归入 reminder/landed 分支（宽 380、高自适应）

## 2. AppStore 徽章状态与方法

- [x] 2.1 新增瞬态 `@Published private(set) var prepPendingTodoIDs: Set<UUID> = []`（不持久化）+ 派生 `hasPrepBadge` / `prepBadgeCount`
- [x] 2.2 `presentPrep(_ todo: Todo, moreCount: Int)`：高优先级 insert 进集合；按输入态护栏决定是否 `present(.prepReminder(...))`
- [x] 2.3 `acknowledgePrep(_ todo:)`：`dismiss()`（集合保留 → 徽章留存）；`reopenPrep()`：取集合中最紧近项 `present(.prepReminder)`；`clearPrep(_ todo:)`：从集合移除
- [x] 2.4 `prunePrepBadges()`：仅保留「存在、未完成、未被 snooze 压住、距有效截止 > finalWindow」的 id；在 `refreshCompactState()` 内调用兜底

## 3. AppDelegate 接线

- [x] 3.1 `reminderScheduler.onFire` 的 `.oneHour` 分支：低→`refreshCompactState()`（现状）；中/高→计算 moreCount 后 `store.presentPrep(todo, moreCount:)`
- [x] 3.2 `.fifteenMin/.due/.overdue` 分支补 `store.clearPrep(todo)`（接管即清徽章）

## 4. PrepReminderCard 视图

- [x] 4.1 新建 `UI/Cards/PrepReminderCard.swift`：仿 JiraLandedCard（header/title/meta + collecting 缩入），文案随 kind 区分，展示距截止时间
- [x] 4.2 中优先级：底部倒计时条 6s（hover 暂停）→ 走完 `collect()`→`store.dismiss()`
- [x] 4.3 高优先级：无倒计时；「知道了」主按钮 → `store.acknowledgePrep(todo)`；moreCount>0 显示「还有 N 项要准备」
- [x] 4.4 在 IslandRootView 卡片态分发处接入 `.prepReminder` → PrepReminderCard

## 5. CompactContent 徽章

- [x] 5.1 `UI/Compact/CompactContent.swift`：左翼 agent 徽章旁，`store.hasPrepBadge` 时显示提前准备徽章（图标 `hourglass`，计数 `prepBadgeCount`），`onTapGesture` → `store.reopenPrep()`
- [x] 5.2 `IslandGeometry` 收缩态宽度：若徽章影响布局，确认 agentBadgeWidth 类机制是否需补（优先复用现有两翼空间，不够再加宽）

## 6. Debug 与验收

- [x] 6.1 菜单栏 Debug 菜单加「模拟提前准备卡（高）」「（中）」触发项
- [x] 6.2 `cd MiniNotch && swift build` 通过；旧 todos.json 启动无崩溃
- [ ] 6.3 冒烟：高→弹卡不自动消失→收起留徽章→点徽章重开→任务临近时徽章自动消失并弹到期卡；中→弹卡 6s 自收无徽章；低→无卡
- [ ] 6.4 输入态（⌘N）下提前量到点：不抢占；高优先级徽章仍出现
