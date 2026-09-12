# ChatterBat workspace and coding roadmap

Approved direction: September 8, 2026. This extends the original chat-first
stages; it does not claim the capabilities below already exist. Implement
one focused slice, test it, and update STATUS.md before starting the next.

Progress: A1–A3, B1 (in-memory conversation state) and B2 (bounded concurrent
execution) implemented and unit/Release-verified. Manual release checks
remain in STATUS.md; per-chat draft/settings persistence remains deferred.
E1 is complete as a host-security design and unwired policy spike; see
CODING_HOST_SECURITY.md. No executable host or OS permission expansion yet.
E2 adds an unwired workspace registry and bounded read-only executor; see
WORKSPACE_READ_ACCESS.md for tested behavior and integration limits.
E3a adds a separately built signed sandboxed bundled-XPC ping probe, with
live allow/reject checks. See IPC_PROBE.md. No production IPC wiring.
E3b verifies separate sandbox-client/CLI to user-host discovery, authentication,
restart and cleanup via a temporary launchd/App Group ping probe. See
IPC_STANDALONE_PROBE.md; packaged deployment/SMAppService/upgrades remain gates.
E4a adds an experimental local-only desktop workspace preview and off-UI
reads with revocation checks; see WORKSPACE_PREVIEW.md for manual grant gates.
Next: E4b verified grants, controlled workspace tools/events and explicit
provider-context consent. E4b–H are not implemented.
C/D remain parallel desktop tracks.

## Product direction

One Mac-hosted agent runtime, with native desktop, terminal CLI, and later
a **separate iOS control app**. The Mac executes coding tasks; the phone
monitors, reviews diffs, approves actions, and sends instructions. Preserve
the existing Swift/SwiftUI/provider work rather than starting a new backend
stack by default. No new third-party libraries are approved by this plan.

## Batches and acceptance gates

| Batch | Scope | Dependencies / release gate |
|---|---|---|
| A1 | Enter sends; Shift+Enter newline; Command+Enter sends; safe marked-text handling | Native event regression tests, full suite, manual keyboard/IME/accessibility checks |
| A2 | Favorite-model bookmark bar; persistent new-chat default; click active pin to return to Auto | Favorites and default pin are distinct; save Auto's anchor policy separately; relaunch tests; no inference on selection |
| A3 | Existing provider filters plus capability filters and task presets | Unknown is labeled honestly; coding/ideating/history are recommendations, not guaranteed API capabilities |
| B | Independent drafts, model/Auto/settings, requests, approvals and cancellation per chat; concurrent chats with bounded queue | Two streams coexist; cancelling one does not affect another; no cross-session leakage |
| C | Finder-style nested folders; move/reorder/search; sidebar keyword, model/provider, total cost and activity | Existing-store migration; no folder cycles; explicit deletion semantics; unknown/partial spend stays visible |
| D1 | Drag/drop attachments: text/code first, then supported images/documents | Preview/remove/size limits; known-incompatible models disabled with reasons; unknown support unverified; no silent provider switch |
| D2 | Folder/subfolder context toggle and explicit context manifest | Snapshot selected messages; deduplicate overlapping folders/current chat; enforce budget and disclose cross-provider sharing |
| E | Workspace registry, headless tool boundary, policy, approvals and runtime events | Host distribution/permissions spike; denied/stale actions cannot execute; scoped file-tool traversal tests |
| F | Read/search/Git diff; propose/apply patch; approved commands; real CLI sharing agent core | Disposable repo: inspect, plan, approve exact patch, edit, test, report; preserve dirty work; cancel process tree |
| G | Persistent Mac host; thin CLI; versioned client protocol and durable events | UI closure does not stop tasks; event replay/deduplication; crash recovery never blindly repeats side effects |
| H | Separate iOS app: pairing, sessions, chat, diff review, approvals, logs, cancel/reconnect | F and G complete; device revocation; provider keys remain on Mac; background behavior explicit |

Critical path: **A → B → E → F → G → H**. C/D are parallel desktop
improvements after B, not prerequisites that indefinitely delay coding.

### A2 selection semantics

- A favorite belongs in the bar; a pin controls the default for new chats.
- Clicking the active pin returns that default to Auto, with its own saved
  service/privacy/price anchor. Missing policy shows setup, not a guess.
- Existing chats retain their configuration once B lands. Never mutate an
  in-flight request. Identify models by service + model ID.

### C/D data and cost semantics

- Use editable topics/local keywords; no hidden paid naming calls.
- Distinguish last-used model from next-selected model and mixed histories.
- Track spend by request attempt, not just surviving transcript messages;
  retry/deletion must not erase recorded spend. Do not conflate currencies.
- Text extraction, vision, PDF input and image editing are separate abilities.
- Local storage does not eliminate input-token cost. Optional summaries are
  explicit billable operations with source/version freshness disclosure.
- Do not silently truncate or automatically upload folder contents.

## Parallel desktop tracks (after session isolation)

- **Quick Bat:** optional corner launcher/global shortcut, compact chat,
  last-used or designated model, shared attachments, promote to main window.
  No ambient clipboard/screen reading.
- **Double-check:** explicit second opinion first; research-backed review
  later. Preserve original, attribute reviewer and spend, show supported /
  disputed / corrected / unresolved findings. Higher cost is not proof of
  better quality. Multiple reviewers are opt-in.
- **Internet Mode:** evaluate native WebKit for tabs/address bar/navigation
  with associated chat. Explicit current-page/selection sharing, URL/title/
  timestamp provenance. This is not Chrome or a promise of extension parity.
  Read-only research before action-taking automation; page content is
  untrusted data, never permission-granting instructions.
- **Local models:** optional Ollama adapter; defer MLX hosting until needed.
  Not a coding-MVP dependency. Cloud models still receive uploaded context;
  local-to-cloud fallback always needs explicit consent.

## Coding host security and storage gates

The current app sandbox grants user-selected **read-only** file access.
Investigate a separately installed user-level coding host before adding
shell execution; decide signing, distribution, permissions, authenticated
local IPC and Keychain access. Do not silently remove the app sandbox.

- Read-only/plan mode and exact patch/command approval initially; no sudo.
- Installs, deletes, destructive Git, pushes and external effects require
  explicit permission. Approvals bind arguments and relevant file versions.
- A working directory is not OS confinement. Tests and package scripts run
  repository-controlled code under the host's permissions.
- Scoped filesystem tools validate traversal/symlinks; arbitrary shell
  confinement needs a separate enforcement design, not a string allowlist.
- Timeouts, bounded logs, process-tree cancellation and secret redaction.
- Concurrent coding writers need workspace locks or isolated worktrees.
- Preserve SwiftData behind interfaces initially. Establish one writer;
  storage replacement is not automatically required for daemon extraction.
- Protocol includes stable run/action IDs, sequence cursors, idempotency,
  approval expiry and version negotiation. Persist important events before
  broadcast; ambiguous side effects become uncertain/interrupted states.
- Existing provider privacy boundaries, no hidden inference, no automatic
  billable POST retries, and no credentials in logs/exports remain in force.

## Mobile and fork gate

No exact Grok bot/OpenMaus repository URL was supplied. Before adopting any
code, verify identity, license/redistribution and dependency obligations,
native iOS suitability, transport/authentication and agent coupling. A fork
is a potential client accelerator, not a committed backend dependency.

Pair devices with revocable credentials, keep provider keys on the Mac,
and use authenticated protected transport. Bonjour is discovery, not trust.
Private VPN access does not replace application authorization. No raw
public terminal port. Use foreground streaming and reconnect/event replay;
APNs later requires a separate infrastructure/privacy decision and does not
make iOS WebSockets persistent background execution.

## Verification contract

Automated tests use fakes, fixture streams and temporary repositories,
never paid APIs or real credentials. Each slice must build and pass the
unit suite. New persistence schema needs an existing-on-disk migration
test. Manual UI/VoiceOver/IME and live-provider checks must be reported
separately rather than inferred from a green build.