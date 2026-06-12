# todo-data (delta)

## ADDED Requirements

### Requirement: 超期锚点与解码兼容
任务的超期判定 SHALL 以 `snoozedUntil ?? dueDate` 为锚（snooze 到未来 → 不超期、回「今日任务」分组）；`Todo` 的持久化解码 SHALL 对缺失字段取默认值（向后兼容），新增模型字段不得导致历史 todos.json 解码失败。

#### Scenario: 超期任务 snooze 到今天下午
- **WHEN** 已超期任务被 snooze 到今天 15:00
- **THEN** 它离开「已超期」进入「今日任务」（按 15:00 排序），15:00 过后才重新计为超期

#### Scenario: 升级后打开旧数据
- **WHEN** 新版本给 Todo 增加了字段，用户用旧 todos.json 启动
- **THEN** 数据全部加载成功，新字段取默认值
