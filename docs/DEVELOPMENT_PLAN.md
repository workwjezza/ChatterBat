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

## Next stage: Stage 1 — Secure account connection

Implement Venice/OpenRouter settings UI, a Keychain service abstraction,
add/replace/remove key flows, connection status, and non-billable
credential verification where the provider API allows it. See the original
brief §7–8 for provider endpoints and Keychain rules, and §11 Stage 1 for
acceptance criteria.
