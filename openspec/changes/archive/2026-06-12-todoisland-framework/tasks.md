# Tasks: todoisland-framework

## 1. 核心契约（主 agent，串行先行）
- [x] 1.1 Package.swift 添加 SwiftGlow 0.1.3 依赖
- [x] 1.2 Core/Models.swift — Todo / Meeting / TodoDraft / 枚举
- [x] 1.3 Core/DesignTokens.swift — prototype 色彩/字号/圆角落地
- [x] 1.4 Core/Persistence.swift — JSON 读写
- [x] 1.5 Core/AppStore.swift — 数据中枢 + compact 态派生 + 演示数据
- [x] 1.6 Island/IslandState.swift — 状态枚举 + 几何映射

## 2. 并行模块（agent team，文件互不重叠）
- [x] 2.1 [agent:ui-cards] UI/Compact + UI/Cards 五个卡片视图
- [x] 2.2 [agent:ui-panels] UI/Panels 四个面板视图
- [x] 2.3 [agent:services] Services/ 六个协议 + Mock + 热键/截图真实现
- [x] 2.4 [agent:effects] Effects/ SwiftGlow 封装 + Touchdown + 撒花 + 庆祝

## 3. 集成（主 agent）
- [x] 3.1 Island/IslandRootView.swift — 状态→视图路由
- [x] 3.2 AppDelegate 装配：服务注入、Debug 菜单、热键启动
- [x] 3.3 swift build 零报错 + swift run 冒烟（15 状态可触发）

## 4. 文档与交付
- [x] 4.1 docs/MODULES.md — 四人分工指南（文件边界 / 接口 / 验收）
- [x] 4.2 README 更新（架构图 + 上手命令 + openspec 工作流）
- [x] 4.3 提交并推送
