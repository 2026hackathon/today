## Context

当前日历模块基于 EventKit 实现了三层同步架构：
- **Layer 1（事件驱动）**: `EKEventStoreChanged` 通知 → 1s 防抖 → 即时刷新
- **Layer 2（定时轮询）**: 15 分钟周期兜底
- **Layer 3（面板展开刷新）**: `$islandState` sink → `.expanded` 时立即拉取

数据流：`EventKitCalendarService.fetchTodayMeetings()` → 查询今日 00:00~24:00 → `AppStore.replaceMeetings()` → JSON 持久化 → `CalendarPanel` 展示单日时间线。

**局限**：数据获取和 UI 展示均限于当天，用户首次使用时无法看到过去一个月的历史日程。

## Goals / Non-Goals

**Goals:**
- 首次授权日历权限后，自动拉取最近 30 天的历史日程数据
- 后续同步持续维护这 30 天窗口的数据（滑动窗口，非一次性）
- CalendarPanel 支持按日期分组展示多日日程
- 保留现有三层同步机制不变
- 过期数据（超出 30 天窗口）自动清理

**Non-Goals:**
- 不实现日历事件的双向写入（不创建/修改 EventKit 事件）
- 不实现日历选择/过滤（用户不能选择特定日历源）
- 不实现超过 30 天范围的自定义配置（固定 30 天窗口足够）
- 不改变 Jira 同步逻辑
- 不增加新的外部依赖

## Decisions

### D1: 统一数据获取范围为 30 天滑动窗口

**决策**: 将 `CalendarService` 协议的 `fetchTodayMeetings()` 替换为 `fetchMeetings(in: DateRange)`，所有同步路径（Layer 1/2/3 + 首次同步）均查询相同的 30 天窗口（过去 29 天 + 今天 + 未来若干天，总计 30 天跨度）。

**理由**:
- EventKit 本地查询极快（毫秒级），全量刷新 30 天窗口的开销与查询单日几乎无差异
- 统一查询范围消除了"首次同步"和"日常同步"的逻辑分支，降低复杂度
- 每次全量替换保证数据一致性，无需增量合并

**替代方案**: 仅首次同步拉历史、后续只拉当天 → 需要两套查询逻辑 + 数据合并策略，复杂度高但收益小。

### D2: 保持 AppStore 扁平数组存储 + 计算属性分组

**决策**: `AppStore.meetings` 仍为 `[Meeting]` 扁平数组，通过计算属性 `meetingsByDate` 按日期分组供 CalendarPanel 消费。不在模型层增加日期键或嵌套结构。

**理由**:
- Meeting 模型本身已有 `start`/`end` 字段，天然支持按日期过滤和分组
- 扁平数组的 `replaceMeetings()` 全量替换逻辑无需修改
- 计算属性分组在 UI 层按需执行，避免数据层冗余
- 持久化格式（`meetings.json`）无需变更，向后兼容

**替代方案**: 改为 `[Date: [Meeting]]` 字典存储 → 破坏持久化兼容性，且 EventKit 返回的是扁平数组，额外转换无意义。

### D3: 首次同步状态用 UserDefaults 追踪

**决策**: 使用 `UserDefaults` 的 `calendarInitialSyncCompleted` 布尔标志追踪首次同步是否完成。首次权限授予后拉取 30 天数据成功即设为 `true`。

**理由**:
- 与现有的 `morningShown-{date}` 等 UserDefaults 用法一致
- 轻量、无新持久化文件
- Debug `resetDemoData()` 时可一并清除

**替代方案**: 检查 `meetings.json` 是否为空 → 不可靠，用户可能手动清空数据。

### D4: CalendarService 协议演进 — 替换方法签名

**决策**:
```
// 旧
func fetchTodayMeetings() async throws -> [Meeting]

// 新
func fetchMeetings(in range: ClosedRange<Date>) async throws -> [Meeting]
```
同时提供默认扩展 `fetchTodayMeetings()` 调用 `fetchMeetings(in: .today)`，保持 Mock 兼容。

**影响范围**:
- `EventKitCalendarService`: 重写 `fetchTodayMeetings()` → `fetchMeetings(in:)`，日期范围参数化
- `MockCalendarService`: 同上，生成 30 天范围的 mock 数据
- `AppDelegate`: 所有调用点改用 `fetchMeetings(in: syncDateRange)`

### D5: CalendarPanel 多日分组视图

**决策**: CalendarPanel 从单日时间线改为按日期分组的滚动视图：
- 每个日期段落含日期标题（"今天 6月12日" / "昨天 6月11日" / "6月10日 周三"）
- 今日段落高亮，过去段落降低不透明度
- 空日期不显示（仅显示有事件的日期）
- 默认滚动到今日段落可见位置
- 日期标题使用 `DS.Fonts.button`，会议列表复用现有 `TimelineRow`

**理由**:
- 复用现有 `TimelineRow` / `MeetingRow`，UI 改动最小化
- 分组展示直观，符合用户查看日历的心智模型
- 空日期不渲染避免大量留白

### D6: 同步范围定义 — 过去 29 天 + 未来 6 天

**决策**: 默认同步窗口为 `Calendar.current.date(byAdding: .day, value: -29, to: startOfToday)` 至 `Calendar.current.date(byAdding: .day, value: 6, to: startOfToday)`，总计 36 天跨度。

**理由**:
- 过去 30 天满足用户需求
- 额外加 6 天未来事件，让用户能看到近一周的日程安排，提升实用性
- EventKit `predicateForEvents` 的边界查询效率高

## Risks / Trade-offs

### R1: 首次同步数据量可能较大
→ **缓解**: EventKit 本地数据库查询不涉及网络 I/O，30 天窗口的数据量（通常 < 200 事件）在毫秒级完成。如果用户日历含数千事件（极端场景），EventKit 的 `predicateForEvents` 已在数据库层过滤，不会全表扫描。

### R2: CalendarPanel 多日视图的滚动性能
→ **缓解**: 30 天窗口内的会议数量有限（通常 < 100 条），SwiftUI `ScrollView` + `ForEach` 渲染无压力。如未来需支持更大范围，可改用 `LazyVStack`。

### R3: `meetings.json` 数据量增长
→ **缓解**: 每次同步全量替换（非追加），数据量恒定在 30 天窗口范围内。JSON 文件大小预计 < 50KB，持久化/读取开销可忽略。

### R4: MockCalendarService 需适配多日数据
→ **缓解**: Mock 实现简单扩展 `fetchMeetings(in:)` 生成窗口范围内的固定演示数据（如每天 1-2 场），不影响 Demo 体验。

### R5: 协议变更影响编译
→ **缓解**: 协议方法替换是 breaking change，但项目仅有两处实现（EventKit + Mock），均在同一代码库内，一次性修改可控。`swift build` 验证编译通过即可。
