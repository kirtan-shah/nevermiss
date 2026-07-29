# NeverMiss — Agent Guidelines

macOS menu bar app that alerts users about upcoming calendar meetings. Syncs Google Calendar (REST API, OAuth 2.0 + PKCE) and native macOS calendars (EventKit). Shows fullscreen/overlay/cover-screen alerts with one-click join, snooze, and dismiss.

## Project Structure

```
NeverMiss/
  App/           AppDelegate (launch window, notifications), AppState
  Models/        SwiftData models (CalendarEvent, SyncMetadata), value types (AlertConfiguration, GoogleAccount)
  Services/
    Calendar/    CalendarSyncManager, EventKitService, GoogleAuthService, GoogleCalendarService
    Scheduling/  MeetingScheduler (timer-based alerts + system notifications)
    Storage/     SettingsManager (UserDefaults), KeychainService (actor), TokenManager (actor)
  Utilities/     Date+Extensions, MeetingURLParser
  Views/
    Alerts/      AlertContentView, AlertWindowController (AppKit), BannerAlertView, FullScreenAlertView
    MenuBar/     MenuBarView (status bar popover)
    Onboarding/  OnboardingView (3-step first-run)
    Settings/    General, Accounts, Alerts, Calendars tabs + SettingsView container
    LaunchView   Launch window (Open Preferences + menu bar toggle)
  NeverMissApp.swift  @main entry: MenuBarExtra, Settings, keepalive Window scenes
```

## Build Configuration

- **macOS 15.7** deployment target (Sequoia)
- Swift 6 strict concurrency: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- **Zero external dependencies** — pure Apple frameworks
- `LSUIElement = true` — no Dock icon, menu bar agent app
- Xcode auto-discovers files via `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits needed when adding files

## Release and Deployment Checklist

A production release is externally visible. Do not create or push a release tag, publish a GitHub Release, or replace an existing tag unless the user explicitly authorizes the release and version.

### 1. Verify the release commit

1. Confirm all intended release changes are committed; a tag never includes uncommitted work.
2. Preserve unrelated user changes. Do not stash, reset, or discard them to prepare a release.
3. Confirm the release commit is the intended `main` commit:

```bash
git status --short
git switch main
git pull --ff-only
git log -1 --oneline
```

4. Push the intended release commit to `origin/main`, then confirm local `HEAD` and `origin/main` are exactly the same commit. A tag must not point to code that is absent from `main`, because the later appcast workflow checks out `main`:

```bash
git push origin main
git fetch origin
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

5. Confirm the version tag does not already exist locally or on the remote.

### 2. Run preflight verification

The current GitHub CI and Release workflows build the app but do **not** run tests. Run the unit tests and a CI-equivalent unsigned universal Release build before tagging:

```bash
NEVERMISS_USE_IN_MEMORY_KEYCHAIN=1 xcodebuild -project NeverMiss.xcodeproj \
  -scheme NeverMiss \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/NeverMissDerivedData \
  -skipPackageUpdates \
  -only-testing:NeverMissTests \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  test

xcodebuild -scheme NeverMiss \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /private/tmp/NeverMissReleaseDerivedData \
  -skipPackageUpdates \
  ARCHS='arm64 x86_64' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The test command uses ad-hoc signing, and XCTest uses an in-memory Keychain store. It does not access the developer signing key or real Google credentials. Use this command instead of Xcode's normal signed test action when a prompt-free run is required.

### 3. Trigger the production release

`.github/workflows/release.yml` runs when a `v*` tag is **pushed**. An annotated tag is preferred because it records release metadata:

```bash
git tag -a v1.0.6 -m "NeverMiss 1.0.6"
git push origin v1.0.6
```

A lightweight tag also works:

```bash
git tag v1.0.6
git push origin v1.0.6
```

Running `git tag v1.0.6` by itself only creates a local tag; CI starts after `git push origin v1.0.6`.

The Release workflow derives `MARKETING_VERSION` from the tag, creates a timestamp build number, archives an `arm64`/`x86_64` app, Developer ID-signs it, creates a DMG, notarizes and staples it, verifies Gatekeeper/signature/architectures, uploads the DMG artifact, and creates a **draft** GitHub Release.

Required GitHub Actions secrets:

- `APPLE_ID`
- `APPLE_APP_PASSWORD`
- `SIGNING_CERTIFICATE_P12`
- `SIGNING_CERTIFICATE_PASSWORD`
- `TEAM_ID`
- `SPARKLE_PRIVATE_KEY`

### 4. Publish and verify distribution

1. Wait for the Release workflow to succeed.
2. Review the generated notes and DMG on the draft GitHub Release.
3. Manually publish the draft when approved. Publishing a non-prerelease triggers `.github/workflows/appcast.yml`.
4. Verify the appcast workflow generated and signed `appcast.xml`, committed it to `main`, and triggered `deploy-website.yml`.
5. Verify the website download points to the latest published DMG and test Sparkle update discovery from an older build.
6. Upload/update the Ko-fi distribution manually; the current workflows do not do this.

For a safe rehearsal, manually dispatch the Release workflow with a throwaway version and `dry_run=true`. It still builds, signs, notarizes, verifies, and uploads a workflow artifact, but it does not create a GitHub Release.

### Release gotchas

- CI runs only for pull requests and pushes to non-`main` branches; it is not a test gate for a tag release.
- Publishing the draft—not merely pushing the tag—makes the release visible and starts the Sparkle appcast update.
- The appcast workflow pushes directly to `main`; branch protection must allow `github-actions[bot]` to do so.
- The Release workflow currently passes `MACOSX_DEPLOYMENT_TARGET=15.0`. Verify that this matches the intended project deployment target before releasing; do not silently change OS compatibility as part of a release.
- Do not move or reuse a published version tag. Fix forward with a new version unless the user explicitly requests otherwise.

## Architecture

**Singletons everywhere.** All services use `static let shared`. Views access them directly — no dependency injection, no `@EnvironmentObject`.

**Hybrid SwiftUI + AppKit.** SwiftUI handles declarative UI (settings, alerts, menu bar). AppKit handles window lifecycle (launch window via `NSHostingController`, alert windows via `NSWindow`/`NSPanel`) because SwiftUI's `Window` scene doesn't auto-open alongside `MenuBarExtra`.

**Concurrency model:**
- `@Observable @MainActor` — UI-driving services: SettingsManager, CalendarSyncManager, GoogleAuthService, EventKitService, MeetingScheduler, AppState, AlertWindowController
- `actor` — Thread-safe services with no UI: GoogleCalendarService, TokenManager, KeychainService

## State Management Patterns

### Service classes use `@Observable`

```swift
@Observable
@MainActor
final class SomeService {
    static let shared = SomeService()

    var uiDrivingProperty = false                          // tracked automatically
    @ObservationIgnored private var timer: Timer?          // not tracked
    @ObservationIgnored private let otherService = Other.shared  // not tracked

    private init() { }
}
```

- Plain `var` properties are automatically tracked — no `@Published` needed
- Mark non-UI stored properties with `@ObservationIgnored` (timers, service refs, cancellables, infrastructure)
- `let` constants don't need `@ObservationIgnored` (they can't change)

### Views access singletons directly

```swift
// Read-only access — use let
struct SomeView: View {
    let settings = SettingsManager.shared

    var body: some View {
        Text(settings.someValue)  // automatically observed
    }
}

// Binding access — use @Bindable (when you need $property for Toggle, Picker, etc.)
struct SettingsFormView: View {
    @Bindable var settings = SettingsManager.shared

    var body: some View {
        Toggle("Enable", isOn: $settings.someFlag)
    }
}
```

### NeverMissApp entry point

```swift
@Bindable var settings = SettingsManager.shared  // for $settings.showMenuBarIcon binding
let syncManager = CalendarSyncManager.shared      // read-only in body
```

`@Bindable` in the App struct is required for `MenuBarExtra(isInserted: $settings.showMenuBarIcon)`.

## Critical Gotchas

### MenuBarExtra binding bounce
`MenuBarExtra(isInserted:)` writes back to its binding during scene lifecycle. A toggle in the Settings scene that drives this binding will bounce back to `true`. The menu bar toggle lives in **LaunchView** (AppKit-hosted, outside scene graph), writes directly to UserDefaults (not the observed property), and requires app relaunch. Do not move this toggle into a SwiftUI scene.

### Settings scene window sizing
The `Settings` scene uses `.windowResizability(.contentSize)` to lock the window to the `TabView`'s fixed `.frame(width: 500, height: 400)`. Without this modifier, macOS resizes the settings window per-tab, causing tab bar icons to squeeze/stretch during transitions.

### SwiftUI Window scene + MenuBarExtra
SwiftUI's `Window` scene does not auto-open when `MenuBarExtra` is present. The launch window is created via `AppDelegate` + `NSHostingController`. A hidden keepalive `Window` scene (`.defaultLaunchBehavior(.suppressed)`) prevents early termination.

### @Observable + NSObject
`GoogleAuthService` inherits from `NSObject` for `ASWebAuthenticationPresentationContextProviding`. `@Observable` is compatible with NSObject subclasses — apply it normally.

### CalendarSyncManager Combine usage
`CalendarSyncManager` uses `NotificationCenter.default.publisher(for:).debounce().sink()` for two observers (calendar data changes + selected calendar changes). This is the Combine NotificationCenter bridge, not `@Published` publishers. `import Combine` is still needed for this pattern.

When `SettingsManager.selectedCalendarIds` changes, it posts `.selectedCalendarIdsChanged` notification (with an `oldValue` guard to avoid redundant posts). CalendarSyncManager debounces this before syncing. The same pattern is used for `syncInterval` (posts `.syncIntervalChanged`, CalendarSyncManager restarts its periodic timer).

### UserDefaults domain
Bundle ID: `codes.maker.NeverMiss`. Reset with: `defaults delete codes.maker.NeverMiss`

### SettingsLink
Only sanctioned way to open the Settings scene. Works inside `NSHostingController`-hosted views. Do not use `NSApp.sendAction(Selector(("showSettingsWindow:")))`.

## Common Recipes

### Add a new setting
1. Add case to `SettingsManager.Key` enum
2. Add `var` with `didSet` that persists to UserDefaults
3. Initialize in `SettingsManager.init()`
4. Add UI in the appropriate settings tab — use `@Bindable var settings` if bindings needed

### Add a new view
1. Create struct in appropriate `Views/` subdirectory
2. Access singletons with `let service = Service.shared` or `@Bindable var service = Service.shared`
3. Use `@State private var` for view-local state only

### Add a new service
1. Create `@Observable @MainActor final class` with `static let shared` and `private init()`
2. Use `@ObservationIgnored` for internal infrastructure
3. For network-only services with no UI, prefer `actor` over `@Observable @MainActor`

### Add a new calendar source
1. Create service in `Services/Calendar/`
2. Add case to `CalendarSource` in `AlertConfiguration.swift`
3. Add sync logic in `CalendarSyncManager.performSync()`
4. Add connection UI in `AccountsSettingsView`

### Add a new meeting platform
1. Add case to `MeetingPlatform` in `MeetingURLParser.swift`
2. Add URL patterns to `meetingPatterns`
3. Add domain to `EventKitService.extractMeetingLink()` keyword list

## Coding Conventions

- `foregroundStyle()` not `foregroundColor()` (deprecated)
- `onChange(of:) { _, newValue in }` (two-parameter closure)
- `Tab("Title", systemImage: "icon", value: .tab) { View() }` not `tabItem { Label(...) }.tag(...)` (deprecated)
- Extract complex view sections into separate `struct` views, not `@ViewBuilder` computed properties
- Keep `@MainActor` explicit on `@Observable` classes even though `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `@Observable` goes before `@MainActor`: `@Observable @MainActor final class ...`
- All `@State` properties must be `private`
- Use `Binding(get:set:)` for array element toggles (see `AlertSettingsView` pattern)
