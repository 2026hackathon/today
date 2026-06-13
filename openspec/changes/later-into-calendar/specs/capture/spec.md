## ADDED Requirements

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
