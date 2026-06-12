# Proposal: todoisland-framework

## Why

TodoIsland（住在 Mac 刘海里的 AI Todo 助手）是 48 小时 hackathon 项目，4 人并行开发。当前仓库只有 MiniNotch 壳子（黑色面板 + hover 展开）。没有统一框架时，4 人会在数据模型、状态机、视觉规范上各写一套，集成必然冲突。本 change 一次性搭好**可编译、可运行、带 mock 数据的全应用骨架**，之后每人只在自己模块的文件内填充真实实现。

## What Changes

- 引入 **Island 状态机**：以 `prototype.html` 的 15 个状态为蓝本（compact 系列 / card 系列 / expanded 系列 / celebrate），统一驱动灵动岛几何形态与内容切换
- 引入 **数据层**：`Todo` / `Meeting` 模型 + `AppStore`（ObservableObject）+ JSON 本地持久化，内置演示数据
- 引入 **服务协议层**：AI 解析、截图、Jira、日历、提醒调度、推送 6 个 protocol，全部提供 Mock 实现，UI 先跑通，成员逐个替换为真实现
- 引入 **动效系统**：集成 SwiftGlow（AI 流光呼吸），实现 Touchdown 任务降落、完成撒花、全屏庆祝的占位动效
- 引入 **设计 tokens**：prototype.html 的颜色 / 圆角 / 字体规范落为 Swift 常量，全员共用
- 新增 **Package.swift 依赖**: SwiftGlow 0.1.3 (MIT, macOS 12+)
- 新增 **模块分工文档**：每个模块一份 owner 指南（接口契约、文件边界、验收标准）

## Capabilities

### New Capabilities
- `island-shell`: 灵动岛窗口、状态机、几何形态切换与动画
- `todo-data`: Todo/Meeting 数据模型、CRUD、分组、持久化
- `ai-pipeline`: AI 解析服务协议（截图→Todo、批量识别、紧急度、晨报/晚报生成）
- `capture`: F2/F3 全局快捷键与截图采集
- `integrations`: Jira / Apple 日历 / 推送的服务协议与 mock
- `reminders`: 到期提醒调度与 Snooze
- `effects`: 统一动效系统（Touchdown / 流光 / 撒花 / 庆祝）

### Modified Capabilities

（无 —— 仓库尚无既有 spec）

## Impact

- `MiniNotch/Package.swift`: 新增 SwiftGlow 依赖
- `MiniNotch/Sources/MiniNotch/`: 重构 NotchView 为状态机驱动；新增 Core / Island / Services / UI / Effects 子目录
- 现有 `NotchPanel` / `NotchGeometry` 保留复用（队友刚改进过，不动）
- 团队工作流：后续每个功能按 openspec change 流程提交，文件边界见 docs/MODULES.md
