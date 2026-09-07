# ChatterBat — Status

## Last completed stage

**Stage 0 — Buildable native foundation.** Complete.

## What's implemented

- XcodeGen-based project (`project.yml`) generating `ChatterBat.xcodeproj`
  with a shared `ChatterBat` scheme covering the app, unit tests, and UI
  tests.
- macOS app target (`com.chatterbat.app`), deployment target macOS 14.0,
  Swift 6 language mode, App Sandbox entitlement with
  `com.apple.security.network.client` (outgoing network only — no
  provider calls exist yet to use it).
- SwiftUI split-view shell (`RootView` → `SidebarView` +
  `ConversationDetailView`) with:
  - Sidebar: search, New Chat (⌘N), context menu rename/delete, empty state.
  - Detail: placeholder transcript explaining what's not yet implemented,
    a disabled composer, and a toolbar button that opens a placeholder
    model-picker sheet (⌘K).
  - `ModelPickerPlaceholderView`: confirms the sheet/shortcut plumbing
    works; explicitly stands in for the real Stage 2 picker.
- Native `Settings` scene (⌘,) with a General pane showing app version and
  a note that account settings arrive in Stage 1.
- In-memory `Conversation` domain type and `DemoFixtures` — explicitly
  labeled as preview/demo-only in doc comments, not wired to any
  networking or persistence path.
- `AppViewModel` (`@Observable`, `@MainActor`) driving the shell: new
  chat, delete, rename, search filtering, selection.
- Unit tests (`ChatterBatTests`): 7 tests covering `AppViewModel`
  (selection defaults, new-chat insertion/selection, delete + selection
  reassignment, rename trimming/empty-guard, case-insensitive search
  filtering) and `Conversation`/`DemoFixtures` (identity-by-UUID, non-empty
  fixture sanity).
- UI test scaffold (`ChatterBatUITests`): one smoke test asserting the app
  launches and the "New Chat" control exists.
- `.gitignore` tuned for an XcodeGen-managed Xcode project (ignores
  `xcuserdata`, `DerivedData`, `.build`; deliberately does **not** ignore
  the generated `.xcodeproj` so the project is openable without requiring
  XcodeGen as a hard prerequisite for casual inspection).

## Build/test commands and actual results

Environment: macOS 26.6.2, Xcode 26.6, Swift 6.3.3 (swift-driver
1.148.6), Apple Silicon. XcodeGen 2.46.0 installed via Homebrew for this
task.

Generate the project (required after any `project.yml` change):
```
xcodegen generate
```
Result: succeeded — `Created project at .../ChatterBat.xcodeproj`.

Discover the scheme:
```
xcodebuild -list -project ChatterBat.xcodeproj
```
Result: Targets `ChatterBat`, `ChatterBatTests`, `ChatterBatUITests`;
Schemes: `ChatterBat`.

Build:
```
xcodebuild -project ChatterBat.xcodeproj -scheme ChatterBat \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/ChatterBatDerivedData build
```
Result: **BUILD SUCCEEDED** (ad hoc code signing; hardened runtime
disabled automatically for ad hoc signing, which is expected/correct for
local unsigned builds).

Unit tests only:
```
xcodebuild -project ChatterBat.xcodeproj -scheme ChatterBat \
  -destination 'platform=macOS' -derivedDataPath /tmp/ChatterBatDerivedData \
  -only-testing:ChatterBatTests test
```
Result: **TEST SUCCEEDED** — 7/7 tests passed
(`AppViewModelTests` × 5, `ConversationTests` × 2).

Full scheme test (`ChatterBatTests` + `ChatterBatUITests` together):
Result: **FAILS** at the `ChatterBatUITests` load step only. Unit tests
still ran and passed in the same invocation before the UI test bundle
failed to load.

## Manual verification performed

- Launched the built `.app` directly (`open .../ChatterBat.app`);
  confirmed via `pgrep` that the process started and stayed running, and
  cleanly quit via AppleScript (`tell application "ChatterBat" to quit`)
  with the process gone afterward. This confirms the app launches and
  terminates normally end to end, not just that it compiles.
- Did **not** get a visual screenshot: `screencapture` failed with
  "could not create image from display" in this non-interactive shell
  environment (no Screen Recording permission granted to the invoking
  process). Layout correctness (split view, sidebar list, composer,
  toolbar button placement) has **not** been visually confirmed — only
  structurally implemented and unit-tested. Recommend a manual visual
  pass in Xcode's own Run/Preview before Stage 1 sign-off, or granting
  Screen Recording permission to whatever process runs these tools.

## Known limitations

1. **XCUITest target fails to load via `xcodebuild test` in this
   environment.** Root cause confirmed via `codesign -dvvv`: with
   automatic signing and no Xcode-managed developer account configured
   non-interactively, the UI test runner and its `.xctest` bundle both
   end up ad hoc-signed with `TeamIdentifier=not set`, and the OS
   `dlopen` rejects loading it with a "different Team IDs" mapping error.
   I attempted to force `DEVELOPMENT_TEAM = 9YQ3NRVHZX` (the one valid
   local codesigning identity, `Apple Development: Jeremy Decarrier`) —
   this then failed with "No Account for Team… Add a new account in
   Accounts settings," confirming `xcodebuild` needs an Xcode
   Accounts-signed-in session to provision automatically, which isn't
   available non-interactively here. Reverted to plain ad hoc signing
   (no `DEVELOPMENT_TEAM` override) since that's what correctly builds
   and runs the app target itself. **Action for a human with Xcode UI
   access:** sign in under Xcode → Settings → Accounts, then either let
   Xcode auto-provision or run UI tests directly from within Xcode
   (⌘U with the ChatterBat scheme).
2. No visual/screenshot confirmation of the UI layout (see above).
3. Everything is in-memory/demo data by design at this stage — no
   persistence, no networking, no credentials. This is expected for
   Stage 0 and is not a defect.

## Next small task

Begin Stage 1: Venice/OpenRouter account settings UI backed by a Keychain
service abstraction, with add/replace/remove flows and non-billable
connection verification where the provider API supports it. See
`docs/DEVELOPMENT_PLAN.md` and the original brief §7–8 and §11 (Stage 1).
