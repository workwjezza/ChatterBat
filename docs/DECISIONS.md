# ChatterBat — Decisions

Only meaningful, non-obvious decisions and their reasoning are recorded
here. Routine implementation choices are not logged.

## Stage 0

### Used XcodeGen instead of hand-authoring/hand-editing the .xcodeproj

**Decision:** Install XcodeGen (via Homebrew) and define the project in
`project.yml`, generating `ChatterBat.xcodeproj` from it.

**Why:** Hand-editing `project.pbxproj` is fragile, hard to diff/review,
and error-prone when adding targets/settings via scripted edits. XcodeGen
gives a small, readable, version-controllable spec that regenerates a
correct project deterministically. The generated `.xcodeproj` is committed
anyway (not gitignored) so the project remains directly openable in Xcode
without requiring XcodeGen as a hard runtime dependency — XcodeGen is only
needed when `project.yml` changes.

### Kept the generated .xcodeproj under version control

**Decision:** Do not add `ChatterBat.xcodeproj` to `.gitignore`.

**Why:** Some teams gitignore generated Xcode projects and require
`xcodegen generate` before every open. That adds friction for a solo
developer and for the next agent picking this up, who may not have
XcodeGen installed yet. Since XcodeGen output is deterministic and small,
committing it and regenerating only when `project.yml` changes is simpler.

### Left code signing on Automatic/ad hoc rather than a fixed team

**Decision:** Do not set `DEVELOPMENT_TEAM` in `project.yml`; let the app
target build with ad hoc signing.

**Why:** A valid local "Apple Development" codesigning identity exists in
Keychain, but `xcodebuild` refused to provision automatically without an
Xcode-managed signed-in developer account ("No Account for Team…"). Since
Stage 0 has no distribution requirement, ad hoc signing is sufficient and
correct — it's what a plain `xcodebuild build` produces by default, and it
lets the app build, launch, and run unit tests without requiring
interactive Xcode account setup. This is the direct cause of the
`ChatterBatUITests` load failure (see STATUS.md); fixing it requires
interactive Xcode access and is left as a documented manual step rather
than worked around with something that would misrepresent the actual
signing state.

### Kept demo/preview fixtures as a clearly separate, documented layer

**Decision:** `DemoFixtures` lives in `Domain/` with an explicit doc
comment stating it must never be wired into production networking or
persistence paths, rather than, e.g., quietly defaulting `AppViewModel`'s
initializer to always load it with no comment.

**Why:** The brief explicitly warns against preview fixtures silently
replacing real networking in production. Making the constraint visible in
the type's own documentation (not just this file) means a future stage
implementer sees the warning at the point of use, not only in a planning
document they may not re-read.

### Did not implement AppKit-level integrations in Stage 0

**Decision:** Stage 0 uses only SwiftUI (`NavigationSplitView`, `Settings`
scene, `TabView` for settings panes) with no custom `NSViewRepresentable`
wrappers.

**Why:** Nothing in Stage 0's scope (shell navigation, Settings scene,
demo data) requires AppKit. The brief reserves AppKit for "focused native
integration" — introducing it now would be premature.

## Stage 1

### Chose non-billable, key-authenticating endpoints over the public model catalog for connection verification

**Decision:** `VeniceConnectionChecker` calls `GET /api_keys/rate_limits`;
`OpenRouterConnectionChecker` calls `GET /api/v1/key`. Neither calls
`GET /models` for verification purposes.

**Why:** The brief is explicit that "a public model-list response is not
proof that a key is valid" — `/models` on both services is a public
catalog that doesn't require (or meaningfully validate) a key. Both
endpoints used here are documented as authenticating the specific calling
key and returning account/usage metadata, and neither runs inference, so
they satisfy "non-billable" while actually proving the key works. Verified
against current docs during this stage:
`https://docs.venice.ai/api-reference/endpoint/api_keys/rate_limits` and
`https://openrouter.ai/docs/api-reference/limits`.

### Built a small ConnectionChecking protocol per service rather than one generic "provider client"

**Decision:** Separate `VeniceConnectionChecker` / `OpenRouterConnectionChecker`
types, each with their own private response-decoding struct, rather than
one generic client parameterized over provider config.

**Why:** The brief repeatedly warns against conflating Venice and
OpenRouter or sharing payload assumptions between them. Their status
endpoints have genuinely different response shapes (`data.limit_remaining`
vs `data.balances.USD`/`data.apiTier`). A shared generic abstraction would
either leak provider-specific fields into a common type or require enough
per-provider configuration that it wouldn't actually save code. Stage 3
will introduce a shared HTTP/SSE layer where the payloads genuinely
overlap (both are OpenAI-compatible chat completions); this is deferred
until that's actually true, not assumed now.

### Redirect-blocking HTTP client instead of trusting URLSession defaults

**Decision:** `URLSessionHTTPClient` takes an `allowedHost` and installs a
`URLSessionTaskDelegate` that refuses any redirect to a different host.

**Why:** The brief requires pinning production connections to the
intended HTTPS hosts and never forwarding `Authorization` to a different
host via redirect. `URLSession` follows redirects by default, including
cross-host ones, and would resend the `Authorization` header unless
something intervenes. This is a small, cheap safeguard against a
misbehaving or compromised upstream silently exfiltrating a bearer token.

### `refreshStoredKeyPresence()` does not auto-verify over the network on launch

**Decision:** On appearing, `AccountSettingsViewModel` only checks whether
a key exists in Keychain (no network call). If one exists but hasn't been
verified this session, it shows "Saved, not yet verified." rather than
either claiming "Connected" or silently issuing a network request.

**Why:** The brief's non-negotiable rules include no hidden network calls
without explicit intent, and one active/global generation model for
simplicity. Auto-verifying every stored key on every app launch would be a
hidden network call the user didn't ask for in that moment. Explicit
"Save & Verify" / "Re-verify" buttons keep verification an intentional,
visible action, at the cost of the UI not showing a green "Connected"
state immediately after every relaunch — an acceptable, documented
trade-off (see STATUS.md limitation 4).

### Kept invalid/unverifiable keys in Keychain rather than auto-deleting them

**Decision:** An `.invalidCredential` or `.error` outcome from a
connection check never deletes the stored key. Only explicit
"Disconnect" removes it.

**Why:** A transient network failure or a temporarily-rate-limited key
should not silently destroy something the user typed in. Auto-deleting on
any non-success response would also make an ambiguous transport failure
indistinguishable from a deliberate "this key is bad" signal, which the
brief's error-handling rules treat as meaningfully different states.

### `AppDependencies` is a plain factory struct, not a DI container

**Decision:** One `@MainActor` struct with a `static func live()` and one
`make...ViewModel()` factory method per feature, constructed once in
`ChatterBatApp` and threaded through explicitly (currently just to
`SettingsView`).

**Why:** The brief explicitly warns against introducing a
dependency-injection container. A single small factory keeps production
wiring in one obvious place without adding an abstraction layer that isn't
needed yet — there are only two dependencies to assemble so far.

## Stage 2

### Used `JSONSerialization` + lenient dictionary lookups instead of `Decodable` for catalog entries

**Decision:** `ModelCatalogDecoding` parses the top-level `{"data": [...]}"`
envelope once, then each fetcher pulls only the specific fields it needs
out of a `[String: Any]` per entry, skipping (not failing) any entry
missing `id`.

**Why:** The brief requires that "one malformed entry" never discard the
rest of the catalog. `Decodable` on `[ModelDTO]` fails the *entire* array
decode if any single element doesn't match the expected shape (missing
required field, wrong type, etc.) — there is no built-in "skip bad
elements" mode for a plain array decode. Decoding entry-by-entry into
loosely-typed dictionaries and defensively reading only the fields
ChatterBat displays makes partial-failure-tolerant decoding
straightforward, at the cost of losing `Decodable`'s compile-time
schema-shape checking. This is called out explicitly in
`ModelCatalogDecoding`'s doc comment as a deliberate, narrow exception.

### Normalized all catalog pricing to USD per 1,000,000 tokens at the fetcher boundary

**Decision:** `ModelPricing` always stores USD/1M-tokens `Decimal?`
values. `OpenRouterModelCatalogFetcher` multiplies OpenRouter's
per-single-token string prices by 1,000,000; `VeniceModelCatalogFetcher`
passes Venice's already-per-1M-token values through unchanged.

**Why:** Verified against current docs during this stage that the two
providers use genuinely different units:
`https://docs.venice.ai/overview/pricing` ("Prices per 1M tokens unless
noted") vs. OpenRouter's `pricing.prompt`/`completion` being a string in
USD per single token
(`https://openrouter.ai/docs/api-reference/models/get-models`,
`"0.00003"`-style example). Converting once at the fetcher boundary means
the rest of the app (picker UI, future cost estimation) only ever deals
with one normalized unit and never has to remember which provider needed
which conversion.

### `ModelInfo`/`ModelPricing`/`CapabilitySupport` conform to `Hashable`, not just `Equatable`

**Decision:** Widened these from `Equatable` to `Hashable`.

**Why:** SwiftUI's `ForEach`/`List` over `[ModelInfo]` and test
assertions comparing arrays both benefit from `Hashable` (e.g. for
potential `Set` de-duplication later), and `Decimal`/`String`/nested enum
members are all already `Hashable`, so there's no cost to widening it now
rather than needing a second pass later.

### Favorites/recents go in `UserDefaults`, not Keychain or SwiftData yet

**Decision:** `ModelPreferencesStore`'s only production implementation is
`UserDefaultsModelPreferencesStore`.

**Why:** The brief explicitly distinguishes API keys (Keychain-only) from
"non-secret settings" like favorites, and separately says persistence
generally moves to SwiftData starting Stage 4. Favorites/recents are
non-secret and don't need SwiftData's relational structure yet (they're
just a small set/list of identifier strings), so `UserDefaults` is the
simplest correct choice for this stage, with a protocol boundary already
in place so swapping the backing store later doesn't touch call sites.

### `refresh(_:)` keeps the last-successful catalog visible through a failure

**Decision:** `CatalogLoadState.failed` carries `cachedModels`/
`cachedFetchedAt` from before the failing attempt, and `ModelPickerViewModel.refresh`
passes the previous `displayableModels` through into both `.loading` and
a subsequent `.failed` state.

**Why:** The brief requires "cache catalogs and show cache age/offline
state" and implies a refresh failure shouldn't regress the UI to empty
when a perfectly good previous catalog is already in memory. This is
tested directly in `testFailedRefreshKeepsPreviouslyLoadedModelsVisible`.

### The model picker performs zero network calls for a service with no stored key

**Decision:** `ModelPickerViewModel.loadAllConfiguredCatalogs()` checks
`credentialStore.loadKey(for:)` first and sets `.notConfigured` without
ever invoking the corresponding fetcher when no key is present.

**Why:** Consistent with the Stage 1 decision not to make hidden network
calls without explicit intent — an unconnected service shouldn't generate
background traffic just because the user opened the picker. Verified in
`testServiceWithNoStoredKeyIsMarkedNotConfiguredWithoutFetching` via the
fetcher's `fetchCount`.
