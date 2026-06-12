# island-shell (delta)

## ADDED Requirements

### Requirement: Jira 新分配通知卡
轮询发现新分配的 Jira ticket 且 island 处于 compact 态时，island SHALL 弹出通知卡展示 ticket（key/标题/优先级/状态），无需用户操作，倒计时（约 5s）结束后 SHALL 播放「收入灵动岛」动效并回落 compact 态；悬停 SHALL 暂停倒计时；点击卡片 SHALL 跳转浏览器打开 ticket。

#### Scenario: 新 ticket 弹卡并自动收回
- **WHEN** 轮询合并发现新 jiraKey 且当前为 compact 态
- **THEN** 通知卡浮起（蓝色 Touchdown 涟漪），5s 倒计时进度条走完后内容缩入岛体、岛体弹簧回缩，compact 计数已 +1

#### Scenario: 悬停暂停
- **WHEN** 倒计时期间鼠标悬停卡片
- **THEN** 倒计时暂停，移开后继续

#### Scenario: 不打断当前操作
- **WHEN** 新 ticket 到达时用户正在展开态/其他卡片态
- **THEN** 不弹卡，ticket 静默入库（涟漪仍播放）

#### Scenario: 首轮同步静默
- **WHEN** 应用启动后第一次 Jira 同步
- **THEN** 不弹通知卡（避免把初始全量当成新分配）
