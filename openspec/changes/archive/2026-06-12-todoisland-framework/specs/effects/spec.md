# effects

统一动效系统。Owner: A。依赖 SwiftGlow 0.1.3（Metal 渲染，macOS 12+，MIT）。

## ADDED Requirements

### Requirement: SwiftGlow 流光
AI 工作中 SHALL 使用 SwiftGlow `.animatedGlow`（appleIntelligence/rainbow 预设）渲染流光呼吸；urgent 态 SHALL 使用红色 glow 脉冲。

#### Scenario: AI 解析中
- **WHEN** islandState == .aiWorking
- **THEN** island 边缘出现彩虹流光呼吸，结束后淡出

### Requirement: Touchdown 任务降落
新增任务 SHALL 播放统一 Touchdown 动效（微震动 → 涟漪扩散 → 卡片浮起 → 3s 后收回），涟漪颜色按来源区分：截图紫 / Jira 蓝 / 手动绿 / 日历橙 / 微信绿。

#### Scenario: 鼠标悬停暂停收回
- **WHEN** 卡片悬浮期间鼠标悬停
- **THEN** 3s 倒计时暂停，移开后继续

### Requirement: 完成反馈
完成 todo SHALL 播放撒花粒子 + 金色高光（~1s）；完成今日全部 SHALL 触发独立全屏透明窗口的庆祝动画（3-5s）+ compact 态显示皇冠。

#### Scenario: 完成最后一个今日任务
- **WHEN** 今日未完成数归零
- **THEN** 全屏庆祝窗口播放并自动关闭，不抢焦点、不影响后台应用

### Requirement: 动效可关闭与降级
所有装饰性动效 SHALL 尊重系统「减弱动态效果」设置并可在设置中关闭；目标 60fps。

#### Scenario: 减弱动态效果开启
- **WHEN** 系统 accessibility reduce motion 开启
- **THEN** 粒子/流光禁用，仅保留几何形变
