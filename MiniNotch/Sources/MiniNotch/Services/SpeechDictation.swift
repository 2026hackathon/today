import AVFoundation
import Speech

// ============================================================
// SpeechDictation —— 语音输入（中文实时转写）。
// SFSpeechRecognizer + AVAudioEngine，转出的文本写回快速录入框，
// 复用既有 0.6s 防抖 → AI 解析管线。说一句话 = 打一句话。
//
// 权限：Info.plist 需 NSSpeechRecognitionUsageDescription +
// NSMicrophoneUsageDescription；首次使用各弹一次系统授权窗
// （需以 .app 运行，裸 swift run 拿不到授权，同日历）。
// ============================================================

@MainActor
final class SpeechDictation: ObservableObject {
    @Published private(set) var isListening = false
    /// 不可用（无识别器 / 权限被拒 / 启动失败）→ UI 隐藏麦克风或灰显
    @Published private(set) var unavailable = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// 实时转写回调：把当前最佳文本写回输入框
    private var onText: ((String) -> Void)?

    func toggle(onText: @escaping (String) -> Void) {
        if isListening { stop() } else { start(onText: onText) }
    }

    private func start(onText: @escaping (String) -> Void) {
        self.onText = onText
        // @Sendable 剥离 MainActor 隔离：TCC 在后台线程回调，闭包若继承 @MainActor
        // 会在入口触发「必须在主执行器」断言 → 崩溃（同 EventKit 那次）。
        // status 是 Sendable 枚举，self 是 MainActor 类(Sendable)，捕获安全
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            Task { @MainActor in
                guard status == .authorized else { self.unavailable = true; return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard let recognizer, recognizer.isAvailable else { unavailable = true; return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // append 是线程安全的（Apple 文档）；tap 在音频线程跑，用 nonisolated(unsafe)
        // 把请求带进闭包，绕过 Swift 6 对非 Sendable 捕获的拦截
        nonisolated(unsafe) let sink = req
        // @Sendable 关键：tap 在音频实时线程回调，闭包若继承 @MainActor
        // 会在入口触发执行器断言崩溃（同 requestAuthorization 那处）
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            sink.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            NSLog("[Speech] audioEngine 启动失败: \(error)")
            cleanup()
            unavailable = true
            return
        }
        isListening = true

        task = recognizer.recognitionTask(with: req) { @Sendable [weak self] result, error in
            // @Sendable + 先取 Sendable 值再跳主线程：回调在后台线程，闭包不能继承
            // @MainActor（否则入口断言崩），SFSpeechRecognitionResult 非 Sendable 不能跨域
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text { self.onText?(text) }
                if done { self.stop() }
            }
        }
    }

    func stop() {
        cleanup()
        isListening = false
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
