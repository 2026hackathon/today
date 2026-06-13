import AppKit
import Foundation

// ============================================================
// MicrosoftOAuth —— O365 邮件的 OAuth2 设备码登录（email-o365-oauth）。
//
// 背景：O365 关闭了 IMAP 基础认证（实测 "NO AUTHENTICATE failed."），
// 只认 OAuth2 token。这里用「设备码流程」：无需注册 Azure 应用的回调地址、
// 无需本地回环服务器——复用公开 client ID（Thunderbird 的，被众多开源邮件
// 客户端用于 O365 IMAP），用户像绑 QQ 邮箱一样浏览器登录一次即可。
//
// 关键：轮询常驻在本单例，不绑定设置面板视图——用户切到浏览器输码时面板会
// 失焦收起，若把轮询挂在视图上会被 onDisappear 取消，导致登录成功却抓不到 token。
//
// refresh token 存 Keychain；access token 内存缓存，过期自动用 refresh 续期。
// ============================================================

enum MicrosoftOAuthError: LocalizedError {
    case http(String)
    case pending
    case declined(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .http(let m): m
        case .pending: "等待用户完成登录"
        case .declined(let m): m
        case .noRefreshToken: "未登录"
        }
    }
}

@MainActor
final class MicrosoftOAuth: ObservableObject {
    static let shared = MicrosoftOAuth()

    /// 已登录（refresh token 在 Keychain）
    @Published private(set) var signedIn: Bool
    /// 登录进行中显示给用户的设备码（非 nil = 等待浏览器完成）
    @Published private(set) var pendingUserCode: String?
    @Published private(set) var verificationURL: String?
    /// 登录失败原因（成功/进行中为 nil）
    @Published private(set) var errorMessage: String?

    private init() {
        signedIn = Keychain.load(account: Self.refreshAccount) != nil
    }

    // 复用微软官方公开应用「Microsoft Graph Command Line Tools / Graph PowerShell」，
    // 含 Mail.Read 等 Graph 委派权限、支持设备码/公共客户端流程。
    // 走 Graph（/me/messages）而非 IMAP —— 不依赖邮箱 IMAP 协议开关（O365 IMAP 被管理员锁时仍可用）。
    private let clientID = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
    private let tenant = "common"
    /// Graph 读邮件 scope + offline_access（拿 refresh token）
    private let scope = "https://graph.microsoft.com/Mail.Read offline_access"

    private var baseURL: String { "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0" }
    // 换 client/scope 后旧 refresh token 失效，用新键名隔离（需重新登录一次）
    private static let refreshAccount = "msGraphRefreshToken"

    private var accessToken: String?
    private var accessExpiry: Date?
    private var flowTask: Task<Void, Never>?

    var isSignedIn: Bool { signedIn }

    func signOut() {
        flowTask?.cancel()
        Keychain.delete(account: Self.refreshAccount)
        accessToken = nil
        accessExpiry = nil
        signedIn = false
        pendingUserCode = nil
        verificationURL = nil
        errorMessage = nil
    }

    // MARK: - 设备码登录（常驻单例，面板收起也继续）

    /// 一键登录：申请设备码 → 复制代码 + 开浏览器 → 后台轮询直到完成。
    /// 再次调用 = 取消旧的、重新生成。
    func beginDeviceLogin() {
        flowTask?.cancel()
        errorMessage = nil
        pendingUserCode = nil
        flowTask = Task { @MainActor in
            do {
                let info = try await requestDeviceCode()
                // 复制代码 + 打开验证页（贴近"绑 QQ 邮箱"体验）；面板收起也已做完
                let pb = NSPasteboard.general; pb.clearContents(); pb.setString(info.userCode, forType: .string)
                if let url = URL(string: info.verificationURL) { NSWorkspace.shared.open(url) }
                pendingUserCode = info.userCode
                verificationURL = info.verificationURL

                let deadline = Date().addingTimeInterval(TimeInterval(info.expiresIn))
                while Date() < deadline {
                    try? await Task.sleep(for: .seconds(max(2, info.interval)))
                    if Task.isCancelled { return }
                    do {
                        try await pollOnce(deviceCode: info.deviceCode)
                        signedIn = true
                        pendingUserCode = nil
                        verificationURL = nil
                        NSLog("[MSOAuth] signed in ✓")
                        return
                    } catch MicrosoftOAuthError.pending {
                        continue
                    }
                }
                errorMessage = "登录超时，请重试"
                pendingUserCode = nil
            } catch let MicrosoftOAuthError.declined(reason) {
                errorMessage = "登录被拒：\(reason)"
                pendingUserCode = nil
            } catch {
                errorMessage = "登录失败：\(error.localizedDescription)"
                pendingUserCode = nil
            }
        }
    }

    private func requestDeviceCode() async throws -> DeviceCodeInfo {
        let json = try await postForm("\(baseURL)/devicecode", [
            "client_id": clientID,
            "scope": scope,
        ])
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let url = json["verification_uri"] as? String else {
            throw MicrosoftOAuthError.http("设备码响应异常")
        }
        NSLog("[MSOAuth] device code issued: \(userCode) → \(url)")
        return DeviceCodeInfo(
            userCode: userCode,
            verificationURL: url,
            message: json["message"] as? String ?? "请在浏览器完成登录",
            deviceCode: deviceCode,
            interval: json["interval"] as? Int ?? 5,
            expiresIn: json["expires_in"] as? Int ?? 900
        )
    }

    private func pollOnce(deviceCode: String) async throws {
        let json = try await postForm("\(baseURL)/token", [
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "client_id": clientID,
            "device_code": deviceCode,
        ], allowError: true)

        if let token = json["access_token"] as? String {
            cache(token: token, expiresIn: json["expires_in"] as? Int ?? 3600)
            if let refresh = json["refresh_token"] as? String {
                Keychain.save(refresh, account: Self.refreshAccount)
                NSLog("[MSOAuth] device login success, refresh token saved (token len=\(token.count))")
            } else {
                NSLog("[MSOAuth] success but NO refresh_token in response")
            }
            return
        }
        let err = json["error"] as? String
        NSLog("[MSOAuth] poll → error=\(err ?? "nil")")
        switch err {
        case "authorization_pending", "slow_down": throw MicrosoftOAuthError.pending
        case let other?: throw MicrosoftOAuthError.declined(json["error_description"] as? String ?? other)
        default: throw MicrosoftOAuthError.http("token 响应异常")
        }
    }

    // MARK: - 取 access token（IMAP XOAUTH2 用）

    func validAccessToken() async throws -> String {
        if let token = accessToken, let exp = accessExpiry, exp.timeIntervalSinceNow > 60 {
            return token
        }
        guard let refresh = Keychain.load(account: Self.refreshAccount) else {
            throw MicrosoftOAuthError.noRefreshToken
        }
        let json = try await postForm("\(baseURL)/token", [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "scope": scope,
            "refresh_token": refresh,
        ], allowError: true)
        guard let token = json["access_token"] as? String else {
            if let err = json["error"] as? String, err == "invalid_grant" { signOut() }
            throw MicrosoftOAuthError.http(json["error_description"] as? String ?? "刷新 token 失败")
        }
        cache(token: token, expiresIn: json["expires_in"] as? Int ?? 3600)
        if let newRefresh = json["refresh_token"] as? String {
            Keychain.save(newRefresh, account: Self.refreshAccount)
        }
        return token
    }

    // MARK: - 内部

    private func cache(token: String, expiresIn: Int) {
        accessToken = token
        accessExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
    }

    private func postForm(_ urlString: String, _ params: [String: String], allowError: Bool = false) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw MicrosoftOAuthError.http("URL 无效") }
        var req = URLRequest(url: url)
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
            let raw = String(data: data.prefix(400), encoding: .utf8) ?? ""
            NSLog("[MSOAuth] \(urlString) → HTTP \(code): \(raw)")
        }
        if !(200..<300).contains(code), !allowError {
            let desc = json["error_description"] as? String ?? String(data: data.prefix(200), encoding: .utf8) ?? "无响应"
            throw MicrosoftOAuthError.http("HTTP \(code)｜\(desc.replacingOccurrences(of: "\r\n", with: " "))")
        }
        return json
    }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }
}

/// 设备码登录提示
struct DeviceCodeInfo: Sendable {
    let userCode: String
    let verificationURL: String
    let message: String
    let deviceCode: String
    let interval: Int
    let expiresIn: Int
}
