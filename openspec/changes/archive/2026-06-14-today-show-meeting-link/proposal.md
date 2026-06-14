## Why

Calendar events already merge into Today as `.calendar` tasks, and the app already extracts each meeting's platform (Zoom/Tencent/Meet/Teams/Feishu/DingTalk) and join URL onto the separate `Meeting` model. But the Today task row only shows a generic「日程/提醒」kind badge — it never surfaces that a task *is a meeting*, nor offers a way to join. Users have to switch to the Calendar tab to find the link, defeating the purpose of an at-a-glance Today view.

## What Changes

- Today task rows for `.calendar` tasks that correspond to a meeting with a detected platform SHALL show a meeting tag (the platform label, e.g.「Zoom」/「腾讯会议」).
- When the corresponding meeting has a join link, the Today row SHALL offer a one-click「加入会议」affordance that opens the link.
- A `.calendar` task is matched to its meeting by `calendarEventId` ↔ `Meeting.eventIdentifier`; rows with no matching meeting or no detected platform/link render unchanged (no empty badge).
- Reuse the existing platform extraction (`CalendarService.extractMeetingLink`) and tag/join UI already used by `MeetingRow` — no new extraction logic, no new design language.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `todo-data`: add a requirement that `.calendar` Today tasks expose their source meeting's platform tag and join link in the task row (display behavior on the existing 三大分组 / 日历同步 task data).

## Impact

- `MiniNotch/Sources/MiniNotch/UI/Panels/TodayPanel.swift` — `PersonalTodoRow` gains an optional meeting tag + join affordance for `.calendar` rows.
- `AppStore` — a lookup helper to resolve a `Todo`'s meeting by `calendarEventId` (or, per design, carry platform/link on the merged `.calendar` Todo).
- No persistence migration if implemented via render-time lookup; if carried on `Todo`, additive `decodeIfPresent` fields only (backward compatible).
- Reuses existing `Meeting.platform` / `Meeting.link` and `extractMeetingLink` — no calendar-sync behavior change.
