# integrations (delta)

## ADDED Requirements

### Requirement: GitHub PR 拉取与通知
`GitHubService` SHALL 通过 GitHub Search API 拉取待我 review（`review-requested:@me`）与指派给我（`assignee:@me`）的 open PR，按 PR URL 去重，映射为只读 todo（source=github，key=`repo#123`，作者作指派人，draft 降为低优先级）。同步 SHALL 复用外部镜像合并（按 github 来源清理），新 PR 且 compact 态 SHALL 弹通知卡（GitHub 紫）。Token 未配置时 SHALL 回退 Mock。

#### Scenario: 新 PR 请求我 review
- **WHEN** 同事在 PR 上 request 我 review，下一轮轮询后
- **THEN** 通知卡浮起（「新 PR 待处理」+ 作者 + repo#编号），倒计时后收入岛体，「今日任务」出现该 PR 行

#### Scenario: PR 合并或移除 review 请求
- **WHEN** PR 关闭/合并/取消 review 请求
- **THEN** 下一轮同步后该行消失（镜像清理，不影响 Jira 来源）

#### Scenario: 点击 PR 行
- **WHEN** 点击 PR 行任意位置
- **THEN** 浏览器打开 PR 页面（只读集成，不提供完成圈）
