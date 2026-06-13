# TodoIsland 模块分工指南

> 框架已搭好：**应用可编译可运行，全部 UI 走通，外部能力全部 Mock**。
> 每个人的工作 = 把自己模块的 Mock 换成真实现 + 打磨体验。
> 动手前必读：`CODING_GUIDELINES.md`、`openspec/changes/todoisland-framework/design.md`、你模块的 spec。

## 快速上手

```bash
cd MiniNotch
swift run        # 跑起来：刘海出现黑岛，菜单栏出现图标
```

菜单栏图标 → **Debug 状态** 子菜单可手动触发全部 island 状态（联调 + Demo 兜底）。
先把每个状态点一遍，你就理解整个产品了。

> **Agent 会话监控**（Claude Code / opencode 状态上刘海）配置见 [AGENT-SESSION-SETUP.md](./AGENT-SESSION-SETUP.md)。

## 架构 60 秒版

- `AppStore`（`Core/AppStore.swift`）= 单一数据源。UI 读它，变更走它的方法。
- `IslandState`（`Island/IslandState.swift`）= 状态机。island 长什么样只由它决定。
- `store.present(.某状态)` 弹出卡片/面板，`store.dismiss()` 回落收缩态。收缩态变体（idle/normal/near/urgent）由数据自动派生，不要手动设置。
- 服务全是 protocol，`AppDelegate.makeServices 区域` 是唯一装配点，换真实现改那里一行。

## 分工表

### A — macOS 工程师：动效 & 交互打磨
**你的文件**：`Effects/*`、`Island/IslandRootView.swift`、`UI/Compact/*`、`UI/Cards/*`
**框架已给你**：
- SwiftGlow 集成完毕：`aiParsingGlow` / `urgentGlow` / `goldFlash`（`Effects/GlowEffects.swift`，含用法注释）
- `TouchdownRipple`（来源色涟漪）、`ConfettiBurst`（撒花）、`CelebrationWindowController`（全屏庆祝）
- 全部已挂到 `IslandRootView`，触发器在 `AppStore.landedSource` / `completionFlash`

**待你完成**（按 PRD 优先级）：
- [ ] F-07 Touchdown 细节打磨（卡片浮起的弹性、微震动）
- [ ] F-08 快捷手势：todo 行右滑完成/左滑 Snooze（`UI/Panels/TodayPanel.swift` 的 todo 行加 gesture）
- [ ] F-18 烟花效果升级（现在是 ConfettiBurst 三波连发，可换真烟花）
- [ ] F-19 悬停预览节奏微调（现 0.8s 触发 / 0.3s 收回）
- [ ] F-20 拖拽文件/链接到 island → Todo（`IslandRootView` 加 `.onDrop`）

### B — 后端/AI 工程师：AI 链路
**你的文件**：`Services/AIService.swift`、`Core/`（数据层归你维护）
**框架已给你**：
- `AIService` 协议 + `MockAIService`（延迟 1.2s 返回演示数据，含批量模式）+ `AnthropicAIService` 骨架
- 调用链全部接好：F2 截图 → `parseScreenshot` → 单卡/批量卡；⌘N → `parseQuickInput`；晨报/晚报 → `generateMorningReport/EveningReport`
- 截图文件路径会自动写进 draft（`AppDelegate.wireServices`）

**待你完成**：
- [ ] F-01 `AnthropicAIService.parseScreenshot`：图片 base64 → 视觉模型 → JSON 结构化输出（标题/优先级/截止/解释），≥3 项自动走批量
- [ ] F-06 紧急度判断 prompt（规则见 PRD 6.1/F-06）
- [ ] F-13/F-28 晨报晚报真 LLM 生成（Mock 已有拼接版可对照格式）
- [ ] API key 从 `store.settings.aiAPIKey` 读，为空回退 Mock（设置面板已有输入框）
- [ ] F-05 收藏截图的 AI 打标签 + OCR（与 C 协作）

### C — 全栈工程师：外部集成
**你的文件**：`Services/`（除 AIService）
**框架已给你**：
- `HotkeyCaptureService`：F2/F3 Carbon 全局热键 + `screencapture -i` 已是真实现（注意：需 Fn+F2 或系统设置把 F 键设为标准功能键）
- `TimerReminderScheduler`：四级提醒 + Snooze + 勿扰时段已是真实现
- `FeishuPushService` / `BarkPushService` 已是真实现（webhook/token 在设置面板填）
- `RealJiraService` / `EventKitCalendarService` 骨架 + TODO 注释；会议链接 6 平台正则提取已实现

**待你完成**：
- [x] ~~F-12 `RealJiraService`~~ **已完成**：`/rest/api/3/search/jql`（注意旧 `/search` 端点已被 Atlassian 下线）+ Basic Auth，已在 wonder.atlassian.net 实测。装配规则：设置面板 Jira 三项填齐 → 自动切真实服务（下个 60s 轮询生效），清空任一项 → 回退 Mock；Debug「模拟 Jira 新分配」始终走 Mock 不受影响
- [ ] F-14 `EventKitCalendarService`：EventKit 授权 + 今日事件拉取（Info.plist 需加 NSCalendarsFullAccessUsageDescription）
- [ ] F-04 提醒推送通道按 settings 装配（现在固定 Noop，改 AppDelegate 装配处按配置选 Feishu/Bark）
- [ ] F-10 快捷键全套（⌘⇧L 展开收起等，参考 HotkeyCaptureService 的 Carbon 写法）
- [ ] F-15 微信 ClawBot（PushService 协议加一个实现即可）

### D — 产品/设计
- 视觉基准 = `prototype.html`（浏览器打开逐状态对照真 app 找 diff）
- 所有颜色/字号/圆角在 `Core/DesignTokens.swift`，调视觉改这一个文件全局生效
- Demo 脚本对应的触发都在菜单栏 Debug 菜单里（含「模拟 Jira 新分配」）

## 状态机速查

| 状态 | 触发方式 | 视图 |
|------|---------|------|
| idle/normal/near/urgent | 数据自动派生 | CompactContent |
| aiWorking | `store.isAIWorking = true` | CompactContent + 流光 |
| hoverPreview | 悬停 0.8s | HoverPreview |
| newTask(draft) | AI 解析返回 1 条 | NewTaskCard |
| batch(drafts) | AI 解析返回 ≥3 条 | BatchCard |
| reminder(todo) | 提醒到期 | ReminderCard |
| quickInput | ⌘N / 菜单 | QuickInputCard |
| expanded(tab) | 点击 island | TodayPanel / SettingsPanel |
| morningReport / eveningReport | 每日首启 ≥8 点 / 18 点 | Morning/EveningReportPanel |
| celebrate | 今日全部完成 | CompactContent(皇冠) + 全屏庆祝窗口 |

## openspec 工作流（每个新功能）

```bash
openspec new change "f08-swipe-gestures"   # 建 change
# 写 proposal.md → specs delta → tasks.md（参考 todoisland-framework 这个 change）
# 实现 → swift build + Debug 菜单冒烟
openspec archive --change "f08-swipe-gestures"  # 完成后归档进 baseline
```

## 已知坑

1. **F2/F3 热键**：Mac 默认 F 键是媒体键，要么 Fn+F2，要么系统设置→键盘→「将 F1、F2 等键用作标准功能键」
2. **首次截图**会弹屏幕录制权限，授权后要重启 app
3. **SwiftGlow** glow 在 compact 态故意只在下沿/左右溢光（顶部出屏裁掉），这是符合预期的
4. **数据文件**在 `~/Library/Application Support/MiniNotch/`，演示数据乱了用 Debug 菜单「重置演示数据」
