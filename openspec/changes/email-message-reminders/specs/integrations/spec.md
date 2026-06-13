## ADDED Requirements

### Requirement: EmailService 协议
框架 SHALL 定义 `EmailService.fetchNewMessages() -> [Message]`；真实现轮询周期 60s（与 Jira 对齐）；拉取结果经 `AppStore.addMessages(_:)` 按 `Message-ID` 去重合并。新消息到达 SHALL 触发降落通知卡（见 island-shell）。

#### Scenario: 轮询拉取新消息
- **WHEN** 轮询发现新的邮件（新 Message-ID）
- **THEN** 对应 Message 入库并触发降落通知卡

### Requirement: MockEmailService 数据联调
框架 SHALL 内置 `MockEmailService`，返回 3 条演示消息（slack / jira / 普通邮件各一，各带对应来源链接），保证「消息」页签与降落卡可独立开发、无需真实邮箱。

#### Scenario: 无凭证启动可演示
- **WHEN** 未配置任何邮件凭据
- **THEN** 「消息」页签仍有 3 条演示消息可看，降落卡可演示

### Requirement: Email 真实拉取与装配降级
`RealEmailService` SHALL 通过 IMAP + 应用密码登录 `settings.emailImapHost`，拉取近 N 封未读邮件并转为 Message。装配 SHALL 动态选择：`emailImapHost`/`emailAddress`/`emailAppPassword` 三项齐全时用 Real，任一为空回退 Mock，设置变更下个轮询周期生效。请求失败（鉴权/网络/非 2xx）SHALL 本轮静默跳过（日志记录），保留上次数据，不弹错误 UI。

#### Scenario: 配置齐全拉取真实邮件
- **WHEN** 设置面板填好邮箱地址/IMAP 主机/应用密码且凭据有效
- **THEN** 60s 内「消息」页签出现真实邮件生成的消息

#### Scenario: 拉取失败静默降级
- **WHEN** IMAP 鉴权失败或网络异常
- **THEN** 本轮静默跳过、列表保持上次数据、不弹错误 UI

#### Scenario: 清空配置回退 Mock
- **WHEN** 用户清空任一邮件配置项
- **THEN** 下个轮询周期起回到 Mock 演示数据
