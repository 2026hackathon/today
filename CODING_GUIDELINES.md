# TodoIsland 编码守则

> 给所有人（和所有 coding agent）的硬规则。违反任何一条都会造成集成冲突。

## 必读

1. 架构契约：`openspec/changes/todoisland-framework/design.md`
2. 需求规格：`openspec/changes/todoisland-framework/specs/<你的模块>/spec.md`
3. 分工与文件边界：`docs/MODULES.md`
4. 视觉蓝本：`prototype.html`（用浏览器打开，15 个状态逐个看）

## 硬规则

- **只改自己模块目录内的文件**。共享契约（`Core/Models.swift`、`Core/AppStore.swift`、`Island/IslandState.swift`、`Core/DesignTokens.swift`）要改先开 openspec change 并在群里同步。
- **单一数据源**：UI 读 `AppStore`（`@EnvironmentObject`），变更走 store 方法。禁止 view 里私藏业务状态、禁止绕过 store 直接写文件。
- **颜色/字号/圆角一律用 `DS.*`**，禁止裸 `Color(...)` 魔法值。
- **服务必须保留 Mock**：接真实现时不要删 Mock，AppDelegate 里换装配即可（Demo 兜底）。
- **状态切换只走 `store.present(_:)` / `store.dismiss()`**，动画统一 `IslandAnimation.spring`。
- **错误不崩 UI**：所有外部调用 `do/catch`，失败走降级路径（spec 里有定义）。
- **Swift 6 严格并发**：UI 与 Store 都是 `@MainActor`；后台干活用 `Task` + `await MainActor.run` 回主线程。
- **岛体视图链必须身份稳定**：给岛体写修饰器时禁止 `if cond { self.xxx() } else { self }` 包住宿主——条件翻转会销毁重建整棵子树，壳体形变动画直接失效（闪现替换）。条件一律放进 `overlay { if ... }` / `background { if ... }` 内部（参考 `Effects/GlowEffects.swift` 的写法）。
- 提交前必须 `cd MiniNotch && swift build` 通过 + `swift run` 冒烟（用菜单栏 Debug 菜单过一遍你改动的状态）。

## 工作流

1. `openspec new change "<your-feature>"` → 写 proposal/specs/tasks
2. 实现 → `swift build` + 冒烟
3. 完成后 `openspec archive --change "<your-feature>"`，specs 进 baseline
4. PR / 直接推 main（hackathon 模式），但推前必须本地能跑

## 验证命令

```bash
cd MiniNotch
swift build          # 编译
swift run            # 运行（菜单栏出现图标，刘海出现黑岛）
./build.sh           # 打包 .app（发给队友测试）
```
