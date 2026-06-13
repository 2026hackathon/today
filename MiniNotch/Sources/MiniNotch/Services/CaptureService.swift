import AppKit
import CoreGraphics
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
    /// 截图完成：(图像数据, 落盘路径) → AI 解析链路。
    /// 统一走数组：F2 单张 = 1 元素；快速录入连续贴多张 = 多元素，归到同一条任务。
    var onTodoCapture: ((_ images: [Data], _ savedPaths: [String]) -> Void)? { get set }
    /// F3 收藏完成：落盘路径（不走 AI）
    var onFavoriteCapture: ((String) -> Void)? { get set }
    /// 安装事件 handler（应用启动时调用一次）
    func start()
    /// 按配置（重新）注册全局热键。设置里改键后再次调用即可热生效，无需重启。
    func applyHotKeys(todo: HotKeyConfig, favorite: HotKeyConfig, voice: HotKeyConfig)
    /// 手动触发（菜单/Debug 用）
    func captureForTodo()
    func captureForFavorite()
    /// 从剪贴板读图识别（兼容 CleanShot/微信等外部截图工具）。
    /// 找到图片 → 走与 F2 相同的 onTodoCapture 管线并返回 true；剪贴板无图返回 false
    func captureFromPasteboard() -> Bool
    /// 已拿到 PNG 字节（如快速录入里 ⌘V 贴的图）：落盘后走与 F2 相同的 onTodoCapture 管线
    func recognize(pngData png: Data)
    /// 多张 PNG（快速录入连续贴多张）：全部落盘后一次走 AI 流水线，归到同一条任务
    func recognize(pngDataList pngs: [Data])
    /// 全局语音热键（⌥Space）：弹出快速录入并自动开始语音
    var onVoiceCapture: (() -> Void)? { get set }
    /// 缺「屏幕录制」权限：截图只会抓到桌面壁纸（窗口内容被系统抹掉），此时引导去授权
    var onScreenRecordingDenied: (() -> Void)? { get set }
}

@MainActor
final class HotkeyCaptureService: CaptureService {

    var onTodoCapture: ((_ images: [Data], _ savedPaths: [String]) -> Void)?
    var onFavoriteCapture: ((String) -> Void)?
    var onVoiceCapture: (() -> Void)?
    var onScreenRecordingDenied: (() -> Void)?

    // MARK: Carbon 热键

    /// 'TDIL' (TodoIsland)
    private static let hotKeySignature: OSType = 0x5444_494C
    private enum HotKeyID: UInt32 {
        case todo = 1      // F2
        case favorite = 2  // F3
        case voice = 3     // ⌥Space
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
        // 具体热键由 applyHotKeys(...) 注册（AppDelegate 启动后用 settings 调用一次，改键后再调）
    }

    /// 按配置重注册：先注销全部旧热键，再注册三个新键（被占用的单个失败只打日志，不影响其它）
    func applyHotKeys(todo: HotKeyConfig, favorite: HotKeyConfig, voice: HotKeyConfig) {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        registerHotKey(todo, id: .todo)
        registerHotKey(favorite, id: .favorite)
        registerHotKey(voice, id: .voice)
    }

    private func registerHotKey(_ config: HotKeyConfig, id: HotKeyID) {
        registerHotKey(keyCode: UInt32(config.keyCode), id: id, modifiers: UInt32(config.modifiers))
    }

    private func registerHotKey(keyCode: UInt32, id: HotKeyID, modifiers: UInt32 = 0) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
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
        case .voice: onVoiceCapture?()
        case nil: break
        }
    }

    // MARK: 截图

    func captureForTodo() {
        capture(into: Persistence.screenshotsDir) { [weak self] data, path in
            self?.onTodoCapture?([data], [path])
        }
    }

    func captureForFavorite() {
        capture(into: Persistence.favoritesDir) { [weak self] _, path in
            self?.onFavoriteCapture?(path)
        }
    }

    func captureFromPasteboard() -> Bool {
        // NSImage(pasteboard:) 能吃 PNG/TIFF 位图，也能吃被复制的图片文件
        guard let image = NSImage(pasteboard: .general),
              let png = Self.pngData(from: image)
        else {
            return false
        }
        recognize(pngData: png)
        return true
    }

    /// 已拿到 PNG 字节（如快速录入里 ⌘V 贴的图）：落盘后走与 F2 截图相同的 AI 流水线
    func recognize(pngData png: Data) {
        recognize(pngDataList: [png])
    }

    /// 多张 PNG（快速录入连续贴多张）：全部落盘后一次性走 AI 流水线，归到同一条任务。
    /// 任一张落盘失败只跳过该张，不影响其余；全部失败则静默返回。
    func recognize(pngDataList pngs: [Data]) {
        var images: [Data] = []
        var paths: [String] = []
        for (i, png) in pngs.enumerated() where !png.isEmpty {
            // 同批多张时间戳可能相同，加序号后缀避免互相覆盖
            let suffix = pngs.count > 1 ? "-paste-\(i + 1)" : "-paste"
            let filename = Self.filenameFormatter.string(from: Date()) + "\(suffix).png"
            let fileURL = Persistence.screenshotsDir.appendingPathComponent(filename)
            do {
                try png.write(to: fileURL)
                images.append(png)
                paths.append(fileURL.path)
            } catch {
                NSLog("[Capture] 贴图落盘失败: \(error)")
            }
        }
        guard !images.isEmpty else { return }
        onTodoCapture?(images, paths)
    }

    /// NSImage → PNG 字节（位图重编码）。失败返回 nil。
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]), !png.isEmpty
        else {
            return nil
        }
        return png
    }

    private static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// 跑 `screencapture -i <path>`：交互选区。esc 取消 → 文件不存在 → 静默返回（capture spec）。
    /// Process 的 terminationHandler 在后台线程触发，读完文件后 hop 回 MainActor。
    private func capture(into dir: URL, completion: @escaping @MainActor @Sendable (Data, String) -> Void) {
        // 没「屏幕录制」权限时，screencapture 只会抓到桌面壁纸（窗口内容被系统抹掉）——
        // 这正是「截图识别一直失败、抓到的全是壁纸」的根因。先检测，缺权限就触发系统弹窗
        // 并把 App 加进「屏幕录制」列表，再引导用户去打开（授权后需重启 App 生效）。
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()   // 首次会弹系统授权框，并把 App 登记进列表
            onScreenRecordingDenied?()
            return
        }

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
