## MODIFIED Requirements

### Requirement: 不打扰的窗口行为
island 窗口 SHALL 不抢焦点、不占 Dock、覆盖全屏应用、在所有 Space 显示（沿用 NotchPanel 既有行为）。面板窗口虽固定为可容纳最大展开态的大尺寸，但 SHALL 仅在岛体当前实际渲染所覆盖的矩形区域内接收鼠标点击；该矩形之外的透明区域 SHALL NOT 拦截点击，点击 SHALL 穿透到下方的应用窗口或桌面。命中矩形 SHALL 随 island 形态（compact / 卡片 / 展开）实时变化，始终覆盖当前可见岛体（含合理 hit-slop 容差）。

#### Scenario: 全屏应用上方可见
- **WHEN** 用户在任意全屏应用中
- **THEN** island 仍然吸附刘海位置可见、可交互

#### Scenario: 收缩态下方透明区点击穿透
- **WHEN** island 处于 compact 态，用户点击岛体下方的透明区域（即面板窗口覆盖、但岛体未渲染的区域）
- **THEN** 该点击穿透到下方应用/桌面正常生效，island 不拦截、不响应

#### Scenario: 命中区随形态扩展
- **WHEN** island 从 compact 展开为完整面板或弹出卡片
- **THEN** 命中矩形同步扩大到覆盖展开后的岛体，面板内部所有控件（按钮、列表、输入框）照常可点击

#### Scenario: 点击透明区触发失焦收起
- **WHEN** island 处于展开/卡片态，用户点击岛体之外的透明区域（落到下方应用窗口）
- **THEN** 点击穿透激活下方应用，触发既有失焦收起逻辑，island 回落 compact 态
