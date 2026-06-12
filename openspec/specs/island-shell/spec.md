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

### Requirement: 悬停与锁定展开
island SHALL 支持 hover 弹出预览，点击 SHALL 锁定展开态（鼠标移出不收起），再次点击或按 esc 收起。

#### Scenario: 悬停预览
- **WHEN** 鼠标悬停 compact 态 ≥ 0.8s
- **THEN** 显示最多 3 条待办的 hoverPreview，移出 0.3s 后收回

### Requirement: Debug 状态菜单
菜单栏 SHALL 提供 Debug 子菜单，可手动触发全部 island 状态（联调与 Demo 兜底用）。

#### Scenario: 手动触发任意状态
- **WHEN** 在菜单栏选择某个状态
- **THEN** island 立即切换到该状态并使用演示数据渲染

