# capture Specification

## Purpose
TBD - created by archiving change todoisland-framework. Update Purpose after archive.
## Requirements
### Requirement: 全局热键
应用 SHALL 注册 F2（截图→Todo）与 F3（截图收藏）全局热键，在任意应用前台时生效，使用 Carbon RegisterEventHotKey（无需辅助功能权限）。

#### Scenario: 任意前台应用按 F2
- **WHEN** 用户在其他应用中按 F2
- **THEN** 进入系统交互式区域截图，完成后图像数据进入 AI 解析链路

### Requirement: 系统截图采集
截图 SHALL 通过 `screencapture -i` 交互选区实现；用户按 esc 取消时 SHALL 静默返回，不触发任何 UI。

#### Scenario: 用户取消截图
- **WHEN** 选区过程中按 esc
- **THEN** 无 AI 调用、island 状态不变

### Requirement: F3 收藏直存
F3 截图 SHALL 直接保存到收藏目录（不走 AI 解析），island 显示「已收藏」轻提示。

#### Scenario: 收藏一张截图
- **WHEN** F3 截图完成
- **THEN** 文件落盘 `~/Library/Application Support/MiniNotch/favorites/`，compact 态短暂高亮

### Requirement: 识图截图保留与关联
F2 截图与剪贴板贴图走 AI 解析链路（区别于 F3 直存收藏）时，原图 SHALL 落盘保留到 `Persistence.screenshotsDir`（`~/Library/Application Support/MiniNotch/screenshots/`），其路径 SHALL 写入解析出的 `TodoDraft.screenshotPath`，并经 `toTodo()` 关联到最终创建的本地任务的 `Todo.screenshotPath`。卡片/任务详情 SHALL 提供查看原图入口；文件缺失时 SHALL 降级提示「原图已不可用」，不崩溃。

#### Scenario: 截图创建的任务关联原图
- **WHEN** F2 截图解析出一个任务并创建
- **THEN** 该任务的 `screenshotPath` 指向 `screenshots/` 下保留的原图，可在卡片中查看

#### Scenario: 贴图创建的项关联原图
- **WHEN** 在快速录入中 ⌘V 贴图并提交识别
- **THEN** 贴图保存为 `screenshots/...-paste.png`，创建项的 `screenshotPath` 指向该文件

#### Scenario: 原图文件缺失降级
- **WHEN** `screenshotPath` 指向的文件已被删除
- **THEN** 查看入口提示「原图已不可用」，应用不崩溃

