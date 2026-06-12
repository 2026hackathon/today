# 角色报告 Prompt 库

> 来源：[today-analysis.md](../today-analysis.md) 3.2 节——报告的正确形态 = 同一套数据 × 角色模板 × 一键去处。
> 晨报 = **规划**（面板渲染，回答"今天怎么打"）；日报 = **交差**（一键复制，格式是收件人期待的格式）。

## 文件清单

| 角色 | 晨报 | 日报（去处） |
|---|---|---|
| 开发 | dev-morning-promt.md | dev-daily-promt.md（站会发言 → Slack/群） |
| 测试 | qa-morning-promt.md | qa-daily-promt.md（测试日报 → 群/邮件） |
| 需求分析 | ba-morning-promt.md | ba-daily-promt.md（需求速报 → 干系人群） |
| 技术 Leader | tl-morning-promt.md | tl-daily-promt.md（组内日报 → 上级/组群） |
| 项目经理 | pm-morning-promt.md | pm-daily-promt.md（一页纸状态 → 老板/干系人） |

## 上下文拼装约定（程序侧职责）

所有 prompt 的 user 消息由以下区块按需拼接（缺哪块就不拼哪块，prompt 已约定缺块输出"无"）：

```
【当前时间】yyyy-MM-dd HH:mm EEEE
【编号任务清单】          ← IndexedContext：[N] 标题 | 优先级 | 截止 | 来源 | 状态
【今日会议】              ← HH:mm–HH:mm 标题（平台）参与者
【昨日完成 / 今日完成】   ← 完成的 todo + 流转的票 + merge 的 PR
【Jira 事件】             ← 状态流转/重开/滞留事件（来自 Lens notifyOn，含时间）
【聚合数据】              ← aggregate 订阅结果：分组计数、滞留清单、燃尽数字
【等待中】                ← waitingOn 任务：等谁 · 等了几天
【明日会议】              ← 日报推荐"明早第一件事"时避开会议用
```

## 全局约束（每份 prompt 末尾都内嵌，此处为出处）

1. **防幻觉**：只引用上下文中明确列出的任务/票号/人名/数字；引用任务用编号 [N]；缺数据的小节输出"无"，禁止硬凑
2. **字数纪律**：晨报整体 ≤25 行；日报按各自模板上限；单行 ≤40 字
3. **时间格式**：一律 HH:mm；日期只在跨天时出现
4. **措辞红线**：对他人只描述"事的状态"（"MD-1024 在张三处停 4 天"），不做绩效化表述
5. **输出纯净**：只输出正文，不要代码块包裹、不要解释自己

## 接入方式

替换 `AIService.generateMorningReport / generateEveningReport` 的 instruction 段，
按 `settings` 中的角色配置选择模板（角色可叠加时取主角色）。Mock 实现各备一份固定输出兜底。
