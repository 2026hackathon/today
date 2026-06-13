# calendar-historical-sync Specification

## Purpose
TBD - created by archiving change apple-calendar-sync. Update Purpose after archive.
## Requirements
### Requirement: 首次同步触发条件
系统 SHALL 在 EventKit 日历权限首次被授权（从 `.notDetermined` 变为 `.fullAccess`）后，自动触发首次历史数据同步。首次同步 SHALL 仅执行一次，通过 `UserDefaults` 的 `calendarInitialSyncCompleted` 标志追踪状态。

#### Scenario: 首次授权后自动同步
- **WHEN** 用户在系统权限弹窗点击「允许」且 `calendarInitialSyncCompleted` 为 `false`
- **THEN** 系统立即执行 30 天窗口历史数据拉取，拉取成功后将 `calendarInitialSyncCompleted` 设为 `true`

#### Scenario: 已有权限启动时跳过首次同步
- **WHEN** 应用启动时 EventKit 权限已为 `.fullAccess` 且 `calendarInitialSyncCompleted` 为 `true`
- **THEN** 系统跳过首次同步流程，直接进入日常同步循环

#### Scenario: 首次同步失败可重试
- **WHEN** 首次历史数据拉取过程中发生错误（如 EventKit 查询失败）
- **THEN** `calendarInitialSyncCompleted` 保持 `false`，下次权限就绪时重新触发首次同步

### Requirement: 30 天滑动窗口数据拉取
CalendarService.fetchMeetings(in:) SHALL 查询以今天为中心的 30 天滑动窗口内的所有日历事件和提醒事项，窗口范围为今天之前 29 天至今天之后 6 天（含今天共 36 天跨度）。

#### Scenario: 正常拉取 30 天窗口数据
- **WHEN** 系统触发日历同步（首次/日常均可）
- **THEN** `fetchMeetings(in:)` 查询 `[today - 29天, today + 6天]` 范围内的所有 EKEvent 和未完成提醒事项，映射为 Meeting 并按 start 升序返回

#### Scenario: 窗口内无事件
- **WHEN** 30 天窗口内日历中无任何事件和提醒事项
- **THEN** 返回空数组

#### Scenario: 跨多天事件
- **WHEN** 日历中存在跨越 3 天的会议事件（如 6月10日~6月12日的会议）
- **THEN** 该事件作为单个 Meeting 返回，start 和 end 保留原始日期时间

### Requirement: 全量替换式数据同步
AppStore.replaceMeetings() SHALL 以同步结果完全替换本地会议数据，保留增量合并逻辑。每次同步均用最新查询结果覆盖 `meetings.json`。

#### Scenario: 日常同步替换数据
- **WHEN** 15 分钟轮询触发同步，查询到 3 场会议
- **THEN** `meetings` 数组被替换为这 3 场会议，旧数据完全清除，`meetings.json` 更新

#### Scenario: 事件驱动同步
- **WHEN** EKEventStoreChanged 通知触发同步
- **THEN** 系统执行与日常同步相同的全量替换流程

### Requirement: 数据过期自动清理
系统 SHALL 在每次同步时自然淘汰超出 30 天滑动窗口的历史数据。无需独立清理任务 —— 全量替换本身即保证窗口外数据不保留。

#### Scenario: 30 天前的会议被自然淘汰
- **WHEN** 今天是 6月12日，上次同步包含 5月13日的会议，本次同步查询范围为 [5月14日, 6月18日]
- **THEN** 5月13日的会议不出现在本次同步结果中，被全量替换清除

### Requirement: 重置演示数据时清除首次同步标志
AppStore.resetDemoData() 或等效的 Debug 重置操作 SHALL 将 `calendarInitialSyncCompleted` 重置为 `false`，使下次权限就绪时重新触发首次同步。

#### Scenario: Debug 重置后重新触发首次同步
- **WHEN** 用户通过 Debug 菜单执行「重置演示数据」
- **THEN** `calendarInitialSyncCompleted` 被设为 `false`，下次日历权限就绪时重新执行首次历史数据拉取

