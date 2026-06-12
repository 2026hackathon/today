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
    @State private var parseTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow

            if !skipAI {
                if phase == .parsing {
                    statusRow
                }
                if case .parsed(let draft) = phase {
                    preview(draft)
                }
            }

            actions
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.bottom, 6)
        .onAppear { focused = true }
        .onDisappear { parseTask?.cancel() }
    }

    // MARK: - 输入行（› 前缀 + 输入框 + return 键帽）

    private var inputRow: some View {
        HStack(spacing: 10) {
            Text("›")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(DS.Colors.text3)
            TextField("输入任务，AI 自动解析时间和优先级", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.text1)
                .focused($focused)
                .onSubmit { create() }
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
            previewRow(key: "截止", value: draft.dueDate?.dsShortLabel ?? "无", aiMarked: true)

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
            // 无解析结果 / 跳过 AI：原文本做标题，manual 来源
            store.add(Todo(title: trimmed, source: .manual))
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
