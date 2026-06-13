import SwiftUI

// ============================================================
// QuickInputCard —— ⌘N 手动新建（AI 自动解析）。
// 对应 prototype.html STATES.quickinput。
// 输入停顿 0.6s 后自动调 onParse；可「跳过 AI」纯手动创建。
// ============================================================

struct QuickInputCard: View {
    /// 集成层注入的 AI 解析（失败/无结果返回 nil，不抛错）
    let onParse: (String) async -> TodoDraft?
    @EnvironmentObject var store: AppStore

    private enum Phase: Equatable {
        case idle
        case parsing
        case parsed(TodoDraft)
    }

    @State private var text = ""
    @State private var phase: Phase = .idle
    @State private var skipAI = false
    /// 手动模式（跳过 AI / 无解析结果）下用户自选的截止与优先级
    @State private var manualDue: Date?
    @State private var manualPriority: Priority = .medium
    @State private var parseTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    @StateObject private var dictation = SpeechDictation()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = store.quickInputNotice {
                noticeBanner(notice)
            }

            inputRow

            if !skipAI {
                if phase == .parsing {
                    statusRow
                }
                if case .parsed(let draft) = phase {
                    preview(draft)
                }
            }
            // 手动模式（跳过 AI / 尚无解析结果）：提供手动 截止/优先级 选择
            if skipAI || (phase != .parsing && !isParsed) {
                manualControls
            }

            actions
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.bottom, 6)
        .onAppear {
            focused = true
            // ⌥Space 语音速记进入：自动开始聆听（消费一次标志）
            if store.quickInputAutoVoice {
                store.quickInputAutoVoice = false
                dictation.toggle { spoken in text = spoken }
            }
        }
        .onDisappear { parseTask?.cancel(); dictation.stop() }
    }

    private var isParsed: Bool {
        if case .parsed = phase { return true }
        return false
    }

    /// 截图解析失败/未识别的提示（alert 色，来自 store.quickInputNotice）
    private func noticeBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(text)
                .font(DS.Fonts.meta)
        }
        .foregroundStyle(DS.Colors.alert)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.alertSoft, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - 手动 截止/优先级（跳过 AI / 无解析结果时展示）

    private var manualControls: some View {
        HStack(spacing: 8) {
            Text("手动")
                .font(DS.Fonts.sectionTitle)
                .kerning(0.8)
                .foregroundStyle(DS.Colors.text3)
            dueMenu(current: manualDue) { manualDue = $0 }
            HStack(spacing: 4) {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        manualPriority = p
                    } label: {
                        Text(p.label)
                            .dsTag(
                                p == .high ? DS.Colors.alert : DS.Colors.text2,
                                bg: p == .high ? DS.Colors.alertSoft : DS.Colors.surface1
                            )
                            .opacity(manualPriority == p ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
    }

    /// 截止时间下拉（手动模式与 AI 预览共用）
    private func dueMenu(current: Date?, onSet: @escaping (Date?) -> Void) -> some View {
        Menu {
            Button("无截止") { onSet(nil) }
            Button("1 小时后") { onSet(Date().addingTimeInterval(3600)) }
            Button("今晚 18:00") {
                onSet(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()))
            }
            Button("今晚 22:00") {
                onSet(Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()))
            }
            Button("明天 09:00") {
                let t = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                onSet(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: t))
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 9))
                Text(current?.dsShortLabel ?? "截止时间")
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(DS.Fonts.meta)
            .foregroundStyle(current == nil ? DS.Colors.text3 : DS.Colors.text1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - 输入行（› 前缀 + 输入框 + return 键帽）

    private var inputRow: some View {
        HStack(spacing: 10) {
            Text("›")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(DS.Colors.text3)
            TextField(dictation.isListening ? "正在聆听…" : "输入或说一句任务，AI 自动解析", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.text1)
                .focused($focused)
                .onSubmit { create() }
            // 语音输入：点麦克风开始/停止实时转写，文本写回输入框自动触发解析
            if !dictation.unavailable {
                Button {
                    dictation.toggle { spoken in text = spoken }
                } label: {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(dictation.isListening ? DS.Colors.alert : DS.Colors.text3)
                        .frame(width: 22, height: 22)
                        .background(
                            dictation.isListening ? DS.Colors.alertSoft : .clear,
                            in: RoundedRectangle(cornerRadius: DS.Radius.s)
                        )
                        .symbolEffect(.pulse, isActive: dictation.isListening)
                }
                .buttonStyle(.plain)
            }
            Text("return")
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .stroke(DS.Colors.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .onChange(of: text) { _, newValue in
            scheduleParse(newValue)
        }
    }

    /// 输入停顿 0.6s 后触发 AI 解析（防抖）
    private func scheduleParse(_ input: String) {
        parseTask?.cancel()
        guard !skipAI else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }
        parseTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            phase = .parsing
            let draft = await onParse(trimmed)
            guard !Task.isCancelled else { return }
            phase = draft.map(Phase.parsed) ?? .idle
        }
    }

    // MARK: - 「AI 正在解析…」

    private var statusRow: some View {
        HStack(spacing: 8) {
            ParsingSparkleIcon()
            Text("AI 正在解析…")
        }
        .font(DS.Fonts.meta)
        .foregroundStyle(DS.Colors.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
    }

    // MARK: - 解析预览（标题 / 截止 / 优先级）

    private func preview(_ draft: TodoDraft) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI 解析结果")
                .font(DS.Fonts.sectionTitle)
                .kerning(0.8)
                .foregroundStyle(DS.Colors.text3)
                .padding(.bottom, 8)

            previewRow(key: "标题", value: draft.title)
            HStack(spacing: 8) {
                Text("截止")
                    .foregroundStyle(DS.Colors.text3)
                    .frame(width: 50, alignment: .leading)
                // AI 给的是建议值，点击可改
                dueMenu(current: draft.dueDate) { setDue($0) }
                Spacer()
                aiMark
            }
            .font(DS.Fonts.button)
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                Text("优先级")
                    .foregroundStyle(DS.Colors.text3)
                    .frame(width: 50, alignment: .leading)
                HStack(spacing: 6) {
                    // 三档可点选：AI 给的是建议值，允许用户在创建前改
                    HStack(spacing: 4) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            priorityChip(p, selected: draft.priority == p)
                        }
                    }
                    if let explanation = draft.aiExplanation, !explanation.isEmpty {
                        Text(explanation)
                            .font(DS.Fonts.meta)
                            .foregroundStyle(DS.Colors.text3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                aiMark
            }
            .font(DS.Fonts.button)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
    }

    private func previewRow(key: String, value: String, aiMarked: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .foregroundStyle(DS.Colors.text3)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .foregroundStyle(DS.Colors.text1)
                .lineLimit(1)
            Spacer()
            if aiMarked { aiMark }
        }
        .font(DS.Fonts.button)
        .padding(.vertical, 4)
    }

    private func priorityChip(_ p: Priority, selected: Bool) -> some View {
        Button {
            setPriority(p)
        } label: {
            Text(p.label)
                .dsTag(
                    p == .high ? DS.Colors.alert : DS.Colors.text2,
                    bg: p == .high ? DS.Colors.alertSoft : DS.Colors.surface1
                )
                .opacity(selected ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }

    /// 用户改写 AI 建议的截止时间（继续输入重新解析后会被新结果覆盖）
    private func setDue(_ date: Date?) {
        guard case .parsed(var draft) = phase else { return }
        draft.dueDate = date
        phase = .parsed(draft)
    }

    /// 用户改写 AI 建议的优先级（注意：继续输入触发重新解析后会被 AI 新结果覆盖）
    private func setPriority(_ p: Priority) {
        guard case .parsed(var draft) = phase, draft.priority != p else { return }
        draft.priority = p
        phase = .parsed(draft)
    }

    private var aiMark: some View {
        Text("AI")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(DS.Colors.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(DS.Colors.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.s))
    }

    // MARK: - 底部操作行

    private var actions: some View {
        HStack(spacing: 6) {
            Button("跳过 AI") {
                parseTask?.cancel()
                skipAI = true
                phase = .idle
            }
            .buttonStyle(DSGhostButtonStyle(fullWidth: false))
            .disabled(skipAI)
            .opacity(skipAI ? 0.4 : 1)

            Spacer()

            Button("取消") { store.dismiss() }
                .buttonStyle(DSGhostButtonStyle(fullWidth: false))

            Button("创建") { create() }
                .buttonStyle(DSPrimaryButtonStyle(fullWidth: false))
                .disabled(createDisabled)
                .opacity(createDisabled ? 0.4 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
    }

    private var createDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        parseTask?.cancel()
        if !skipAI, case .parsed(let draft) = phase {
            store.add(draft.toTodo())
        } else {
            // 无解析结果 / 跳过 AI：原文本做标题 + 手动选择的截止/优先级
            store.add(Todo(title: trimmed, source: .manual, priority: manualPriority, dueDate: manualDue))
        }
        store.dismiss()
    }
}

// MARK: - 解析中 sparkles 微动画

private struct ParsingSparkleIcon: View {
    @State private var up = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS.Colors.accent)
            .scaleEffect(up ? 1.12 : 0.86)
            .opacity(up ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}
