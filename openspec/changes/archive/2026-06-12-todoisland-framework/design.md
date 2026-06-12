# Design: TodoIsland 框架

> 本文是全项目的架构契约。各模块 owner（人或 agent）实现功能前必读。
> 参考物：`docs/TodoIsland-PRD-分工版.md`（需求）、`prototype.html`（视觉与状态蓝本）。

## 1. 总体架构

```
┌─────────────────────────────────────────────────────────┐
│  AppDelegate (菜单栏 + NotchPanel 窗口 + 服务装配)        │
└──────────────────────────┬──────────────────────────────┘
                           │ 注入
┌──────────────────────────▼──────────────────────────────┐
│  AppStore (ObservableObject, 单一数据源)                  │
│  - todos / meetings / settings                           │
│  - islandState: IslandState (驱动一切 UI)                 │
│  - 派生: 分组列表、紧急程度、下一个到期                     │
└───────┬───────────────────────────────┬─────────────────┘
        │ @EnvironmentObject            │ 调用 protocol
┌───────▼────────────┐        ┌─────────▼─────────────────┐
│  IslandRootView    │        │  Services (全部 protocol)  │
│  状态机 → 几何+内容  │        │  AIService / Capture /     │
│  UI/Compact|Cards| │        │  Jira / Calendar /        │
│  Panels|Effects    │        │  Reminder / Push          │
└────────────────────┘        │  默认 Mock 实现            │
                              └───────────────────────────┘
```

原则：
- **单一数据源**：所有 UI 读 `AppStore`，所有变更走 `AppStore` 方法。禁止 view 私藏业务状态。
- **协议优先**：外部能力（AI/Jira/日历/截图/推送）一律 protocol + Mock。换真实现 = 改 `AppDelegate` 里一行装配代码。
- **状态机驱动 UI**：island 长什么样只由 `IslandState` 决定，与 prototype.html 的 `STATES` 一一对应。

## 2. 目录与文件边界（并行开发的红线）

```
MiniNotch/Sources/MiniNotch/
├── main.swift / AppDelegate.swift          # 装配点（改动需吼一声）
├── NotchPanel.swift / NotchGeometry.swift  # 窗口基建（已稳定，别动）
├── Core/
│   ├── Models.swift          # Todo, Meeting, 枚举（契约，改动需同步全员）
│   ├── AppStore.swift        # 数据中枢 + 状态机入口（契约）
│   ├── Persistence.swift     # JSON 读写 ~/Library/Application Support/MiniNotch/
│   └── DesignTokens.swift    # 颜色/字号/圆角/间距（契约）
├── Island/
│   ├── IslandState.swift     # 状态枚举 + 每态几何 (契约)
│   └── IslandRootView.swift  # 状态→视图路由 + 形状变形动画
├── UI/
│   ├── Compact/CompactContent.swift   # 收缩态左右内容
│   ├── Cards/NewTaskCard.swift        # 任务降落卡
│   ├── Cards/ReminderCard.swift       # 到期提醒卡（含 Snooze）
│   ├── Cards/BatchCard.swift          # 批量识别卡
│   ├── Cards/QuickInputCard.swift     # ⌘N 手动新建
│   ├── Cards/HoverPreview.swift       # 悬停预览
│   ├── Panels/TodayPanel.swift        # 展开态三分组列表
│   ├── Panels/MorningReportPanel.swift
│   ├── Panels/EveningReportPanel.swift
│   └── Panels/SettingsPanel.swift
├── Services/
│   ├── AIService.swift        # protocol + MockAIService
│   ├── CaptureService.swift   # protocol + ScreencaptureCLIService（F2/F3 热键在此）
│   ├── JiraService.swift      # protocol + MockJiraService
│   ├── CalendarService.swift  # protocol + MockCalendarService
│   ├── ReminderScheduler.swift# protocol + TimerReminderScheduler（真实现，简单）
│   └── PushService.swift      # protocol + NoopPushService
└── Effects/
    ├── GlowEffects.swift      # SwiftGlow 封装: aiParsingGlow / urgentPulse
    ├── TouchdownEffect.swift  # 任务降落涟漪（按来源着色）
    ├── ConfettiView.swift     # 完成撒花
    └── CelebrationOverlay.swift # 全部完成庆祝（独立全屏窗口）
```

每个模块 owner 只改自己目录下的文件 + 在 AppDelegate 的装配处换实现。`Core/` 与 `Island/IslandState.swift` 是共享契约，改动必须先开 openspec change 并通知全员。

## 3. 核心契约

### 3.1 模型（Core/Models.swift）

```swift
enum Priority: String, Codable { case high, medium, low }
enum TodoSource: String, Codable { case screenshot, jira, manual, calendar, wechat }
enum MeetingPlatform: String, Codable { case zoom, tencent, googleMeet, teams, feishu, dingtalk, other }

struct Todo: Identifiable, Codable {
    var id: UUID
    var title: String
    var note: String?
    var source: TodoSource
    var priority: Priority
    var dueDate: Date?
    var createdAt: Date
    var completedAt: Date?      // nil = 未完成
    var snoozedUntil: Date?
    var snoozeCount: Int
    var screenshotPath: String? // 原始截图
    var jiraKey: String?        // "MD-1024"
    var jiraURL: URL?
    var jiraStatus: String?     // "In Progress"
    var aiExplanation: String?  // 紧急度判断依据
    var tags: [String]
}

struct Meeting: Identifiable, Codable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var link: URL?
    var platform: MeetingPlatform?
    var attendees: [String]
    var calendarName: String?
}
```

### 3.2 状态机（Island/IslandState.swift）

与 prototype.html `STATES` 对应。compact 态之间自动派生（由数据决定），card/expanded 态由事件触发：

```swift
enum IslandState: Equatable {
    // compact（自动派生: AppStore.compactState）
    case idle, normal, near, urgent, aiWorking, justCompleted
    // 悬浮交互
    case hoverPreview
    // 卡片（事件触发）
    case newTask(draft: TodoDraft)
    case reminder(todo: Todo)
    case batch(drafts: [TodoDraft])
    case quickInput
    // 展开
    case expanded(tab: PanelTab)   // .today / .inbox / .favorites / .settings
    case morningReport, eveningReport
    // 庆祝
    case celebrate
}
```

每个 state 映射一个几何尺寸（IslandGeometry），数值抄 prototype：compact 200/220×32、wide 340×32、card 380×~200、cardTall 380×~300、input 480×~190、expanded 460×540、hover 280×~170。变形动画统一 `.spring(response: 0.45, dampingFraction: 0.72)`（对应 prototype 的 cubic-bezier 弹簧）。

### 3.3 服务协议（签名以代码为准，这里给意图）

```swift
protocol AIService {        // owner: B
    func parseScreenshot(_ image: Data) async throws -> [TodoDraft]  // 1 个=单卡, ≥3 个=批量
    func parseQuickInput(_ text: String) async throws -> TodoDraft
    func generateMorningReport(_ ctx: ReportContext) async throws -> String
    func generateEveningReport(_ ctx: ReportContext) async throws -> String
}
protocol CaptureService {   // owner: C — F2/F3 全局热键 + 区域截图
    var onTodoCapture: ((Data) -> Void)? { get set }
    var onFavoriteCapture: ((Data) -> Void)? { get set }
    func start()
}
protocol JiraService {      // owner: C — 60s 轮询 assigned tickets
    func fetchAssignedTickets() async throws -> [Todo]
}
protocol CalendarService {  // owner: C — EventKit, 今日+7 天
    func fetchTodayMeetings() async throws -> [Meeting]
}
protocol ReminderScheduler { // owner: C — 4 级提醒
    func reschedule(for todos: [Todo])
    var onFire: ((Todo, ReminderLevel) -> Void)? { get set }
}
protocol PushService {      // owner: C — 飞书/Bark/ClawBot
    func push(title: String, body: String) async
}
```

Mock 行为约定：`MockAIService` 延迟 1.2s 返回固定 drafts（保证演示流畅）；`MockJiraService` 返回 3 条 PRD 里的示例 ticket；`MockCalendarService` 返回今天 2 场会议。

### 3.4 设计 tokens（Core/DesignTokens.swift）

抄 prototype.html `:root`：纯黑岛体 `#000`；surface 白 6%/10%；文字 1/2/3 级；accent `#6AA8F5`；alert `#FF6B61`；success `#4CD27D`；来源色 截图紫 `#AF52DE` / Jira 蓝 `#007AFF` / 手动绿 `#34C759` / 日历橙 `#FF9500` / 微信绿 `#07C160`；圆角 6/10/14、展开态 24。

## 4. 关键决策与取舍

| 决策 | 选择 | 理由 |
|------|------|------|
| 持久化 | JSON 文件（非 SwiftData/CoreData） | hackathon 量级 <1k 条，零迁移成本，git 可 diff |
| 截图 | `screencapture -i -c` CLI | 系统自带交互选区，免写选区 UI；权限提示系统代劳 |
| 全局热键 | Carbon `RegisterEventHotKey` | F2/F3 无需辅助功能权限（NSEvent global monitor 需要） |
| AI 接入 | protocol + Mock 先行 | key/模型未定，B 可独立换真实现不阻塞 UI |
| 流光呼吸 | SwiftGlow `appleIntelligence`/`rainbow` 预设 | 现成 Metal 渲染，Demo 效果即开即用 |
| 庆祝动画 | 独立透明全屏 NSWindow | 不能撑大 notch 面板（会挡屏幕），叠加层独立 |
| 展开触发 | hover 展开保留 + 点击锁定 | 队友刚调好 hover 热区；锁定避免鼠标移出就收起 |

## 5. 错误处理与降级

- AI 失败 → island 红色短闪 + 卡片提示「未识别到任务，手动录入？」（进 quickInput）
- Jira/日历网络失败 → 静默用上次缓存（持久化层已存）
- 所有服务调用包 `Task` + `do/catch`，禁止让异常崩 UI

## 6. 测试与验证

- 冒烟标准：`swift build` 零警告通过；`swift run` 后 15 个状态可经菜单栏 Debug 菜单逐个触发（框架内置 Debug 菜单，演示/联调共用）
- 每个 owner 接真实现时保留 Mock，可在设置里切换（Demo 兜底，PRD 风险 1/2 的缓解措施）
