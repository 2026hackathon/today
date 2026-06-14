## Context

`.calendar` Todos are produced by `AppStore.replaceMeetings` merging the day's `Meeting`s into the task list (`todo-data` spec,「日历与提醒同步为今日任务」). The merged `Todo` keeps only `title`/`dueDate`/`calendarEventId` — it drops the meeting's `platform` and `link`, which remain on the parallel `Meeting` value (`Models.swift`). `CalendarService.extractMeetingLink` already detects 6 platforms from event notes/location/URL. `MeetingRow` already renders a platform `dsTag()` and an「加入会议」button. `PersonalTodoRow` (`TodayPanel.swift`) renders the `.calendar` row today but shows no meeting info.

So the data and the UI vocabulary already exist; the gap is wiring the meeting's platform/link into the Today task row.

## Goals / Non-Goals

**Goals:**
- A `.calendar` Today row whose source meeting has a detected platform shows that platform as a tag.
- When the meeting has a join link, the row offers a one-click join affordance.
- Reuse existing extraction + tag/join visuals; no new design language.

**Non-Goals:**
- No change to calendar sync, extraction regexes, or platform list.
- No meeting badge for non-`.calendar` tasks (manual/screenshot todos are not meetings).
- No editing/joining of meetings that lack a link (e.g. reminders, all-day, link-less events) — those render exactly as today.

## Decisions

### Decision 1: Resolve meeting at render time via `calendarEventId`, do not carry link/platform on `Todo`

`Todo` already holds `calendarEventId`; `Meeting` holds `eventIdentifier`. Add an `AppStore` helper `meeting(for: Todo) -> Meeting?` that returns the meeting whose `eventIdentifier == todo.calendarEventId` (only for `.calendar` source). `PersonalTodoRow` calls it to obtain `platform`/`link`.

- **Why over carrying fields on `Todo`:** keeps `Meeting` the single source of truth for meeting metadata (no duplication that can drift across sync), needs no `todos.json` migration, and the lookup is a cheap in-memory match over the already-loaded meetings list.
- **Alternative considered — add `meetingURL`/`meetingPlatform` to `Todo`:** consistent with the additive `decodeIfPresent` pattern, but duplicates state that the merge would have to keep in sync every poll, and persists derived data. Rejected for drift risk and unnecessary persistence; the render-time lookup is simpler.

### Decision 2: Render the tag and join affordance by reusing `MeetingRow`'s vocabulary

Show the platform via the same `Text(platform.label).dsTag()` used in `MeetingRow`, placed alongside the existing kind/recurring tags in `PersonalTodoRow`. The join affordance reuses `MeetingRow`'s「加入会议」link/button behavior (open `meeting.link`). Gate strictly: tag shows only when `platform != nil`; join shows only when `link != nil`. No matching meeting → row is byte-for-byte unchanged.

- **Why:** visual consistency with the Calendar tab and zero new components.

## Risks / Trade-offs

- [Stale/missing match if `calendarEventId` is absent or meetings not yet synced] → lookup returns `nil`, row renders unchanged (graceful degradation, never an empty badge).
- [Row horizontal space is tight (title + time + tags + priority + thumbnail)] → platform tag is compact; join affordance follows the same hover/placement conventions as existing row controls to avoid crowding the resting layout.
- [A `.calendar` task can be a reminder, not a meeting] → reminders have no `platform`/`link`, so the gate naturally hides the affordances.

## Migration Plan

No data migration. Render-time only; rollback is reverting the `PersonalTodoRow` change and the `AppStore` helper.

## Open Questions

- Join affordance placement: always-visible compact icon vs hover-revealed button. Default to matching the existing row's hover-control convention unless the meeting tag warrants an always-visible quick-join.
