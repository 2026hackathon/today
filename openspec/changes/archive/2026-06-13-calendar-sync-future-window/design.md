## Context

`calendar-list-ux-window`（已归档）把日历页签展示窗扩到「昨天 ~ today+15」，但故意把同步深度列为 Non-Goal，未改 `CalendarSyncConfig.syncDaysFuture`。当时假设「本地任务可达 +15，苹果事件受 +7 同步限制是可接受的上界裁剪」。用户实测发现这不可接受：+8 ~ +15 天的苹果日程完全不可见。本变更补上这道缺口。

## Root Cause

- `CalendarService.swift:52` `syncDaysFuture = 7` → `defaultRange() = [today, today+8)`。
- 展示层 `CalendarPanel.dayGroups` 接受到 `today+15`，但数据源里根本没有 +8 ~ +15 的苹果条目。
- 主 spec 自相矛盾：`同步窗口`(未来7) vs `同步范围常量`(`calendarSyncDaysFuture=6`、范围 `[today-29, today+7]`)，且都与展示窗 +15 不一致。

## Decisions

- **未来窗 7 → 15**：单点改 `CalendarSyncConfig.syncDaysFuture`，`defaultRange()` 自动覆盖到 today+15，AppDelegate 三处同步（初始/周期/事件驱动）全部经 `defaultRange()`，无需逐处改。
- **下界保持 today 00:00、不引入历史**：展示窗中「昨天」段按既有约定只显示本地自建未完成项，不需要昨天的苹果数据；引入历史会放大同步量且与「不含历史」要求冲突。
- **顺手修正 spec 矛盾**：把 `同步范围常量`、`同步窗口`、`今日事件拉取` 的默认窗描述统一到「today ~ today+15、不含历史」，并让常量描述对齐真实代码（常量名 `CalendarSyncConfig.syncDaysFuture`，无 past 常量），消除遗留的 6/7/29 三套数字打架。

## Non-Goals

- 不改展示窗逻辑（`dayGroups` 已支持 +15）。
- 不引入历史回溯 / past 同步常量。
- 不动提醒完成态 30 天兜底窗（已完成提醒回溯窗，与未来窗无关）。

## Risks

- 同步条目随窗口增大略增（7→15 天），EventKit predicate 查询与 meetings.json 体积小幅上升——可接受，量级仍在数十~百条。
