## ADDED Requirements

### Requirement: Disk cleanup section in Settings

The system SHALL present a "磁盘清理" (Disk Cleanup) section as the final section of the Settings panel, below the existing Reminders & Appearance section.

#### Scenario: Section visible and last

- **WHEN** the user opens the Settings panel and scrolls to the bottom
- **THEN** a "磁盘清理" section is rendered after all existing sections, built from the existing `SettingsSection`/`SettingsRow` components

#### Scenario: Idle state before scanning

- **WHEN** no scan has been run yet
- **THEN** the section shows a "扫描" (Scan) action and no result list

### Requirement: Read-only disk scan

The system SHALL scan disk usage read-only, mirroring the storage-analyzer skill's scope, without modifying or deleting any file during the scan.

#### Scenario: Scan enumerates space consumers

- **WHEN** the user triggers a scan
- **THEN** the system enumerates immediate children of the home directory, `/Applications`, `~/Library` (Caches, Containers, Application Support), `~/Downloads`, and developer caches (Xcode `DerivedData`, `CoreSimulator`, npm, cargo, pip/uv, docker, go) using `du -sk`
- **AND** returns entries above a size threshold (≥100 MB for home/apps, ≥50 MB for library/downloads/dev caches), each with name, absolute path, and byte size

#### Scenario: Scan reports overall disk capacity

- **WHEN** a scan completes
- **THEN** the system reports total, used, and free disk capacity for display

#### Scenario: Inaccessible path is skipped, not fatal

- **WHEN** a target path cannot be read (e.g. macOS Full Disk Access not granted)
- **THEN** the system skips that path, continues scanning the rest, and surfaces a non-blocking notice that some locations were inaccessible

### Requirement: AI-driven safety classification

The system SHALL classify scanned space consumers into three safety tiers using the app's AI model: 🟢 green (pure cache/temp/installer remnants, regenerable without data loss), 🟡 yellow (contains user data or a judgment call), 🔴 red (clearable but not recommended). Each classified item SHALL carry a one-line rationale. To stay faithful to the storage-analyzer skill, 🟡 yellow items SHALL additionally carry at least three concrete disposal suggestions (how to confirm contents, where to move/keep, and a risk note), and 🔴 red items SHALL carry safe-handling suggestions (e.g. how to uninstall properly) rather than deletion advice.

#### Scenario: Classification via AI model

- **WHEN** a scan completes and an AI API key is configured
- **THEN** the system sends the scan entries to the AI model with a classification prompt and groups the returned items by tier with their rationales

#### Scenario: Yellow and red items carry handling suggestions

- **WHEN** classification produces 🟡 yellow or 🔴 red items
- **THEN** each such item is displayed with actionable handling suggestions (yellow: ≥3 disposal options with a risk note; red: safe-removal guidance), via the AI model when available or the rule-based fallback otherwise

#### Scenario: Fallback without AI key

- **WHEN** no AI API key is configured
- **THEN** the system classifies items using built-in rules (known cache/temp paths → green, downloads/project folders → yellow, applications/system → red) and proceeds without error

#### Scenario: AI failure falls back gracefully

- **WHEN** the AI request fails or returns unparseable output
- **THEN** the system falls back to rule-based classification and surfaces a non-blocking notice that AI classification was unavailable

### Requirement: Move-to-Trash cleanup with confirmation

The system SHALL only reclaim space by moving selected items to the Trash via `FileManager.trashItem`, never by permanent deletion and never automatically. Cleanup SHALL require explicit per-item user confirmation. To stay faithful to the storage-analyzer skill, 🔴 red items SHALL NOT offer a deletion/Trash action; instead they SHALL offer a "reveal in Finder" action so the user can inspect or uninstall them manually.

#### Scenario: Confirmed cleanup of a green item

- **WHEN** the user selects a 🟢 green item and confirms cleanup
- **THEN** the system moves that item to the Trash and updates the displayed reclaimed space and disk capacity

#### Scenario: Red item is reveal-only, not deletable

- **WHEN** the disk cleanup results include a 🔴 red item
- **THEN** that item offers only a "reveal in Finder" action and provides no Trash/delete button
- **AND** activating it opens Finder with the item selected, without removing anything

#### Scenario: No item is removed without confirmation

- **WHEN** a scan and classification have completed
- **THEN** no file is moved or deleted until the user explicitly confirms cleanup of a specific item

#### Scenario: Trash failure is reported

- **WHEN** moving an item to the Trash fails
- **THEN** the system reports the failure for that item and leaves it untouched, without aborting the rest of the session
