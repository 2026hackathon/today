import Foundation

// ============================================================
// ReminderScheduler —— 四级到期提醒调度（真实现，非 Mock）。
// Owner: C
//
// 设计（reminders spec）：
// - 每 15s 一个 repeating Timer 扫描（spec 要求误差 < 30s）。
// - 四级：提前 1h（弱）/ 提前 15min（中）/ 到期（强）/ 已过期（极强）。
// - 去重 key 含 dueDate 时间戳：用户改截止时间后各级重新武装。
// - 过期级每 5 分钟重复一次（key 带 5min 时间桶）。
// - snoozedUntil 未到 → 跳过；到点 → 以 due 级重新提醒（key 带 snooze 时间戳，
//   每次 snooze 后都能再触发；UI 层用 snoozeCount>0 区分黄色脉冲）。
// - quietCheck(now)==true（勿扰时段）→ 不回调也不记 key，勿扰结束后按当时级别正常触发。
//
// 接入：AppStore todos/settings 变化后调 reschedule(for:quietCheck:)，
// onFire 由 AppDelegate 装配为 store.present(.reminder(todo:)) + 推送。
// ============================================================

enum ReminderEvent: Sendable {
    case level(ReminderLevel, Todo)
}

@MainActor
protocol ReminderScheduler: AnyObject {
    var onFire: ((Todo, ReminderLevel) -> Void)? { get set }
    /// 数据变化后重新调度。quietCheck：勿扰时段判断（settings.isQuietHour）。
    func reschedule(for todos: [Todo], quietCheck: @escaping (Date) -> Bool)
}

@MainActor
final class TimerReminderScheduler: ReminderScheduler {

    var onFire: ((Todo, ReminderLevel) -> Void)?

    private var todos: [Todo] = []
    private var quietCheck: ((Date) -> Bool)?
    private var timer: Timer?
    /// 已触发去重："\(id)-\(dueTs)-\(level)"；overdue 级带 5min 时间桶
    private var firedKeys: Set<String> = []

    init() {}

    func reschedule(for todos: [Todo], quietCheck: @escaping (Date) -> Bool) {
        self.todos = todos
        self.quietCheck = quietCheck

        // 清掉已删除 todo 的 key，防止集合无限增长
        let liveIDs = Set(todos.map { $0.id.uuidString })
        firedKeys = firedKeys.filter { key in
            liveIDs.contains(where: { key.hasPrefix($0) })
        }

        startTimerIfNeeded()
        scan(now: Date()) // 数据变化后立即评估一次（如新增已过期任务）
    }

    /// 停止调度（应用退出/测试用，协议外的便捷方法）
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        // Timer block 在主 run loop 执行 → assumeIsolated 安全跳回 MainActor
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scan(now: Date())
            }
        }
        timer?.tolerance = 3
    }

    // MARK: 扫描

    private func scan(now: Date) {
        // 勿扰时段：不弹卡片也不记 key（reminders spec：compact 颜色由 AppStore 派生，与此无关）
        if quietCheck?(now) == true { return }

        for todo in todos where !todo.isCompleted {
            guard let due = todo.dueDate else { continue }

            // Snooze 处理（review-fixes #9）：压住期间静默；到点后以 snooze
            // 时间为新的有效截止走标准分级管线（due 一次 + 过期每 5 分钟重复），
            // 不再一次性提醒后永久静音。key 含 effectiveDue 时间戳，
            // 每次 snooze 自动获得独立的提醒额度。
            let effectiveDue: Date
            if let snooze = todo.snoozedUntil {
                if snooze > now { continue } // 压住中，跳过所有级别
                effectiveDue = snooze
            } else {
                effectiveDue = due
            }

            let interval = effectiveDue.timeIntervalSince(now)
            let dueTs = Int(effectiveDue.timeIntervalSince1970)
            let base = "\(todo.id.uuidString)-\(dueTs)"

            // 提前量由 AI 按任务性质给出（会议提前 1-2h，吃饭喝水提前 5-10min），
            // nil 则按优先级兜底。两道预警：heads-up（lead）→ 临近（finalWindow）
            let leadSec = TimeInterval(todo.effectiveLeadMinutes * 60)
            let finalSec = TimeInterval(todo.finalWindowMinutes * 60)

            switch interval {
            case ..<(-60):
                // 已过期 > 1min：每 5 分钟重复一次（key 加时间桶）
                let bucket = Int(now.timeIntervalSince1970 / 300)
                fire(todo, level: .overdue, key: "\(base)-overdue-\(bucket)")
            case ..<0:
                fire(todo, level: .due, key: "\(base)-due")
            case ..<finalSec:
                fire(todo, level: .fifteenMin, key: "\(base)-final")
            case ..<leadSec:
                fire(todo, level: .oneHour, key: "\(base)-headsup")
            default:
                continue
            }
        }
    }

    private func fire(_ todo: Todo, level: ReminderLevel, key: String) {
        guard !firedKeys.contains(key) else { return }
        firedKeys.insert(key)
        onFire?(todo, level)
    }
}
