# Cost hygiene and local Auto — September 8, 2026

**A2 update:** the initial session-only Auto setup below is historical.
See `MODEL_BOOKMARKS.md` for the current explicit saved-policy flow. Auto
now uses saved service/privacy/rate ceilings; catalog refresh cannot raise
them. Favorites, pin and Auto policy persist independently. Request privacy
uses saved restrictions plus any stricter current settings. Other cost
accounting/value-highlighting rules below remain unchanged.

## Scope

Native macOS SwiftUI feature pass, no new packages, paid routing call,
embedding index, background polling, persistence schema or chat truncation.
The earlier uncommitted SwiftData container-lifetime fix is preserved.

### Lean Venice requests

`venice_parameters.include_venice_system_prompt` is explicitly false by
default. Advanced Settings → Venice Prompt restores it. This control is
independent of reasoning capabilities and is never sent to OpenRouter.
Like existing advanced settings it lasts for the app session, not relaunch.
Saved messages/context are unchanged. Behavior/personality may differ;
actual token savings require a live before/after comparison.

### Accounting

Streaming decodes all events in a frame, including simultaneous content,
tool fragments, finish and usage. Separate cost-only frames are supported.
Usage snapshots merge missing fields instead of adding duplicate counts.
Reported USD remains provider-supplied, not calculated from catalog prices.
Missing usage remains unknown. Draft text is included in the rough context
estimate, with explicit exclusions for provider/tool overhead.

### Value outline

Subtle 12-second rainbow border; 15fps only on visible eligible rows in an
active scene, static with Reduce Motion/inactive scene. Text stays still.
The ✦ marker and tooltip provide a non-color explanation.

Score = 3 × listed input USD/M + listed output USD/M. This fixed 3:1 mix
is a comparison heuristic, NOT measured quality or a request cost quote.
Compare only same service, privacy label, exact tools/reasoning/vision flags,
and context bucket (<32K, 32K–<128K, >=128K; unknown separate).
Require at least four priced peers and a price spread; highlight the
cheapest quarter, at most three per group. Ties sort by stable identity.
Unknown/negative/NaN prices cannot qualify. Zero prices are valid when
actually reported. Catalog price text preserves up to six decimal places.

### 🤖 Auto (opt-in, session-only)

1. Open the model picker and select a model. This sets service/privacy and
   separate input/output **listed rate** ceilings, not a hard dollar budget.
2. Star other models you trust. The eligible pool is your selection plus
   these favorites, never the entire catalog. With no favorites Auto can
   only use the selected model, if it meets the task's requirements.
3. Enable 🤖. The composer shows the next candidate and local rule. Nothing
   is sent until Send. Manual selection remains the ceiling; it is not
   overwritten by the cheapest candidate. Actual replies retain attribution.
4. English whole-word code/math/analysis hints (and code fences) require
   known reasoning support. The previous two eligible user messages (last
   2,000 characters each) keep brief follow-ups attached to their task.
   Explicit reasoning controls also require reasoning support. This is NOT
   a semantic classifier, multilingual intelligence score or quality promise.
5. Tools require known support. Context must be known and fit a conservative
   UTF-8 byte budget plus per-message overhead and 4,096 tokens of headroom.
   This does not tokenize exactly or guarantee room for later file-tool
   results; no history is dropped. File approval remains unchanged.
6. Choose minimum 3:1 price score among eligible models. No candidate means
   a visible explanation, not silent downgrade, higher-price fallback or
   automatic retry. OpenRouter's `openrouter/*` server routers are excluded.
7. No cross-service or changed Venice privacy-label routing. Existing
   disclosure still applies when the user manually changes services.
   OpenRouter's existing per-request provider privacy settings are retained.

The shared catalog survives picker dismissal for this session. A failed,
loading or >=15-minute-old catalog cannot drive Auto/value decisions.
Open/reload the picker to refresh using non-inference catalog GET requests.
Send rechecks freshness; a preview may age while idle. Prices are not frozen
contracts: tiers, cache discounts, tools, output length and provider routing
can affect actual bills. No provider-side dollar cap has been added.

## Deliberately deferred

- Quality benchmarks/provider trait fetchers and automatic summaries.
- Cached/reasoning-token detail persistence and conversation spending ledger.
- Changes to existing file-result replay/persistence semantics.
- Per-conversation or cross-launch Auto/advanced preferences.

## Documentation checked

- https://docs.venice.ai/api-reference/endpoint/chat/completions
- https://docs.venice.ai/overview/pricing
- https://docs.venice.ai/guides/features/prompt-caching
- https://docs.venice.ai/api-reference/endpoint/models/traits
- https://openrouter.ai/docs/guides/routing/routers/auto-router

OpenRouter documents server-side Auto with no additional routing fee, but
it is not local classification. Venice traits are task/model mappings, not
proof of per-prompt local routing. Neither is called by this implementation.

## Manual checks before TestFlight

- In fresh chats, compare the same Venice model/message with provider
  instructions off/on and reconcile reported usage with provider billing.
- Star a cheaper general model and a reasoning model; select an appropriate
  ceiling, toggle Auto, try ordinary chat, code, follow-ups and long context.
- Check chosen model attribution, cross-service disclosure, tool approval,
  relaunch persistence, failed requests and explicit retries.
- Inspect the picker on a real display (narrow rows/long names), keyboard
  focus/VoiceOver and the gradient with Reduce Motion on/off.
- Verify App Store Connect app record, paid Developer Program enrollment,
  distribution signing/provisioning, privacy disclosures/policy, export
  compliance, release archive validation and upload. Local development
  signing alone does not establish TestFlight eligibility.

## Verification results

- XcodeGen project regeneration succeeded.
- Full `ChatterBatTests` run: **248 tests passed, zero failures**.
  Includes router constraints/tie-breaking, stale catalog rejection, current
  price metadata, combined streaming events, split usage persistence,
  prompt preference gating and unchanged context/history.
- Release configuration: **BUILD SUCCEEDED**. Only the expected warning
  that AppIntents metadata extraction is skipped (no framework dependency).
- `git diff --check`: clean.
- Logs: `/tmp/ChatterBatValueTestsFinal.log` and
  `/tmp/ChatterBatValueRelease.log`.

No paid inference calls, visual/VoiceOver verification, UI test execution,
distribution archive validation or TestFlight uploads were performed by
this feature pass. The manual checklist above remains necessary.