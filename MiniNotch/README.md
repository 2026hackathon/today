# MiniNotch

macOS 刘海（Notch）应用的最小壳子。目前只有：

- 一个贴在刘海位置的黑色面板，鼠标悬停展开 / 移开收起
- 一个菜单栏图标（显示/隐藏面板、退出）
- 不占 Dock、不抢焦点、覆盖全屏应用

业务功能尚未接入，展开态是占位内容。

## 环境要求

- macOS 14+ (Sonoma)
- Xcode 16+（自带 Swift 6 工具链即可，无需安装其他工具）

## 跑起来

```bash
# 命令行直接跑
swift run

# 或者用 Xcode 开发（直接打开包，没有 .xcodeproj）
open Package.swift
```

> 没有刘海的屏幕（外接显示器 / Intel 机型）会在屏幕顶部中央画一个 200×32 的"伪刘海"，方便调试。

## 打包发布

```bash
./build.sh
# 产出 dist/MiniNotch.app 和 dist/MiniNotch.zip（ad-hoc 签名，无需开发者账号）
```

收到 zip 的人首次打开：右键 .app → 打开 → 再点「打开」（绕过 Gatekeeper）。

## 工程约定

- **纯 SwiftPM，不用 XcodeGen，不提交任何 .xcodeproj**。Xcode 通过 `open Package.swift` 直接开发，避免多人协作时 project 文件冲突。
- 新模块放在 `Sources/MiniNotch/` 下新建文件即可，SwiftPM 自动纳入编译。

## 代码结构

```
Sources/MiniNotch/
├── main.swift           # 入口，启动 NSApplication
├── AppDelegate.swift    # 菜单栏 + 创建刘海面板
├── NotchPanel.swift     # 不抢焦点的悬浮 NSPanel（核心窗口行为）
├── NotchGeometry.swift  # 刘海尺寸/面板位置计算
└── NotchView.swift      # SwiftUI 视图：假刘海 + hover 展开（含 NotchShape）
```

各人开发新功能时，主要改动点是把自己的视图挂进 `NotchView.contentView`，把数据层文件加到 `Sources/MiniNotch/` 即可。
