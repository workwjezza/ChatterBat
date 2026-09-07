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

## Next stage: Stage 3 — Reliable streaming chat

Implement request assembly for `POST /chat/completions` on both
services, a robust SSE parser (fragmented chunks, split UTF-8, LF/CRLF,
comments/keep-alives, `[DONE]`, usage-only frames, HTTP-200-carried
errors, premature disconnects, cancellation), a chat coordinator/state
machine (idle/connecting/streaming/completed/cancelled/failed/
interrupted), Stop and explicit Retry, per-message service/model
attribution, and cross-service history disclosure when the user switches
services mid-conversation. This is the first stage that sends real,
potentially billable requests — automated tests must still use injected
transport/fixtures only, never live keys. See the original brief §6
(Concurrency), §7 (Streaming, Errors and retries), and §11 Stage 3 for
acceptance criteria.
