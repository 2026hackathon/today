## 1. Data model & service contract

- [ ] 1.1 Define `DiskEntry` (name, path, sizeBytes, human-readable size) and `CleanupTier` (green/yellow/red) types
- [ ] 1.2 Define `ClassifiedEntry` (entry + tier + rationale) and `DiskCapacity` (total/used/free) types
- [ ] 1.3 Define `@MainActor protocol DiskCleanupService` with `scan() async throws -> (capacity, [DiskEntry], inaccessiblePaths)`, `classify([DiskEntry]) async -> [ClassifiedEntry]`, and `trash(_ entry) throws`

## 2. Scanning (read-only)

- [ ] 2.1 Implement `RealDiskCleanupService.scan()` running `du -sk` via `Process` off the main actor for home, `/Applications`, `~/Library` (Caches/Containers/Application Support), `~/Downloads`, and dev caches (Xcode DerivedData, CoreSimulator, npm, cargo, pip/uv, docker, go)
- [ ] 2.2 Apply size thresholds (≥100 MB home/apps, ≥50 MB library/downloads/dev) and cap to top N (~40) per group, sorted by size desc
- [ ] 2.3 Read disk capacity (total/used/free) for display
- [ ] 2.4 Skip unreadable paths (Full Disk Access denied), collect them into `inaccessiblePaths`, never throw fatally

## 3. AI-driven classification

- [ ] 3.1 Build a classification prompt that sends only name/path/size of entries and requests strict JSON (path → tier + one-line rationale)
- [ ] 3.2 Wire `RealDiskCleanupService.classify()` to call the injected `AIService` and tolerant-parse the JSON keyed by path
- [ ] 3.3 Implement rule-based fallback classifier (known caches/temp → green, downloads/projects → yellow, apps/system → red); default unmatched to yellow
- [ ] 3.4 Use the fallback when no AI key is set or when the AI call fails/returns unparseable output, surfacing a non-blocking notice
- [ ] 3.5 Implement `MockDiskCleanupService` (static sample entries + rule-based classification) for the no-key/demo path

## 4. Cleanup (move to Trash)

- [ ] 4.1 Implement `trash(_ entry)` via `FileManager.default.trashItem(at:resultingItemURL:)`; surface per-item failures without aborting

## 5. State & wiring

- [ ] 5.1 Add scan state to `AppStore` (status: idle/scanning/classifying/done/error, classified results, capacity, reclaimedBytes) as `@Published`
- [ ] 5.2 Add `AppStore` methods: `runDiskScan()` (scan → classify → publish) and `trashEntry(_:)` (trash → update capacity/reclaimed/results)
- [ ] 5.3 Add `DiskCleanupService` instance + `currentDiskCleanupService()` factory in `AppDelegate` (real wrapping `currentAIService()`, else mock) and wire into `wireServices()`

## 6. Settings UI

- [ ] 6.1 Add `diskCleanupSection` to `SettingsPanel.swift` and append it after `reminderSection` in the section `VStack`
- [ ] 6.2 Idle state: show disk capacity summary + "扫描" button
- [ ] 6.3 Scanning/classifying state: show progress indicator; render inaccessible-paths and AI-unavailable notices when present
- [ ] 6.4 Results: group items by 🟢/🟡/🔴 tier with size, path, and rationale, using `SettingsRow` components
- [ ] 6.5 Per-item "移到废纸篓" action with a confirmation dialog; 🔴 items require a second-stage warning
- [ ] 6.6 After cleanup, reflect updated reclaimed space and disk capacity in the UI

## 7. Verification

- [ ] 7.1 Build the app (`swift build` / project build) and confirm no errors
- [ ] 7.2 Manually verify: scan populates tiers, no-key path uses rule fallback, confirmed green item moves to Trash and updates capacity, red item shows extra warning, denied path shows notice without crashing
