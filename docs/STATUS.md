# ChatterBat — Status

## E4a — Local read-only workspace preview (September 8, 2026)

Added an experimental Workspace toolbar panel per chat: explicit folder
selection, relative-path list/read proposals, exact local approval/denial,
bounded preview, Stop/Disconnect and rolling local event labels. Preview
content never enters draft, transcript, persistence or provider requests.
This is not a model tool, production IPC client or installed coding backend.

Async registry paths move opening/reading to a shared serial worker actor.
MainActor retains consent and scope/binding revision checks before and after
I/O. Revoke/unbind/rebind (including same-workspace rebind) suppress late
results. Security-scoped URL leases stay alive through outstanding I/O.
App-wide preview registry caps 32 roots/four outstanding reads, one per session;
chat deletion disconnects its preview. No new app entitlements or schema.

Verification: **363 app unit tests passed (9 new); Release build succeeded;
git diff --check clean.** Final logs: `/tmp/ChatterBatWorkspaceUITests.log`,
`/tmp/ChatterBatWorkspaceUIRelease.log`. Tests use temporary directories and
controlled suspended workers, with no paid calls or live keys. No interactive
UI/VoiceOver or real NSOpenPanel grant verification was performed.

**Limitations:** real sandbox-selected roots may fail E2's conservative
ancestor reopening/symlink rules; panel explicitly says experimental. Serial
off-UI I/O is cooperative cancellation, not a hard filesystem timeout. E2
hostile-filesystem limitations still apply. See WORKSPACE_PREVIEW.md.

**Next E4b:** verify normal-build folder grants, then integrate controlled
workspace tools, typed runtime events and explicit context/provider consent.
No automatic upload or shell/write authority follows from local preview.

## Workspace roadmap E3b — Separate-host discovery/lifecycle probe (September 8, 2026)

Added isolated signed ping host/CLI and sandboxed standalone app/negative
client targets, using a documented team-prefixed macOS App Group Mach service.
Production ChatterBat entitlements/dependencies remain unchanged. Host/client
signing requirements pin exact identities/team in both directions plus OS UID.
No workspace, approval, credential, file-write or command RPC was added.

Live build-only Release matrix passed twice: app and CLI ping successfully;
same host PID survives app-client exit; same-group/team wrong client is denied;
wrong expected host is denied from app/CLI; authorized CLI remains healthy;
controlled host restart changes PID and CLI reconnects; bootout removes service
and further CLI ping fails. XPC log confirmed wrong-client check-in dropped
for code-signing requirement. Strict signature and exact entitlement checks
passed. Host/CLI have only the test App Group; app clients have Sandbox plus
that group. No temporary exceptions or get-task-allow in Release probes.

The test runner uses a temporary plist/current-user GUI launchd registration
with guarded cleanup, no sudo or Library/LaunchAgents install. **Cleanup
verified: no probe registration remains.** Initial run exposed bare tool
signing identifier mismatch; explicit codesign IDs fixed it without loosening
trust. Listener denial can report interruption instead of request error; only
clean known exit-2 outcomes pass negatives, never timeout/crash/pong.

Verification: **354 app tests + 8 separate probe tests passed** (2 new probe
tests); app, standalone probe and bundled regression Release builds succeeded.
Both live matrices and shell syntax/git diff --check passed. See
`IPC_STANDALONE_PROBE.md` for commands/logs and precise evidence.

**E3b development feasibility complete, not production deployment.** Packaged
companion/SMAppService consent, upgrades/notarization, physical macOS 14,
different-user testing and durable recovery remain gates. No user data or
provider keys accessed. E4a local preview/off-UI reads are now implemented;
E4b model/provider integration remains gated. No writes/shell/host install.

## Workspace roadmap E3a — Signed bundled XPC probe (September 8, 2026)

Added isolated ChatterBatIPCProbe scheme/targets: sandboxed authorized app,
bundled ping-only XPC service, same-team wrong-identity app and six protocol
tests. None are linked into the normal ChatterBat app. Both directions pin
exact signing identifier/team/Apple anchor before resume and check OS UID;
ping validates version, size and nonce. No workspace or credential operation.

**Live build-only Release matrix passed:** authorized → verified pong/exit 0;
wrong client identity → rejected/exit 2; wrong expected service → rejected/
exit 2. Strict signatures passed. Actual entitlements for both apps/service:
**App Sandbox only**, no temporary exceptions, network/file grants or
get-task-allow. Reproducer: `IPCProbe/verify.sh` with absolute Release products
path; see `IPC_PROBE.md` for exact commands and evidence.

Initial test-instrumented artifacts had injected test sandbox exceptions and
were excluded from feasibility evidence. Initial negative-path callbacks also
crashed on inferred Swift actor isolation; fixed explicit Sendable callbacks
and reran cleanly. No timeout/crash counted as a successful rejection.

Verification: **354 app tests + 6 separate probe tests passed**, both app and
probe Release builds succeeded; shell syntax and git diff --check clean.
Final logs: `/tmp/ChatterBatIPCProbeTests.log`, `/tmp/ChatterBatIPCProbeRelease.log`,
`/tmp/ChatterBatE3AppTests.log`, `/tmp/ChatterBatE3AppRelease.log`; live probe
logs listed in IPC_PROBE.md. Tested on current development macOS, not physical
macOS 14. No paid APIs, provider keys, host install, launch-agent registration,
notarization or production app entitlement changes. OS may retain probe
sandbox containers and earlier crash diagnostics.

**E3b now verifies separate-process development discovery/basic lifecycle;
see the newer entry above.** Neither probe is a production coding host.

## Workspace roadmap E2 — Bounded read-only workspace prototype (September 8, 2026)

Implemented an unwired in-process WorkspaceReadRegistry: explicit root
registration, retained directory handles, session binding, read-only scope,
single-use exact-action approval consumption, revision invalidation and
revoke/unbind cleanup. Workspace scope is looked up internally, not accepted
from an execution caller. Max 32 roots; no persistent grants or host/UI wiring.

WorkspaceReadAccess traverses relative components via openat/O_NOFOLLOW,
checks type/device/link count and handle/path identity, rejects detected
root/file mutation, and checks resolved names against conservative deny
rules. Reads cap at 200,000 bytes; UTF-8/NUL checks; no whole-file mapping.
Listings cap at 1,000 scanned entries and 64,000 output bytes with omissions
disclosed. Symlinks, multiply linked files and special files are rejected or
omitted. Descriptors are close-on-exec and close through RAII.

**Limits:** synchronous main-actor prototype, not hard I/O timeout or complete
hostile-filesystem race prevention. No .gitignore parsing/secret scanning,
real bookmark grants, provider upload or production tool integration. No
mount/device isolation experiment performed. See `WORKSPACE_READ_ACCESS.md`
for exact mechanisms, tested races, remaining gates and conservative policy.
Existing Stage 7 tools and app entitlements remain unchanged; no writes,
shell or listener enabled.

Verification: **354 unit tests passed (18 new); Release build succeeded;
git diff --check clean.** Final logs: `/tmp/ChatterBatWorkspaceReadTests.log`,
`/tmp/ChatterBatWorkspaceReadRelease.log`. Project regenerated with XcodeGen.
New tests run real I/O only in disposable directories. No user repo/keys,
paid APIs, interactive permission/UI checks or host installation involved.

**E3a bundled ping is verified; E3b separate-host deployment remains.**

## Workspace roadmap E1 — Host security spike and policy foundation (September 8, 2026)

Recorded the separate user-level Swift coding-host recommendation, sandbox /
distribution / local IPC / Keychain / workspace threat model and concrete
E2–E4/F gates in `CODING_HOST_SECURITY.md`. Apple SMAppService, XPC, Keychain
sharing and notarization references were checked via public Markdown docs.
The current Release artifact has get-task-allow; no distribution-readiness
claim is made. Existing Keychain queries do not establish shared host access.

Added an **unwired** WorkspacePermissionPolicy and WorkspaceApprovalLedger:
typed read/edit/command proposals, read-only default, all permitted actions
require approval, credential/elevation cases denied, exact payload and
session/action/workspace revision binding, bounded ticket lifetime/capacity,
single-use consumption, expiry, observed clock rollback, revoke/cancel and
current-scope recheck. Lexical path checks are not filesystem containment.
The ledger is not client authentication or a persistent idempotency journal.

No host/CLI/listener installed, no new frameworks/packages, no shell/file-write
execution enabled, no production tools rewired, no sandbox/entitlement or
Keychain changes. E1 is complete as a design/policy spike, not host feasibility
validation. Signed IPC/installation, OS grant and migration behavior remain
explicitly unproven and gated before integration.

Verification: **336 unit tests passed (18 new); Release build succeeded;
git diff --check clean.** XcodeGen regenerated the project. Final logs:
`/tmp/ChatterBatPermissionsTests.log`, `/tmp/ChatterBatPermissionsRelease.log`.
No paid APIs, live credential access, host install, distribution submission or
interactive UI/IPC/Keychain sharing checks performed.

**E2 is now implemented as an unwired read-only prototype; see above.**

## Workspace roadmap B2 — Concurrent chats (September 8, 2026)

Implemented per-conversation execution with 2 active turns by default,
session-configurable 1–4, and up to 8 waiting FIFO chats. One turn per chat;
duplicate/full admission rejects without modifying history or clearing the
draft. Sidebar shows active counts, queue positions, approval/stopping state,
limit selector, scoped Stop and Stop all. Composer labels queued admission;
busy chats no longer lock model selection in unrelated conversations.

Queued requests capture prompt/context/model/settings/tools; credentials are
loaded at dispatch. Auto's captured policy is locally revalidated before
dispatch; expired/changed choices fail visibly without a request or fallback.
Cancellation retains active slots until tasks unwind and prevents late
cleanup from affecting replacement turns. Stop all never drains the queue.

Approval waits hold their turn's slot, while other slots can continue.
Native file panels serialize, with cancellation checks before/after picking
and real-panel dismissal requested on task cancellation. Stop now terminates
locally without a billable denial follow-up; explicit Deny still continues
the tool conversation. Unknown/unoffered tools cannot execute. All active,
stopping and queued chats are protected from deletion.

No persistence schema change: queued placeholders are unfinished transcript
records with live Queued UI; relaunch marks them interrupted, never resumes
the queue. Per-chat drafts/settings remain in memory until app quit; global
defaults and completed transcripts/usage stay durable. See
`CONCURRENT_CHATS.md` for semantics and limitations.

Verification: **318 unit tests passed (15 new); Release build succeeded;
git diff --check clean.** Project regenerated with XcodeGen. Final logs:
`/tmp/ChatterBatConcurrentTests.log`, `/tmp/ChatterBatConcurrentRelease.log`.
No paid provider calls, real credentials, interactive UI/native panel checks
or XCUITest execution. Manual simultaneous-provider, panel cancellation,
keyboard/VoiceOver and queue-layout checks remain release gates.

**E1 is now completed as a design/policy spike; E2 follows.** C/D remain
parallel desktop tracks, not blockers for the CLI coding milestone.

## Workspace roadmap B1 — Independent conversation state (September 8, 2026)

Implemented conversation-owned draft, model/identity, Auto mode/policy
snapshot, advanced settings, tool toggle and selection notices. Detail
bindings target a specific observable session, not the globally selected
chat. Switching restores that chat's state. New/imported chats start from
saved defaults with fresh tool/settings state; existing loaded chats keep
their own snapshots when defaults change elsewhere, even if unopened.

**In-memory only:** drafts and per-chat settings survive switching but not
app quit. This is disclosed below the composer. Transcript persistence and
saved global new-chat defaults remain unchanged; no schema migration or
secret/draft storage in UserDefaults/exports was added.

Tool approval is now an inline conversation-local card; navigation leaves
it pending instead of denying implicitly. Decisions check the owning chat
and expected call ID and are claimed synchronously to prevent duplicates.
Active chat deletion is blocked in UI/view model. Background transcript
updates refresh sidebar metadata for changed IDs without altering selection.
Cross-provider confirmation validates its owning draft/settings/tools/model.

**One global generation still applies.** Other chats can be drafted, with
a visible explanation and Show active chat button. This is B1, not full
Batch B completion; concurrent generation/queueing and per-chat cancellation
are B2. See `SESSION_STATE.md` for behavior and remaining manual UI checks.

Verification: **303 unit tests passed (13 new); Release build succeeded;
git diff --check clean.** XcodeGen regenerated the project. Final logs:
`/tmp/ChatterBatSessionsTests.log`, `/tmp/ChatterBatSessionsRelease.log`.
No paid API calls, interactive UI/IME/VoiceOver or XCUITest execution. Existing
UI-test actor-isolation warnings remain. Inline approval layout, navigation,
native picker and confirmation flows still need manual release verification.

**B2 is now implemented; see the newer entry above.**

## Workspace roadmap A3 — Capability filters and task presets (September 8, 2026)

Implemented combinable Tool calling / Reasoning / Image understanding
filters alongside provider, search and favorites controls. Recent and
provider sections now share the same predicate as search. Added matching
counts, Reset filters, a no-match state, and capability details distinguishing
reported support, reported lack of support and unknown metadata. Selection,
info and favorite are sibling buttons rather than nested buttons.

Coding is explicitly a reasoning-based heuristic shortlist, with its
requirement visibly checked/locked. Ideating and Historical references are
guidance-only presets with no invented quality ranking. Web browsing and
Image editing are labeled not available yet and show explanations, not
false matches. Image input remains catalog metadata until attachments ship.
Filters never change prompts, defaults, Auto's pool or tool permissions.

Fixed OpenRouter partial/null/malformed capability fields being interpreted
as unsupported; these now stay unknown. Valid explicit lists still yield
supported/unsupported. No new provider fields, packages or schema changes.

Verification: **290 unit tests passed (13 new); Release build succeeded;
git diff --check clean.** XcodeGen regenerated the project. Logs:
`/tmp/ChatterBatFiltersTests.log`, `/tmp/ChatterBatFiltersRelease.log`.
No paid API calls, interactive UI/VoiceOver checks or XCUITest execution.
Existing UI-test actor-isolation warnings remain. See `MODEL_FILTERS.md`
for semantics and outstanding visual/accessibility checks (including the
expanded 640 × 660 picker layout and independent row controls).

**Follow-up B1 is implemented; B2 concurrency remains.** A1–A3 implementation
is complete; manual release gates remain as documented.

## Workspace roadmap A2 — Model bookmarks and saved defaults (September 8, 2026)

Implemented the favorite-model bookmark bar, independent persistent new-chat
pin, and explicit saved Auto policy. Click a chip to pin/select; click it
again to return the default to Auto. Picker selection remains temporary;
New Chat restores the default. Unavailable and unstarred pins remain visible
and removable. Relaunch needs explicit Refresh/picker loading to resolve
saved identities; there is no hidden network request or fallback.

Auto setup now uses **Save Auto policy from current model**. Pinning another
model or refreshing cannot change saved rate/privacy boundaries. Unknown
prices, changed anchor privacy, missing/stale/failed catalogs block routing.
Saved OpenRouter restrictions combine with stricter current settings and
are applied to outgoing requests. Current selection is still app-wide,
explicitly disclosed; session isolation is not included in this slice.

Verification: **277 unit tests passed (17 new); Release build succeeded;
git diff --check clean.** XcodeGen regenerated the project. Logs:
`/tmp/ChatterBatBookmarksTests.log`, `/tmp/ChatterBatBookmarksRelease.log`.
No paid API calls, interactive UI/VoiceOver checks, or XCUITest execution.
No SwiftData schema or third-party dependencies changed. See
`MODEL_BOOKMARKS.md` for usage, exact semantics and manual release checks.

**Follow-up A3 is now implemented; see the newer entry above.**

## Workspace roadmap A1 — Composer keyboard input (September 8, 2026)

Implemented the first slice of `WORKSPACE_ROADMAP.md`; later batches are
not implemented. `ComposerTextEditor` bridges a plain AppKit text view into
the existing SwiftUI composer: Return sends, Shift+Return inserts a newline
at the selection, and Command+Return sends while the editor is focused.
Numeric-pad Enter also sends. Whitespace-only drafts, repeated send keys,
disabled send state and noneditable input cannot submit. The editor grows
to six lines before scrolling, supports native editing/undo, and exposes
the Message accessibility label. No new packages, schema or API changes.

Marked text is handed to native input handling for ordinary Return;
Command+Return is consumed without sending or discarding a composition.
The Send button no longer owns a window-level Command+Return shortcut,
which could bypass that check. Mouse/accessible Send and Escape Stop remain.

Verification: **260 unit tests passed (12 new); Release build succeeded;
git diff --check clean.** New tests cover native keyboard event handlers,
marked text, multiline insertion/binding, and a SwiftUI-hosted editor's
height, accessibility label and editable-state updates. Logs:
`/tmp/ChatterBatComposerTests.log`, `/tmp/ChatterBatComposerRelease.log`.
No paid API calls or real credentials used. Existing UI-test actor-isolation
warnings remain; this pass did not run the XCUITest target.

Manual release checks still required (automated marked-text tests do not
substitute for a physical input method): verify Japanese/Chinese candidate
confirmation with Return, Shift+Return and Command+Return; keyboard focus,
Tab/Shift+Tab and Escape; multiline paste/undo; six-line scrolling at narrow
window widths; light/dark appearance and VoiceOver. This entry supersedes
older composer Return-key caveats below, but not their other limitations.

**Follow-up A2 is now implemented; see the newer entry above.**

## Cost hygiene, value highlighting and local Auto (September 8, 2026)

Implemented a reversible lean Venice prompt default, multi-event streaming
usage accounting, draft-aware context estimates, sparse rainbow price
outlines, and opt-in local 🤖 Auto using trusted favorites plus the selected
model within service/privacy/listed-rate constraints. Shared session catalog
includes freshness/error disclosure and explicit refresh. No persistence
schema changes, paid router, or automatic history truncation.

Verification: **248 unit tests passed; Release build succeeded**. No paid
API calls, visual accessibility pass or distribution upload performed.
See `COST_AND_AUTO.md` for rules, limitations and pre-TestFlight checklist.

## Last completed stage

**Stage 7 — Permission-controlled agent beta (read-only tools).** Complete.

## App icon

`Assets.xcassets/AppIcon.appiconset` now contains a real icon,
generated from two user-supplied source images (`chatterbaticon512.png`
512×512, `chatterbaticon1024.png` 1024×1024) via `sips`, covering all
ten required macOS sizes (16/32/128/256/512 pt at 1x/2x). Previously
the iconset's `Contents.json` listed the required slots but had no
actual image files or `filename` keys, so the app built and ran with
no crash but an empty/default icon. Verified the generated
`AppIcon.icns` in the built app bundle is a valid, non-blank RGBA icns
with alpha (`sips -g all`) and that the app still launches normally
with it. The two original source PNGs were removed from the repo root
after being baked into the asset catalog at the correct sizes — they
were never referenced by any build setting, so deleting them changes
nothing about the build.

## Stage 7 — what's implemented

- `AgentTool` (`read_file`, `list_directory`): a deliberately small,
  read-only tool catalog. Each tool's JSON Schema parameters accept
  only a `reason` string — never a path — so the model can request
  *a kind of* access and explain why, but can never itself name a
  filesystem location. Verified against current OpenAI-compatible
  `tools`/`tool_choice`/streaming `delta.tool_calls` docs (OpenRouter's
  tool-calling guide and streaming reference) and confirmed Venice's
  chat completions schema accepts the same `tools`/`tool_choice`
  fields and returns `tool_calls` in the same shape.
- `ChatStreamEvent.toolCallDelta`/`ChatStreamDecoder`: decodes the
  streaming `delta.tool_calls[0]` fragment shape (`id`/`name` present
  only on the first chunk per call, `arguments` a fragment to
  concatenate) — `ChatRequestBuilder` always sends
  `parallel_tool_calls: false` whenever any tool is offered, so only
  index 0 ever needs tracking (see docs/DECISIONS.md). `OutgoingChatMessage`
  gained `toolCalls`/`toolCallID` (both default to empty/`nil`, so
  every pre-Stage-7 call site compiles and behaves unchanged);
  `ChatRequestBuilder` encodes the full assistant-`tool_calls`/`tool`-role
  round trip in the exact OpenAI-compatible shape both providers
  document. `ChatStreamingClient` gained a `tools:` parameter via the
  same backward-compatible protocol-extension-overload pattern Stage 6
  used for `settings:`.
- `ChatCoordinator`: offers tools only when
  `model.supportsTools == .supported` (`.unknown` treated as
  unsupported for request-safety, same posture as Stage 6's
  `AdvancedChatSettings.applicable(to:)`). On a tool-call request,
  pauses generation in a new `GenerationState.awaitingToolApproval`
  and appends a permanent, visible `.tool`-role `TranscriptMessage`
  (`.awaitingApproval` status) — never runs anything before this.
  `respondToToolApproval(in:approve:)` is the single place a decision
  is made: approving calls `AgentToolExecutor`, which presents a real
  `NSOpenPanel` (`AgentToolPanelPresenter`, injected so tests never pop
  a real one) and reads only whatever the user actually picks there;
  denying never touches the filesystem. Either outcome (plus a
  cancelled panel, a read failure, or an unrecognized tool name) is
  recorded permanently on the `.tool` message and fed back to the
  model as a real follow-up request, so the model can respond
  honestly rather than the turn dead-ending. `Stop`/Escape while
  awaiting approval denies the pending call rather than being a dead
  no-op. A defensive `maxToolCallsPerTurn` (4) stops *offering* tools
  after that many rounds in one turn — explicitly documented as not
  the actual safety mechanism, since every round already requires its
  own approval regardless.
- `.tool`-role messages are permanently persisted (new, plain
  additive `PersistedMessage` columns: `toolRaw`, `toolCallID`,
  `toolModelStatedReason`, `toolApprovedItemName` — same "plain
  optional column, no `@Relationship`" posture as Stage 6's context
  boundary) and included in conversation export/import
  (`ConversationExport.ExportedMessage` gained the same four fields).
  They are always excluded from `isEligibleForContext` — never
  replayed as ordinary history on a later, unrelated turn; the
  in-memory `ActiveToolContext` handles the one-shot round trip a
  tool call itself needs. Two new `MessageStatus` cases:
  `.awaitingApproval` (rewritten to `.interrupted` at next launch by
  `interruptAllStreamingMessages`, exactly like an interrupted
  `.streaming` message) and `.toolDenied` (a deliberate user choice,
  never displayed as an error).
- UI: `AgentToolApprovalView` — a `.sheet` shown for every single tool
  request (tool name/description, the model's own stated reason,
  Approve/Deny) — is the only path that can trigger
  `AgentToolExecutor.run`. The "Agent Tools (Beta)" toggle lives inside
  the existing `AdvancedSettingsView` popover (off by default, hidden
  entirely for a model with `.unsupported`/`.unknown` tool support) —
  deliberately not a prominent top-level control, per the brief's
  "explicitly separate, optional mode" requirement.
  `MessageBubble`/`TranscriptView` render `.tool` messages with their
  own distinct body (tool name, model's reason, approved item name,
  result) and status badges for `.awaitingApproval`/`.toolDenied`.
- `ChatterBat.entitlements` gained
  `com.apple.security.files.user-selected.read-only` — required for
  the sandboxed app to actually read what the user picks via the new
  panel; verified present in the signed, built app bundle via
  `codesign -d --entitlements`.
- 227/227 unit tests pass (37 new: `AgentToolTests` (4),
  `AgentToolExecutorTests` (5, against real temp-directory fixtures,
  never a real `NSOpenPanel`), `ChatCoordinatorAgentToolsTests` (9),
  `SwiftDataConversationRepositoryAgentToolsTests` (4),
  `TranscriptMessageAgentToolsTests` (5), plus 3 new
  `ChatStreamDecoderTests` cases, 5 new `ChatRequestBuilderTests`
  cases, and 2 new `ConversationExportCodingTests` cases; all Stage
  0–6 suites still pass unchanged, 190 from before).

Known gap, honestly documented: none of this stage's new UI (the
approval sheet, the "Agent Tools (Beta)" toggle, the actual
`NSOpenPanel` behavior when picking a file/folder) was interactively
exercised in this environment — same `osascript`-lacks-Accessibility-
permission limitation carried forward from Stage 6. See Known
Limitations below.

## Stage 6 — what's implemented

- `AdvancedChatSettings` (+ `ReasoningEffort`, `VeniceAdvancedSettings`,
  `OpenRouterRoutingPreferences`, `DataCollectionPreference`): a
  deliberately small set of per-send advanced controls. Every field
  defaults to a value that changes nothing about the request that
  would otherwise be sent, per the brief's "advanced controls must
  stay hidden by default." `applicable(to:)` is the single,
  unit-tested place capability-aware gating happens: `.unknown`
  reasoning support is treated the same as `.unsupported` for
  *request-safety* purposes (never send a parameter a model might
  reject), even though `.unknown` displays differently from
  `.unsupported` everywhere else in the UI — 9 dedicated tests.
- Provider fields chosen after re-verifying current docs during this
  stage: Venice's `reasoning_effort` (top-level string) and
  `venice_parameters.{disable_thinking, strip_thinking_response}`
  (booleans); OpenRouter's `reasoning_effort` (same field, shared
  vocabulary) and `provider.{allow_fallbacks, data_collection, zdr}`
  (verified exact field names/defaults/allowed values against
  OpenRouter's Provider Routing docs). OpenRouter's richer
  `order`/`only`/`ignore`/`quantizations`/`sort` provider-routing
  fields were deliberately *not* exposed — per the brief's "a
  deliberately small set," and because those need a separate
  provider-slug catalog ChatterBat doesn't fetch anywhere yet.
- `ChatRequestBuilder.body`/`.requestData` now take `service:` and
  `settings:` and add `reasoning_effort`/`venice_parameters`/`provider`
  only when they'd differ from doing nothing — 8 dedicated tests
  confirm each field is included only when non-default and never sent
  to the wrong service.
- `ChatStreamingClient` protocol gained a `settings:` parameter; a
  protocol-extension overload without it (defaulting to
  `AdvancedChatSettings()`) means every Stage 0–5 call site and test
  compiles unchanged.
- `ChatUsage` gained `costUSD`/`costCredits` — kept as two distinct,
  never-conflated fields rather than one generic "cost," because
  Venice's non-streaming response documents an actual `cost.usd` (real
  USD), while OpenRouter's `usage.cost` is documented only as "cost in
  credits" — no OpenRouter documentation page found during this
  stage's research states a credit-to-USD exchange rate, so treating
  it as USD would misrepresent real spend. `ChatStreamDecoder` parses
  both, each only from its own service's documented location; 3 new
  decoder tests, including one that explicitly asserts OpenRouter's
  cost is never read into `costUSD`.
- `MessageBubble`'s usage footer now appends cost with its actual unit
  label ("$X.XXXXX" or "N credits") whenever the provider reported it.
- **Context management**: `ChatCoordinator.setContextBoundary`/
  `contextBoundaryMessageID`/`contextUsageEstimate`. A context boundary
  never deletes or hides any message — it only changes which messages
  are included in *future* sends' context, set via a message's own
  "Start Context Here" context-menu action (`MessageBubble`) and
  cleared from the Advanced Settings popover. Persisted via a new
  plain `PersistedConversation.contextBoundaryMessageID: UUID?` column
  (see the known gap below) and
  `ConversationRepository.contextBoundaryMessageID(for:)`/
  `.setContextBoundary(_:forConversation:)`. `ContextUsageEstimate` is
  a pure, honestly-labeled *rough estimate* (character-count-based,
  never a real tokenizer) of how much of the next send would use —
  never displayed without "estimated," never used to auto-truncate
  anything. 5 new coordinator tests + 5 `ContextUsageEstimateTests` +
  4 new SwiftData persistence tests for the new column.
- **Versioned JSON export/import**: `ConversationExport`/
  `ConversationExportCoding`. Every export carries an explicit
  `schemaVersion`; `decode` rejects (rather than silently misreads) any
  file with a newer version than this build understands. Export
  includes only conversation/message content already visible in the
  transcript — no API keys, no account identifiers (verified by a
  dedicated test scanning the encoded JSON for key-like field names).
  Import always creates a brand-new conversation with a fresh ID
  (never overwrites/merges), so importing the same file twice yields
  two independent conversations. Dates round-trip via a custom ISO
  8601-with-fractional-seconds codec (plain `.iso8601` would have
  truncated to whole seconds); this still loses precision below one
  millisecond, an accepted, documented limitation for a "conversation
  last updated" display field. Wired into `SidebarView` via
  `.fileExporter`/`.fileImporter`; `AppViewModel` surfaces specific
  user-presentable errors (never generic) for decode failure vs.
  unsupported future schema vs. persist failure. 7
  `ConversationExportCodingTests` + 6 `AppViewModelExportImportTests`.
- `AdvancedSettingsView`: a toolbar popover showing only the sections
  that apply to the currently-selected model (reasoning controls only
  when `supportsReasoning == .supported`; Venice/OpenRouter sections
  only for their own service), plus the context-usage readout and a
  "Clear Context Boundary" action.
- 190/190 unit tests pass (52 new since Stage 5's 138: new test files
  `AdvancedChatSettingsTests`, `ChatRequestBuilderTests`,
  `ContextUsageEstimateTests`, `ChatCoordinatorAdvancedSettingsTests`,
  `SwiftDataConversationRepositoryContextBoundaryTests`,
  `ConversationExportCodingTests`, `AppViewModelExportImportTests`,
  plus additions to `ChatStreamDecoderTests`).

**Known gap, honestly documented:** `PersistedConversation.contextBoundaryMessageID`
was added as a plain optional column with a default value rather than
a new `ChatterBatSchemaV1`→`V2` `VersionedSchema`/`SchemaMigrationPlan`
stage. This is the correct call for a purely-additive, always-optional
field under SwiftData's automatic lightweight migration — but it has
only been exercised against **freshly created** in-memory and on-disk
stores in this stage's testing (all
`SwiftDataConversationRepositoryContextBoundaryTests` use
`ChatterBatModelContainer.inMemory()`, and manual app launches used a
store already wiped clean per this project's manual-testing
convention). It has **not** been verified against a real pre-Stage-6
on-disk store that already contained conversations created before this
column existed. **Action for a human:** before relying on this with
real user data, build the pre-Stage-6 commit, run it once to create a
store with real conversations, then run the Stage-6 build against that
same store file and confirm it still launches and those conversations
still load correctly.

## Stage 5 — what's implemented

- `MessageContentBlock`/`MessageContentParser`: splits raw message
  content into plain-text and fenced-code-block segments by scanning
  for ` ``` ` fence lines. Deliberately supports only this one
  block-level construct, per the brief ("Keep the initial supported
  subset deliberate and tested") — no headings, lists, block quotes, or
  tables. Handles an unterminated fence (a still-streaming message
  whose content ends mid-code-block) by treating the remainder as code
  rather than losing it or crashing. 11 dedicated tests, including the
  unterminated-fence case and an empty code block (`` ``` `` immediately
  followed by `` ``` ``, which required a real parser fix — see below).
- `MessageContentView`: renders parsed blocks — plain text via native
  `Text(markdown:)` with `.inlineOnlyPreservingWhitespace` (bold/
  italic/inline-code/links only, never block Markdown), code blocks via
  `CodeBlockView`.
- `CodeBlockView`: monospaced, horizontally scrollable (so long lines
  stay readable instead of wrapping awkwardly or being truncated), with
  a per-block Copy button (`NSPasteboard`) and an optional language
  label.
- `MessageBubble` (replacing the old inline bubble in `TranscriptView`):
  adds a per-message Copy Response button and a combined, readable
  VoiceOver `accessibilityLabel` (speaker + content + terminal-status
  note for cancelled/failed messages).
- `AutoScrollPolicy`: pure, unit-tested decision object (4 tests) for
  "should new content auto-scroll the transcript to the bottom" vs. "the
  user scrolled up, so stop following until they return to the bottom
  or switch conversations." Wired into `TranscriptView` via a
  `ScrollViewReader` + a `GeometryReader`-based bottom-anchor offset
  preference — the *decision logic* is tested; the actual on-screen
  scroll behavior has not been visually confirmed (no display in this
  environment).
- `OnboardingView` + `OnboardingStateStore`/`UserDefaultsOnboardingStateStore`:
  a single first-run welcome sheet (not a multi-step wizard) explaining
  bring-your-own-key billing and pointing at Settings → Accounts;
  dismissal is persisted (non-secret, `UserDefaults`) so it only shows
  once. 2 dedicated tests using an isolated `UserDefaults` suite.
- `SidebarView` now distinguishes a genuinely empty conversation list
  ("No Conversations Yet — Start a new chat with ⌘N") from a search
  with no matches (`ContentUnavailableView.search`) — previously both
  showed the same search-style empty state.
- Accessibility labels/hints added to: the model-picker row and
  favorite-star button (with an honestly-documented caveat about
  nested-button keyboard focus — see `ModelRow`'s doc comment), the
  composer's message field and Send/Stop buttons, the conversation
  toolbar's model button, the sidebar's New Chat button and conversation
  rows, and the Settings API key field.
- `ComposerView` placeholder text now reflects *why* sending isn't
  possible yet ("Select a model to start chatting" vs. plain
  "Message"), via a new `hasSelectedModel` parameter.

## Stage 4 — what's implemented

- SwiftData schema: `PersistedConversation`/`PersistedMessage` (plain
  file-scope `@Model` classes — NOT nested inside the `VersionedSchema`
  enum; see the crash story below), referenced by `ChatterBatSchemaV1`
  (`VersionedSchema`) and `ChatterBatMigrationPlan` (`SchemaMigrationPlan`,
  currently zero stages since there's only one schema version). Messages
  reference their conversation via a plain `conversationID: UUID` column
  — NOT a SwiftData `@Relationship` (also part of the crash story).
- `ChatterBatModelContainer.live()` (real on-disk store) /
  `.inMemory()` (isolated, for tests/previews).
- `ConversationRepository` protocol (`@MainActor`, exposes only plain
  `Sendable` `Conversation`/`TranscriptMessage` — SwiftData model
  instances never cross this boundary, per the brief) +
  `SwiftDataConversationRepository`: `loadAllConversations`,
  `loadMessages`, `createConversation`, `rename`, `deleteConversation`
  (explicit cascade-delete of messages), `appendMessage`,
  `updateMessage`, `deleteMessage`, `interruptAllStreamingMessages`.
  Every query does an unfiltered `FetchDescriptor` fetch followed by
  Swift-side `.filter`/`.sorted` — no `#Predicate`, no `sortBy:` — see
  the crash story below for why.
- `MessageStatusCoding`: encodes/decodes `MessageStatus` to/from the
  plain string columns SwiftData stores; an unrecognized raw value
  decodes to `.interrupted` (an honest "needs attention" state) rather
  than crashing or guessing `.completed`.
- `ChatCoordinator` now persists through an optional
  `ConversationRepository`: `send` persists the user+assistant messages
  synchronously before the network call starts; streaming checkpoints
  the assistant message to the repository every `checkpointInterval`
  content-delta events (default 20 — "not on every token" per the
  brief) with an unconditional final write on every terminal state
  (completed/cancelled/failed); `retryLastTurn` deletes the failed
  pair from the repository (not just the in-memory transcript) before
  re-sending; `markInterruptedGenerationsAtLaunch()` delegates to the
  repository. `messages(for:)` lazily loads a conversation's transcript
  from the repository on first access per session.
- `AppViewModel` now has `attachRepository(_:initialConversations:)` —
  the production path, which takes an already-fetched conversation list
  rather than fetching itself (see crash story) — plus the older
  `loadFromRepository(_:)` (kept for flexibility/tests, but production
  code uses `attachRepository`). `startNewConversation`/`delete`/`rename`
  all write through to the repository when one is attached, falling back
  to in-memory-only behavior when not (previews/some tests).
  `refreshConversationMetadata(conversationID:)` re-reads one
  conversation's preview/`updatedAt` and re-sorts the list — called from
  `ConversationDetailView.onChange` whenever that conversation's
  messages change, so the sidebar reflects new activity without polling.
- `Conversation.preview` renamed to `lastMessagePreview` throughout
  (domain type, SwiftData column, `SidebarView`, fixtures, tests) for
  clarity now that it's a real persisted, message-derived field rather
  than a Stage 0 placeholder string.
- `AppDependencies.live()` now constructs the real SwiftData container/
  repository, runs `markInterruptedGenerationsAtLaunch()`, and fetches
  the initial conversation list — all synchronously, before
  `ChatterBatApp.body` is even evaluated (see crash story for why this
  specific placement matters). `RootView.init` passes that pre-fetched
  list into `AppViewModel.attachRepository` — `RootView` itself never
  calls into SwiftData.
- New tests (11): `SwiftDataConversationRepositoryTests` (6),
  `SwiftDataConversationRepositoryAdditionalTests` (5) — both using
  `ChatterBatModelContainer.inMemory()`, constructed fully inline in
  every test method (see crash story: no `setUp()`, no helper function).

### The SwiftData crash story (important — read before touching `Persistence/`)

This stage hit a serious, toolchain-specific SwiftData bug (Xcode 26.6 /
macOS 26.6.2, Swift 6.3.3) that cost most of this session's time and is
recorded here in detail so it is never accidentally reintroduced.

**Symptom 1 — app crashes at launch (EXC_BREAKPOINT / SIGTRAP) the
moment any view fetches from SwiftData**, but only once the on-disk
store contains rows and/or under certain launch timings. Root cause,
found by bisection with a series of minimal standalone reproduction
apps (built and run outside the ChatterBat project) and reading actual
crash reports via `python3` JSON parsing of `~/Library/Logs/
DiagnosticReports/ChatterBat-*.ips`:
- Nesting `@Model` classes inside the `VersionedSchema` enum body
  (Apple's commonly-shown sample pattern) was suspected first and
  un-nested to file scope — this did **not** fix it, but is kept as the
  file layout anyway since it's arguably cleaner and rules out that
  hypothesis for good.
- Using a SwiftData `@Relationship(deleteRule:inverse:)` between
  `PersistedConversation` and `PersistedMessage`, combined with
  `#Predicate`/`sortBy:` FetchDescriptors, was the actual trigger.
  Replacing the relationship with a plain `conversationID: UUID` column
  and replacing every `#Predicate`/`sortBy:` FetchDescriptor with an
  unfiltered fetch + Swift-side `.filter`/`.sorted` eliminated the
  crash entirely, verified across many consecutive real `open`-launches
  (not just `xcodebuild build`) with a real, non-empty on-disk store.

**Symptom 2 — after fixing the app-launch crash, the new persistence
*unit tests* still failed**, but as **hangs** (each test took ~20–22s
then XCTest logged "Restarting after unexpected exit, crash, or test
timeout" and relaunched for the next test), not crashes. Root cause,
found the same way (minimal repro tests added and removed from
`ChatterBatTests` during bisection):
- `setUp()`/`tearDown()` overriding a stored `SwiftDataConversationRepository`
  instance property hung every test.
- Removing `setUp`/`tearDown` but calling a `private func
  makeRepository()` helper (even `@MainActor`, even called correctly)
  **also hung**.
- The exact same container/repository construction code, inlined
  directly in the test method body with no `setUp` and no helper
  function, passed in single-digit milliseconds.
- This reproduces with a free (non-member) helper function too, so it
  is not specific to instance methods. It looks like a toolchain/
  debugger-instrumentation interaction specific to calling into
  `ModelContainer`/`ModelContext` construction through any intermediate
  function under XCTest's `-Onone` test-runner instrumentation on this
  toolchain — not a bug in the production code.
- Fix: every persistence test in `SwiftDataConversationRepositoryTests`/
  `SwiftDataConversationRepositoryAdditionalTests` constructs its
  container and repository **inline**, directly in the test method,
  with no `setUp`, no `tearDown`, and no wrapping helper function. This
  is intentionally duplicated across tests rather than factored out —
  see the doc comment at the top of both files, which explicitly warns
  against "cleaning up" this duplication without re-verifying against a
  real timed run first.

**Practical implications for future stages:**
- Prefer plain foreign-key columns over `@Relationship` for any new
  persisted model until this is re-verified as fixed on a newer
  toolchain.
- Prefer unfiltered fetch + Swift-side filtering over `#Predicate`/
  `sortBy:` FetchDescriptors for the same reason. This is a real,
  measured performance trade-off (O(n) client-side filtering instead of
  a store-level query), acceptable at the expected scale of one user's
  local chat history, but worth revisiting if conversation/message
  counts ever grow large.
- Never wrap SwiftData container/context construction in a helper
  function inside a test file. Inline it, every time, in every test.
- If a future stage's manual/automated testing shows an inexplicable
  hang or crash touching `Persistence/`, re-read this section before
  assuming it's a new bug.

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
- Stage 4: extensive manual launch verification given the crash story
  above — real `open`-launches (not just `xcodebuild build`, which
  does not exercise the sandboxed launch path or AppKit window
  restoration where the original crash occurred) of the actual signed
  app bundle, repeated across a completely fresh container, a container
  with real accumulated conversation/message rows, and multiple
  consecutive quit/relaunch cycles — all via `open` +
  `osascript ... quit` (not raw process kill, so real AppKit
  termination/restoration paths are exercised) — with zero crashes and
  zero entries in `~/Library/Logs/DiagnosticReports/` after the fix.
  Cleared the on-disk store (`~/Library/Containers/com.chatterbat.app/
  Data/Library/Application Support/default.store*`) before finishing
  this stage so the next manual run starts from a clean slate.
- Stage 5: launched the rebuilt app fresh (no on-disk store, no
  onboarding-completed flag) via `open` and confirmed via `pgrep` it
  started with no crash — this exercises the new onboarding sheet
  presenting at launch. Confirmed via `defaults write .../
  hasCompletedOnboarding -bool true` + relaunch that the app also
  starts cleanly when onboarding is already marked complete (sheet
  should not reappear — this was inferred from the stored flag and the
  `!hasCompletedOnboarding()` check in `RootView.init`, not visually
  confirmed, since no screen capture is available here). Noted that an
  `osascript ... quit` sent while the onboarding sheet is showing is
  intercepted (macOS treats it as "User canceled" rather than quitting)
  — this is expected modal-sheet behavior, not a bug, and was confirmed
  by observing that quit worked normally once the onboarding-completed
  flag was set. Did not visually confirm the onboarding sheet's layout,
  the new empty/search-empty sidebar states, code-block rendering,
  auto-scroll behavior, or any accessibility label via VoiceOver — all
  of these are implemented and (where logic-testable) unit-tested, but
  not eyeballed or screen-reader-tested. Cleared the on-disk store and
  onboarding flag again before finishing.

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
Result (Stage 5, current): **TEST SUCCEEDED** — 138/138 tests passed
(17 new from Stage 5: `MessageContentParserTests` (11),
`AutoScrollPolicyTests` (4), `UserDefaultsOnboardingStateStoreTests` (2);
all Stage 0–4 suites still pass unchanged, 121 from before). One real
bug was caught and fixed during this stage's own test run: the fenced-
code-block parser initially dropped an empty code block (`` ``` ``
immediately followed by `` ``` ``) because its flush function
early-returned on empty pending lines — fixed by distinguishing "about
to close a fence" from "ordinary end-of-text flush." Re-ran the full
suite after the fix — 138/138, ~1.4s total.

Full scheme test (`ChatterBatTests` + `ChatterBatUITests` together):
Result: still **FAILS** at the `ChatterBatUITests` load step only (same
root cause as Stage 0, unchanged by this stage's work — see Known
Limitations). Unit tests still ran and passed in the same invocation
before the UI test bundle failed to load.

Result (Stage 6, current): **TEST SUCCEEDED** — 190/190 tests passed
(52 new: `AdvancedChatSettingsTests` (9), `ChatRequestBuilderTests`
(8), `ContextUsageEstimateTests` (5), `ChatCoordinatorAdvancedSettingsTests`
(7), `SwiftDataConversationRepositoryContextBoundaryTests` (5),
`ConversationExportCodingTests` (7), `AppViewModelExportImportTests`
(6), plus 3 new cases added to the existing `ChatStreamDecoderTests`;
all Stage 0–5 suites still pass unchanged, 138 from before). One real
issue was caught by this stage's own new tests: the initial ISO 8601
date-encoding strategy for conversation export (plain `.iso8601`) was
lossy across an encode/decode round trip; fixed with a custom
fractional-seconds-aware codec (still millisecond-precision, not
perfectly lossless — see the Stage 6 "known gap" note above). Re-ran
the full suite 3 times consecutively after all fixes — 190/190 every
time, 1.4–1.9s total, zero hangs, zero new crash reports in
`~/Library/Logs/DiagnosticReports/`.

Result (Stage 7, current): **TEST SUCCEEDED** — 227/227 tests passed
(37 new — see the Stage 7 what's-implemented section above for the
exact breakdown; all Stage 0–6 suites still pass unchanged, 190 from
before). No regressions and no new fixes required — every new test
passed on first run. Full main-target build (`xcodebuild ...
build`) also succeeded with zero warnings.

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
- Stage 6: rebuilt and launched the app after adding the advanced
  settings popover, context-boundary context-menu action, and export/
  import UI — confirmed via `pgrep` it starts with no crash on a
  freshly-wiped store (exercising the new `contextBoundaryMessageID`
  column's default value on brand-new `PersistedConversation` rows).
  Relaunched 3 more times in a row, each terminated cleanly via `kill`,
  with zero new crash reports. Attempted to script a full interactive
  walkthrough (create a chat, open the Advanced Settings popover,
  right-click a message for "Start Context Here," export via ⌘-less
  toolbar button, re-import the file) via `osascript`
  keystroke-sending, but this environment's `osascript` has no
  Accessibility permission ("osascript is not allowed to send
  keystrokes") — the same class of limitation as every prior stage's
  "no interactive display" note, just hit at the keystroke-automation
  layer this time instead of at `screencapture`. As a result: the
  popover's actual on-screen layout/sections-shown-per-model, the
  message context menu's "Start Context Here" item, the sidebar's
  Export…/Import Conversation… menu items and their native
  save/open-panel behavior, and the whole export→import round trip as
  a real user action have **not** been visually or interactively
  confirmed — only implemented and unit-tested (`AppViewModelExportImportTests`
  covers the underlying encode/decode/persist logic without any file
  panel). **Action for a human:** actually click through Advanced
  Settings for a Venice reasoning model and an OpenRouter model,
  right-click a message and confirm the boundary marker appears on the
  right message, export a real conversation to a file, inspect the
  JSON, and re-import it to confirm it appears as a new, correct
  conversation.
- Stage 7: rebuilt and launched the app after adding the agent-tools
  approval sheet, the entitlement change, and the new
  `PersistedMessage` columns — confirmed via `ps aux`/`pgrep` it starts
  with no crash on a freshly-wiped store, then terminated it cleanly.
  Verified via `codesign -d --entitlements :-` on the built,
  ad-hoc-signed app bundle that
  `com.apple.security.files.user-selected.read-only` is actually
  present alongside the existing sandbox/network entitlements. Did
  **not** interactively trigger a real tool call or click through the
  approval sheet/native panel — same `osascript`-lacks-Accessibility
  limitation as Stage 6; see Known Limitation 20 below for the
  specific human action recommended.

## Known limitations

1. ~~XCUITest target fails to load via `xcodebuild test` in this
   environment.~~ — **fixed, see Known Limitation 22.** Root cause was
   confirmed via `codesign -dvvv`: with automatic signing and no
   Xcode-managed developer account configured, the UI test runner and
   its `.xctest` bundle both ended up ad hoc-signed with
   `TeamIdentifier=not set`, and the OS `dlopen` rejected loading it
   with a "different Team IDs" mapping error. Once an Apple ID was
   signed into Xcode → Settings → Accounts on this machine and
   `DEVELOPMENT_TEAM: "AM3FXP5BXT"` was set in `project.yml` (see
   Known Limitation 22 and `docs/DECISIONS.md`), `xcodebuild test
   -scheme ChatterBat -destination 'platform=macOS'` ran
   `ChatterBatUITests.testAppLaunchesAndShowsSidebar` successfully —
   confirmed passing alongside all 227 `ChatterBatTests`. Left here
   (struck through) rather than deleted so the history stays legible.
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
5. ~~Persistence (SwiftData) is still entirely unimplemented~~ — **now
   implemented as of Stage 4.** Left here (struck through) rather than
   deleted so the stage-by-stage history stays legible; see the Stage 4
   section above for what's actually implemented.
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
12. **`ConversationDetailView`'s `.onChange`-triggered
    `refreshConversationMetadata` (which calls
    `repository.loadAllConversations()` from a live view, after Send)
    has not been exercised with a real repository + real chat
    completion** — only indirectly, since it requires an actual
    provider key to trigger (see limitation 9). Given the crash story
    above was specifically about *launch-time* SwiftData fetches from
    views, and this fetch happens well after launch in response to a
    genuine user action, it is expected to be safe by the same
    reasoning that fixed `RootView`/`AppDependencies` — but this
    specific call path has not been directly, manually confirmed with a
    live key. **Action for a human:** send a real message and confirm
    the sidebar's preview/ordering updates without any crash or hang.
13. No SwiftData migration has ever actually been exercised (there is
    only one schema version, and `ChatterBatMigrationPlan.stages` is
    empty). The plumbing exists (`ChatterBatSchemaV1`,
    `ChatterBatMigrationPlan`) but is entirely unverified beyond "it
    doesn't crash with zero migration stages" — a real migration stage
    should be added and tested from a v1-populated store the first time
    the schema actually changes, not assumed to work by inspection.
14. Given the SwiftData relationship/predicate/sortBy issues found in
    Stage 4, other untested `FetchDescriptor` usages elsewhere in the
    codebase were not searched for (there are none currently — all
    persistence access goes through `SwiftDataConversationRepository`
    — but this is worth re-confirming if `Persistence/` grows).
15. **Nothing in this stage was visually confirmed on screen** — no
    screenshot tooling, no VoiceOver testing, no manual scroll-position
    interaction, and no Tab-key-only navigation walkthrough were
    possible in this environment (see Stage 0's original
    `screencapture` limitation, which still applies). Everything in
    this stage that has *decidable logic* (Markdown/code-block parsing,
    auto-scroll follow/stop decisions, onboarding persistence) is unit-
    tested; everything that is purely visual/interactive layout,
    contrast, VoiceOver phrasing quality, and keyboard focus order
    (especially the nested favorite-star button flagged in `ModelRow`)
    is implemented per the brief's spec but genuinely unverified.
    **Action for a human:** run the app, tab through the composer →
    Send/Stop → sidebar → model picker without a mouse; turn on
    VoiceOver and listen to a few messages and the onboarding sheet;
    send a message containing a fenced code block and confirm it
    renders monospaced with a working Copy button; scroll up during a
    long streaming response and confirm it stops auto-following, then
    scroll back down and confirm it resumes.
16. Long-transcript performance (per the brief's Stage 5 requirement)
    was not specifically profiled — `TranscriptView` uses `LazyVStack`
    inside a `ScrollView`, which is the standard SwiftUI approach for
    large lists, but no measurement was done with a very long
    conversation (hundreds of messages) since generating one requires
    either a live provider or extensive synthetic data not yet built
    for this purpose.
17. **No `osascript`/UI-automation walkthrough of Stage 6's new UI was
    possible** — this environment's `osascript` lacks the
    Accessibility permission needed to send keystrokes or drive
    controls (confirmed via the literal error "osascript is not
    allowed to send keystrokes"). The Advanced Settings popover,
    per-message "Start Context Here" context-menu item and its visible
    boundary marker, and the sidebar's Export…/Import Conversation…
    `.fileExporter`/`.fileImporter` flow are implemented and covered by
    unit tests for their underlying logic, but the actual on-screen
    behavior (popover layout and section visibility per model, native
    save/open panel behavior, real file round-trip) has not been
    interactively exercised. See the Stage 6 manual-verification entry
    above for the specific human action recommended.
18. `PersistedConversation.contextBoundaryMessageID` (the new
    Stage 6 column) has only been tested against freshly-created
    stores, never against a real pre-Stage-6 on-disk store with
    existing data — see the "Known gap" note under Stage 6's
    what's-implemented section above for the specific verification
    step a human should run before trusting this with real user data.
19. OpenRouter's richer provider-routing controls (`order`, `only`,
    `ignore`, `quantizations`, `sort`, `max_price`, `enforce_distillable_text`)
    were deliberately not implemented this stage — only
    `allow_fallbacks`, `data_collection`, and `zdr` are exposed. If a
    future stage wants to expose provider ordering/allow-listing, it
    will need a way to fetch and display OpenRouter's provider-slug
    catalog first (there is currently no fetcher for it anywhere in
    the codebase).
20. **No interactive walkthrough of Stage 7's new UI was possible** —
    same `osascript`-lacks-Accessibility-permission limitation as
    Stage 6. The approval sheet (`AgentToolApprovalView`), the "Agent
    Tools (Beta)" toggle in `AdvancedSettingsView`, and the actual
    on-screen `NSOpenPanel` behavior (its title/prompt text, whether
    it correctly restricts to files vs. folders per tool) have not
    been visually confirmed, only unit-tested at the logic layer
    (`ChatCoordinator`'s approval state machine, `AgentToolExecutor`'s
    file/directory reading against real temp-directory fixtures with
    a scripted fake panel presenter). **Action for a human:** connect
    a real Venice or OpenRouter account with a tool-calling-capable
    model, turn on "Agent Tools (Beta)" in Advanced Settings, ask a
    question that would plausibly prompt a tool call (e.g. "what's in
    this file: <describe a real local file>"), confirm the approval
    sheet shows the right tool/reason, approve it, confirm the native
    panel appears and only reads the chosen file, and confirm denying
    a request is honestly reflected in the transcript.
21. **No live end-to-end round trip against a real Venice/OpenRouter
    tool-calling-capable model was performed** — same "automated tests
    never call paid APIs" constraint as every prior stage. The exact
    request/response shapes were verified against current provider
    documentation (OpenRouter's tool-calling guide and streaming
    reference; Venice's chat completions schema) and exercised via
    `FakeChatStreamingClient`-scripted events, but a real model's
    actual behavior when offered these two specific tool
    definitions — whether it reliably includes a `reason`, whether it
    ever emits more than one function call despite
    `parallel_tool_calls: false`, whether some models refuse to use
    tools with no path argument at all — has not been observed.
22. **Ad hoc code signing (no `DEVELOPMENT_TEAM`) caused two real,
    reported user-facing problems and has now been fixed — read this
    before touching `project.yml`'s signing settings again.** First
    manual end-to-end run-through of the built app (post-Stage-7)
    surfaced: (a) creating a new conversation crashed with
    `EXC_BREAKPOINT` inside `SwiftDataConversationRepository.
    createConversation`'s `context.insert`/`context.save` — but *only*
    when launched via Xcode's own Run/Debug (⌘R), which attaches
    LLDB; a plain `xcodebuild build` + `open ChatterBat.app` launch (no
    debugger) never crashed, and neither did the exact same
    `context.insert`/`context.save` code extracted into a standalone
    CLI binary run directly against a copy of the real on-disk store.
    Running that identical CLI binary under `lldb` reproduced an
    indefinite hang on the same call — consistent with the SwiftData +
    debugger-instrumentation class of bug already documented in this
    stage's crash story above, just triggered by a different code path
    (`insert`/`save` during interactive use, rather than construction
    during test-runner instrumentation). **This means EXC_BREAKPOINT
    on this toolchain when running via Xcode's debugger is not
    necessarily a new regression — always try a debugger-less launch
    (Build-only, then open the built `.app` directly) before assuming
    the persistence code itself is broken.** (b) the user reported
    needing to repaste their Venice/OpenRouter API keys after every
    relaunch during development. Root cause, confirmed via `codesign
    -dvvv` across consecutive clean rebuilds: ad hoc-signed builds get
    `TeamIdentifier=not set` and a *different* CDHash every single
    build. Since the app is sandboxed
    (`com.apple.security.app-sandbox`), Keychain's per-app access
    control is anchored to the app's code identity, so a build with no
    stable team identity can lose access to Keychain items it
    previously saved as soon as it's rebuilt. Fix (see
    `docs/DECISIONS.md`'s updated Stage 0 entry): once an Apple ID was
    signed into Xcode → Settings → Accounts on this machine,
    `DEVELOPMENT_TEAM: "AM3FXP5BXT"` was added to `project.yml`
    (`CODE_SIGN_STYLE` stays `Automatic`); confirmed
    `TeamIdentifier=AM3FXP5BXT` is now identical across multiple
    consecutive clean rebuilds, both via `xcodebuild` and via Xcode's
    own Build/Run. **Action for a human on a different machine:** this
    exact team ID (`AM3FXP5BXT`) is specific to the Apple ID signed
    into Xcode on this machine — on a fresh machine, sign into Xcode →
    Settings → Accounts first, then update `DEVELOPMENT_TEAM` in
    `project.yml` to that machine's own team ID (visible under Xcode →
    Settings → Accounts, or in `security find-identity -v
    -p codesigning`/existing `.mobileprovision` files under
    `~/Library/Developer/Xcode/UserData/Provisioning Profiles`), then
    re-run `xcodegen generate`.

## Next small task

Stages 0–7 are now complete per the brief's scope (chat-first MVP,
enhanced chat controls, and the permission-controlled agent beta).
Stage 8 — hardening and distribution — is next. See
`docs/DEVELOPMENT_PLAN.md` and the original brief for Stage 8's
acceptance criteria before starting; per this project's established
rule, do not implement multiple stages in one pass.
