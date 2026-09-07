# ChatterBat — Status

## Last completed stage

**Stage 2 — Catalog and unified model picker.** Complete.

## Stage 2 — what's implemented

- Domain types: `ModelIdentity` (service + modelID, the only true model
  identity per the brief), `CapabilitySupport` (supported/unsupported/
  unknown — a missing provider field always maps to `.unknown`, never
  `.unsupported`), `ModelPricing` (USD per 1,000,000 tokens, `nil` means
  unknown — never displayed as free/zero), `ModelInfo` (the normalized,
  picker-facing model description), `CatalogLoadState` (per-service
  loading/loaded/failed state that keeps previously-cached models visible
  through a failed refresh).
- `ModelCatalogFetching` protocol + one fetcher per service, both using
  `JSONSerialization`-based lenient decoding (`ModelCatalogDecoding`) so
  one malformed catalog entry is skipped rather than discarding the whole
  list:
  - `VeniceModelCatalogFetcher` → `GET /models?type=text` (the documented
    filter for chat/text models —
    `https://docs.venice.ai/api-reference/endpoint/models/list`). Venice
    already reports pricing in USD per 1,000,000 tokens
    (`https://docs.venice.ai/overview/pricing`, "Prices per 1M tokens
    unless noted"), so no unit conversion is applied.
  - `OpenRouterModelCatalogFetcher` → `GET /models` (defaults to
    text-output models per
    `https://openrouter.ai/docs/guides/overview/models`). OpenRouter
    reports `pricing.prompt`/`completion` as a numeric *string* in USD
    per single token (e.g. `"0.00003"`); this fetcher multiplies by
    1,000,000 to normalize into `ModelPricing`'s convention.
  - Both map 401/403 → `.invalidCredential`, decode failure/unexpected
    status → `.unrecognizedResponse`, transport errors →
    `.transportFailure`. Test coverage includes a fixture built directly
    from Venice's own documented example object, so drift from that
    exact shape would be caught.
- `ModelPreferencesStore` protocol + `UserDefaultsModelPreferencesStore`:
  favorites (`Set<ModelIdentity>`) and recents (capped at 10, most-recent
  first), stored as plain non-secret settings — never in Keychain, and
  never conflated with API keys.
- `ModelPickerViewModel`: per-service `CatalogLoadState`, `loadAllConfiguredCatalogs()`
  (skips any service with no stored key — zero network calls for
  unconnected services), `refresh(_:)` (keeps last-successful models
  visible through a failure), search/service-filter/favorites-only
  filtering via `filteredModels`, `recentModels` resolved against
  currently-known catalog entries, `toggleFavorite`, `recordSelection`.
- Real `ModelPickerView` + `ModelRow` + `ModelPickerServiceFilter`,
  replacing `ModelPickerPlaceholderView` (deleted this stage): search
  field, All/Venice/OpenRouter segmented filter, Favorites-only toggle,
  Recent/per-service sections, service badge, secondary model-ID line,
  context length, price (or "Price unknown" — never "Free"), Tools/
  Reasoning/Vision badges shown only when actually `.supported`, Venice
  privacy label when present, and a star toggle. Selecting a row only
  calls `onSelect` and dismisses — it does not send any chat request.
- `AppViewModel.selectedModel` now holds the chosen `ModelInfo`;
  `ConversationDetailView`'s toolbar button shows "Select Model" until a
  choice is made, then shows "`<name>` · `<service>`".
- `AppDependencies` extended with both catalog fetchers and the
  preferences store; `makeModelPickerViewModel()` wires the real
  implementations. `RootView`/`SettingsView` previews updated with
  additional preview-only fakes (never touching real Keychain/UserDefaults
  /network).
- New test doubles: `FakeModelCatalogFetcher`, `InMemoryModelPreferencesStore`.
- New tests: `VeniceModelCatalogFetcherTests` (6, including the
  documented-example-shape regression test),
  `OpenRouterModelCatalogFetcherTests` (7), `ModelPickerViewModelTests`
  (7 — covering not-configured/no-fetch, successful load, failed-refresh
  cache retention, service+search filtering, same-name-different-service
  non-merging, favorites, recents), `UserDefaultsModelPreferencesStoreTests`
  (5 — using an isolated, randomly-named `UserDefaults` suite removed in
  `tearDown`, the same isolation pattern as the Stage 1 Keychain tests).

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
Result (Stage 2, current): **TEST SUCCEEDED** — 60/60 tests passed across
11 suites: `AccountSettingsViewModelTests` (8), `AppViewModelTests` (5),
`ConversationTests` (2), `KeychainCredentialStoreTests` (7),
`ModelPickerViewModelTests` (7), `OpenRouterConnectionCheckerTests` (8),
`OpenRouterModelCatalogFetcherTests` (7), `UserDefaultsModelPreferencesStoreTests`
(5), `VeniceConnectionCheckerTests` (5), `VeniceModelCatalogFetcherTests` (6).
Verified via `xcodebuild ... test | grep "Test Suite"` that every suite
actually started and passed (i.e. the two suites touching real OS state —
`KeychainCredentialStoreTests` and `UserDefaultsModelPreferencesStoreTests`
— were not silently skipped).

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
- Stage 2: rebuilt and launched the app again after wiring the real
  model picker into `RootView`/`ConversationDetailView`; confirmed via
  `pgrep` it started with no crash, then terminated it (`kill`, since an
  AppleEvent `quit` timed out this run — see limitation 6). Did not click
  ⌘K interactively for the same reason as Stage 1 (no UI automation
  available here), so the picker's actual on-screen behavior (search,
  segmented filter, favorites star, sheet sizing) is implemented and
  unit-tested but not eyeballed.
- Confirmed no stray state from this stage's tests either: no
  `com.chatterbat.app.apikeys` Keychain item, and `defaults read
  com.chatterbat.app.favoriteModelIdentities` (the real-app UserDefaults
  key) reports the domain doesn't exist — confirming
  `UserDefaultsModelPreferencesStoreTests`' isolated per-test suite name
  never touched real app preferences.
- Did **not** get a visual screenshot: `screencapture` failed with
  "could not create image from display" in this non-interactive shell
  environment (no Screen Recording permission granted to the invoking
  process). Layout correctness (split view, sidebar list, composer,
  toolbar button placement, Accounts tab, model picker sheet) has **not**
  been visually confirmed — only structurally implemented and
  unit-tested. Recommend a manual visual pass in Xcode's own Run/Preview,
  or granting Screen Recording permission to whatever process runs these
  tools.

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
5. Persistence (SwiftData) and chat itself are still entirely
   unimplemented — expected before Stage 3/4, not a defect.
6. **Catalog fetchers have not been exercised against the real
   Venice/OpenRouter `/models` endpoints with a live key**, for the same
   reason as limitation 3 (tests must never call live endpoints). Fixture
   coverage includes a test built directly from Venice's own published
   example object, which reduces but does not eliminate the risk of
   drift. **Action for a human:** open the model picker (⌘K) with a real
   key connected in Settings → Accounts and confirm models load with
   sensible names/pricing/context values.
7. One `osascript ... quit` call during manual verification timed out
   with an AppleEvent error (-1712) rather than quitting the app; the
   process was instead stopped with a plain `kill` (SIGTERM). This looks
   like an environment/AppleEvent quirk (the app may have still been
   finishing SwiftUI scene setup) rather than an app hang, but it was not
   root-caused further since it did not block verification. Worth
   rechecking if it recurs in Stage 3+ manual passes.
8. `ModelPickerView`'s empty/loading/error states were written to cover
   the documented state combinations (`.notConfigured` for all,
   `.loading` for any, otherwise show the first error) but have only been
   exercised via `ModelPickerViewModelTests` against the view *model* —
   not the view itself, since no UI test/screenshot tooling is available
   here (see limitation 2/5 pattern above).

## Next small task

Begin Stage 3: reliable streaming chat — request assembly, a robust SSE
parser (fragmented chunks, split UTF-8, CRLF/LF, comments/keep-alives,
usage-only frames, HTTP-200-carried errors), a chat coordinator/state
machine, Stop/Retry, per-message service/model attribution, and
cross-service history disclosure when switching services mid-conversation.
This is the first stage that actually sends `POST /chat/completions` to
either provider. See `docs/DEVELOPMENT_PLAN.md` and the original brief §7
(Streaming, Errors and retries) and §11 (Stage 3).
