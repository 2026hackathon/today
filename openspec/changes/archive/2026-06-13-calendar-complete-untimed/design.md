## Context

`AppStore.canComplete(_:)` 现规则：苹果 `.calendar` 项→可完成；本地任务→仅「今天/超期」可完成，未来与无截止都返回 false（显示静态小点）。本轮把「无截止」从小点改为可完成。

完成状态的对勾在本轮被统一放大到 16pt（`PersonalTodoRow` 与 `MeetingRow` 的 `checkmark.circle.fill`），用户反馈偏大，恢复到此前的 11pt。

## Goals / Non-Goals

**Goals:**
- 无截止本地任务可勾选完成。
- 已完成对勾恢复 11pt 小样式。

**Non-Goals:**
- 不改未来本地任务的「小点」表现（仍不可完成）。
- 不改苹果项可完成规则、删除/回写逻辑、可完成的空心圈尺寸。

## Decisions

### D1：canComplete 对无截止本地任务返回 true
`guard let anchor = todo.effectiveDue else { return false }` 改为 `else { return true }`。即：本地任务无截止 → 可完成；有截止 → 仅今天/超期可完成（未来仍不可，保留小点）。苹果项与外部源规则不变。

### D2：已完成对勾尺寸 16 → 11
`PersonalTodoRow` 与 `MeetingRow` 的已完成分支 `Image(systemName: "checkmark.circle.fill").font(.system(size: 16))` 改为 `size: 11`，对齐前一版本观感。可完成的空心圈（16pt）保持不变。

## Risks / Trade-offs

- [无截止任务现可完成 → 完成后落入日历「无固定时间」区并加删除线] → 与 later-into-calendar「已完成不隐藏」一致，符合预期。
- [对勾与空心圈尺寸不一（11 vs 16）] → 两者为不同状态、不同视觉权重，可接受；若仍突兀可后续统一。
