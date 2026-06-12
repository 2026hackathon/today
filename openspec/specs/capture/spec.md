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

