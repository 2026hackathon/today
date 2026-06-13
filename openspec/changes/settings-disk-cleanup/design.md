## Context

MiniNotch is a non-sandboxed SwiftUI/AppStore macOS app (SwiftPM, no `.entitlements`). State lives in `AppStore` (`@Published` + `didSet` persistence); services follow a `XyzService` protocol with `MockXyzService` / `RealXyzService` implementations, instantiated and selected in `AppDelegate` via factory methods (e.g. `currentAIService()` returns `OpenAIChatAIService` when an API key is set, else `MockAIService`). The Settings UI (`UI/Panels/SettingsPanel.swift`) composes section view-builders in a `VStack`, using reusable `SettingsSection`/`SettingsRow` components.

The `storage-analyzer` skill (Python + Claude) scans with `du -sk`, has Claude classify space hogs into green/yellow/red tiers, and offers reversible move-to-Trash cleanup. We are reimplementing that concept natively, reusing MiniNotch's AI service for the classification step.

## Goals / Non-Goals

**Goals:**
- A Disk Cleanup section at the bottom of Settings that scans (read-only), classifies via the AI model, and cleans by moving to Trash.
- Full-disk scan scope mirroring the skill (home, `/Applications`, `~/Library`, `~/Downloads`, dev caches).
- Reuse the existing AI service path for classification; rule-based fallback when no key.
- Reversible, confirmation-gated cleanup only.

**Non-Goals:**
- Generating an HTML report or running a local web server (the skill's `build_report.py`/`server.py`) — results render natively in-panel.
- Permanent deletion or any auto-cleanup.
- Continuous/background disk monitoring — scans are user-initiated.
- Cleaning other users' data or requiring elevated privileges.

## Decisions

- **Scanning via `du -sk` through `Process`** (not a Swift recursive walk). Rationale: matches the skill exactly, is fast and battle-tested, and avoids reimplementing size aggregation. Alternative (FileManager recursive enumeration) is slower and error-prone on large trees.
- **`DiskCleanupService` protocol + `RealDiskCleanupService` + `MockDiskCleanupService`**, matching the codebase pattern. `AppDelegate.currentDiskCleanupService()` injects the real one (wrapping `currentAIService()` for classification) and falls back to mock-style rule classification when no AI key. Rationale: consistency, testability, demo-friendly.
- **Classification reuses `AIService`** with a dedicated prompt asking for strict JSON output (item path → tier + rationale). Rationale: the user explicitly asked for the LLM-prompt approach; reusing the existing service avoids new dependencies. A rule-based classifier provides deterministic fallback and parses-failure recovery.
- **State on `AppStore`**: scan status (idle/scanning/classifying/done/error), the tiered results, disk capacity, and reclaimed-space total — `@Published` so the panel reacts. Any persisted preference (e.g. last-known result is *not* persisted; it is recomputed per scan to avoid stale paths). Minimal `AppSettings` additions only if a user preference is needed.
- **Cleanup via `FileManager.default.trashItem(at:resultingItemURL:)`**, per item, gated by a SwiftUI confirmation dialog; 🔴 items get a second-stage warning. Rationale: reversible, OS-native, matches the skill's safety principle.

## Risks / Trade-offs

- **Full Disk Access (TCC) not granted** → some `~/Library` paths return permission errors. Mitigation: skip inaccessible paths, continue, and show a non-blocking notice; do not crash.
- **`du` on a huge home directory is slow / blocks** → Mitigation: run off the main actor (async `Process`), show a scanning indicator, cap results (top N per group like the skill's 40), and rely on the size threshold to prune.
- **AI returns malformed/partial JSON** → Mitigation: tolerant parsing keyed by path; any unclassified item defaults to 🟡 yellow (conservative) or rule-based fallback.
- **User trashes something important** → Mitigation: confirmation per item, extra warning for 🔴, Trash (reversible) only, clear rationale shown before action.
- **Large free-text sent to AI** → Mitigation: send only name/path/size of the top entries, not file contents; keep the payload bounded.

## Migration Plan

Additive feature; no data migration. New `AppSettings` fields (if any) decode with defaults via the existing backward-compatible `init(from:)`. Rollback = remove the section from the `VStack` and the new service file; no persisted schema break.

## Open Questions

- Should the most recent scan result be cached across app launches, or always re-scanned on open? (Current decision: always re-scan to avoid stale paths.)
- Final size thresholds and top-N caps — start with the skill's values (100 MB / 50 MB, top 40) and tune if results are noisy.
