import Foundation

// ============================================================
// PushService —— 外部推送协议 + Noop / 飞书 webhook / Bark 实现。
// Owner: C
//
// 接入说明：
// - 默认装配 NoopPushService（只打日志）。
// - settings.feishuWebhook 非空 → 换 FeishuPushService（真实现，已可用）。
// - settings.barkToken 非空 → 换 BarkPushService（真实现，已可用）。
// - 所有失败静默 NSLog，绝不抛错崩 UI（integrations spec / CODING_GUIDELINES）。
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

// MARK: - 飞书自定义机器人 webhook（真实现）

@MainActor
final class FeishuPushService: PushService {

    /// 飞书群机器人 webhook 地址（settings.feishuWebhook）
    var webhook: String

    init(webhook: String) {
        self.webhook = webhook
    }

    func push(title: String, body: String) async {
        guard !webhook.isEmpty, let url = URL(string: webhook) else {
            NSLog("[Push][Feishu] webhook 未配置或非法，跳过")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "msg_type": "text",
            "content": ["text": "\(title)\n\(body)"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            NSLog("[Push][Feishu] payload 序列化失败")
            return
        }
        request.httpBody = data
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                NSLog("[Push][Feishu] HTTP \(http.statusCode)")
            }
        } catch {
            // 失败静默（integrations spec：推送是 best-effort）
            NSLog("[Push][Feishu] 发送失败: \(error)")
        }
    }
}

// MARK: - Bark（iOS 推送，真实现）

@MainActor
final class BarkPushService: PushService {

    /// Bark 设备 token（settings.barkToken）
    var token: String

    init(token: String) {
        self.token = token
    }

    func push(title: String, body: String) async {
        guard !token.isEmpty else {
            NSLog("[Push][Bark] token 未配置，跳过")
            return
        }
        // GET https://api.day.app/<token>/<title>/<body>，path 段需百分号转义（含 "/"）
        guard let url = URL(string: "https://api.day.app/\(token)/\(Self.escaped(title))/\(Self.escaped(body))") else {
            NSLog("[Push][Bark] URL 构造失败")
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                NSLog("[Push][Bark] HTTP \(http.statusCode)")
            }
        } catch {
            NSLog("[Push][Bark] 发送失败: \(error)")
        }
    }

    /// path 段转义：在 urlPathAllowed 基础上额外转义 "/"，避免标题/正文里的斜杠切碎路径
    private nonisolated static func escaped(_ text: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
