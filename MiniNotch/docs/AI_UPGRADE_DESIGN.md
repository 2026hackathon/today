# AI 升级设计：下一件事推荐 / 自动任务收集 / 对话式晨晚报

> 三个功能的共同原则：**AI 负责草拟，用户只做一次确认**；所有岛上输出约束为一行可点击的话；
> AI 失败时一律静默回落到现有行为（Mock / 静态文案），绝不让岛卡死在等待态。
>
> 复用现有契约：`AIService` 协议（Services/AIService.swift）、`IslandState` 状态机
> （Island/IslandState.swift）、`AppStore` 单一数据源、`ReminderScheduler` 的 firedKeys 去重模式。

---

## 共享基础设施（三个功能都依赖，先做）

### S-1 带编号的任务上下文（防幻觉的关键）

LLM 引用任务一律用**编号**而不是标题/UUID——模型抄错一个字 UUID 就废了，编号映射回本地数组永远准确。

```swift
/// 喂给 LLM 的任务快照：编号 ↔ todo.id 的映射由调用方持有
struct IndexedContext {
    let lines: String          // "[1] 提交 PRD 草稿 | 高 | 今天18:00截止 | 个人" ...
    let idByIndex: [Int: UUID] // 解析 LLM 返回的 taskIndex 时反查
}
```

构造规则（在现有 `contextText(_:)` 基础上改）：
- 只编号**可操作**的任务（排除 Jira/GitHub 只读源——AI 不该建议用户"完成"一个只读 ticket）
- 每行格式：`[N] 标题 | 优先级 | 截止描述 | 来源 | 预计耗时(SP换算，可缺省)`
- 会议单独列，不编号（会议不可被"建议完成"）

### S-2 卡片冷却管理（防打扰的关键）

主动弹卡的功能（F1 的 nudge、F2 的会后跟进）共用一个冷却器，模式照抄 `TimerReminderScheduler.firedKeys`：

```swift
@MainActor
final class ProactiveGate {
    private var firedKeys: Set<String> = []
    private var lastFiredAt: Date?
    /// 全局规则：勿扰时段不弹；岛非 compact 不弹；距上一张主动卡 < cooldown 不弹
    func allow(key: String, cooldown: TimeInterval, settings: AppSettings, state: IslandState) -> Bool
}
```

### S-3 JSON 解码

照抄 `decodeDrafts` 的防御模式（剥 ```json 围栏 → JSONDecoder → 失败 throw `.invalidResponse`），
每个新返回类型一个 `Envelope` struct。

---

## F1 智能"下一件事"推荐

### 目标

把 Today 面板底部的静态一句话建议，升级为**全天跟随上下文变化的"现在最值得做的一件事"**，
并在合适的空隙主动轻推一次。

### 数据模型

```swift
/// AI 推荐结果（Models.swift 新增）
struct NextAction: Equatable, Sendable, Codable {
    enum Kind: String, Codable { case focus, prep, gap, wrapup, rest }
    var taskIndex: Int?     // 引用 IndexedContext 编号；rest/prep 可为 nil
    var headline: String    // ≤14 字，动词开头，岛上显示这一行
    var reason: String      // ≤20 字，hover/面板里显示
    var kind: Kind
}
```

`AppStore` 新增 `@Published private(set) var nextAction: (action: NextAction, todoID: UUID?)?`，
替代现有 `aiSuggestion` 字符串（保留 `aiSuggestion` 作为降级文案）。

### AIService 扩展

```swift
/// 推荐"现在最值得做的一件事"。ctx 额外携带：距下个会议分钟数、当前时段
func generateNextAction(_ ctx: ReportContext) async throws -> NextAction
```

### Prompt（system，jsonMode = true）

```
你是用户的专注助理。根据当前时间、会议安排和任务清单，推荐"现在最值得做的一件事"。
只输出 JSON 对象：
{"taskIndex": 任务编号或 null, "headline": "≤14字", "reason": "≤20字", "kind": "focus|prep|gap|wrapup|rest"}

当前时间：{now}。距下一个会议还有 {gapMinutes} 分钟（无会议则为 null）。

决策规则（按优先级）：
1. 有已超期或 1 小时内截止的任务 → 推它，kind=focus
2. 距下个会议 <15 分钟 → kind=prep，headline 为会前准备动作（如「过一遍产品评审议程」），taskIndex=null
3. 距下个会议 15-45 分钟 → 从清单挑一件能在间隙内完成的小事（低优先级/无截止的优先），kind=gap
4. 时间 >17:00 且有今天截止未完成 → 推最后冲刺项，kind=wrapup
5. 今日任务已清空 → kind=rest，headline 给一句轻松的话（如「今天的事清了，歇口气」）

硬性约束：
- headline ≤14 个字，以动词开头，必须可直接执行
- taskIndex 只能引用下方编号列出的任务，禁止编造任务；不指向具体任务时必须为 null
- 不要解释，不要输出 JSON 之外的任何内容
```

user 消息：`IndexedContext.lines` + 会议列表。

### 触发时机（事件驱动 + 低频兜底，全部经 debounce 5s 合并）

| 触发器 | 接入点 | 说明 |
|---|---|---|
| 启动后首次数据就绪 | AppDelegate 现有 suggestion 生成处（AppDelegate.swift:276） | 直接替换现有调用 |
| 完成任务 | `AppStore.onTodoCompleted` 回调 | 推荐对象大概率变了 |
| 新任务落地 | `AppStore.onTodoLanded` 回调 | 高优插队 |
| 会议边界 | 复用 15s 提醒扫描：`meeting.end` 过线 / `start-15min` 过线 | prep ↔ gap 切换点 |
| 兜底刷新 | 30 分钟 Timer | 上下文漂移 |

勿扰时段：照常**生成**（面板要显示），但**不弹 nudge 卡**。

### UI 状态机

不新增 compact 态。改动三处：

**a) Today 面板建议条（被动，永远可见）**
现有 `aiSuggestion` 文案条改为显示 `headline — reason`，点击时若 `todoID != nil` 高亮滚动到该任务行。

**b) hoverPreview（被动）**
悬停预览顶部加一行 `✨ headline`，已有的 hover 流程不变。

**c) 主动 nudge 卡（新增 IslandState case）**

```swift
case aiNudge(action: NextAction, todoID: UUID?)   // 卡片态，几何同 newTask(380pt)
```

转换图：

```
compact(normal/idle)
   │  触发器命中 且 ProactiveGate.allow(key: "nudge-\(小时桶)", cooldown: 45min)
   ▼
.aiNudge ──「开始 →」──▶ present(.expanded(tab:.today)) 并高亮 todoID
   │ ──「知道了」/ 点外部 / 8s 倒计时（cardHeld 解除倒计时，复用现有模式）
   ▼
dismiss() → compact
```

弹卡的额外门槛（比生成严格得多，宁可不弹）：
- 仅 `kind == .gap || kind == .focus` 弹卡；prep/rest/wrapup 只更新面板
- focus 卡与 ReminderScheduler 的到期提醒卡可能撞车 → nudge 让位（reminder 优先，nudge 丢弃不补发）

### 降级

生成失败/未配置 Key → `nextAction = nil`，面板显示现有静态 `aiSuggestion`，不弹卡。Mock 实现返回固定 `NextAction`（demo 可演示）。

---

## F2 自动任务收集

两条线：**(a) 外部 ticket 落地时 AI 摘要**，**(b) 会后跟进卡**。

### (a) Jira/GitHub 落地摘要

#### 问题

`mergeExternalTodos` 落地的 ticket 标题是服务器原文（如 `Fix: refactor auth module (#482)`），
且每轮同步会被服务器覆写（AppStore.swift:449 `todos[i].title = ticket.title`）——所以 AI 产物**不能写进 title**。

#### 数据模型

`Todo` 新增字段（记得同步向后兼容 `init(from:)`，Models.swift:139 的模式）：

```swift
/// AI 对外部 ticket 的一句话行动摘要（同步不覆写，本地生成本地持有）
var aiBrief: String?
```

#### AIService 扩展 + Prompt

```swift
func briefExternalTask(_ todo: Todo) async throws -> String
```

```
你是任务摘要助手。把一条 Jira ticket / GitHub PR 信息改写成给当事人看的一句话行动提示。
只输出 JSON：{"brief": "≤20字，动词开头，含关键对象"}
例：
- PR "Fix: refactor auth module (#482)" + 请求 review → {"brief": "Review auth 模块重构 PR"}
- Jira "支付回调偶发超时" 被张三指派 → {"brief": "排查支付回调超时（张三指派）"}
不确定动作时用「跟进」开头。不要输出 JSON 之外内容。
```

#### 触发时机

`mergeExternalTodos` 的 `landed` 分支：落地后异步逐条 `briefExternalTask`，回来后 `store.update(todo)` 写入 `aiBrief`。
卡片**不等** AI——`jiraLanded` 卡照常立即弹（显示原标题），`aiBrief` 回来后卡片若还在就刷新文案（`@Published` 自动驱动）。

#### UI

无新状态。`JiraLandedCard` / Today 行：有 `aiBrief` 时主行显示 brief，原标题降为副行小字。

### (b) 会后跟进卡

#### AIService 扩展 + Prompt

```swift
/// 会后一句话 → 草稿列表（可能多条："让陈昊发数据，我整理纪要"）
func parseFollowUp(_ text: String, meeting: Meeting) async throws -> [TodoDraft]
```

system prompt 在现有 `parseQuickInput` 基础上加会议上下文：

```
你是任务解析助手。用户刚开完会议「{meeting.title}」（{start}–{end}，参与者：{attendees}），
正在口述会后跟进事项，可能一句话包含多件事。
只输出 JSON 对象：{"todos": [{"title": "...", "priority": "high|medium|low",
"dueDate": "yyyy-MM-dd HH:mm" 或 null, "recurrence": null, "aiExplanation": "一句话依据"}]}
当前时间：{now}。
规则：
- 每件独立的事拆成一条；title 补全会议语境（「发我数据」→「跟进陈昊发送数据」）
- 未提截止时间的跟进事项默认明天上午 10:00（aiExplanation 注明「默认次日上午」）
- 「会上说的/刚才提到的」等指代，结合会议标题推断对象
- 优先级标准与快速录入一致：仅明确紧急语气 → high；其余 → medium
```

#### 触发时机

复用 `ReminderScheduler` 同款 15s Timer 扫描（或并入其 `scan`）：

```
对每个 meeting：
  meeting.end 在 (now-120s, now] 区间        // 刚结束 2 分钟内
  且 !meeting.isReminder                      // 提醒事项不算会
  且 meeting.end - meeting.start >= 15min     // 太短的不问
  且 ProactiveGate.allow(key: "followup-\(meeting.id)", cooldown: 0)  // 每会只问一次
  且 islandState.isCompact 且 非勿扰时段
→ present(.followUp(meeting: meeting))
```

#### UI 状态机（新增 IslandState case）

```swift
case followUp(meeting: Meeting)   // 卡片态，几何同 quickInput(480pt，含输入框)
```

```
compact ──会议结束扫描命中──▶ .followUp(meeting)
   │  卡片：「『产品评审』结束了，有要跟进的事吗？」 [输入框] [没有]
   │
   ├─ 输入提交 ──▶ isAIWorking=true（彩虹流光，复用现有）
   │                parseFollowUp(text, meeting)
   │                ├─ 1 条  ──▶ .newTask(draft)      ← 复用现有降落卡确认流
   │                ├─ ≥2 条 ──▶ .batch(drafts)       ← 复用现有批量卡确认流
   │                └─ 失败  ──▶ .quickInput + quickInputNotice("没听清，手动补一下？")
   │                              （文本回填输入框，复用现有失败回退模式）
   ├─ 「没有」按钮 / 点外部 / esc ──▶ dismiss()
   └─ 30s 无交互自动收回（聚焦输入即 cardHeld=true 解除倒计时，现有机制）
```

关键复用点：解析结果直接进 `newTask`/`batch` 现有确认流，**确认、动效、入库零新代码**。

#### 降级

未配置 Key：跟进卡照常弹（这是规则触发不是 AI 触发），提交走 `MockAIService` 固定解析。

---

## F3 对话式晨晚报

### 目标

晨报从"罗列"变"**给出一版排好序的当日计划 + 一句话即可调整**"；
晚报从"汇报"变"**未完成任务逐条给处置建议，一键应用**"。

### 数据模型（Models.swift 新增）

```swift
struct DayPlan: Codable, Equatable, Sendable {
    struct Block: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        enum Kind: String, Codable { case meeting, task, breather }
        var kind: Kind
        var start: Date
        var end: Date
        var taskIndex: Int?    // kind==task 时引用编号
        var title: String
        var note: String?      // "会前留了 10 分钟缓冲" 等
    }
    var headline: String       // 一句话总览，≤30 字
    var blocks: [Block]
    var tips: [String]         // ≤2 条
}

struct EveningReview: Codable, Equatable, Sendable {
    struct Disposition: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        enum Action: String, Codable { case tomorrow, split, downgrade, drop }
        var taskIndex: Int
        var action: Action
        var newDue: Date?          // tomorrow 时建议时间
        var subtasks: [String]?    // split 时 2-4 条
        var reason: String         // ≤20 字
        var accepted = true        // UI 勾选，默认全选
    }
    var headline: String           // 完成度一句话
    var celebrations: [String]     // 今日完成的高光，≤3 条
    var dispositions: [Disposition]
}
```

### IslandState 扩展

```swift
// 替代纯文本态；旧的 morningReport/eveningReport(text:) 保留作 AI 失败降级
case morningPlan(plan: DayPlan)
case eveningReview(review: EveningReview)
```

几何同现有 `morningReport`（460×540）。面板内部的 loading/refining 用 SwiftUI `@State`，不进 IslandState——
壳子状态机只管形态，进度是面板内部事。

### AIService 扩展

```swift
/// instruction == nil 生成初版；否则携带上一版 plan，做增量调整
func generateDayPlan(_ ctx: ReportContext, previous: DayPlan?, instruction: String?) async throws -> DayPlan
func generateEveningReview(_ ctx: ReportContext) async throws -> EveningReview
```

### 晨报 Prompt（jsonMode = true）

```
你是用户的日程规划助理。把今天的会议（固定不可动）和任务清单编排成一份当日计划。
只输出 JSON：
{"headline": "≤30字总览", "blocks": [{"kind": "meeting|task|breather",
"start": "HH:mm", "end": "HH:mm", "taskIndex": 编号或null, "title": "...", "note": "..."或null}],
"tips": ["≤2条建议"]}

当前时间：{now}。工作时段 {workStart}–{workEnd}。

编排规则：
- 会议原样进 blocks（kind=meeting），时间不可改动
- 已超期和今天截止的任务必须排进计划，且排在截止时间之前
- 高优先级排上午（精力好），琐事排午后；单个任务块 ≤90 分钟
- 每个会议前留 10 分钟缓冲（kind=breather，title「会前准备」）
- 12:00–13:30 只排午休（kind=breather），不排任务
- 排不下的任务宁可不排，在 tips 里说明「今天排不下 X，建议改期」
- taskIndex 只能引用编号清单里的任务，禁止编造
```

**调整轮**（用户输入「把写文档挪到下午」后）追加到 user 消息：

```
上一版计划：{previous 的 JSON}
用户要求：{instruction}
只做用户要求的调整并解决由此产生的冲突，其余 blocks 尽量保持不变。输出完整新 JSON。
```

### 晚报 Prompt（jsonMode = true）

```
你是用户的复盘助理。今天结束了，对每条未完成任务给出处置建议。
只输出 JSON：
{"headline": "≤30字完成度总结", "celebrations": ["今日完成里值得肯定的，≤3条"],
"dispositions": [{"taskIndex": 编号, "action": "tomorrow|split|downgrade|drop",
"newDue": "yyyy-MM-dd HH:mm"或null, "subtasks": ["..."]或null, "reason": "≤20字"}]}

当前时间：{now}。明天的会议：{tomorrowMeetings}。

处置标准：
- 今天截止没做完、仍重要 → tomorrow，newDue 给明天上午（避开明天的会议）
- 创建超过 3 天没动、或标题宽泛（如「优化性能」）→ split，拆成 2-4 步、每步 ≤45 分钟可独立完成
- snoozeCount ≥ 2（反复推迟说明意愿低）→ downgrade 或 drop，reason 里说出判断
- drop 要慎用，仅明显过时/重复的任务
- 每条未完成任务都必须出现且只出现一次；taskIndex 禁止编造
```

（上下文行里带上 `createdAt 距今天数` 和 `snoozeCount`，否则模型无从判断"躺了 3 天"。）

### 应用计划/处置（纯本地代码，不经 AI）

| 动作 | 落库逻辑 | 备注 |
|---|---|---|
| 晨报「应用计划」 | 仅给 **dueDate == nil** 的任务写入 block.start 作为 dueDate | 已有截止的是承诺，AI 不许动 |
| tomorrow | `dueDate = newDue` | |
| split | 原任务 delete，subtasks 逐条 add（继承 source/priority，note 记「拆自 X」） | 走 `add(_:)` 有降落动效 |
| downgrade | `priority = .low` | |
| drop | `delete(_:)` | UI 上默认**不勾选**，必须用户手动勾——删除不能默认 |
| 外部源（Jira/GitHub） | 一律不进 dispositions（构造上下文时就排除） | 只读镜像 |

### 触发时机

| 场景 | 接入点 | 改动 |
|---|---|---|
| 晨报 | 现有 `maybeShowMorningReport()`（AppDelegate.swift:559） | 改调 `generateDayPlan`；先 `present(.morningPlan(空骨架))` + 面板内 loading，结果回来填充——不让用户对着 compact 干等 |
| 晨报调整 | 面板底部输入框提交 | 面板内 loading，`generateDayPlan(ctx, previous:, instruction:)`，回来替换 plan |
| 晚报 | 现有每小时检查（AppDelegate.swift:547） | 改调 `generateEveningReview` |
| 晚报提前 | `onCompletedAll` 回调且时间 ≥16:00 | 庆祝动画结束后弹（皇冠日提前复盘，可选，P2） |

### 面板内交互（@State，非 IslandState）

```
晨报面板：loading → ready(plan) ⇄ refining(输入调整中) → applied(按钮变「已应用」)
晚报面板：loading → ready(review，逐条勾选) → applying → done(显示「明天见 👋」)
```

### 降级

`generateDayPlan` / `generateEveningReview` 失败 → 回落 `present(.morningReport(text:))` 走现有静态文案路径。
Mock 实现返回手工构造的 DayPlan/EveningReview（demo 必须能离线演示完整交互）。

---

## 实施顺序建议（按演示价值/成本比）

1. **F2(a) ticket 摘要** —— 半天。一个字段 + 一个 prompt，Jira/GitHub 落地卡立刻变聪明
2. **F1 推荐** —— 一天。S-1/S-2 基建 + prompt + 面板/hover 改造；nudge 卡可后置
3. **F2(b) 会后跟进卡** —— 一天。确认流全复用，主要是触发扫描 + 一张新卡
4. **F3 晨报计划** —— 一天半。新面板 UI 是大头；调整轮（对话）做不完可以砍，先保「生成+应用」
5. **F3 晚报处置** —— 一天。与晨报共享面板组件

每步独立可演示、可单独合入 main，符合 hackathon 节奏。

## 风险与红线

- **打扰预算**：主动卡（nudge + followUp + reminder）理论上可能连环弹。ProactiveGate 全局兜底：任意两张**主动**卡间隔 ≥10 分钟，reminder（用户自己定的截止）永远优先且不受限
- **字数失控**：所有岛上文案 prompt 里写死字数上限之外，**代码层再 truncate**（`.lineLimit(1)` 已有，但截断要在数据层做，别让 UI 吞字）
- **Equatable**：新 IslandState case 的关联值都已是 Equatable struct，状态机判等不受影响
- **改 Models.swift 字段** 按契约需开 openspec change 并通知全员（`aiBrief` 一处）
