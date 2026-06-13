## Why

今日列表里两种行混排却长得不一样：日历/提醒走 `MeetingRow`（时间在最前、单行、无优先级），个人任务走 `PersonalTodoRow`（标题在前、第二行才出现「优先级 + 时间」）。同一份清单里时间一会儿在前一会儿在后、行高也忽高忽低，扫读时眼睛要在两套布局间来回跳。统一成「时间在前、优先级在后」的单行模板，列表才能一眼对齐扫读。

## What Changes

- 个人任务行（`PersonalTodoRow`）从「标题 + 第二行元信息」改为与 `MeetingRow` 一致的单行布局：状态字形 → 等宽时间轨 → 标题 → kind 徽章（提醒/日程）→ Spacer → 尾部优先级徽章 → 悬停操作。
- 时间从第二行挪到行首等宽时间轨（与 `MeetingRow` 同宽同字体同对齐），无截止时间的任务时间轨留空但保留占位，保证所有行标题左对齐到同一竖线。
- 优先级徽章从第二行行首挪到行尾（Spacer 之后），实现「优先级放后面」。
- 两种行共享同一套视觉度量（时间轨宽度、状态字形宽度、HStack 间距、字体），确保 `MeetingRow` 与 `PersonalTodoRow` 在同一列表中像素级对齐。
- 不改数据模型、不改完成/删除/编辑等行为，纯展示层重排。

## Capabilities

### New Capabilities
<!-- 无新增能力，纯展示层调整 -->

### Modified Capabilities
- `island-shell`: 为 Today/任务列表新增「任务行统一布局」要求——同一列表内个人任务行与日历/提醒行 SHALL 采用一致的单行模板，时间在行首等宽时间轨、优先级在行尾。

## Impact

- 代码：`MiniNotch/Sources/MiniNotch/UI/Panels/TodayPanel.swift`（`PersonalTodoRow` 重排；可能抽取与 `MeetingRow` 共享的行布局度量/子视图）。
- 影响出现 `TaskRow`/`PersonalTodoRow` 的全部位置：Today 页签的「已超期 / 今日任务 / 今日无时间任务」三段，以及「任务」纯列表页签。
- 无数据/持久化/同步影响；无 API 变更。
