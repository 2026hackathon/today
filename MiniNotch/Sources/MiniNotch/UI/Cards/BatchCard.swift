import SwiftUI

// ============================================================
// BatchCard —— 批量识别卡（截图里识别到多个任务）。
// 对应 prototype.html STATES.batch。
// ============================================================

struct BatchCard: View {
    let drafts: [TodoDraft]
    @EnvironmentObject var store: AppStore

    /// 勾选集合（初始尊重 draft.isSelected）
    @State private var selectedIDs: Set<UUID>

    init(drafts: [TodoDraft]) {
        self.drafts = drafts
        _selectedIDs = State(initialValue: Set(drafts.filter(\.isSelected).map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(drafts) { draft in
                row(draft)
            }
            footer
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                Text("识别到 \(drafts.count) 个任务")
                    .font(DS.Fonts.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.text2)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "camera")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.Colors.text3)
                    Text("截图")
                }
                .font(DS.Fonts.tag)
                .foregroundStyle(DS.Colors.text3)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: 4))
            }
            Rectangle()
                .fill(DS.Colors.border)
                .frame(height: 1)
        }
        .padding(.bottom, 4)
    }

    // MARK: - 任务行（点击整行切换勾选）

    private func row(_ draft: TodoDraft) -> some View {
        let checked = selectedIDs.contains(draft.id)
        return Button {
            if checked {
                selectedIDs.remove(draft.id)
            } else {
                selectedIDs.insert(draft.id)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .fill(checked ? DS.Colors.text1 : Color.clear)
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .stroke(checked ? DS.Colors.text1 : DS.Colors.text3, lineWidth: 1.5)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.Colors.islandBG)
                    }
                }
                .frame(width: 16, height: 16)

                Text(draft.title)
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.text1)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let due = draft.dueDate {
                    Text(due.dsShortLabel)
                        .font(DS.Fonts.meta)
                        .foregroundStyle(DS.Colors.text3)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部（全选链接 + 添加按钮）

    private var allSelected: Bool { selectedIDs.count == drafts.count }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Colors.border)
                .frame(height: 1)
                .padding(.top, 12)
            HStack {
                Button {
                    if allSelected {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = Set(drafts.map(\.id))
                    }
                } label: {
                    Text(allSelected ? "取消全选" : "全选")
                        .font(DS.Fonts.button)
                        .foregroundStyle(DS.Colors.text2)
                        .underline(true, color: DS.Colors.text3)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("添加 \(selectedIDs.count) 项") { addSelected() }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .frame(width: 108)
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.4 : 1)
            }
            .padding(.top, 10)
        }
    }

    private func addSelected() {
        let updated = drafts.map { draft in
            var copy = draft
            copy.isSelected = selectedIDs.contains(draft.id)
            return copy
        }
        store.add(drafts: updated)
        store.dismiss()
    }
}
