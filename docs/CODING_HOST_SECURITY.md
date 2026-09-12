# E1 — Coding host security and distribution spike

September 8, 2026. **Design + unwired policy prototype, not a working host.**
No executable target, listener, launch service, filesystem grant, write tool,
command runner, Keychain migration or entitlement change was installed.

**E2 update:** an unwired in-process workspace registry and bounded read-only
executor now exist. See `WORKSPACE_READ_ACCESS.md` for tested behavior and
remaining TOCTOU, OS-grant, synchronous-I/O and integration limitations.
The original E1-only descriptions below remain historical design context.

**E3a update:** isolated signed sandbox-app ↔ bundled XPC ping passed a live
positive/negative authentication matrix. See `IPC_PROBE.md`. Separate host/
CLI discovery and launch-agent deployment remain unverified E3b gates; do
not treat the bundled probe as proof of the recommended host architecture.

**E3b update:** the separate-host ping prototype now verifies App Group
discovery from a sandboxed app and signed CLI, peer rejection, survival of
client exit, reconnect after restart and temporary registration removal.
See `IPC_STANDALONE_PROBE.md`. Packaged installation, SMAppService approval,
upgrade/downgrade and production distribution remain unimplemented gates.

## Recommendation

Preserve the existing sandboxed ChatterBat desktop app. Build a separately
installed, explicitly enabled **user-level ChatterBat coding host** in Swift,
with a CLI sharing its domain/policy/tool code. Do not add a root daemon,
sudo, Full Disk Access requirement, or silently remove the desktop sandbox.

Start the future host as a foreground executable for development and
disposable-repository tests. A separate signed companion app can later own
the user-level launch agent and setup UI. Evaluate SMAppService for that
companion's bundled helper after transport/signing tests. Persistent service
registration belongs to G, not E1. macOS 14 remains the deployment baseline.

The execution host may ultimately be unsandboxed to support normal build
tools. That is an **explicit user-account authority boundary**, not workspace
OS confinement. If product requirements demand that arbitrary repository
code cannot read/write outside a project, a separate VM/container isolation
design and verification is required before offering that guarantee.

## Evidence from this repository / local artifact

- Current entitlements: App Sandbox, outgoing network client, user-selected
  read-only file access. No listener/app-group/Keychain-sharing entitlements.
- Current file tools accept only a reason; the user chooses each item in an
  NSOpenPanel. The new workspace policy is not wired into those tools.
- No Process runner, workspace bookmarks/registry, XPC service, launch agent
  or host executable exists. The coordinator remains UI-process-owned and
  main-actor-bound. B2 concurrency is not a daemon or a headless agent API.
- XcodeGen defines one macOS application plus unit/UI test targets.
- Inspected the existing B2 Release artifact at
  `/tmp/ChatterBatConcurrentRelease/Build/Products/Release/ChatterBat.app`:
  team AM3FXP5BXT, hardened-runtime flag, sandbox/read-only/client entitlements,
  **get-task-allow true**. A local Release build is not a distribution proof.
  No Developer ID availability, notarization or App Store eligibility tested.
- KeychainCredentialStore queries generic passwords by service/account,
  without kSecUseDataProtectionKeychain, kSecAttrAccessGroup or synchronizable.
  Existing comments about this-device accessibility do not establish shared
  host access or universal macOS lock-state behavior. Do not migrate blindly.

## Decisions and rejected shortcuts

| Area | Decision | Why / remaining verification |
|---|---|---|
| Language | Extend Swift/Foundation domain and service interfaces | No Node/Python/Rust rewrite or new third-party dependency justified |
| App boundary | Keep chat app sandbox; separate opt-in host | Read-only entitlement cannot safely be treated as coding authority |
| Privilege | User-level process only | No root daemon, privileged helper or sudo tool |
| Distribution | Plan Developer ID + notarization for coding companion | App Store/TestFlight chat distribution is separate; neither notarization nor same-team signing grants tool authority |
| IPC candidate | Authenticated local XPC for Mac app/CLI | Native candidate, not implemented/proven; minimum-OS API and sandbox service lookup need a signed-target spike |
| Persistent service | Companion-owned user agent, later SMAppService evaluation | Registration subject to user approval; cannot infer unattended lifetime from a generic XPC example |
| Credentials | Host-owned Keychain namespace with explicit setup | Avoid assuming existing app items are shared; no provider secrets in CLI args/env or remote client |
| Storage | Keep chat SwiftData intact; host owns its own future execution store | No two processes mutating one store, no cross-process SwiftData objects |
| Tools | Structured typed operations, reviewed edits, approved commands | Never parse prose into shell; never classify tests/package scripts as read-only |

### Local IPC security gate (E3, before a listener ships)

Define a bounded versioned protocol independently of transport. App and CLI
authenticate the host; host authenticates allowed client code identities and
the local user. Bind every request to the authenticated connection, session
and authorized workspace. Use OS-provided peer identity/audit information and
supported signing checks, not PID-only lookup, caller-supplied bundle/team
strings or claimed workspace paths. Same UID is not sufficient product trust.
Verify release identities, replacement/update behavior and downgrade handling.
Development relaxations must be explicit and unavailable in release builds.

Prototype signed app ↔ helper ↔ CLI communication under the actual sandbox
before selecting service names/entitlements. If that does not work within
supported Apple mechanisms, stop and revisit the transport: do not ship a
temporary Mach-lookup exception or unauthenticated localhost fallback. No
HTTP port, Bonjour advertisement or remote access is part of E1/E2.

App-bundled XPC, user launch agents and separate companion apps have different
lifecycles/lookup rules. The Apple example proves basic request/reply setup,
not our specific packaging, trust or persistence design. Those remain open.

### Credential ownership

Initially configure the host's provider credentials independently through a
secure local setup surface with Keychain-backed storage. Do not read the
desktop's namespace and interpret errSecItemNotFound as a missing user key
without handling access/identity/locked-state errors distinctly. If a later
opt-in transfer is implemented, authenticate both ends, keep transfer local,
avoid logs, validate storage and leave the original untouched on failure.

Apple's access-group sharing article explicitly limits the described macOS
behavior to data-protection Keychain or synchronizable queries. Same team is
not a substitute for entitlement/query/item migration design. A move to
shared access groups requires isolated-item, signed-build migration tests,
including locked Keychain, upgrade/reinstall, rollback and disconnect.
Repository subprocesses must not inherit model keys, authentication tokens,
SSH agent sockets or arbitrary parent environment by default. An environment
allowlist limits accidental exposure but does not isolate an unsandboxed
subprocess from all user-account resources.

## Workspace authorization (E2)

The host owns an allowlisted registry: opaque workspace UUID → local root
identity and authorization revision. Only human setup chooses roots. Clients
send that ID and relative paths; a model cannot authorize a root or register
an arbitrary absolute path. Bind sessions to workspace IDs explicitly.

For the sandboxed app, persist/reopen security-scoped bookmarks only after
testing the relevant entitlement and stale/revoked bookmark behavior. Do not
assume a bookmark is a portable grant to a separate host. The host performs
its own explicit workspace setup/OS-permission checks.

First ship **read-only workspace tools**. Scope metadata and lexical path
validation are not file-access enforcement. The executor must:

1. Hold an authorized root handle, not just compare path prefixes.
2. Traverse relative components safely; reject absolute/parent paths and
   symlink traversal, including intermediate links. Define root-symlink policy.
3. Check file type and bound actual reads before allocating/mapping input;
   reject devices/FIFOs/sockets; test inaccessible and disappearing files.
4. Account for root replacement, case/Unicode aliases, hard links, mounts and
   TOCTOU races. Fail closed; do not advertise containment before tests pass.
5. Respect deny rules for secrets/generated/ignored content and display
   exactly what context will leave the host for a selected cloud provider.

Read permission does not equal permission to upload entire repositories.
Preserve provider/privacy disclosure and context budgets. Revoking a workspace
increments its revision, invalidates pending approvals, blocks queued work
and cancels active work where possible; it cannot undo already completed I/O.

## E1 policy prototype (implemented, intentionally not an executor)

WorkspacePermissionScope defaults to readOnly. Every allowed operation still
requires explicit approval. EditWithApproval permits proposing patches and
commands, not automatic execution. Credential/elevation action cases are
always denied. Unknown action names have no enum representation; future wire
decoding must reject them before constructing a proposal.

WorkspaceActionProposal binds action/session/workspace IDs, workspace revision
and an exact typed payload. A patch carries expected old bytes (nil means
must not exist) and new bytes. A command carries absolute executable, argument
array and workspace-relative cwd. Bounded sizes and lexical paths prevent
obviously malformed proposals, **not arbitrary-command privilege escalation**.
A shell argument can do anything under its OS authority; the policy does not
inspect strings and claim to detect sudo, network effects or destructive code.
The current runtime has no executor for any of these future actions.

WorkspaceApprovalLedger is a main-actor, bounded, in-memory single-use ticket
store: request → human decision → consume exact proposal under current scope.
Ticket lifetime defaults to 120 seconds, max 300; expiry/clock rollback,
denial, cancellation, revocation, changed payload/session or workspace revision
all fail closed. Consumption invalidates the ticket, even on mismatch. No
persisted approvals or silent approval recovery after crash. Old action IDs
can be proposed again only as a new request needing fresh approval: this is
not a persistent execution-idempotency journal.

Only a future trusted host human-control path may call resolve. There is no
authentication implemented by this ledger; a UUID/ticket or caller-provided
approve boolean is not proof of a human decision. Runtime integration must
look up scope from the host registry rather than trust client-supplied scope.
The executor must check expected bytes and scope under its file handles at
execution time, after consuming consent; no automatic retry after ambiguous
side effects. Disk preconditions are not tested by this pure policy module.

## Before writes / commands (F)

- Real patch diff/preview; verify old bytes and absence preconditions; define
  atomicity/partial failure and rollback without discarding unrelated edits.
- One writer per workspace or isolated worktrees; chat concurrency alone
  does not authorize concurrent repository mutation.
- Resolve executable/cwd safely, use explicit argument vectors and sanitized
  environment, time/output limits and process-tree cancellation. Build tools
  can change outside files or use network. No automatic "safe test" exemption.
- Bind approval to full immutable execution plan (including limits, env policy,
  executable identity and filesystem preconditions) before that schema ships.
- Detect ambiguous outcomes, journal intent/result, never rerun side effects
  on restart. Signed-code validation of a host is not validation of repository
  code launched by it. No full-autonomy mode in the first coding release.

## Next slices and exit criteria

1. **E2:** workspace registry + bounded read-only executor in disposable
   directories, no shell. Adversarial traversal/symlink/race/revocation tests.
2. **E3:** signed local IPC/companion feasibility target with a harmless ping
   operation, no credentials or execution. Prove sandbox lookup, reject an
   unauthorized client, document lifecycle and install/revoke behavior.
3. **E4:** integrate workspace approval/runtime events with desktop; extract
   UI-independent interfaces suitable for a future CLI. No duplicated engine.
4. **F:** reviewed patches and approved noninteractive commands; disposable
   repo inspect → plan → approve → apply → test → report; cancellation.
5. **G/H:** persistent host, durable event/idempotency storage and separate iOS
   client, only after a working CLI. No remote terminal listener before auth.

Distribution gate: signed complete artifacts, Developer ID, hardened runtime,
no get-task-allow in distributed builds, notarization/stapling/Gatekeeper tests,
upgrade/uninstall/revocation and TCC/key access behavior. No certificate or
provisioning changes made by this spike. App Store review is not established.

## References checked

Apple pages retrieved September 8, 2026 via their public Markdown variants:

- https://developer.apple.com/documentation/servicemanagement/smappservice
  — macOS 13+, bundled login items/agents/daemons, registration subject to
  user approval and status reporting; not proof of our packaging choice.
- https://developer.apple.com/documentation/xpc/creating-xpc-services
  — listener acceptance/rejection and Codable request/reply example; does
  not establish our peer-authentication or long-running-host lifecycle.
- https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps
  — access groups, entitlements and explicit macOS query applicability.
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
  — Developer ID/hardened runtime requirements, notarization not App Review.

Runtime validation this slice: policy/ledger unit tests plus unchanged app
suite and Release build. No host installation, OS permission expansion,
live-key access, distribution submission or manual IPC/Keychain sharing test.