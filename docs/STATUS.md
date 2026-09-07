# ChatterBat — Status

## Last completed stage

**Stage 3 — Reliable streaming chat.** Complete.

## Stage 3 — what's implemented

- Domain types: `ChatRole`/`OutgoingChatMessage` (minimal request-body
  shape), `ChatUsage` (all fields optional — missing is unknown, never
  zero), `TranscriptMessage`/`MessageStatus` (streaming/completed/
  cancelled/failed/interrupted, matching the brief's generation-state
  list) with `isEligibleForContext` encoding the brief's context-
  eligibility rules (exclude failed-empty assistant messages; cancelled
  partial output is excluded by default, not silently sent as complete).
- `SSEParser`: incremental, byte-level Server-Sent-Events parser.
  Verified via 12 dedicated tests to correctly handle: arbitrary
  fragmentation across multiple `feed()` calls, a multi-byte UTF-8
  character (é) deliberately split mid-character across two feeds,
  LF and CRLF line endings, multiple `data:` lines joined per the SSE
  spec, comment/keep-alive lines (`: ...`) being skipped rather than
  passed to JSON parsing, multiple complete events in one feed, and
  other SSE fields (`id:`, `event:`) not disrupting parsing.
- `ChatStreamDecoder`: decodes one SSE payload into a `ChatStreamEvent`
  (contentDelta/finished/usage/streamError/ignorable). Returns `nil` for
  `"[DONE]"` and invalid JSON rather than crashing. Content is checked
  before `finish_reason` so trailing content in a chunk that also
  carries a finish reason isn't dropped. Mid-stream errors (HTTP 200
  carrying a top-level `error` + `finish_reason: "error"`, exact shape
  verified against
  `https://openrouter.ai/docs/api-reference/streaming`) are surfaced as
  `.streamError`, including when it's the first and only event.
- `StreamingHTTPClient`/`URLSessionStreamingHTTPClient`: chunked-response
  transport (`URLSession.bytes(for:)`), same ephemeral/no-cache/
  cross-host-redirect-blocking policy as the Stage 1 buffered client.
  Cancelling the consuming task cancels the underlying network task.
- `ChatRequestBuilder`: builds the OpenAI-compatible request body
  (`model`, `messages`, `stream: true`,
  `stream_options.include_usage: true`) — verified as accepted by both
  services' documented request schemas (Venice's documented example
  request body includes `stream_options.include_usage`; OpenRouter's SDK
  example reads `chunk.usage` off the final chunk). No provider-specific
  fields (`venice_parameters`, OpenRouter `provider` routing) are sent
  yet — deferred to Stage 6.
- `ChatRequestError`: user-actionable error classification
  (invalidCredential/insufficientCredit/rateLimited/modelUnavailable/
  contextOverflow/unsupportedParameter/offlineOrTimeout/providerFailure/
  malformedResponse/streamError/prematureDisconnect), with
  `.from(httpStatus:providerMessage:)` mapping documented status codes
  (401/402/403/404/429/502/503, plus a context-overflow heuristic on
  400) to these cases.
- `ChatStreamingClient`/`StandardChatStreamingClient`: shared streaming
  implementation for both services (justified in DECISIONS.md — unlike
  catalog/connection-check decoding, the actual OpenAI-compatible chunk
  *shape* really is the same for plain text chat on both providers).
  Handles: pre-stream HTTP errors (buffered JSON body, mapped via
  `ChatRequestError.from`), mid-stream errors (thrown as
  `.streamError`), and premature disconnect (stream ends with no
  `finished`/`usage` event ever observed → `.prematureDisconnect`).
- `GenerationState` (idle/connecting/streaming, single global slot per
  the brief) and `ChatCoordinator`: owns in-memory transcripts keyed by
  conversation ID, `send`/`stopGeneration`/`retryLastTurn`,
  `wouldShareHistoryAcrossServices` (cross-service disclosure — only
  true once a message actually exists in that conversation, never
  merely from opening the picker), and per-(conversationID,
  messageID)-scoped updates so a stale/superseded stream can never
  mutate the wrong conversation's transcript. Retry removes the failed
  assistant message and re-sends the same prior user turn without
  duplicating it.
- Real chat UI: `TranscriptView`/`MessageBubble` (plain-text, per-message
  service/model attribution, status badges, usage display that only
  shows fields the provider actually reported), `ComposerView`
  (Send/Stop, disabled while generating), `ConversationDetailView`
  wired to `ChatCoordinator` with a cross-service-disclosure alert
  before sending when applicable. The toolbar's model-picker button
  (real since Stage 2) is now also disabled while generating in that
  conversation.
- `AppDependencies` extended with both `ChatStreamingClient`s and one
  shared, app-lifetime `ChatCoordinator` instance (not per-view, since
  it owns the single global generation slot).
- New test doubles: `FakeStreamingHTTPClient`, `FakeChatStreamingClient`.
- New tests (39 total): `SSEParserTests` (12), `ChatStreamDecoderTests`
  (10), `StandardChatStreamingClientTests` (8 — including the exact
  documented mid-stream-error shape and a manually-fragmented-mid-event
  byte split), `ChatCoordinatorTests` (4) + `ChatCoordinatorAdditionalTests`
  (5) covering: happy path, no-stored-key immediate failure without
  calling the client, a second send while generating being rejected,
  Stop preserving partial content as `.cancelled`, failure→retry without
  duplicating the user turn, full isolation between two conversation
  IDs, cross-service disclosure only after a real message exists, and a
  cancelled message's content being excluded from the next request's
  context.

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
Result (Stage 3, current): **TEST SUCCEEDED** — 99/99 tests passed across
17 suites (see Stage 3 section above for the 5 new suites; carried-forward
suites from Stages 0–2 all still pass unchanged). Verified via
`xcodebuild ... test | grep "Test Suite"` that every suite actually
started and passed, and re-ran the full suite **3 times in a row** to
check for flakiness in the timing-sensitive `ChatCoordinator` tests
(cancellation races) — all 3 runs passed with 99/99.

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
- Stage 3: rebuilt and launched the app again after wiring
  `ChatCoordinator`/real chat into `ConversationDetailView`; confirmed
  via `pgrep` it started successfully with no crash, then terminated it
  with `kill` (SIGTERM). Confirmed again afterward that no
  `com.chatterbat.app.apikeys` Keychain item exists. Did **not** click
  Send interactively or exercise a live chat completion — no UI
  automation and no real API key are available in this environment (see
  limitations below). The full streaming pipeline (SSE parsing,
  chunk decoding, error mapping, cancellation, cross-conversation
  isolation, cross-service disclosure, retry) is exercised end-to-end
  by `ChatCoordinatorTests`/`ChatCoordinatorAdditionalTests`/
  `StandardChatStreamingClientTests` against fakes, run 3 times
  consecutively with no flakiness — but never against a real provider.

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
5. Persistence (SwiftData) is still entirely unimplemented — everything
   in `ChatCoordinator`/`AppViewModel` is in-memory only and is lost on
   quit. Expected before Stage 4, not a defect.
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
9. **No real chat completion has ever been sent to Venice or
   OpenRouter.** This is the most significant unverified area of Stage
   3: `StandardChatStreamingClient` is tested against fixtures matching
   the documented SSE/chunk shapes for both providers, and
   `ChatRequestBuilder` sends only fields verified against each
   provider's documented request schema, but neither has been confirmed
   against a live response. In particular: (a) whether Venice's actual
   streamed chunks match the exact OpenAI-compatible shape assumed here
   when `stream_options.include_usage` is set; (b) whether OpenRouter
   reliably includes a usage frame in every case, not just the SDK
   example shown in its docs; (c) real latency/behavior of Stop actually
   halting provider-side billing, which the brief says isn't guaranteed
   anyway. **Action for a human:** connect a real key, send a short
   message on each service, and confirm: text streams in visibly,
   Stop actually halts new text within roughly a second, and a
   deliberately-triggered error (e.g. an invalid model ID typed into a
   future settings override, or simply exhausting credit) surfaces a
   sensible message rather than a crash.
10. Composer Return-to-send behavior is unverified interactively (see
    `ComposerView`'s doc comment) — SwiftUI's `TextField(axis: .vertical)`
    is known in some OS versions to treat Return as a newline rather
    than firing `onSubmit`. ⌘Return is wired as a guaranteed fallback,
    but plain Return should be manually confirmed on the target macOS
    version. Input-method (IME) marked-text behavior during composition
    was likewise not tested.
11. `retryLastTurn` only handles the single most common case (last
    message is a failed assistant reply preceded by the matching user
    turn). It intentionally does nothing (silently) if the transcript
    shape doesn't match that exact pattern, rather than guessing —
    covered by the guard clauses in `ChatCoordinator.retryLastTurn`, but
    there is no dedicated test for the "does nothing when the shape is
    unexpected" case specifically; only the standard success path is
    tested.

## Next small task

Begin Stage 4: durable conversation history — a SwiftData schema and
repository, wiring `AppViewModel`/`ChatCoordinator` to persist
conversations/messages/favorites instead of holding them only in memory,
rename/delete/search against real storage, generation checkpoints so a
relaunch marks any still-`.streaming` message `.interrupted` (not lost or
silently resumed), and persistence tests using an isolated/in-memory
SwiftData store. See `docs/DEVELOPMENT_PLAN.md` and the original brief §8
(Persistence and security) and §11 (Stage 4).
