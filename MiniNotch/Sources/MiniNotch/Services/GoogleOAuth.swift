import AppKit
import CryptoKit
import Foundation
import Network

// ============================================================
// GoogleOAuth —— Gmail 的 OAuth2 登录（email-google-oauth）。
//
// Gmail 用 OAuth2 授权码 + PKCE（桌面应用推荐流程）：复用 Thunderbird 的公开
// Google client（被众多开源邮件客户端用于 Gmail IMAP），本地起一个回环 HTTP 服务
// 接 Google 的 code 回调，换 token。Gmail IMAP 默认开着，拿到 token 后走 XOAUTH2 拉信。
//
// refresh token 存 Keychain；Gmail 地址（XOAUTH2 user 需要）存 UserDefaults。
// ============================================================

enum GoogleOAuthError: LocalizedError {
    case http(String)
    case timeout
    case noCode
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .http(let m): m
        case .timeout: "登录超时"
        case .noCode: "未收到授权码"
        case .noRefreshToken: "未登录"
        }
    }
}

@MainActor
final class GoogleOAuth: ObservableObject {
    static let shared = GoogleOAuth()

    @Published private(set) var signedIn: Bool
    @Published private(set) var accountEmail: String
    @Published private(set) var waiting = false
    @Published private(set) var errorMessage: String?

    private init() {
        signedIn = Keychain.load(account: Self.refreshAccount) != nil
        accountEmail = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
    }

    // Thunderbird 的公开 Google OAuth client（installed/desktop 型，支持回环重定向；
    // 被 mbsync/mutt 等开源工具广泛复用于 Gmail）。Google「installed app」的 secret 非机密。
    private let clientID = "406964657835-aq8lmia8j95dhl1a2bvharmfk3t1hgqj.apps.googleusercontent.com"
    private let clientSecret = "kSmqreRr0qwBWJgbf5Y-PjSU"
    /// Gmail 全量（IMAP/SMTP）+ 取邮箱地址（XOAUTH2 user 需要）
    private let scope = "https://mail.google.com/ https://www.googleapis.com/auth/userinfo.email"

    private static let refreshAccount = "googleRefreshToken"
    private static let emailKey = "googleAccountEmail"

    private var accessToken: String?
    private var accessExpiry: Date?
    private var flowTask: Task<Void, Never>?

    var isSignedIn: Bool { signedIn }

    func signOut() {
        flowTask?.cancel()
        Keychain.delete(account: Self.refreshAccount)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        accessToken = nil; accessExpiry = nil
        signedIn = false; accountEmail = ""; waiting = false; errorMessage = nil
    }

    // MARK: - 登录（授权码 + PKCE + 本地回环）

    func beginSignIn() {
        flowTask?.cancel()
        errorMessage = nil
        flowTask = Task { @MainActor in
            let server: LoopbackServer
            do { server = try LoopbackServer() } catch {
                errorMessage = "本地回环启动失败：\(error.localizedDescription)"; return
            }
            defer { server.stop() }
            do {
                let port = try await server.start()
                let redirect = "http://127.0.0.1:\(port)"
                let verifier = Self.pkceVerifier()
                let challenge = Self.pkceChallenge(verifier)

                var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
                comps.queryItems = [
                    .init(name: "client_id", value: clientID),
                    .init(name: "redirect_uri", value: redirect),
                    .init(name: "response_type", value: "code"),
                    .init(name: "scope", value: scope),
                    .init(name: "code_challenge", value: challenge),
                    .init(name: "code_challenge_method", value: "S256"),
                    .init(name: "access_type", value: "offline"),
                    .init(name: "prompt", value: "consent"),
                ]
                waiting = true
                NSWorkspace.shared.open(comps.url!)

                let code = try await server.waitForCode(timeout: 300)
                let tokens = try await exchangeCode(code, verifier: verifier, redirect: redirect)
                let email = try await fetchEmail(accessToken: tokens.access)

                Keychain.save(tokens.refresh ?? "", account: Self.refreshAccount)
                UserDefaults.standard.set(email, forKey: Self.emailKey)
                cache(token: tokens.access, expiresIn: tokens.expiresIn)
                accountEmail = email
                signedIn = true
                waiting = false
                NSLog("[GoogleOAuth] signed in ✓ \(email)")
            } catch {
                waiting = false
                errorMessage = "Google 登录失败：\(error.localizedDescription)"
                NSLog("[GoogleOAuth] sign-in failed: \(error)")
            }
        }
    }

    // MARK: - access token（Gmail IMAP XOAUTH2 用）

    func validAccessToken() async throws -> String {
        if let token = accessToken, let exp = accessExpiry, exp.timeIntervalSinceNow > 60 {
            return token
        }
        guard let refresh = Keychain.load(account: Self.refreshAccount), !refresh.isEmpty else {
            throw GoogleOAuthError.noRefreshToken
        }
        let json = try await postForm("https://oauth2.googleapis.com/token", [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        guard let token = json["access_token"] as? String else {
            throw GoogleOAuthError.http(json["error_description"] as? String ?? "刷新 token 失败")
        }
        cache(token: token, expiresIn: json["expires_in"] as? Int ?? 3600)
        return token
    }

    // MARK: - 内部

    private struct Tokens { let access: String; let refresh: String?; let expiresIn: Int }

    private func exchangeCode(_ code: String, verifier: String, redirect: String) async throws -> Tokens {
        let json = try await postForm("https://oauth2.googleapis.com/token", [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect,
        ])
        guard let access = json["access_token"] as? String else {
            throw GoogleOAuthError.http(json["error_description"] as? String ?? "换取 token 失败")
        }
        // 诊断：Google 实际授予的 scope（Workspace 可能砍掉 mail.google.com）
        NSLog("[GoogleOAuth] granted scope: \(json["scope"] as? String ?? "<none>")")
        return Tokens(access: access, refresh: json["refresh_token"] as? String,
                      expiresIn: json["expires_in"] as? Int ?? 3600)
    }

    private func fetchEmail(accessToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return json?["email"] as? String ?? ""
    }

    private func cache(token: String, expiresIn: Int) {
        accessToken = token
        accessExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    private func postForm(_ urlString: String, _ params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params
            .map { "\($0.key)=\(Self.encode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if !(200..<300).contains(code) {
            NSLog("[GoogleOAuth] \(urlString) → HTTP \(code): \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
        }
        return json
    }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    // MARK: - PKCE

    private static func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func pkceChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - 本地回环 HTTP 服务（接 Google OAuth 的 code 回调）

/// 在 127.0.0.1 随机端口起一个一次性 HTTP 服务，收到带 ?code= 的请求后回一页提示并交回 code。
final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "oauth.loopback")
    private var codeCont: CheckedContinuation<String, Error>?

    init() throws {
        listener = try NWListener(using: .tcp)
    }

    /// 启动并返回绑定端口
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener.port?.rawValue {
                        cont.resume(returning: port)
                    } else {
                        cont.resume(throwing: GoogleOAuthError.http("无法获取回环端口"))
                    }
                case .failed(let e): cont.resume(throwing: e)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
        }
    }

    /// 等待浏览器回调带回 code（带超时）
    func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            codeCont = cont
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let c = self.codeCont else { return }
                self.codeCont = nil
                c.resume(throwing: GoogleOAuthError.timeout)
            }
        }
    }

    func stop() { listener.cancel() }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let code = Self.parseCode(request)
            let body = "<html><head><meta charset='utf-8'></head><body style='font-family:-apple-system,sans-serif;text-align:center;padding-top:80px;color:#333'><h2>✅ 登录成功</h2><p>可以关闭此页面，返回 MiniNotch。</p></body></html>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            if let code, let c = self.codeCont {
                self.codeCont = nil
                c.resume(returning: code)
            } else if code == nil, let c = self.codeCont {
                self.codeCont = nil
                c.resume(throwing: GoogleOAuthError.noCode)
            }
        }
    }

    /// 从 "GET /?code=XXX&scope=... HTTP/1.1" 抽 code
    static func parseCode(_ request: String) -> String? {
        guard let firstLine = request.split(separator: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, let query = parts[1].split(separator: "?").dropFirst().first else { return nil }
        for kv in query.split(separator: "&") {
            let pair = kv.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == "code" {
                return String(pair[1]).removingPercentEncoding
            }
        }
        return nil
    }
}
