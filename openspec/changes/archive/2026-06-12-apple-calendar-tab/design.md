## Context

EventKitCalendarService 骨架已存在（含 `extractMeetingLink` 真实现），TodayPanel 已有会议 section 复用 MeetingRow。PanelTab 当前 4 case（today/inbox/favorites/settings），TabBar 有 `visibleTabs` 控制逻辑。

## Goals / Non-Goals

**Goals:**
- EventKitCalendarService 真实拉取今日会议
- 新增「日历」独立页签，时间线视觉
- 权限动态装配（真/Mock 自动降级）

**Non-Goals:**
- 不做多日视图（只看今天）
- 不做日历事件创建/编辑（只读集成）
- 不改 Today 页签中现有的「今日会议」section

## Decisions

### Decision 1: EventKit 权限检测与降级策略

AppDelegate 始终优先尝试 EventKitCalendarService。首次拉取若抛 `.accessDenied` 或 `.notImplemented`，降级到 MockCalendarService 并缓存降级标记。设置面板变更权限相关配置后下个轮询周期重新尝试。

权限检测使用 `EKEventStore.authorizationStatus(for: .event)`：
- `.fullAccess` → 直接 EventKitCalendarService
- `.denied` → 直接 MockCalendarService
- `.notDetermined` → 先 EventKitCalendarService（内部会 request），失败后降级

### Decision 2: CalendarPanel 复用 MeetingRow

将 TodayPanel.swift 中的 `MeetingRow` 从 `private struct` 改为 `struct`（internal 可见），CalendarPanel 直接复用。不重复造轮子。

### Decision 3: CalendarPanel 布局——时间线形式

顶部日期标题 + 会议计数，下方纵向时间线：
- 左侧时间标记（HH:mm）+ 圆点
- 右侧复用 MeetingRow 展示会议详情
- 空态：日历图标 + 「今日暂无会议」

### Decision 4: PanelTab 枚举 .calendar 插入位置

`.calendar` 插入在 `.today` 和 `.inbox` 之间：
```
[ Today ] [ 日历 ] [ Inbox ] [ 收藏 ]
```

TabBar `visibleTabs` 更新为 `[.today, .calendar, .inbox, .favorites]`。
