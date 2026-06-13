import Foundation

// ============================================================
// PushService —— 外部推送协议 + Noop 实现。
// Owner: C
//
// 当前只装配 NoopPushService（系统通知中心已覆盖到期提醒，外部 webhook 推送暂不需要）。
// 失败一律静默 NSLog，绝不抛错崩 UI（integrations spec / CODING_GUIDELINES）。
// ============================================================

@MainActor
protocol PushService: AnyObject {
    /// 推送一条提醒。实现内部自行处理失败（静默），不抛错。
    func push(title: String, body: String) async
}

// MARK: - Noop（默认装配）

@MainActor
final class NoopPushService: PushService {

    init() {}

    func push(title: String, body: String) async {
        NSLog("[Push][Noop] \(title) — \(body)")
    }
}
