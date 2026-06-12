## Why

当前日历模块已实现基础的三层同步架构（EventKit 事件驱动 + 15 分钟轮询 + 面板展开刷新），但仅获取**当天**的日历事件。用户首次授权或首次启动时，无法看到过去一个月的历史日程，导致上下文缺失。需要增加首次同步时的历史数据拉取能力，让日历面板能展示近一个月的完整日程视图。

## What Changes

- 新增**首次同步历史数据**能力：首次授权日历权限后，自动拉取最近 30 天的历史日程数据（包含过去和未来的事件）
- 保留现有**实时同步**机制：基于 `EKEventStoreChanged` 通知的事件驱动刷新
- 保留现有**定时同步**机制：15 分钟轮询作为 fallback
- 扩展 `CalendarService` 的数据获取范围：从"仅今天"扩展为可配置的时间范围
- 扩展 `AppStore` 的会议数据存储和管理：支持多日日程的存储、查询与过期清理
- 扩展 `CalendarPanel` 的 UI 展示：支持按日期分组展示多日日程

## Capabilities

### New Capabilities

- `calendar-historical-sync`: 首次日历同步时拉取最近 30 天历史数据的能力，包含首次同步触发逻辑、历史数据批量拉取、数据过期清理策略

### Modified Capabilities

- `apple-calendar-integration`: 现有 spec 的数据获取范围从"仅今天"扩展为可配置时间范围；CalendarPanel 从单日视图扩展为多日分组视图；AppStore 的 replaceMeetings 需适配多日数据管理

## Impact

- **Services**: `CalendarService.swift` — `fetchTodayMeetings()` 需扩展为支持日期范围参数的 `fetchMeetings(in:)` 方法；新增 `hasCompletedInitialSync` 状态追踪
- **Core**: `AppStore.swift` — 会议数据模型需支持多日存储和按日期查询；`replaceMeetings` 方法需适配增量更新或按日期范围替换
- **Core**: `Models.swift` — 可能需要为 Meeting 添加 `fetchDate` 或缓存时间戳字段以支持过期清理
- **UI**: `CalendarPanel.swift` — 从单日时间线视图扩展为按日期分组的多日视图，需考虑滚动和性能
- **AppDelegate**: 首次授权后的同步流程需增加历史数据拉取步骤，需追踪首次同步状态
- **Persistence**: `meetings.json` 的数据结构可能需要变更以支持多日数据（**BREAKING** — 旧格式不兼容时需迁移）
- **依赖**: 无新增外部依赖，仍使用 EventKit
