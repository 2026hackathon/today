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

            // Snooze 处理
            if let snooze = todo.snoozedUntil {
                if snooze > now { continue } // 压住中，跳过所有级别
                // snooze 到点 → due 级重新提醒（每次 snooze 一次）
                fire(todo, level: .due, key: "\(todo.id.uuidString)-snoozed-\(Int(snooze.timeIntervalSince1970))")
                continue
            }

            let interval = due.timeIntervalSince(now)
            let dueTs = Int(due.timeIntervalSince1970)
            let base = "\(todo.id.uuidString)-\(dueTs)"

            switch interval {
            case ..<(-60):
                // 已过期 > 1min：每 5 分钟重复一次（key 加时间桶）
                let bucket = Int(now.timeIntervalSince1970 / 300)
                fire(todo, level: .overdue, key: "\(base)-overdue-\(bucket)")
            case ..<0:
                fire(todo, level: .due, key: "\(base)-due")
            case ..<(15 * 60):
                fire(todo, level: .fifteenMin, key: "\(base)-fifteenMin")
            case ..<(60 * 60):
                fire(todo, level: .oneHour, key: "\(base)-oneHour")
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
