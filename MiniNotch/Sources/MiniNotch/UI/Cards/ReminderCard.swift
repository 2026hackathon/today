import SwiftUI

// ============================================================
// ReminderCard —— 任务到期提醒卡（含 Snooze）。
// 对应 prototype.html STATES.reminder。
// ============================================================

struct ReminderCard: View {
    let todo: Todo
    @EnvironmentObject var store: AppStore

    @State private var bellDimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Text(todo.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Colors.alert)
                .lineLimit(2)
                .padding(.bottom, 6)

            overdueBadge
                .padding(.bottom, 12)

            // complete() 内部处理状态回落（justCompleted 闪光 / celebrate），不再 dismiss
            Button("标记完成") { store.complete(todo) }
                .buttonStyle(DSPrimaryButtonStyle())
                .padding(.bottom, 10)

            snoozeRow
        }
        .padding(.top, 36)   // 摄像头区
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    // MARK: - 头部（bell 脉冲 + 「任务到期」 + 时间 tag）

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Colors.alert)
                    .opacity(bellDimmed ? 0.4 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                            bellDimmed = true
                        }
                    }
                Text("任务到期")
                    .font(DS.Fonts.meta.weight(.medium))
                    .foregroundStyle(DS.Colors.alert)
                Spacer()
                Text(todo.dueDate?.dsHHmm ?? "现在")
                    .font(DS.Fonts.tag)
                    .foregroundStyle(DS.Colors.alert)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(DS.Colors.alertSoft, in: RoundedRectangle(cornerRadius: 4))
            }
            Rectangle()
                .fill(DS.Colors.border)
                .frame(height: 1)
        }
        .padding(.bottom, 10)
    }

    // MARK: - 超时徽章

    private var overdueBadge: some View {
        Text(overdueText)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(DS.Colors.alert)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(DS.Colors.alertSoft, in: RoundedRectangle(cornerRadius: 4))
    }

    private var overdueText: String {
        guard let due = todo.dueDate else { return "现在到点了" }
        let minutes = Int(Date().timeIntervalSince(due) / 60)
        return minutes >= 1 ? "已超时 \(minutes) 分钟" : "现在到点了"
    }

    // MARK: - Snooze 选项行（snooze() 内部已 dismiss）

    private var snoozeRow: some View {
        HStack(spacing: 6) {
            snoozeButton("5 分钟") { snooze(minutes: 5) }
            snoozeButton("15 分钟") { snooze(minutes: 15) }
            snoozeButton("1 小时") { snooze(minutes: 60) }
            snoozeButton("明天") { store.snooze(todo, until: Self.tomorrowMorning()) }
            snoozeButton("自定义") { snooze(minutes: 30) }
        }
    }

    private func snooze(minutes: Int) {
        store.snooze(todo, until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    private static func tomorrowMorning() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func snoozeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DS.Fonts.meta)
                .foregroundStyle(DS.Colors.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s)
                        .stroke(DS.Colors.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s))
        }
        .buttonStyle(.plain)
    }
}
