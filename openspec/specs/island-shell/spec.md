# island-shell Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: 状态机驱动的形态切换
灵动岛 SHALL 由唯一的 `IslandState` 决定几何尺寸与内容，状态间切换 SHALL 使用统一弹簧动画（response 0.45 / damping 0.72）。

#### Scenario: 收缩态自动派生
- **WHEN** 数据变化（todo 数、最近截止时间、AI 是否工作中）
- **THEN** compact 态在 idle / normal / near / urgent / aiWorking 间自动切换，无需手动指定

#### Scenario: 事件触发卡片态
- **WHEN** AI 解析完成 / 提醒到期 / 用户按 ⌘N
- **THEN** island 切换到对应卡片态（newTask / reminder / quickInput），完成或超时后回到 compact 态

### Requirement: 不打扰的窗口行为
island 窗口 SHALL 不抢焦点、不占 Dock、覆盖全屏应用、在所有 Space 显示（沿用 NotchPanel 既有行为）。

#### Scenario: 全屏应用上方可见
- **WHEN** 用户在任意全屏应用中
- **THEN** island 仍然吸附刘海位置可见、可交互

### Requirement: 悬停直接展开
island SHALL 在悬停 compact 态时直接展开完整面板（无中间预览态，点击可跳过悬停延迟立即展开），鼠标移出、esc 或失去焦点（点击其他应用 / ⌘Tab 切走）SHALL 收起所有非 compact 态。

#### Scenario: 悬停展开
- **WHEN** 鼠标悬停 compact 态 ≥ 0.25s（防路过误触发）
- **THEN** 壳体从刘海向下弹性拉伸，直接展开完整 Today 面板，内容延迟淡入；移出 0.2s 后收回

#### Scenario: 失焦收起
- **WHEN** island 处于展开/卡片态，用户点击其他应用窗口或通过 ⌘Tab 等方式激活其他应用
- **THEN** island 回落到 compact 态

### Requirement: Debug 状态菜单
菜单栏 SHALL 提供 Debug 子菜单，可手动触发全部 island 状态（联调与 Demo 兜底用）。

#### Scenario: 手动触发任意状态
- **WHEN** 在菜单栏选择某个状态
- **THEN** island 立即切换到该状态并使用演示数据渲染

