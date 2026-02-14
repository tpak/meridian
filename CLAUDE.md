# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## App Identity

**Meridian** (formerly Clocker) — macOS menu bar world clock app. Directory structure uses `Clocker/` on disk (renaming would break Xcode project refs). Bundle ID: `com.tpak.Meridian`. Forked from [Clocker](https://github.com/n0shake/Clocker) by Abhishek Banthia.

## Git Workflow

**Always create a feature branch before making changes.** Never commit directly to `main`. Use descriptive branch names like `fix/icloud-cache-bug` or `feature/accessibility-labels`. Open a PR when the work is ready for review. This applies to all work — bug fixes, features, refactors, doc updates.

## Build & Test Commands

```bash
# Build (Debug)
xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug build \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# Build + Static Analysis
xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug build analyze \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# All unit tests
xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug test \
  -only-testing:ClockerUnitTests -parallel-testing-enabled NO -disable-concurrent-destination-testing \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# Single test
xcodebuild -project Clocker/Clocker.xcodeproj -scheme Meridian -configuration Debug test \
  -only-testing:ClockerUnitTests/ClockerUnitTests/testTimeDifference -parallel-testing-enabled NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=

# Lint
swiftlint

# API key setup (required before building)
cp Clocker/Config/Keys.xcconfig.example Clocker/Config/Keys.xcconfig
```

**Critical**: Always use `-parallel-testing-enabled NO` for unit tests. Parallel runners crash with "exit code 0" on macOS 15 due to Launch Services failures.

## Architecture

### Data Flow

`DataStore` (singleton) → `TimezoneData` (model, NSSecureCoding) → `TimezoneDataOperations` (computed display values)

- **DataStore** (`Overall App/DataStore.swift`) — central state hub, stores timezone list in UserDefaults, syncs to iCloud via NSUbiquitousKeyValueStore. Protocol `DataStoring` enables test injection.
- **TimezoneData** (`CoreModelKit/Sources/CoreModelKit/TimezoneData.swift`) — core model persisted as Data blobs in UserDefaults. Holds timezone ID, coordinates, custom label, format overrides.
- **TimezoneDataOperations** (`Panel/Data Layer/TimezoneDataOperations.swift`) — takes a TimezoneData + slider offset, produces formatted time/date strings.

### UI Layers

**Menu bar panel** (main UI):
- `PanelController` → `ParentPanelController` (base class, manages table + slider + events)
- `TimezoneDataSource` drives the NSTableView of `TimezoneCellView` rows
- Modern slider scrubs ±48h; extensions in `ParentPanelController+ModernSlider.swift`

**Floating window** (alternative mode): `FloatingWindowController.shared()` — toggled via preferences.

**Preferences**: `PreferencesViewController` manages timezone list. Search/add logic extracted to `TimezoneAdditionHandler` and `TimezoneSearchService` (shared with onboarding, `@MainActor`, async/await).

### Network & APIs

- `NetworkManager` — async/await, Google Geocoding + Timezone APIs
- `TimezoneSearchService` — shared search client for preferences and onboarding
- `VersionUpdateHandler` — checks GitHub Releases API for updates (HTTPS-only)
- API key stored in gitignored `Clocker/Config/Keys.xcconfig` (build var `GEOCODING_API_KEY`)

### Calendar Integration

`EventCenter` (singleton) observes EventKit changes → `CalendarHandler` fetches upcoming events → displayed in `UpcomingEventsDataSource` collection view in the panel.

### SPM Packages (local, under `Clocker/`)

- **CoreLoggerKit** — OSLog wrapper
- **CoreModelKit** — TimezoneData model (depends on CoreLoggerKit)
- **StartupKit** — Login item management via SMLoginItemSetEnabled

### Vendored Dependencies (no package managers)

ShortcutRecorder, PTHotKey (Obj-C), DateTools, Solar (Swift). All in `Clocker/Dependencies/`.

## Key Files

| File | Role |
|------|------|
| `Panel/ParentPanelController.swift` | Main panel — largest UI file |
| `Preferences/General/PreferencesViewController.swift` | Timezone management |
| `Overall App/DataStore.swift` | Singleton state hub (150+ call sites) |
| `Overall App/Themer.swift` | Colors/fonts/images singleton |
| `Menu Bar/StatusItemHandler.swift` | NSStatusBar item management |
| `Clocker/Clocker-Info.plist` | App plist (ATS, permissions) |

## Test Notes

- Unit tests in `Clocker/ClockerUnitTests/` (~145 tests)
- `MockDataStore` available for DI; `MockURLProtocol` for network mocking
- UI tests back up/restore UserDefaults via pre/post actions
- Time-dependent tests (e.g., `EventInfoTests`) handle midnight-crossing edge cases

## SwiftLint Rules

Config in `.swiftlint.yml`. Key limits: line length 160/200, type body 300/600, function body 50/100, `force_cast` and `force_try` are errors. `Clocker/Dependencies/` and test directories are excluded.

## Analysis & TODO

Detailed analysis and prioritized TODO plan in `ANALYSIS_AND_TODO.md` (repo root, gitignored) and `memory/ANALYSIS_AND_TODO.md` (persistent). Keep both in sync.
