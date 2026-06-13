import SwiftUI

// ============================================================
// EditTaskCard —— 编辑已有个人任务（标题 / 截止 / 优先级）。
// 由 Today 面板任务行右键「编辑」触发（store.present(.editTask(todo:))）。
// 只用于个人来源任务；Jira/GitHub 只读不进此卡。
// 保存走 store.update()，删除走 store.delete()——改截止时间会经
// $todos 自动触发提醒重排（AppDelegate sink），本卡无需关心。
// ============================================================

struct EditTaskCard: View {
    let todo: Todo
    @EnvironmentObject var store: AppStore

    @State private var title: String
    @State private var priority: Priority
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var lead: Int?
    @FocusState private var titleFocused: Bool

    init(todo: Todo) {
        self.todo = todo
        _title = State(initialValue: todo.title)
        _priority = State(initialValue: todo.priority)
        _hasDue = State(initialValue: todo.dueDate != nil)
        _lead = State(initialValue: todo.reminderLeadMinutes)
        // 无截止时给一个合理默认（今天 18:00），打开开关即用
        _due = State(initialValue: todo.dueDate
            ?? Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // 标题
            TextField("任务标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.text1)
                .focused($titleFocused)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.s))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .strokeBorder(titleFocused ? DS.Colors.accent : DS.Colors.border, lineWidth: 1)
                )
                .padding(.bottom, 12)

            fieldRow("优先级") {
                HStack(spacing: 4) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        priorityChip(p)
                    }
                }
            }

            fieldRow("截止") {
                HStack(spacing: 8) {
                    Toggle("", isOn: $hasDue.animation(IslandAnimation.spring))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    if hasDue {
                        DatePicker("", selection: $due)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .scaleEffect(0.9, anchor: .leading)
                    } else {
                        Text("无截止")
                            .font(DS.Fonts.meta)
                            .foregroundStyle(DS.Colors.text3)
                    }
                    Spacer()
                }
            }

            // 提前提醒：仅有截止时间时可设（chips，不用 Menu——非激活面板里 Menu 不渲染）
            if hasDue {
                fieldRow("提前") {
                    HStack(spacing: 4) {
                        ForEach([0, 5, 15, 30, 60], id: \.self) { m in
                            leadChip(m)
                        }
                    }
                }
            }

            actions
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .onAppear { titleFocused = true; store.cardHeld = true }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                Text("编辑任务")
                    .font(DS.Fonts.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.accent)
                Spacer()
            }
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
        .padding(.bottom, 12)
    }

    // MARK: - 字段行（左标签 + 右控件）

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DS.Fonts.button)
                .foregroundStyle(DS.Colors.text3)
                .frame(width: 50, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func leadChip(_ m: Int) -> some View {
        let isSel = (lead ?? todo.kind.defaultLeadMinutes) == m
        return Button { lead = m } label: {
            Text(NewTaskCard.leadChip(m))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSel ? DS.Colors.text1 : DS.Colors.text2)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(isSel ? DS.Colors.accentSoft : DS.Colors.surface1,
                           in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func priorityChip(_ p: Priority) -> some View {
        Button {
            priority = p
        } label: {
            Text(p.label)
                .dsTag(
                    p == .high ? DS.Colors.alert : DS.Colors.text2,
                    bg: p == .high ? DS.Colors.alertSoft : DS.Colors.surface1
                )
                .opacity(priority == p ? 1 : 0.35)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部操作（删除 / 取消 / 保存）

    private var actions: some View {
        HStack(spacing: 6) {
            // 删除走自绘红色 label：DSGhostButtonStyle 内部固定前景色，外层 override 无效
            Button {
                store.delete(todo)
                store.dismiss()
            } label: {
                Text("删除")
                    .font(DS.Fonts.button)
                    .foregroundStyle(DS.Colors.alert)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            Spacer()

            Button("取消") { store.dismiss() }
                .buttonStyle(DSGhostButtonStyle(fullWidth: false))

            Button("保存") { save() }
                .buttonStyle(DSPrimaryButtonStyle(fullWidth: false))
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.4 : 1)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.Colors.border).frame(height: 1)
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        var updated = todo
        updated.title = trimmedTitle
        updated.priority = priority
        updated.dueDate = hasDue ? due : nil
        updated.reminderLeadMinutes = hasDue ? lead : nil
        store.update(updated)
        store.dismiss()
    }
}
