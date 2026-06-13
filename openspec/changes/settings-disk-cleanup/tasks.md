## 1. Data model & service contract

- [x] 1.1 Define `DiskEntry` (name, path, sizeBytes, human-readable size) and `CleanupTier` (green/yellow/red) types
- [x] 1.2 Define `ClassifiedEntry` (entry + tier + rationale) and `DiskCapacity` (total/used/free) types
- [x] 1.3 Define `@MainActor protocol DiskCleanupService` with `scan() async throws -> ScanResult` (capacity + entries + inaccessiblePaths), `classify([DiskEntry]) async -> DiskClassification` (entries + aiUnavailable), and `trash(_ entry) throws`

## 2. Scanning (read-only)

- [x] 2.1 Implement `RealDiskCleanupService.scan()` running `du -sk` via `Process` off the main actor (`DiskScanner` in a detached task) for home, `/Applications`, `~/Library` (Caches/Containers/Application Support), `~/Downloads`, and dev caches (Xcode DerivedData, CoreSimulator, npm, cargo, pip/uv, docker, go)
- [x] 2.2 Apply size thresholds (≥100 MB home/apps, ≥50 MB library/downloads/dev) and cap to top N (40) per group, sorted by size desc; dedup across groups
- [x] 2.3 Read disk capacity (total/free → used) for display
- [x] 2.4 Skip unreadable paths (Full Disk Access denied), collect them into `inaccessiblePaths`, never throw fatally

## 3. AI-driven classification

- [x] 3.1 Build a classification prompt (added `classifyStorageItems` to `AIService`) that sends only size/path of entries and requests strict JSON (path → tier + one-line rationale)
- [x] 3.2 Wire `RealDiskCleanupService.classify()` to call the injected `AIService.classifyStorageItems` and tolerant-parse the JSON keyed by path
- [x] 3.3 Implement rule-based fallback classifier `StorageRules` (known caches/temp → green, downloads/projects → yellow, apps/system → red); default unmatched to yellow
- [x] 3.4 Use the fallback when no AI key is set or when the AI call fails/returns unparseable output, surfacing a non-blocking notice (`diskAIUnavailable`)
- [x] 3.5 ~~Implement `MockDiskCleanupService`~~ **Refined:** scanning needs no credentials, so `RealDiskCleanupService` is used always; the no-key/demo path is `MockAIService.classifyStorageItems` throwing → `StorageRules` rule-based fallback. A separate fake-data mock service was unnecessary (avoided dead code)

## 4. Cleanup (move to Trash)

- [x] 4.1 Implement `trash(_ entry)` via `FileManager.default.trashItem(at:resultingItemURL:)`; surface per-item failures without aborting (`diskActionError`)

## 5. State & wiring

- [x] 5.1 Add scan state to `AppStore` (`DiskScanStatus` idle/scanning/classifying/done/failed, classified results, capacity, reclaimedBytes, inaccessiblePaths, aiUnavailable, actionError) as `@Published`
- [x] 5.2 Add `AppStore` methods: `runDiskScan()` (scan → classify → publish) and `trashDiskEntry(_:)` (trash → update capacity/reclaimed/results)
- [x] 5.3 Add `currentDiskCleanupService()` factory in `AppDelegate` (real wrapping `currentAIService()`) and wire `store.diskCleanupServiceProvider` into `wireServices()`. **Refined:** always Real (scan needs no creds); no-key handled by AI-classify throwing → rule fallback

## 6. Settings UI

- [x] 6.1 Add `diskCleanupSection` to `SettingsPanel.swift` and append it after `reminderSection` in the section `VStack`
- [x] 6.2 Idle state: show disk capacity summary + "扫描磁盘" button
- [x] 6.3 Scanning/classifying state: show progress indicator; render inaccessible-paths and AI-unavailable notices when present
- [x] 6.4 Results: group items by 🟢/🟡/🔴 tier with size, path, and rationale (`DiskEntryRow`)
- [x] 6.5 Per-item action: 🟢/🟡 "移到废纸篓" with a confirmation dialog; 🔴 items are reveal-only ("在 Finder 中显示" via `NSWorkspace`, no delete button) — aligned to the storage-analyzer skill. 🟡/🔴 also render handling suggestions
- [x] 6.6 After cleanup, reflect updated reclaimed space and disk capacity in the UI

## 7. Verification

- [x] 7.1 Build the app (`swift build`) and confirm no errors
- [ ] 7.2 Manually verify: scan populates tiers, no-key path uses rule fallback, confirmed green item moves to Trash and updates capacity, red item shows extra warning, denied path shows notice without crashing
