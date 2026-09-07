# ChatterBat — Status

## Last completed stage

**Stage 1 — Secure account connection.** Complete.

## Stage 1 — what's implemented

- `AIService` enum (`.venice`, `.openRouter`) with display name, pinned
  API host, and the exact official key-management URL for each
  (`https://venice.ai/settings/api`, `https://openrouter.ai/settings/keys`).
- `CredentialStore` protocol + `KeychainCredentialStore` (Security
  framework, generic password items scoped by a fixed `service` string and
  per-`AIService` `account`, `.whenUnlockedThisDeviceOnly` accessibility,
  no iCloud sync). Save/replace/delete/missing-item are all handled
  explicitly; empty/whitespace-only keys are rejected before ever reaching
  Keychain.
- `HTTPClient` protocol + `URLSessionHTTPClient`: ephemeral session
  (no disk cache, no cookie storage) and a redirect-blocking delegate that
  refuses to follow any redirect to a host other than the one the client
  was pinned to, so an `Authorization` header can never leak to another
  host.
- `ConnectionChecking` protocol + one implementation per service, each
  calling a **non-billable, key-authenticating** endpoint (verified against
  current provider docs, not assumed):
  - `VeniceConnectionChecker` → `GET /api_keys/rate_limits`
    (`https://docs.venice.ai/api-reference/endpoint/api_keys/rate_limits`).
  - `OpenRouterConnectionChecker` → `GET /api/v1/key`
    (`https://openrouter.ai/docs/api-reference/limits`).
  Both map 401/403 → `.invalidCredential`, decode-failure/unexpected status
  → `.unrecognizedResponse`, transport errors → `.transportFailure`, and
  build a short, non-sensitive summary string from only the fields meant
  for that purpose (credit/balance/tier) — never the raw body.
- `AccountSettingsViewModel`: per-service `ConnectionState`
  (notConfigured / checking / connected(summary) / invalidCredential /
  error(message)), `saveAndVerify`, `verifyConnection`, `disconnect`, and
  `refreshStoredKeyPresence` (which honestly reports "saved, not yet
  verified" for a key that exists in Keychain from a prior session rather
  than claiming it's connected or silently re-checking it over the network
  on every launch).
- `AccountsSettingsView`: one card per service — status row, `SecureField`
  key entry, Save & Verify / Re-verify / Disconnect, a link to the
  service's real key-management page, and an explanatory note that this
  connects the user's *existing* account rather than creating a
  ChatterBat-operated one. No base-URL field. Added as a new "Accounts"
  tab in the Settings scene (General tab kept, now points to Accounts).
- `AppDependencies`: a small factory (not a DI container) that assembles
  the real `KeychainCredentialStore` + both `URLSessionHTTPClient`-backed
  checkers for the running app; constructed once in `ChatterBatApp` and
  passed into `SettingsView`. Tests and previews never use this — they
  construct view models directly with fakes/in-memory doubles.
- Test doubles added under `ChatterBatTests/Fakes/`:
  `InMemoryCredentialStore`, `FakeConnectionChecker`, `FakeHTTPClient`
  (+ `FakeTransportError`). None of these touch the real Keychain or
  network.
- New tests: `AccountSettingsViewModelTests` (8), and provider-checker
  request/response-mapping tests: `OpenRouterConnectionCheckerTests` (8),
  `VeniceConnectionCheckerTests` (5) — all using `FakeHTTPClient`, so zero
  real network calls. `KeychainCredentialStoreTests` (7) is the one suite
  that touches the real Keychain, using a randomized per-test-run
  namespace and deleting everything it wrote in `tearDown`.

## Stage 0 — what's implemented (carried forward)

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
Result (Stage 1, current): **TEST SUCCEEDED** — 35/35 tests passed across
6 suites: `AccountSettingsViewModelTests` (8), `AppViewModelTests` (5),
`ConversationTests` (2), `KeychainCredentialStoreTests` (7),
`OpenRouterConnectionCheckerTests` (8), `VeniceConnectionCheckerTests` (5).
Verified via `xcodebuild ... test | grep "Test Suite"` that every suite
actually started and passed (i.e. `KeychainCredentialStoreTests` — the one
suite touching the real Keychain — was not silently skipped).

Full scheme test (`ChatterBatTests` + `ChatterBatUITests` together):
Result: still **FAILS** at the `ChatterBatUITests` load step only (same
root cause as Stage 0, unchanged by this stage's work — see Known
Limitations). Unit tests still ran and passed in the same invocation
before the UI test bundle failed to load.

## Manual verification performed

- Stage 0: launched the built `.app` directly (`open .../ChatterBat.app`);
  confirmed via `pgrep` that the process started and stayed running, and
  cleanly quit via AppleScript (`tell application "ChatterBat" to quit`)
  with the process gone afterward.
- Stage 1: re-launched the rebuilt `.app` after adding the Accounts tab;
  confirmed via `pgrep` it started successfully with no crash, then
  terminated the instance this session launched. Did **not** click
  through the Accounts UI interactively (no Screen Recording / UI
  automation available in this shell — see limitation below), so the
  *visual* correctness of the new Settings tab (layout, SecureField,
  button states) is implemented and unit-tested but not eyeballed.
- Confirmed no stray Keychain items after the full test run:
  `security find-generic-password -s com.chatterbat.app.apikeys` reports
  "item could not be found" (expected — no real key was ever saved
  through the UI in this session), and a scan for any
  `com.chatterbat.tests.*` namespace found zero leftovers, confirming
  `KeychainCredentialStoreTests`' per-test cleanup worked.
- Did **not** get a visual screenshot: `screencapture` failed with
  "could not create image from display" in this non-interactive shell
  environment (no Screen Recording permission granted to the invoking
  process). Layout correctness (split view, sidebar list, composer,
  toolbar button placement, new Accounts tab) has **not** been visually
  confirmed — only structurally implemented and unit-tested. Recommend a
  manual visual pass in Xcode's own Run/Preview, or granting Screen
  Recording permission to whatever process runs these tools.

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
3. **Connection verification has not been exercised against the real
   Venice/OpenRouter APIs with a live key.** Per the testing contract,
   automated tests must never call paid or even non-billable live
   endpoints, so `VeniceConnectionChecker`/`OpenRouterConnectionChecker`
   are only verified against `FakeHTTPClient` fixtures matching the
   *documented* response shapes for `GET /api_keys/rate_limits` and
   `GET /api/v1/key`. If either provider's actual response shape has
   drifted from current docs (retrieved during this stage — see
   `docs/DEVELOPMENT_PLAN.md` for the exact doc URLs), the decode could
   fail in practice even though it's correct against the documented
   schema. **Action for a human:** paste a real key into Settings →
   Accounts once and confirm "Save & Verify" shows a sensible connected
   summary (this is intentionally a manual, explicitly-consented step —
   not something this task should do automatically with a real credential).
4. `AccountSettingsViewModel.refreshStoredKeyPresence()` does not
   automatically re-verify a previously-saved-and-verified key on every
   app launch (it only checks *presence*, reporting "saved, not yet
   verified" until the user re-verifies or saves again). This is a
   deliberate choice (see DECISIONS.md) to avoid a hidden network call on
   every launch, but means the connected/green state does not persist
   across relaunches by itself — only the underlying key does.
5. Persistence (SwiftData), catalogs, and chat itself are still entirely
   unimplemented — expected for Stage 1, not a defect.

## Next small task

Begin Stage 2: Venice/OpenRouter model catalog integration and the
unified searchable model picker (replacing `ModelPickerPlaceholderView`),
built on top of the now-real credential/connection layer from Stage 1.
See `docs/DEVELOPMENT_PLAN.md` and the original brief §7 and §11 (Stage 2).
