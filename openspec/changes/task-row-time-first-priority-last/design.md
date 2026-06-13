## Context

Today 列表里两类行混排：

- `MeetingRow`（TodayPanel.swift:494）渲染 `Meeting`（日历/提醒）。已是「时间在前」单行布局：状态字形(16) → 时间轨(`PanelFormat.hm`，宽 44，`DS.Fonts.compactSide`) → 标题 → 提醒/平台徽章 → Spacer → 操作。无优先级概念。
- `PersonalTodoRow`（TodayPanel.swift:174）渲染 `Todo`（个人任务）。是「标题在前 + 第二行元信息」两行布局：状态字形 → VStack{ 标题；HStack[ 优先级徽章 → kind 徽章 → 时间(`PanelFormat.due`，如「今天 15:15」) → tag/截图 ] }。

两者度量、行高、时间位置都不一致。用户要求「样式统一，时间放前面，优先级放后面」。`MeetingRow` 已符合方向，改造重心在 `PersonalTodoRow`：拍平成单行、时间提到行首时间轨、优先级挪到行尾。

约束：纯展示层，不动 `Todo`/`Meeting` 数据模型，不动完成/删除/编辑/截图预览等行为；保留超期红、snooze 铃铛、截图相机/缩略图、悬停编辑删除等既有能力。

## Goals / Non-Goals

**Goals:**
- `PersonalTodoRow` 改为与 `MeetingRow` 一致的单行模板：状态字形 → 时间轨 → 标题 → kind 徽章 → Spacer → 优先级徽章 → 悬停操作。
- 时间与 `MeetingRow` 共用同一时间轨度量（宽 44、左对齐、`DS.Fonts.compactSide`），无截止时间留空占位以对齐标题。
- 优先级徽章移到行尾。
- 两类行在同一列表里像素级对齐。

**Non-Goals:**
- 不抽象出强约束的统一组件层（除非自然顺手）；以「对齐度量 + 元素顺序一致」为达标线。
- 不改 `MeetingRow` 的功能行为（其已是目标布局，只在度量/常量需要共享时微调）。
- 不改时间「文案」的业务含义，只改其位置与（必要时）紧凑化。
- 不动 `CompletedRow`（已完成折叠区，无时间、本就极简，不在本次统一范围）。

## Decisions

### D1：以 `MeetingRow` 为视觉基准改 `PersonalTodoRow`
`MeetingRow` 已是「时间在前」单行，改动面最小且方向正确。把 `PersonalTodoRow` 的 VStack 两行拍平为一行 HStack，复用相同的状态字形宽(16)、时间轨宽(44)、`spacing: 8`、字体。
- 备选：重写两者为共享组件 → 否决，`Meeting` 与 `Todo` 字段、完成/删除路径差异大，强行抽象收益低、风险高。

### D2：时间轨格式
个人任务时间轨显示 `effectiveDue`：当天用 `PanelFormat.hm`（裸 `HH:mm`，与 `MeetingRow` 一致，如「09:00」）；非当天（超期段/未来项）用紧凑日期标签（如 `dsShortLabel`/`PanelFormat.due` 的短形）。snooze 过的项保留小铃铛前缀。超期项时间用 `DS.Colors.alert`。
- 时间轨宽 44 对裸 `HH:mm` 足够；非当天的较长标签允许在该列内左对齐显示，必要时该行时间轨可放宽，但当天行（占绝大多数）严格对齐。
- 备选：一律 `PanelFormat.due` → 否决，「今天 15:15」过宽，破坏 44 宽对齐与「时间在前」的紧凑感。

### D3：无截止时间任务保留时间轨占位
`todayUntimedTodos` 没有 `effectiveDue`。时间轨仍渲染等宽空占位（`Color.clear`/空 `Text` 撑 44 宽），保证标题左对齐到同一竖线，不让无时间任务的标题左移。

### D4：优先级徽章放到 Spacer 之后（行尾）
满足「优先级放后面」。低优先级（`.low`，灰）视觉很弱，行尾不抢眼；中/高有色徽章靠右成列。与悬停出现的编辑/删除按钮共处行尾时，徽章在前、操作按钮在后；非悬停态行尾只有优先级徽章，干净。
- 备选：优先级紧跟标题之后 → 否决，那只是「在时间之后」，不满足「放后面」的语义（用户截图里优先级原本就在元信息行最左，明确要挪到尾部）。

### D5：保留并重新安置既有附属元素
kind 徽章（提醒/日程）跟在标题后（与 `MeetingRow` 提醒徽章位置一致）；tag（重复规则）、截图相机/缩略图按钮维持原功能，安置在标题后或行尾合适处，不破坏单行对齐。

## Risks / Trade-offs

- [单行后标题被挤窄]（时间轨 + 尾部徽章 + 截图按钮挤压标题宽度）→ 标题 `lineLimit(1)` + `Spacer(minLength: 0)`，截图缩略图等较宽元素维持原行尾位置；窄面板下标题截断可接受（`MeetingRow` 现状即如此）。
- [非当天任务时间标签超出 44 宽]→ 仅当天行严格对齐（绝大多数场景），非当天行允许该列稍宽，不影响整体扫读。
- [低优先级行尾留白感]（`.low` 徽章很弱，行尾偏空）→ 可接受；与 `MeetingRow` 无优先级行视觉一致。
- [遗漏复用点]（`TaskRow`→`PersonalTodoRow` 被多处引用）→ 改动集中在 `PersonalTodoRow` 本体，所有引用方自动受益，无需逐处改。

## Migration Plan

纯前端展示重排，无数据迁移、无回滚策略需求。改完在 Today 三段（已超期/今日任务/今日无时间）与「任务」纯列表页签目视核对：时间成列、优先级在尾、与 `MeetingRow` 对齐。

## Open Questions

- 非当天个人任务的时间轨文案最终取 `dsShortLabel` 还是 `PanelFormat.due` 短形，实现时按对齐效果定，不影响 spec。
