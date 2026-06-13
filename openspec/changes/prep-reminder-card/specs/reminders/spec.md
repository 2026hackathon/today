## ADDED Requirements

### Requirement: 提前准备卡按优先级分级呈现
lead（提前量 `effectiveLeadMinutes`，即调度器 `.oneHour` 档）触发时，系统 SHALL 按任务优先级分级呈现「提前准备」提示：

- **高优先级**：SHALL 弹 prep 卡且**不自动收回**；用户「知道了」或点外侧收起后，该任务 SHALL 进入待准备集合并在 compact 显示提前准备徽章，直至被清除条件命中。
- **中优先级**：SHALL 弹 prep 卡并带 ~6s 倒计时条（悬停暂停），走完 SHALL 完全收回到 compact，不留徽章。
- **低优先级**：SHALL NOT 弹卡，仅 `refreshCompactState()` 刷新颜色（维持原行为）。

prep 卡 SHALL NOT 抢占输入态（快速新建 / 任务降落 / 批量卡）；勿扰时段内 SHALL 不弹卡（沿用调度器既有勿扰逻辑）。

#### Scenario: 高优先级提前量到点
- **WHEN** 一条高优先级任务到达其提前量时刻
- **THEN** 弹出 prep 卡且不自动消失；收起后 compact 出现提前准备徽章

#### Scenario: 中优先级提前量到点
- **WHEN** 一条中优先级任务到达其提前量时刻
- **THEN** 弹出带倒计时条的 prep 卡，~6s 后完全收回，compact 不留徽章

#### Scenario: 低优先级提前量到点
- **WHEN** 一条低优先级任务到达其提前量时刻
- **THEN** 不弹卡，仅刷新 compact 颜色

#### Scenario: 输入中提前量到点
- **WHEN** 提前量到点时用户正在 ⌘N 输入或有降落/批量卡
- **THEN** prep 卡不抢占当前输入态

### Requirement: 提前准备徽章自动清除
待准备集合中的任务 SHALL 在命中以下任一条件时自动移除（无需用户手动清除）：任务进入 finalWindow（即 `.fifteenMin`/`.due`/`.overdue` 提醒接管）、任务被完成、或任务被删除。

#### Scenario: 临近接管清徽章
- **WHEN** 某待准备任务进入 finalWindow，fifteenMin/到期提醒触发
- **THEN** 该任务从待准备集合移除，提前准备徽章计数相应减少或消失

#### Scenario: 完成清徽章
- **WHEN** 用户在徽章生效期间完成该任务
- **THEN** 该任务从待准备集合移除

### Requirement: 多条提前准备聚合
同一轮 lead 同时触发多条（高/中）时，系统 SHALL 只展开一张 prep 卡（最紧近的一项），其余 SHALL 计入聚合计数，由卡片以「还有 N 项要准备」（`moreCount`）呈现。

#### Scenario: 多条同时到提前量
- **WHEN** 同一扫描周期内 3 条任务同时到达提前量
- **THEN** 展开 1 张 prep 卡且卡上显示「还有 2 项要准备」
