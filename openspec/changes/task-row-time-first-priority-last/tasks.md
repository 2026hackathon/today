## 1. 共享度量对齐

- [x] 1.1 在 TodayPanel.swift 确认/抽出 `MeetingRow` 行布局的共享常量：状态字形宽 16、时间轨宽 44、HStack `spacing: 8`、时间字体 `DS.Fonts.compactSide`（可定义私有常量供两行复用）

## 2. 重排 PersonalTodoRow 为单行布局

- [x] 2.1 将 `PersonalTodoRow` 的 `VStack{ 标题; HStack[元信息] }` 拍平为单行 `HStack(spacing: 8)`，元素顺序：状态字形 → 时间轨 → 标题 → kind 徽章 → Spacer → 优先级徽章 → 悬停操作
- [x] 2.2 在标题前插入时间轨：`Text` 显示 `effectiveDue` 时间，宽 44 左对齐、`DS.Fonts.compactSide`，与 `MeetingRow` 一致；保留 snooze 铃铛前缀，超期用 `DS.Colors.alert`
- [x] 2.3 时间文案：当天用 `PanelFormat.hm`（裸 HH:mm），非当天用紧凑日期标签（`dsShortLabel` 或 `PanelFormat.due` 短形）
- [x] 2.4 无 `effectiveDue` 的任务渲染等宽空占位时间轨（撑 44 宽），保证标题左对齐
- [x] 2.5 将 `PanelPriorityTag(priority:)` 从原第二行行首移到 Spacer 之后的行尾；纯任务/无优先级时的显示规则保持合理
- [x] 2.6 kind 徽章（提醒/日程）跟在标题后，与 `MeetingRow` 提醒徽章位置一致；纯任务不显示
- [x] 2.7 保留 tag（重复规则）、截图相机按钮、行尾截图缩略图、悬停编辑/删除按钮的原有功能，重新安置进单行布局不破坏对齐
- [x] 2.8 标题 `lineLimit(1)` + `Spacer(minLength: 0)`，确保单行不溢出、被挤窄时截断

## 3. 验证对齐与回归

- [x] 3.1 编译通过（`swift build` 或 Xcode 构建无错）
- [x] 3.2 Today 页签目视核对：已超期 / 今日任务 / 今日无时间任务三段中，个人任务行时间在前、优先级在尾，且与相邻 `MeetingRow` 的状态字形、时间轨、标题起始位置对齐
- [x] 3.3 「任务」纯列表页签目视核对单行布局正确
- [x] 3.4 回归验证：完成/撤销、悬停编辑、悬停删除（本地直删 / 苹果来源确认弹窗）、截图预览、snooze 铃铛与超期红色均正常
