## ADDED Requirements

### Requirement: 今日任务展示会议标签与加入链接

Today 列表中 `.calendar` 来源的任务，若其对应会议（按 `Todo.calendarEventId` 匹配 `Meeting.eventIdentifier`）已检测到会议平台（`Meeting.platform`），任务行 SHALL 展示该平台标签（如「Zoom」「腾讯会议」）。若该会议带有加入链接（`Meeting.link`），任务行 SHALL 额外提供一键「加入会议」入口以打开该链接。

匹配 SHALL 优雅降级：当 `.calendar` 任务找不到对应会议、或对应会议无平台/无链接（如提醒事项、全天事件、无链接日程）时，任务行 SHALL 与现状完全一致渲染，不显示空标签或失效按钮。平台与链接 SHALL 复用既有提取结果（`CalendarService.extractMeetingLink`），本需求不改变日历同步与链接提取行为。

#### Scenario: 带平台与链接的日程在今日任务显示会议标签与加入入口

- **WHEN** 今天 14:00 的日历事件「评审会」notes 含 Zoom 链接，已同步为 `.calendar` 任务并出现在「今日任务」
- **THEN** 该任务行展示「Zoom」会议标签
- **AND** 该任务行提供「加入会议」入口，点击后打开该 Zoom 链接

#### Scenario: 仅有平台无链接时只显示标签

- **WHEN** 某 `.calendar` 任务对应会议检测到平台但 `Meeting.link` 为空
- **THEN** 任务行展示平台标签
- **AND** 任务行 SHALL NOT 显示「加入会议」入口

#### Scenario: 非会议的日历任务保持原样

- **WHEN** 一个 `.calendar` 来源任务对应的是提醒事项或无可识别平台的事件
- **THEN** 任务行不展示会议标签与加入入口，与未改动前的渲染一致

#### Scenario: 会议尚未同步或无 calendarEventId 时不报错

- **WHEN** 某 `.calendar` 任务的 `calendarEventId` 缺失，或对应会议尚未出现在已加载的 meetings 列表中
- **THEN** 行内会议查找返回空，任务行按现状渲染，不出现空标签
