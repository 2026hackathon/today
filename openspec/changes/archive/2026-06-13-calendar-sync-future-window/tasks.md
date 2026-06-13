## 1. 扩展同步未来窗

- [x] 1.1 `CalendarService.swift`：`CalendarSyncConfig.syncDaysFuture` 由 7 改为 15，更新注释为「今天起到未来 15 天，不含历史」。
- [x] 1.2 确认 `defaultRange()` 仍为 `[today 00:00, today + (syncDaysFuture+1))`，AppDelegate 初始/周期/事件驱动三处同步均经 `defaultRange()`，无硬编码 7 的残留。

## 2. 验证

- [x] 2.1 `swift build` 通过。
- [ ] 2.2 运行 app：苹果日历中创建一条 +10 天的事件，重新同步后日历页签在对应日期段可见（+8~+15 不再缺失）。
- [ ] 2.3 确认昨天段仍只显示本地自建未完成项，不出现昨天的苹果事件（下界未变）。
