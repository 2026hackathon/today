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
        ensureEventsFile()
        // 首次启动从文件末尾开始读（不回放历史事件，避免崩溃前的陈旧状态复活）
        readOffset = (try? FileManager.default.attributesOfItem(atPath: eventsFile.path)[.size] as? UInt64) ?? 0
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
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // 文件被轮转/删除 → 重开
                self.reopenWatcher()
            } else {
                self.drainNewLines()
            }
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
        out = {
            "event": d.get("hook_event_name", ""),
            "session_id": d.get("session_id", ""),
            "cwd": d.get("cwd", ""),
            "message": d.get("message", ""),
            "agent": "Claude Code",
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
        let cmd = "python3 \(hookScript.path)"

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

        function emit(event: string, sessionID: string, cwd: string, message: string) {
          if (last.get(sessionID) === event) return  // 去抖：状态没变不重复写
          last.set(sessionID, event)
          try {
            fs.mkdirSync(path.dirname(EVENTS), { recursive: true })
            fs.appendFileSync(
              EVENTS,
              JSON.stringify({ event, session_id: sessionID, cwd, message, agent: "opencode" }) + "\\n"
            )
          } catch {}
        }

        export const MiniNotchPlugin: Plugin = async ({ directory }) => {
          return {
            event: async ({ event }: any) => {
              const p = event.properties ?? {}
              const sid = p.sessionID ?? p.sessionId ?? directory
              switch (event.type) {
                case "session.status":
                  if (p.status?.type === "busy") emit("UserPromptSubmit", sid, directory, "")
                  break
                case "permission.updated":
                  emit("Notification", sid, directory, "opencode 请求确认")
                  break
                case "permission.replied":
                  emit("UserPromptSubmit", sid, directory, "")
                  break
                case "session.idle":
                  emit("Stop", sid, directory, "")
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
