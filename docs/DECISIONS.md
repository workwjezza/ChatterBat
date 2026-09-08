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

## Stage 3

### One shared `ChatStreamingClient` implementation for both services, unlike catalog/connection decoding

**Decision:** `StandardChatStreamingClient` is a single, non-provider-
specific type, parameterized only by `service` (for labeling) and
`endpointURL`. Both Venice's and OpenRouter's `AppDependencies` chat
clients are instances of the same type.

**Why:** This looks inconsistent with the Stage 2 decision to keep
`VeniceModelCatalogFetcher`/`OpenRouterModelCatalogFetcher` fully
separate, but the underlying facts are genuinely different here: catalog
responses have provider-specific fields and pricing units (verified
different in Stage 2), while plain-text chat completions from both
services use the same OpenAI-compatible
`{"choices":[{"delta":{...},"finish_reason":...}],"usage":...}` SSE
chunk shape — this is exactly why "OpenAI-compatible" is a meaningful
claim both providers' docs make. Sharing the implementation here reflects
a real shared contract, not an assumption of similarity. If Stage 6 adds
provider-specific request fields (`venice_parameters`, OpenRouter
`provider` routing), those get added at the request-building layer
(`ChatRequestBuilder` or a provider-specific variant of it), not by
forking the streaming/decoding logic itself, since the response shape
contract remains shared.

### Sent `stream_options.include_usage: true` on every request

**Decision:** `ChatRequestBuilder` always includes
`"stream_options": {"include_usage": true}`.

**Why:** Verified in Venice's own documented example request body
(`https://docs.venice.ai/api-reference/endpoint/chat/completions`) that
this exact field is accepted. OpenRouter's SDK streaming example reads
`chunk.usage` directly off the final chunk without showing this field
being set explicitly, suggesting it may default to included for
OpenRouter — but since sending it explicitly is documented-safe for
Venice and is the standard OpenAI-compatible way to request this, sending
it unconditionally on both requests is the safer choice than guessing
provider-specific default behavior.

### Treated a stream ending with no `finished`/`usage` event as an error (`.prematureDisconnect`)

**Decision:** `StandardChatStreamingClient.run` throws
`ChatRequestError.prematureDisconnect` if the byte stream ends (clean
EOF) without ever having observed a `.finished` or `.usage` decoded
event.

**Why:** The brief explicitly calls out "premature disconnects" as a
streaming failure mode distinct from a clean finish. Without this check,
a connection that silently drops mid-response (network blip, provider
timeout) would look identical to a successful completion that happened
to have a short response — the assistant message would just be marked
`.completed` with whatever partial text arrived, misrepresenting a
failure as success. This is tested directly in
`testPrematureDisconnectWithNoFinishOrUsageThrows`.

### `ChatCoordinator` scopes every mutation to (conversationID, messageID) pairs, not a single "current" pointer

**Decision:** All transcript mutations go through a private `update(_
messageID:, in conversationID:, _:)` helper that looks up the specific
message by ID within the specific conversation's array, rather than the
coordinator holding a single "currently streaming message" reference.

**Why:** The brief requires that switching conversations cannot redirect
incoming text into another chat, and that repeated Send cannot create
unintended duplicate requests. Scoping by both IDs together means even
if two streams were somehow active in overlapping windows (shouldn't
happen given the single global `generationState`, but this makes it safe
regardless of that invariant holding), a stale event from one stream
can never mutate a different conversation's message. Verified directly
in `testTwoConversationsAreFullyIsolated`.

### Cross-service disclosure state lives in `ChatCoordinator`, keyed by conversation, and only updates after a successful send

**Decision:** `lastUsedService[conversationID]` is set only inside the
success branch of `runStream` (after streaming completes without being
cancelled), not when a message is merely queued or when the model picker
is opened.

**Why:** The brief is explicit: "Never send history merely because the
user opened the picker" and disclosure must be based on what was actually
sent, not what's merely selected. Updating this dictionary only on
confirmed successful delivery (not on send-attempt, not on failure)
means `wouldShareHistoryAcrossServices` reflects genuine history-sharing
that already happened, not a hypothetical. Verified in
`testWouldShareHistoryAcrossServicesDetectsSwitchOnlyAfterAMessageExists`.

## Stage 4

### File-scope `@Model` classes, plain `conversationID` foreign key, no `#Predicate`/`sortBy:`

**Decision:** `PersistedConversation`/`PersistedMessage` are declared at
file scope (not nested inside `ChatterBatSchemaV1`); `PersistedMessage`
has a plain `conversationID: UUID` column instead of a SwiftData
`@Relationship`; every `SwiftDataConversationRepository` query does an
unfiltered `context.fetch(FetchDescriptor<T>())` followed by Swift-side
`.filter`/`.sorted`, never a `#Predicate` or `sortBy:` argument on the
descriptor.

**Why:** All three were empirically proven, via bisection with minimal
standalone reproduction apps and real crash-report analysis, to
reproducibly crash the app with EXC_BREAKPOINT at launch on this exact
toolchain (Xcode 26.6, macOS 26.6.2, Swift 6.3.3) — specifically the
`@Relationship` combined with predicate/sortBy usage; un-nesting the
`@Model` classes was tried first and didn't fix it alone, but is kept
since it's a reasonable file organization regardless. See
`docs/STATUS.md`'s "SwiftData crash story" for the full bisection
narrative. This is a deliberate, documented deviation from Apple's
commonly-shown sample code, not an oversight — do not "modernize" this
back to relationships/predicates without first re-verifying on a
different toolchain version that the underlying bug is actually fixed.

### Persistence tests construct SwiftData state inline, never via `setUp()`/`tearDown()` or a helper function

**Decision:** Every test in `SwiftDataConversationRepositoryTests`/
`SwiftDataConversationRepositoryAdditionalTests` calls
`ChatterBatModelContainer.inMemory()` and constructs
`SwiftDataConversationRepository` directly in the test method body.
No `override func setUp()`, no `private func makeRepository()` helper.

**Why:** Both alternatives were proven, via the same bisection process,
to hang every single test for ~20 seconds (until XCTest's timeout killed
and relaunched the test host) on this toolchain — while byte-identical
code inlined directly in the test method ran in single-digit
milliseconds. This looks like a debugger/test-runner instrumentation
interaction specific to calling into `ModelContainer`/`ModelContext`
construction through any intermediate function under XCTest's `-Onone`
build on this toolchain, not a flaw in the production code (the
production `AppDependencies.live()` code path, which also calls through
a function, does not hang — only the *test-runner* context reproduces
it). The resulting duplication across test methods is intentional and
should not be "cleaned up" into a shared helper without first
re-verifying against a real timed test run.

### Initial conversation-list fetch and interrupted-generation recovery happen synchronously in `AppDependencies.live()`, not in any SwiftUI view lifecycle hook

**Decision:** `AppDependencies.live()` calls
`chatCoordinator.markInterruptedGenerationsAtLaunch()` and
`repository.loadAllConversations()` synchronously, before returning,
and before `ChatterBatApp.body` is ever evaluated. `RootView.init`
receives the already-fetched list via
`AppViewModel.attachRepository(_:initialConversations:)` and never
itself calls into SwiftData. `.task {}`, `.onAppear` (even with a
`DispatchQueue.main.async` deferral), and a plain `RootView.init` that
fetches directly were all tried and reproducibly crashed at launch.

**Why:** The crash trace consistently showed the fetch happening during
AppKit's window-restoration re-entrancy
(`_reopenWindowsAsNecessaryIncludingRestorableState` in the stack).
Moving the fetch to before any `View` exists at all — inside the plain
synchronous factory function that constructs the app's dependencies —
sidesteps that re-entrant window entirely and was the only placement
that never crashed across many repeated real launches. This does mean
`AppDependencies.live()` does synchronous disk I/O on the main thread
at startup; given the expected data volume (one user's local chat
history) this is an acceptable trade-off for correctness.

## Stage 5

### Markdown support is deliberately fence-only, via a hand-written line scanner, not a general Markdown library

**Decision:** `MessageContentParser` only recognizes fenced code blocks
as a block-level construct; everything else is one plain-text blob
rendered through SwiftUI's native `Text(markdown:)` with
`.inlineOnlyPreservingWhitespace` (so it also never accidentally
renders headings/lists/tables from that path).

**Why:** The brief explicitly warns against assuming `Text` provides
complete block-Markdown support and asks for "a deliberate, tested
subset." A hand-written fence scanner is simple enough to reason about
and test exhaustively (11 tests, including the unterminated-fence and
empty-code-block edge cases), and avoids adding a third-party Markdown
dependency for a deliberately small, well-defined subset. No third-party
package was evaluated or introduced — consistent with the brief's "no
third-party runtime dependencies for the initial stages" guidance.

### Auto-scroll decision logic extracted into a plain, unit-testable `AutoScrollPolicy`

**Decision:** The "should the transcript scroll to the newest message"
decision lives in `AutoScrollPolicy`, a plain struct with no SwiftUI
dependency, wired into `TranscriptView` via a `GeometryReader`-based
bottom-anchor offset preference.

**Why:** This environment has no interactive display, so any scroll
behavior embedded directly in view code would be entirely unverifiable
this session. Extracting the decision into a plain type means the
*logic* (follow by default; stop following once the user scrolls away;
resume on return to bottom or conversation switch) is fully covered by
fast unit tests, while the remaining risk is narrowed to "is the
SwiftUI wiring correct," which is now a smaller, more reviewable
surface — explicitly flagged as unverified in `docs/STATUS.md` rather
than claimed as tested.

### First-run onboarding is one screen, not a wizard, and does not duplicate account-connection UI

**Decision:** `OnboardingView` is a single sheet with an explanation and
one button that opens Settings (the real Accounts UI) — it does not
re-implement key entry, model selection, or a multi-step flow.

**Why:** The brief's first-run flow describes several steps (explain
billing, connect a service, pick a model), but ChatterBat already has a
real, reachable Settings → Accounts flow and a real model picker;
building a second, parallel version of either inside onboarding would
be duplicated logic that could drift out of sync. Directing the user to
the real settings UI keeps a single source of truth for account
connection.

## Stage 6

### OpenRouter cost is stored/displayed as "credits," never treated as equal to USD

**Decision:** `ChatUsage.costCredits` is a distinct field from
`costUSD`, and `MessageBubble` labels it "N credits," never "$N."

**Why:** OpenRouter's Usage Accounting documentation describes
`usage.cost` only as "Cost in credits" and never states a credit-to-
USD exchange rate anywhere this stage's research found (checked the
Usage Accounting page, the Credits API reference, the FAQ's billing
section, and the pricing page). Venice's documented `cost.usd` field,
by contrast, is explicitly USD. Presenting OpenRouter's credits as a
dollar amount would be a guess dressed up as a fact — exactly what the
brief's "unknown must never be displayed as if known" principle
forbids, generalized from capability/pricing fields to cost reporting.

### Only three OpenRouter provider-routing fields are exposed, not the full `provider` object

**Decision:** `OpenRouterRoutingPreferences` exposes only
`allow_fallbacks`, `data_collection`, and `zdr` — not `order`, `only`,
`ignore`, `quantizations`, `sort`, `max_price`, or
`enforce_distillable_text`, all of which are real, documented fields
on OpenRouter's `provider` request object.

**Why:** The brief explicitly asks for "a deliberately small set of
OpenRouter routing controls," not full parity with OpenRouter's API
surface. The three chosen fields are booleans/enums with fixed,
self-explanatory values a UI can present with a toggle or picker with
no extra data fetching. The excluded fields (`order`/`only`/`ignore`)
need a list of provider slugs to choose from, which would require
adding a new provider-catalog fetcher and picker UI — out of scope for
"deliberately small." `quantizations`/`max_price`/`sort` are more
advanced routing/cost-optimization concepts that don't map to any
existing ChatterBat concern the way `data_collection`/`zdr` map to the
privacy concerns Venice's privacy labels already surface.

### Context boundary is a plain additive SwiftData column, not a new schema version

**Decision:** `PersistedConversation.contextBoundaryMessageID: UUID?`
was added directly to the existing `@Model` class with a default of
`nil`, rather than introducing `ChatterBatSchemaV2` and a migration
stage.

**Why:** SwiftData performs this specific kind of change (a new
optional attribute with a default value on an existing model) as an
automatic lightweight migration — no new `VersionedSchema` is needed
for it to work. Introducing a full new schema version for a single
optional column would add migration-plan complexity with no
corresponding benefit, and this project's Stage 4 crash story already
demonstrated that SwiftData's more advanced machinery
(`@Relationship`, `#Predicate`, `sortBy:`) is fragile on this
toolchain — minimizing exposure to that machinery further is a
deliberate choice, not an oversight. The trade-off (documented
honestly in `docs/STATUS.md`) is that this has only been verified
against freshly-created stores, not a real pre-Stage-6 store with
existing data.

### Context boundary hides nothing; it only changes future-request context

**Decision:** `ChatCoordinator.setContextBoundary` never deletes,
hides, or visually dims any message in the transcript. It only changes
which messages `eligibleOutgoingMessages` includes in the *next*
request's `messages` array.

**Why:** The brief's context-management requirement is about giving
the user control over token/cost usage, not about editing history. A
feature that silently made past messages disappear from view would be
surprising and could look like data loss. Keeping the full transcript
always visible, with only a small marker showing where the boundary
is, keeps the mental model simple: "everything you see happened;
only some of it counts toward the next request."

### Conversation export always creates a new conversation with a fresh ID, and only carries transcript-visible fields

**Decision:** `ConversationExport` has no field for an API key or
account identifier, and `ConversationExportCoding.importAsNewConversation`
always assigns a fresh `Conversation.id` rather than reusing the
exported one.

**Why:** Per the brief, API keys must live only in Keychain and never
appear in logs, exports, or source — an export format is exactly the
kind of artifact a user might email or upload somewhere, so it must be
structurally incapable of carrying a secret, not just conventionally
kept free of one. A dedicated test scans the encoded JSON for
key-like field names to catch any future accidental addition. Fresh
IDs on import mean importing the same file twice (e.g. after being
sent to another Mac and back) creates two independent conversations
rather than silently overwriting or merging with an existing one,
which would risk losing data with no undo.

### Retry removes and re-sends rather than replaying stored request state

**Decision:** `retryLastTurn` pops the failed assistant message and the
preceding user message off the transcript, then calls the normal `send`
path again with that same user text — it does not keep a separate
"last request" snapshot to replay.

**Why:** Simpler and avoids a second source of truth for "what was sent
last." Since `send` already reconstructs the outgoing message list from
transcript content filtered by `isEligibleForContext`, replaying through
`send` naturally picks up the current transcript state (including
anything that might have changed) rather than blindly resending a frozen
snapshot. The guard clauses in `retryLastTurn` are deliberately strict
(exact last-two-messages shape) so it does nothing rather than guessing
at an ambiguous transcript shape — see STATUS.md limitation 11 for the
one gap this leaves in test coverage (the "does nothing" paths aren't
each individually tested).

## Stage 7

### The model can never supply a filesystem path; the user always picks it via a native panel

**Decision:** Both `AgentTool.readFile`/`.listDirectory` accept only a
`reason` string argument in their JSON Schema — never a path. The
actual file/folder is chosen exclusively by the user, live, via
`NSOpenPanel` (`AgentToolPanelPresenter`), triggered only after the
user taps "Approve" on the specific request.

**Why:** The brief requires every tool invocation to be visible and
individually approvable, "never silently expanding scope beyond
what's shown." If the model could supply a path, "approve this tool"
would implicitly also mean "approve reading whatever path the model
names," which is a much larger, less legible grant than what's shown
in the approval sheet. Making the path structurally ungrantable by
the model — rather than merely displaying it for confirmation — means
there is no code path in ChatterBat that resolves a model-supplied
string against the filesystem at all, which is a stronger guarantee
than a UI convention.

### Stage 7 is read-only file access, not a general sandboxed-execution framework

**Decision:** Only two tools exist (`read_file`, `list_directory`),
both read-only, both gated by the same sandbox entitlement
(`com.apple.security.files.user-selected.read-only`) already used for
ordinary export/import file panels.

**Why:** `docs/DEVELOPMENT_PLAN.md` explicitly scopes Stage 7 to
"read-only tools" and separately lists shell execution/autonomous file
edits/MCP/browser automation as out of scope for the foreseeable
future. Reusing the existing user-selected-file sandbox mechanism
(rather than requesting broader entitlements like
`com.apple.security.files.downloads.read-write` or full filesystem
access) means the agent beta's tools are exactly as powerful as
ChatterBat's own export/import feature already was — no new privilege
is introduced, only a new, permission-gated way to invoke the
existing one.

### Tool-calling round trips are rebuilt per-turn in memory, never reconstructed from persisted transcript history

**Decision:** `ChatCoordinator.ActiveToolContext` keeps the exact
`outgoingSoFar` message list (including the assistant's `tool_calls`
message and the `.tool`-role result) for the current turn only, in
memory. `TranscriptMessage.isEligibleForContext` always excludes
`.tool`-role messages, so a *later*, unrelated turn never tries to
replay an old tool call from persisted history.

**Why:** Correctly replaying a tool-calling round trip requires the
exact original `tool_calls` JSON arguments and matching `tool_call_id`
— reconstructing that faithfully from a persisted transcript weeks
later would require persisting and round-tripping raw provider JSON
verbatim, which doesn't fit this project's existing plain-column
persistence model and would reintroduce the kind of nested/relational
complexity Stage 4's crash story already ruled out. Since the
brief's own use case for tools is answering the *current* question,
not maintaining a permanent tool-calling session, scoping the replay
to one in-memory turn is sufficient and much simpler. The `.tool`
message itself is still permanently persisted and displayed — only
its *replay to the model* is scoped to the turn that created it.

### `parallel_tool_calls: false` is always sent whenever any tool is offered

**Decision:** `ChatRequestBuilder.body` sets
`"parallel_tool_calls": false` unconditionally whenever `tools` is
non-empty (both Venice and OpenRouter document this OpenAI-compatible
parameter).

**Why:** The approval flow (`ChatCoordinator`'s `ActiveToolContext`)
is built around tracking exactly one pending tool call at a time —
`ChatStreamDecoder.decode` also only inspects `delta.tool_calls[0]` for
this reason. Forcing single tool calls server-side turns "there is at
most one in-flight call" from an assumption about model behavior into
a documented, provider-enforced request property, which is safer than
hoping models never emit more than one function call per turn.

### A denied/cancelled/unrecognized tool call still gets a real follow-up request, never a dead end

**Decision:** `ChatCoordinator.continueAfterToolOutcome` always sends
a follow-up request (replaying the tool_calls/tool-result pair) after
*any* outcome — approved-and-succeeded, denied, panel-cancelled, read
failure, or even an unrecognized tool name — never just stopping and
leaving the conversation mid-turn.

**Why:** Per OpenAI-compatible tool semantics, once a model's message
contains `tool_calls`, the *next* message in the conversation must be
a `tool`-role response to each of those calls before the model can be
asked anything else — omitting it would produce an invalid request on
any subsequent send. It's also better UX: a denial should let the
model gracefully explain it can't help with that part rather than the
turn just silently going nowhere.
