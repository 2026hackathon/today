## Why

Users have no way to understand or reclaim disk space from within MiniNotch, and macOS gives little visibility into what is hoarding storage (caches, dev artifacts, downloads). Inspired by the `storage-analyzer` skill, we add a disk-cleanup tool at the bottom of Settings that scans the disk, uses the AI model to classify space hogs by cleanup safety, and lets the user reclaim space by moving items to the Trash — safely and reversibly.

## What Changes

- Add a new **磁盘清理 (Disk Cleanup)** section as the last section of the Settings panel.
- Scan the disk read-only (full-disk scope, mirroring the original skill): home dir & `/Applications`, `~/Library` (Caches, Containers, Application Support), `~/Downloads`, and developer caches (Xcode `DerivedData`, `CoreSimulator`, npm, cargo, pip/uv, docker, go) using `du -sk`.
- Send the scan results to MiniNotch's existing AI model (the `AIService` / `OpenAIChatAIService` path) with a prompt that classifies each space hog into 🟢 green (safe regenerable cache), 🟡 yellow (user data / judgment call), 🔴 red (clearable but not recommended), with a one-line rationale and recommendation per item.
- Present results grouped by tier with human-readable sizes and overall disk capacity.
- Cleanup action = **move to Trash** via `FileManager.trashItem`, requiring explicit per-item user confirmation; never auto-execute, never permanent delete, never act on 🔴 items without an extra warning.
- Provide a graceful fallback (rule-based classification) when no AI API key is configured, consistent with the app's existing Mock-service pattern.

## Capabilities

### New Capabilities
- `disk-cleanup`: Read-only disk scanning, AI-driven safety classification of storage consumers, and reversible (move-to-Trash) cleanup surfaced in the Settings panel.

### Modified Capabilities
<!-- None: classification reuses the existing AI service path but introduces no new requirements on the ai-pipeline spec. -->

## Impact

- **New file**: `MiniNotch/Sources/MiniNotch/Services/DiskCleanupService.swift` (protocol + Real + Mock, following the existing service pattern).
- **UI**: `MiniNotch/Sources/MiniNotch/UI/Panels/SettingsPanel.swift` — new `diskCleanupSection` appended after `reminderSection`.
- **State**: `MiniNotch/Sources/MiniNotch/Core/AppStore.swift` / `Models.swift` — scan state, results, and any new `AppSettings` fields (auto-persisted).
- **Wiring**: `AppDelegate.swift` — service instantiation + factory selection (real vs. mock based on AI key), reusing `currentAIService()`.
- **System**: Uses `Process` (`du`) and `FileManager.trashItem`; relies on the app being non-sandboxed. Some paths may require macOS Full Disk Access (TCC) — surfaced gracefully when denied.
- No external dependencies added.
