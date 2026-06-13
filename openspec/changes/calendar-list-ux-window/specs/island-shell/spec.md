## ADDED Requirements

### Requirement: 确认弹窗打开时抑制自动收起
当应用内有确认弹窗（如删除苹果日程/提醒的二次确认）打开时，island SHALL 抑制悬停移出触发的自动收起，直到弹窗关闭；其余收起途径（esc / 失焦）不受影响。AppStore SHALL 暴露一个可观察的弹窗态标志，由展示确认弹窗的视图在打开/关闭时置位，`IslandRootView` 的悬停移出收起判定 SHALL 读取该标志。

#### Scenario: 弹窗打开时移出不收起
- **WHEN** 用户在日历页签点删除一个苹果日程，二次确认弹窗弹出，鼠标移向弹窗上的「删除」按钮（途中离开 island 悬停区）
- **THEN** island 不自动收起，弹窗保持可见，用户可点到「删除」或「取消」

#### Scenario: 弹窗关闭后恢复正常收起
- **WHEN** 确认弹窗被「删除」或「取消」关闭后，鼠标移出 island
- **THEN** 悬停移出自动收起恢复生效，0.2s 后回落 compact 态
