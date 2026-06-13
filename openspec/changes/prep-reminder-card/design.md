# 设计说明

## 核心取舍

复用 app 既有的隐含卡片语法：**需要动手 = 常驻（到期卡），纯告知 = 倒计时自收（降落卡）**。把「高优先级提前准备」归入前者、「中优先级」归入后者。但「高常驻」不等于让整张卡赖在刘海上一小时——改为**三段降级**：弹卡 →（收起）→ compact 常驻徽章 →（接管/完成）清除。徽章既保「不丢失」，又不霸占刘海。

## 持久度只看优先级（一维）

刻意不让 `kind` 参与持久度分级，避免「优先级 × kind」二维交叉难预测。`kind` 仅影响 **文案**（日程「去准备」/ 任务「该开始」）与 **提前时机**（已由 `effectiveLeadMinutes` / `DraftKind.defaultLeadMinutes` 决定）。

## 徽章生命周期（瞬态，不写盘）

`AppStore.prepPendingTodoIDs: Set<UUID>`：

- **加入**：`.oneHour` 触发且 priority == .high → `presentPrep` 同时 insert。中优先级不 insert（自收即弃）。
- **清除（自动）**：`prunePrepBadges()` 在 `refreshCompactState()` 内兜底执行，规则 = 仅保留「仍存在、未完成、未被 snooze 压住、且距有效截止 > finalWindow」的 id；另在 `.fifteenMin/.due/.overdue` onFire 显式 `clearPrep(todo)` 即时清除。
- 因为是瞬态集合，应用重启后自然清空（提前准备是当下窗口的事，无需跨会话）。

## 抢占与接管

- prep 卡复用到期卡的输入态护栏：`islandState` 为 `.quickInput/.newTask/.batch` 时不 `present`（但高优先级仍 insert 进 `prepPendingTodoIDs`，使徽章照常出现）。
- 后续 `.fifteenMin/.due` 触发会 `present(.reminder)` 直接覆盖未收起的 prep 卡（状态机后到者胜），同时 `clearPrep` 去徽章——无须特殊「顶替」逻辑。

## 聚合

`presentPrep(_ todo:)` 把聚合/去重收进 AppStore：高优先级 insert 进 `prepPendingTodoIDs`；若当前已是 `.prepReminder` 态或输入态则只更新徽章集合不重复弹卡；否则弹卡，`moreCount` = `prepBadgeCount`（高优先级排除自身）。卡片 `moreCount` 不要求随后续 fire 实时变化（与 jiraLanded 一致）。

## 卡片视图（PrepReminderCard）

仿 `JiraLandedCard` 骨架（header / title / metaRow + 可选 countdownBar + collecting 缩入动画）：

- header：`hourglass`/`clock.badge` 图标 + 「提前准备」+ kind 标签 + 距截止「N 分钟后」。
- 中优先级：底部 `countdownBar`（6s，hover 暂停），`runCountdown` 走完 `collect()` → `dismiss()`。
- 高优先级：无 countdownBar；底部「知道了」主按钮 → `store.acknowledgePrep(todo)`（内部 `dismiss()`，徽章已在集合中故留存）。点卡片外侧（isDismissable）同样收起留徽章。
- 身份稳定：`collecting` 等条件态放进 overlay/modifier 内部，遵守「岛体视图链身份稳定」硬规则。
