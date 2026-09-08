# ChatterBat Development Plan

This is the condensed, working reference for the staged build-out. The full
original brief (product intent, UX spec, provider integration requirements,
testing contract, and reusable agent prompts) is the authoritative source;
this file exists so future stages don't need that entire document pasted
into every session. Consult the original brief for detail beyond what's
summarized here.

## Scope boundary

**Chat-first MVP = Stages 0–5.** Enhanced chat controls are Stage 6. A
permission-controlled, tool-using agent beta is Stage 7 — explicitly not
part of the initial product. Stage 8 is hardening/distribution.

Out of scope for the foreseeable future: shell execution, autonomous file
edits, MCP, browser automation, cloud sync, a ChatterBat backend, local
model hosting, automatic cross-service fallback, image/audio/video
generation, RAG, multi-agent orchestration, client-side E2EE, App Store
purchase flows, an updater.

## Stages

| Stage | Name | Depends on |
|---|---|---|
| 0 | Buildable native foundation | — |
| 1 | Secure account connection (Keychain, Venice/OpenRouter settings) | 0 |
| 2 | Catalog and unified model picker | 1 |
| 3 | Reliable streaming chat | 1, 2 |
| 4 | Durable conversation history (SwiftData) | 3 |
| 5 | Native polish and MVP release gate | 0–4 |
| 6 | Enhanced chat controls (reasoning, routing, cost, export) | 5 |
| 7 | Permission-controlled agent beta (read-only tools) | 5 |
| 8 | Hardening and distribution | 5 (6/7 optional) |

Each stage must build, pass its own tests, and update `docs/STATUS.md`
before the next stage begins. Do not implement multiple stages in one pass.

## Non-negotiable engineering rules (apply to every stage)

- Automated tests never call paid APIs. Use fixtures, injected transport
  (`URLProtocol` or equivalent), mock credential storage, and temp folders.
- API keys live only in Keychain — never UserDefaults, SwiftData, logs,
  exports, or source.
- No hidden model calls for titles, summaries, ranking, or routing.
- Unknown capability/price is "Unknown," never silently treated as
  unsupported or free.
- Venice and OpenRouter are distinct services with distinct payloads;
  never send one provider's fields to the other.
- Model identity = (service, modelID). Never merge across services by name.
- Stop/cancel must cancel the actual network task; explain that local
  cancellation doesn't guarantee upstream billing stopped.
- No automatic retries of billable chat POSTs after ambiguous failures.
- One active generation globally in the MVP (documented in UI, not hidden).

## Key references

- OpenRouter: `https://openrouter.ai/api/v1` — `/models`, `/chat/completions`,
  Bearer auth, SSE streaming per `https://openrouter.ai/docs/api-reference/streaming`.
- Venice: `https://api.venice.ai/api/v1` — `/models`, `/chat/completions`,
  Bearer auth, OpenAI-compatible, `venice_parameters` for provider-specific
  features. Privacy is per-model (`anonymized` / `private` / TEE / E2EE) —
  never claim a blanket privacy guarantee across all Venice models.

Re-verify exact field names/behavior against current docs before
implementing each stage; both APIs evolve.

## Stage 0 summary (complete)

Xcode project generated via XcodeGen (`project.yml` is the source of
truth), SwiftUI split-view shell, Settings scene, unit + UI test targets,
App Sandbox entitlement with outgoing network client access, demo/preview
fixtures explicitly labeled and isolated from any production path. See
`docs/STATUS.md` for verification detail and known limitations.

## Stage 1 summary (complete)

`AIService` domain enum; `CredentialStore`/`KeychainCredentialStore`
(Security framework, per-service Keychain items, no iCloud sync);
`HTTPClient`/`URLSessionHTTPClient` (ephemeral session, cross-host
redirect blocking); `ConnectionChecking` with one implementation per
service calling a verified non-billable, key-authenticating endpoint
(`GET /api_keys/rate_limits` for Venice, `GET /api/v1/key` for
OpenRouter — not the public `/models` catalog); `AccountSettingsViewModel`
+ `AccountsSettingsView` (new Settings → Accounts tab); `AppDependencies`
factory wiring the real implementations into the app. 35/35 unit tests
pass, including an isolated real-Keychain integration suite. See
`docs/STATUS.md` for full detail, and `docs/DECISIONS.md` for why these
specific endpoints and boundaries were chosen.

Known gap carried into Stage 2: connection verification has only been
tested against fixtures matching documented response shapes, not a live
key — see STATUS.md limitation 3 for the recommended manual check.

## Stage 2 summary (complete)

`ModelIdentity`/`CapabilitySupport`/`ModelPricing`/`ModelInfo`/
`CatalogLoadState` domain types; `ModelCatalogFetching` with
`VeniceModelCatalogFetcher` (`GET /models?type=text`) and
`OpenRouterModelCatalogFetcher` (`GET /models`), both using lenient
per-entry `JSONSerialization` decoding so one malformed entry doesn't
discard the catalog; pricing normalized to USD/1M-tokens at the fetcher
boundary (Venice already reports that unit, OpenRouter reports per-token
strings that get multiplied by 1,000,000); `ModelPreferencesStore`/
`UserDefaultsModelPreferencesStore` for favorites/recents;
`ModelPickerViewModel` + real `ModelPickerView`/`ModelRow` replacing
`ModelPickerPlaceholderView`. 60/60 unit tests pass, including one built
directly from Venice's documented example response. See `docs/STATUS.md`
for full detail and `docs/DECISIONS.md` for why `JSONSerialization` was
chosen over `Decodable` here.

Known gap carried into Stage 3: catalog fetchers have only been tested
against fixtures, not a live key — see STATUS.md limitation 6.

## Stage 3 summary (complete)

`SSEParser` (byte-level, fragmentation/UTF-8-split/CRLF/comments-safe),
`ChatStreamDecoder` (OpenAI-compatible chunk → contentDelta/finished/
usage/streamError/ignorable, mid-stream-HTTP-200-error-aware),
`StreamingHTTPClient`/`URLSessionStreamingHTTPClient` (chunked transport,
redirect-blocked, cancellable), `ChatRequestBuilder`/`ChatRequestError`,
one shared `StandardChatStreamingClient` for both services (justified in
DECISIONS.md — the chunk shape genuinely is shared, unlike catalog
decoding), and `ChatCoordinator` (in-memory transcripts, single global
generation slot, Stop/Retry, cross-conversation isolation, cross-service
disclosure gated on actual sent history). Real chat UI
(`TranscriptView`/`ComposerView`/`ConversationDetailView`) replaces the
Stage 0 disabled placeholder composer. 99/99 unit tests pass (39 new),
re-run 3× to check for timing flakiness in cancellation tests. See
`docs/STATUS.md` for full detail and `docs/DECISIONS.md` for the
shared-vs-separate-implementation reasoning.

Known gap carried into Stage 4: no real chat completion has been sent to
either live provider yet — see STATUS.md limitation 9 for the recommended
manual check.

## Stage 4 summary (complete)

SwiftData schema (`PersistedConversation`/`PersistedMessage`,
`ChatterBatSchemaV1`/`ChatterBatMigrationPlan`) and
`ConversationRepository`/`SwiftDataConversationRepository`;
`ChatCoordinator` now persists on send/checkpoint/terminal-state/retry
and recovers interrupted generations at launch; `AppViewModel` writes
through to the repository for create/rename/delete. 121/121 unit tests
pass. This stage also uncovered and fixed a serious toolchain-specific
SwiftData crash/hang bug — **read `docs/STATUS.md`'s "SwiftData crash
story" and `docs/DECISIONS.md`'s Stage 4 entries before modifying
anything in `Persistence/` or its tests.** In short: no
`@Relationship`, no `#Predicate`/`sortBy:` FetchDescriptors, no
SwiftData construction inside `setUp()`/`tearDown()` or a wrapping
helper function, and the initial launch-time fetch happens synchronously
in `AppDependencies.live()`, not in any SwiftUI view lifecycle hook.

Known gaps carried into Stage 5: the `.onChange`-triggered sidebar
refresh after a real Send has not been manually confirmed with a live
key (STATUS.md limitation 12); no real schema migration has ever been
exercised (limitation 13).

## Stage 5 summary (complete)

`MessageContentParser`/`MessageContentView`/`CodeBlockView` add a
deliberate, fence-only Markdown/code-block rendering subset with per-
code-block and per-message Copy actions, replacing the old plain-text-
only `TranscriptView`. `AutoScrollPolicy` is a pure, unit-tested
follow/stop-following decision object wired into `TranscriptView`'s
scroll behavior. `OnboardingView` + `OnboardingStateStore` add a
single, honest first-run welcome sheet that defers to the real
Settings → Accounts UI rather than duplicating it. `SidebarView` now
distinguishes a genuinely empty conversation list from a search with
no matches. Accessibility labels/hints were added across the model
picker, composer, sidebar, conversation toolbar, and Settings API key
field — including an honestly-documented caveat about the model
picker's nested favorite-star button's keyboard focus (`ModelRow`'s doc
comment). 138/138 unit tests pass (17 new: `MessageContentParserTests`
(11) — which caught and fixed a real empty-code-block parsing bug —
`AutoScrollPolicyTests` (4), `UserDefaultsOnboardingStateStoreTests`
(2)). This completes the chat-first MVP (Stages 0–5).

Known gaps carried forward, all explicitly documented in
`docs/STATUS.md` limitations 15–16: nothing in this stage was visually
confirmed (no screen capture in this environment) — code-block
rendering, the onboarding sheet's layout, the new sidebar empty states,
actual on-screen auto-scroll behavior, and all accessibility labels via
VoiceOver/keyboard-only navigation are implemented and, where the logic
is decidable, unit-tested, but not eyeballed or screen-reader-tested.
Long-transcript scrolling performance was not specifically profiled.

## Stage 6 summary (complete)

`AdvancedChatSettings` (+ `ReasoningEffort`/`VeniceAdvancedSettings`/
`OpenRouterRoutingPreferences`) adds capability-aware reasoning
settings and a deliberately small set of Venice/OpenRouter advanced
controls — every field defaults to a no-op value, and
`applicable(to:)` strips anything that doesn't apply to the selected
model (treating `.unknown` reasoning support the same as
`.unsupported` for request-safety, though it displays differently).
`ChatRequestBuilder`/`ChatStreamingClient` thread `service`/`settings`
through to the request body via a backward-compatible protocol
extension. `ChatUsage` gained `costUSD`/`costCredits` as two distinct,
never-conflated fields (Venice reports real USD; OpenRouter's `cost`
is documented only as "credits," with no confirmed USD exchange
rate). `ChatCoordinator` adds context management
(`setContextBoundary`/`contextBoundaryMessageID`/`contextUsageEstimate`)
— a per-message, explicit, non-destructive "start context here"
marker persisted via a new plain, additive `PersistedConversation`
column — and a versioned JSON export/import format
(`ConversationExport`/`ConversationExportCoding`) wired into
`SidebarView`, which always imports as a brand-new conversation and
never carries any key/account-identifier field. 190/190 unit tests
pass (52 new). This completes Stage 6.

Known gaps carried into Stage 7, both explicitly documented in
`docs/STATUS.md` limitations 17–19: none of Stage 6's new UI (advanced
settings popover, context-boundary context menu, export/import file
panels) was interactively exercised in this environment (no
Accessibility permission for UI automation); the new
`contextBoundaryMessageID` column has only been tested against
freshly-created stores, not a real pre-Stage-6 store with existing
data; OpenRouter's richer provider-routing fields (`order`/`only`/
`ignore`/`quantizations`/`sort`/`max_price`) remain unexposed pending a
provider-catalog fetcher that doesn't exist yet.

## Next stage: Stage 7 — Permission-controlled agent beta

Implement a read-only, tool-using agent beta as an explicitly
separate, optional mode from the chat-first product — every tool
invocation must be visible and individually approvable by the user
before it runs, never auto-approved, and never silently expanding
scope beyond what's shown. See the original brief §11 Stage 7 and its
permission-model requirements for acceptance criteria before starting.
