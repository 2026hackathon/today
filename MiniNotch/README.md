# TodoIsland (MiniNotch)

住在 Mac 刘海里的 AI Todo 助手 —— hackathon 项目。

**框架已就绪**：状态机、数据层、服务协议、SwiftGlow 动效、全部 UI 均可运行（外部能力为 Mock）。
每人在框架上替换自己模块的实现即可，分工见 [docs/MODULES.md](../docs/MODULES.md)。

## 跑起来

```bash
cd MiniNotch
swift run            # 刘海出现黑岛 + 菜单栏图标
# 或用 Xcode：open Package.swift
```

跑起来后：**菜单栏图标 → Debug 状态**，把 15 个状态逐个点一遍即可理解整个产品。

## 环境要求

- macOS 14+ (Sonoma)，Xcode 16+（Swift 6 工具链）
- 依赖：[SwiftGlow](https://github.com/margox/SwiftGlow) 0.1.3（SPM 自动拉取）

## 必读文档

| 文档 | 内容 |
|------|------|
| [docs/MODULES.md](../docs/MODULES.md) | **分工指南**：每人的文件边界、已就绪能力、待办清单 |
| [CODING_GUIDELINES.md](../CODING_GUIDELINES.md) | 硬规则（文件边界 / 单一数据源 / DS tokens） |
| `openspec/changes/archive/2026-06-12-todoisland-framework/design.md` | 架构契约（必读） |
| `openspec/specs/` | 7 个 capability 的需求基线 |
| `prototype.html`（仓库根） | 视觉蓝本，浏览器打开逐状态对照 |

## 代码结构

```
Sources/MiniNotch/
├── main.swift / AppDelegate.swift   # 装配点：服务注入、Debug 菜单、轮询
├── NotchPanel.swift                 # 不抢焦点的悬浮窗（稳定，别动）
├── NotchGeometry.swift              # 刘海尺寸计算（稳定，别动）
├── Core/                            # 契约：模型 / AppStore / 持久化 / 设计 tokens
├── Island/                          # 状态机 + 状态→视图路由
├── UI/Compact|Cards|Panels/         # 收缩态 / 5 种卡片 / 4 种面板
├── Services/                        # 6 个协议 + Mock（AI/截图/Jira/日历/提醒/推送）
└── Effects/                         # SwiftGlow 流光 / Touchdown / 撒花 / 全屏庆祝
```

## 工程约定

- 纯 SwiftPM，不提交 .xcodeproj；`open Package.swift` 开发
- 新功能走 openspec：`openspec new change "<name>"` → 实现 → `openspec archive <name>`
- 推 main 前必须 `swift build` 通过 + Debug 菜单冒烟

## 打包发布

```bash
./build.sh   # 产出 dist/MiniNotch.app + .zip（ad-hoc 签名）
```

## 已知坑

- F2/F3 热键需要 Fn 配合，或系统设置→键盘→「将 F1、F2 等键用作标准功能键」
- 首次截图弹屏幕录制权限，授权后重启 app
- 本地数据在 `~/Library/Application Support/MiniNotch/`，乱了用 Debug 菜单「重置演示数据」
