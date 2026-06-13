import AppKit
import Foundation

// ============================================================
// AgentSessionService —— coding agent 会话采集（agent-session spec）。
// 借鉴 Vibe Island。接入机制（对 Claude Code）：
//   1. 生成 python3 hook 脚本，写到 app support
//   2. hook 把每次事件以一行 JSON 追加到 agent-events.jsonl
//   3. 本服务用 DispatchSource 监听该文件，新行解析成 AgentEvent → onEvent
//   4. installClaudeCodeHook() 把脚本注册进 ~/.claude/settings.json（含备份）
// 未安装 hook 时文件不增长，徽章为空，不报错。
// ============================================================

@MainActor
final class AgentSessionService {

    /// 每解析到一条事件回调（AppDelegate 接到 store.applyAgentEvent）
    var onEvent: ((AgentEvent) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var readOffset: UInt64 = 0

    private var eventsFile: URL { Persistence.baseDir.appendingPathComponent("agent-events.jsonl") }
    private var hookScript: URL { Persistence.baseDir.appendingPathComponent("claude-agent-hook.py") }
    /// opencode 全局插件目录（实测 1.17.4：plugin/ 单数，与 workmux 示例一致）
    private var openCodePlugin: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugin/mininotch.ts")
    }

    // MARK: - 启动监听

    func start() {
        ensureHookScript()
        // 已安装的 opencode 插件随代码更新（拿到新的 env 捕获等）；未装则不动
        if FileManager.default.fileExists(atPath: openCodePlugin.path) {
            _ = installOpenCodePlugin()
        }
        ensureEventsFile()
        // 首次启动从文件末尾开始读（不回放历史事件）。
        // 注意：NSNumber 不能直接 as? UInt64（恒为 nil），必须经 NSNumber.uint64Value —
        // 否则 readOffset=0 会每次启动回放整个历史文件，海量事件高频改 @Published 数组，
        // 与 SwiftUI 渲染争用导致内存损坏崩溃。
        let attrs = try? FileManager.default.attributesOfItem(atPath: eventsFile.path)
        readOffset = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        openWatcher()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func openWatcher() {
        fileDescriptor = open(eventsFile.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            NSLog("[Agent] cannot open events file for watching")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            // 关键：DispatchSource 回调不直接改 @MainActor 状态——投递成 MainActor 作业，
            // 与 SwiftUI 的渲染/读取在同一 actor 上串行互斥，杜绝并发改 agentSessions
            // 导致的野指针崩溃（EXC_BAD_ACCESS in swift_retain）。
            Task { @MainActor in self?.drainNewLines() }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
        drainNewLines() // 补读启动到 resume 间可能写入的行
    }

    private func reopenWatcher() {
        stop()
        ensureEventsFile()
        readOffset = 0
        openWatcher()
    }

    /// 读取 readOffset 之后的新行并解析
    private func drainNewLines() {
        guard let handle = try? FileHandle(forReadingFrom: eventsFile) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: readOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        readOffset += UInt64(data.count)

        let decoder = JSONDecoder()
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let event = try? decoder.decode(AgentEvent.self, from: Data(line)) else { continue }
            onEvent?(event)
        }
    }

    // MARK: - hook 脚本 / 事件文件

    private func ensureEventsFile() {
        if !FileManager.default.fileExists(atPath: eventsFile.path) {
            FileManager.default.createFile(atPath: eventsFile.path, contents: nil)
        }
    }

    /// 生成（幂等覆盖）hook 脚本：读 stdin JSON → 追加一行精简 JSON 到事件文件
    private func ensureHookScript() {
        let path = eventsFile.path
        let script = """
        #!/usr/bin/env python3
        import sys, json, os
        try:
            d = json.load(sys.stdin)
        except Exception:
            d = {}
        ev = d.get("hook_event_name", "")
        # title = 你的提问（UserPromptSubmit 带 prompt），作 session 名兜底
        title = " ".join(d.get("prompt", "").split())
        # 完成事件才读 transcript（大文件，避免每次工具调用都扫）：
        # name = 会话名（custom-title / agentName）；answer = agent 最后一条回复
        name = ""
        answer = ""
        if ev in ("Stop", "SubagentStop"):
            tp = d.get("transcript_path", "")
            if tp and os.path.exists(tp):
                try:
                    last_a = ""
                    with open(tp) as tf:
                        for line in tf:
                            try:
                                o = json.loads(line)
                            except Exception:
                                continue
                            t = o.get("type")
                            if t == "custom-title" and o.get("customTitle"):
                                name = o["customTitle"]
                            elif t == "agent-name" and o.get("agentName") and not name:
                                name = o["agentName"]
                            m = o.get("message", o)
                            if m.get("role") == "assistant" or t == "assistant":
                                c = m.get("content", "")
                                if isinstance(c, list):
                                    c = " ".join(
                                        p.get("text", "") for p in c
                                        if isinstance(p, dict) and p.get("type") == "text"
                                    )
                                if isinstance(c, str) and c.strip():
                                    last_a = c
                    answer = " ".join(last_a.split())
                except Exception:
                    pass
        out = {
            "event": ev,
            "session_id": d.get("session_id", ""),
            "cwd": d.get("cwd", ""),
            "message": d.get("message", ""),
            "agent": "Claude Code",
            "title": title[:80],
            "name": name[:60],
            "answer": answer[:120],
            "term": os.environ.get("TERM_PROGRAM", ""),
            "term_bundle": os.environ.get("__CFBundleIdentifier", ""),
            "iterm_session": os.environ.get("ITERM_SESSION_ID", ""),
            "tmux_pane": os.environ.get("TMUX_PANE", ""),
        }
        p = "\(path)"
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a") as f:
            f.write(json.dumps(out, ensure_ascii=False) + "\\n")
        """
        try? script.write(to: hookScript, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScript.path)
    }

    // MARK: - 安装到 Claude Code

    /// 把 hook 注册进 ~/.claude/settings.json（合并写入 + 时间戳备份）。
    /// 返回提示文案（成功/失败）。
    @discardableResult
    func installClaudeCodeHook() -> String {
        ensureHookScript()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        // 路径含空格（"Application Support"）→ 命令经 shell 执行必须加引号，否则被截断
        let cmd = "python3 '\(hookScript.path)'"

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
            // 备份（仅在原文件存在时）
            let backup = settingsURL.deletingPathExtension()
                .appendingPathExtension("mininotch-bak.json")
            try? data.write(to: backup)
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SubagentStop", "SessionEnd"]
        for ev in events {
            // 跳过已含本脚本的事件（幂等）
            let existing = hooks[ev] as? [[String: Any]] ?? []
            let already = existing.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == cmd } ?? false
            }
            if already { continue }
            let entry: [String: Any] = ["hooks": [["type": "command", "command": cmd]]]
            hooks[ev] = existing + [entry]
        }
        root["hooks"] = hooks

        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: settingsURL)
            return "已安装 Claude Code Hook（已备份原 settings.json）。重启 Claude Code 生效。"
        } catch {
            NSLog("[Agent] install hook failed: \(error)")
            return "安装失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 跳转到终端 session（agent-landed-jump spec）

    /// 尽力跳转：tmux 选 pane → iTerm 选 session → 激活终端 App → 兜底打开 cwd。
    func jumpTo(_ session: AgentSession) {
        let t = session.terminal

        // 1) tmux：选中那个 pane（跨进程经 tmux server 生效），再激活宿主终端
        if let pane = t?.tmuxPane, !pane.isEmpty {
            runShell("tmux select-window -t '\(pane)' \\; select-pane -t '\(pane)'")
            if let bundle = t?.bundleID ?? t?.program.flatMap(Self.bundleID(forProgram:)) {
                activateApp(bundleID: bundle)
            }
            return
        }

        // 2) iTerm2：ITERM_SESSION_ID = wNtNpN:UUID，按 UUID 选中那个 session
        if let iterm = t?.itermSession, !iterm.isEmpty,
           (t?.program ?? "").localizedCaseInsensitiveContains("iterm") {
            let uuid = iterm.split(separator: ":").last.map(String.init) ?? iterm
            runAppleScript("""
            tell application "iTerm2"
              activate
              repeat with w in windows
                repeat with tb in tabs of w
                  repeat with s in sessions of tb
                    if id of s is "\(uuid)" then
                      select w
                      select tb
                      select s
                      return
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """)
            return
        }

        // 3) 激活终端 App（Warp / Terminal / 其它无 pane API 的）
        if let bundle = t?.bundleID, !bundle.isEmpty {
            activateApp(bundleID: bundle); return
        }
        if let program = t?.program, let bundle = Self.bundleID(forProgram: program) {
            activateApp(bundleID: bundle); return
        }

        // 4) 兜底：打开工作目录（Finder）
        if let cwd = session.cwd, !cwd.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
        }
    }

    /// 把指定 bundle 的 App 带到前台。accessory 应用用 NSWorkspace.openApplication
    /// 比 NSRunningApplication.activate 可靠（后者在后台 app 里常激活不动）。
    private func activateApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("[Agent] app not found: \(bundleID)")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// TERM_PROGRAM → bundle id（拿不到 __CFBundleIdentifier 时的兜底）。
    /// 大小写无关 + 包含匹配，避免因环境变量字符串变体（ghostty/Ghostty 等）漏判。
    nonisolated private static func bundleID(forProgram program: String) -> String? {
        let p = program.lowercased()
        if p.contains("warp") { return "dev.warp.Warp-Stable" }
        if p.contains("iterm") { return "com.googlecode.iterm2" }
        if p.contains("ghostty") { return "com.mitchellh.ghostty" }
        if p.contains("wezterm") { return "com.github.wez.wezterm" }
        if p.contains("kitty") { return "net.kovidgoyal.kitty" }
        if p.contains("alacritty") { return "org.alacritty" }
        if p == "vscode" { return "com.microsoft.VSCode" }
        if p.contains("apple_terminal") || p == "terminal" { return "com.apple.Terminal" }
        return nil
    }

    private func runShell(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]  // 登录 shell 拿到 PATH 里的 tmux
        try? p.run()
    }

    private func runAppleScript(_ source: String) {
        // NSAppleScript 须在主线程
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { NSLog("[Agent] applescript jump failed: \(err)") }
    }

    // MARK: - 安装到 opencode（只通知，无双向）

    /// 写一个 opencode 插件，把事件转成与 Claude Code 同 schema 的 JSONL（agent="opencode"），
    /// 复用同一个事件文件与监听 —— Swift 端无需任何改动。
    @discardableResult
    func installOpenCodePlugin() -> String {
        let path = eventsFile.path
        // 事件映射对齐 workmux-status.ts 实测的 opencode 事件类型：
        // session.status(busy)→working / permission.updated→waiting /
        // permission.replied→working / session.idle→done(replied)
        let plugin = """
        import type { Plugin } from "@opencode-ai/plugin"
        import { createRequire } from "module"
        const require = createRequire(import.meta.url)
        const fs = require("fs")
        const path = require("path")

        const EVENTS = "\(path)"
        const last = new Map<string, string>()
        // 终端定位（opencode 进程在终端里启动，env 含这些；用于点击跳转）
        const TERM = {
          term: process.env.TERM_PROGRAM ?? "",
          term_bundle: process.env.__CFBundleIdentifier ?? "",
          iterm_session: process.env.ITERM_SESSION_ID ?? "",
          tmux_pane: process.env.TMUX_PANE ?? "",
        }

        const names = new Map<string, string>()

        function emit(event: string, sessionID: string, cwd: string, message: string, name: string) {
          if (name) names.set(sessionID, name)
          if (last.get(sessionID) === event) return  // 去抖：状态没变不重复写
          last.set(sessionID, event)
          try {
            fs.mkdirSync(path.dirname(EVENTS), { recursive: true })
            fs.appendFileSync(
              EVENTS,
              // name = opencode 自动会话名；answer 暂不抓（插件事件无最后回复，留空）
              JSON.stringify({ event, session_id: sessionID, cwd, message, agent: "opencode", name: names.get(sessionID) ?? "", answer: "", ...TERM }) + "\\n"
            )
          } catch {}
        }

        export const MiniNotchPlugin: Plugin = async ({ directory }) => {
          return {
            event: async ({ event }: any) => {
              const p = event.properties ?? {}
              const sid = p.sessionID ?? p.sessionId ?? p.info?.id ?? directory
              // opencode 自动生成的 session 标题（session.updated/idle 的 info.title）
              const name = (p.info?.title ?? "").slice(0, 60)
              switch (event.type) {
                case "session.status":
                  if (p.status?.type === "busy") emit("UserPromptSubmit", sid, directory, "", name)
                  break
                case "session.updated":
                  emit(last.get(sid) ?? "UserPromptSubmit", sid, directory, "", title)
                  break
                case "permission.updated":
                  emit("Notification", sid, directory, "opencode 请求确认", name)
                  break
                case "permission.replied":
                  emit("UserPromptSubmit", sid, directory, "", name)
                  break
                case "session.idle":
                  emit("Stop", sid, directory, "", name)
                  break
              }
            },
          }
        }
        """
        do {
            try FileManager.default.createDirectory(
                at: openCodePlugin.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plugin.write(to: openCodePlugin, atomically: true, encoding: .utf8)
            return "已安装 opencode 插件到 \(openCodePlugin.path)。重启 opencode 生效。"
        } catch {
            NSLog("[Agent] install opencode plugin failed: \(error)")
            return "安装失败：\(error.localizedDescription)"
        }
    }
}
