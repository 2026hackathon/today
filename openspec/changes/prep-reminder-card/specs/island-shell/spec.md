## ADDED Requirements

### Requirement: 提前准备卡状态
`IslandState` SHALL 提供 `prepReminder(todo: Todo, moreCount: Int)` 卡片态，用于在任务 lead（提前量）时刻呈现「提前准备」提示。该态 SHALL 为 `isDismissable`（非 compact），点外侧 / Esc 可收起。`IslandGeometry` SHALL 为该态提供与到期提醒卡一致的宽度（380）、高度自适应。

#### Scenario: 进入提前准备卡态
- **WHEN** AppStore 调 `present(.prepReminder(todo:moreCount:))`
- **THEN** 灵动岛展开为 prep 卡，宽 380、高随内容自适应

#### Scenario: 收起回落
- **WHEN** 用户点 prep 卡外侧或按 Esc
- **THEN** 灵动岛回落到数据派生的 compact 态

### Requirement: 提前准备常驻徽章
当存在「高优先级 lead 已触发但任务尚未进入 finalWindow / 未完成」的待准备项时，compact 左翼 SHALL 在 agent 徽章一侧显示一个「提前准备」徽章（图标 + 计数，复用既有徽章视觉），计数为 `prepBadgeCount`。点击该徽章 SHALL 调 `reopenPrep()` 重新展开 prep 卡。徽章为瞬态、SHALL NOT 持久化。

#### Scenario: 高优先级收卡后留徽章
- **WHEN** 高优先级 prep 卡被「知道了」或点外侧收起
- **THEN** compact 左翼出现提前准备徽章，计数为当前待准备项数

#### Scenario: 点击徽章重开卡片
- **WHEN** 用户点击提前准备徽章
- **THEN** 重新展开 prep 卡（多项时展示最紧近的一项 + `moreCount`）

#### Scenario: 中/低优先级不产生徽章
- **WHEN** 中优先级 prep 卡倒计时走完收回，或低优先级 lead 触发
- **THEN** compact 左翼不出现提前准备徽章
