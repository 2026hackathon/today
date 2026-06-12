import Foundation
import Carbon.HIToolbox

// ============================================================
// CaptureService —— F2/F3 全局热键 + 系统交互截图。
// Owner: C
//
// 实现说明：
// - 全局热键用 Carbon RegisterEventHotKey（无需辅助功能权限，见 design.md 决策表）。
// - 截图走 /usr/sbin/screencapture -i（系统交互选区，esc 取消时不产出文件 → 静默返回）。
// - ⚠️ F 键限制：大多数 Mac 键盘上 F2/F3 默认是亮度/调度中心等媒体功能键，
//   需要按住 Fn+F2 才会发出 F2 键码；或在「系统设置 → 键盘」勾选
//   「将 F1、F2 等键用作标准功能键」。Demo 前务必确认该设置。
// - 热键注册失败（如被其他 App 占用）只 NSLog，不崩溃（capture spec / CODING_GUIDELINES）。
//
// 接真实现步骤（C）：本文件已是真实现，无 Mock。如需换截图方案（ScreenCaptureKit 等）
// 只需保持 CaptureService 协议不变，在 AppDelegate 装配处替换。
// ============================================================

@MainActor
protocol CaptureService: AnyObject {
    /// F2 截图完成：(图像数据, 落盘路径) → AI 解析链路
    var onTodoCapture: ((Data, _ savedPath: String) -> Void)? { get set }
    /// F3 收藏完成：落盘路径（不走 AI）
    var onFavoriteCapture: ((String) -> Void)? { get set }
    /// 注册全局热键（应用启动时调用一次）
    func start()
    /// 手动触发（菜单/Debug 用）
    func captureForTodo()
    func captureForFavorite()
}

@MainActor
final class HotkeyCaptureService: CaptureService {

    var onTodoCapture: ((Data, _ savedPath: String) -> Void)?
    var onFavoriteCapture: ((String) -> Void)?

    // MARK: Carbon 热键

    /// 'TDIL' (TodoIsland)
    private static let hotKeySignature: OSType = 0x5444_494C
    private enum HotKeyID: UInt32 {
        case todo = 1      // F2
        case favorite = 2  // F3
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var started = false

    init() {}

    func start() {
        guard !started else { return }
        started = true

        // 1. 安装事件 handler（应用级 target，回调在主线程的 Carbon 事件循环里派发）
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                // C 回调（不可捕获上下文）：userData = unmanaged self
                guard let eventRef, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr else { return err }
                let service = Unmanaged<HotkeyCaptureService>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                // 应用级 Carbon 事件 handler 在主线程派发 → 可安全 assumeIsolated 跳回 MainActor
                MainActor.assumeIsolated {
                    service.handleHotKey(id: id)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
        if installStatus != noErr {
            NSLog("[Capture] InstallEventHandler failed: \(installStatus)")
            return
        }

        // 2. 注册 F2 / F3（无 modifier）
        registerHotKey(keyCode: UInt32(kVK_F2), id: .todo)      // 0x78
        registerHotKey(keyCode: UInt32(kVK_F3), id: .favorite)  // 0x63
    }

    private func registerHotKey(keyCode: UInt32, id: HotKeyID) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id.rawValue)
        let status = RegisterEventHotKey(keyCode, 0, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr || ref == nil {
            // 注册失败（被占用等）不崩溃，仅打日志
            NSLog("[Capture] RegisterEventHotKey keyCode=\(keyCode) failed: \(status)")
            return
        }
        hotKeyRefs.append(ref!)
    }

    private func handleHotKey(id: UInt32) {
        switch HotKeyID(rawValue: id) {
        case .todo: captureForTodo()
        case .favorite: captureForFavorite()
        case nil: break
        }
    }

    // MARK: 截图

    func captureForTodo() {
        capture(into: Persistence.screenshotsDir) { [weak self] data, path in
            self?.onTodoCapture?(data, path)
        }
    }

    func captureForFavorite() {
        capture(into: Persistence.favoritesDir) { [weak self] _, path in
            self?.onFavoriteCapture?(path)
        }
    }

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// 跑 `screencapture -i <path>`：交互选区。esc 取消 → 文件不存在 → 静默返回（capture spec）。
    /// Process 的 terminationHandler 在后台线程触发，读完文件后 hop 回 MainActor。
    private func capture(into dir: URL, completion: @escaping @MainActor @Sendable (Data, String) -> Void) {
        let filename = Self.filenameFormatter.string(from: Date()) + ".png"
        let fileURL = dir.appendingPathComponent(filename)
        let path = fileURL.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", path]
        process.terminationHandler = { _ in
            // 后台线程：用户 esc 取消 → 文件不存在 → 静默返回，不触发任何回调
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
                return
            }
            Task { @MainActor in
                completion(data, path)
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("[Capture] screencapture 启动失败: \(error)")
        }
    }
}
