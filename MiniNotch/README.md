# TodoIsland (MiniNotch)

住在 Mac 刘海里的 AI Todo 助手 —— hackathon 项目。

**框架已就绪**：状态机、数据层、服务协议、SwiftGlow 动效、全部 UI 均可运行（外部能力为 Mock）。
每人在框架上替换自己模块的实现即可，分工见 [docs/MODULES.md](../docs/MODULES.md)。

## 跑起来

```bash
cd MiniNotch
./certs/setup-cert.sh   # 首次一次性：导入团队签名证书（见下）
./run.sh                # debug 编译 → 组装 .app → 启动
```

跑起来后：**菜单栏图标 → Debug 状态**，把 15 个状态逐个点一遍即可理解整个产品。

> ⚠️ 不要直接 `swift run`：裸二进制没有绑定 Info.plist，拿不到日历/提醒权限，
> EventKit 同步永远 accessDenied。Xcode 调试 UI 没问题，但验证日历功能必须走 `./run.sh`。

### 团队签名证书（certs/）

`certs/FocusIslandDev.p12` 是团队共用的自签名代码签名证书（含私钥，仅限本仓库开发用）。
每人每台机器跑一次 `./certs/setup-cert.sh` 导入并信任后，`run.sh` / `build.sh` 会自动用它签名。

为什么需要：ad-hoc 签名的身份是二进制 cdhash，每次重编译都变 → macOS 把它当新应用，
日历(TCC)授权随之失效。用固定证书签名后身份 = bundle id + 证书，重编译、换人构建都不掉权限。

## 系统要求（使用者）

运行这个 App 的 Mac 需要满足：

- **系统版本**：macOS 14.0 (Sonoma) 或更新 —— 硬门槛。刘海定位依赖 `NSScreen.safeAreaInsets.top`，14 之前不支持。
- **芯片**：Apple Silicon (M 系列) 与 Intel 均可。发布包是 Universal Binary（arm64 + x86_64），两类 Mac 都原生运行。
- **刘海：不是必须**。
  - 带刘海的 MacBook Pro 14"/16"（M1 Pro/Max 起，2021 款及以后）→ 面板精确贴合真刘海，体验最佳；
  - 没刘海的机器（老 MacBook Air/Pro、Intel 机型、Mac mini/Studio/iMac 接显示器）→ 自动在屏幕顶部正中用 200×32 的「伪刘海」回退，功能完全一致。
- **GPU**：辉光基于 Metal（SwiftGlow），所有能跑 macOS 14 的 Mac 都内置支持，无额外门槛。
- **权限（可选，按需授权）**：日历 / 提醒事项（显示今日会议与提醒）、麦克风 / 语音识别（语音输入待办）。不授权也能用，仅对应功能关闭。
- **网络 / AI（可选）**：截图解析、自然语言建议、晨/晚报需联网并配置 AI Key；未配置或断网时有不出网的本地规则兜底，核心待办照常用。
- **首次打开**：非 App Store 分发（自签名 / ad-hoc），首次需右键 →「打开」绕过 Gatekeeper。

## 环境要求（开发）

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
./build.sh   # 产出 dist/MiniNotch.app + .zip（优先 FocusIsland Dev 证书，无则 ad-hoc）
```

## 已知坑

- F2/F3 热键需要 Fn 配合，或系统设置→键盘→「将 F1、F2 等键用作标准功能键」
- 首次截图弹屏幕录制权限，授权后重启 app
- 本地数据在 `~/Library/Application Support/MiniNotch/`，乱了用 Debug 菜单「重置演示数据」
