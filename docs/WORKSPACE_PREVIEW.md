# E4a — Local read-only workspace preview

The conversation toolbar now has **Workspace**, opening an experimental
local preview panel. Choose a local directory, enter a relative path (`.`
for its root), request a listing/text read, and approve or deny the exact
operation. Nothing is uploaded, appended to a chat draft/transcript, or saved
to history. This is not yet a model tool or an installed coding host.

## Boundary and lifecycle

- Each chat owns its preview state: folder name, relative path, pending
  proposal, current local result and a rolling 30-event operation log.
  Switching chats does not redirect callbacks to another chat.
- App-wide registry caps roots at 32 and outstanding preview reads at four,
  one per session. A shared serial worker actor performs file operations.
- Explicit NSOpenPanel selection supplies the sandbox resource URL. A
  reference-counted security lease starts/stops security-scoped access and
  remains alive while a worker holds that root, even if UI revokes it.
  No bookmarks persist and no entitlement changes were made.
- Registration and reads run on WorkspaceReadWorker, not MainActor. Approval
  presentation does not validate roots with filesystem I/O; validation occurs
  on the worker after ticket consumption. Earlier synchronous APIs remain
  only for existing low-level tests/prototypes, not the new UI path.
- MainActor consumes exact approval against registry-owned scope before
  dispatch. After I/O, cancellation, workspace revision, session binding and
  binding generation are checked again. Revocation/unbind/rebind drops late
  results, including unbind + rebind to the same ID. Consumed tickets are
  never reused. Denial/expiry starts no read.
- Stop requests cancellation and keeps the operation busy until it unwinds.
  Disconnect immediately invalidates grants/results/approvals, but a running
  syscall may finish later; its result is discarded. No replacement read can
  race the old operation in that chat. Chat deletion disconnects its preview.
- Folder access, previews and event log are memory-only until disconnect or
  app quit. Previous local result is cleared before proposing a new operation.

## Filesystem limitations remain explicit

E2 limits/deny rules/handle traversal still apply (200 KB text, bounded
listings, symlink/hard-link/special-file checks). Shared root handles are
immutable close-on-exec RAII references; workers use metadata/openat on them,
not shared directory offsets. Child read descriptors stay worker-local.
WorkspaceFileHandle and WorkspaceSecurityLease use narrow unchecked Sendable
conformance for immutable ownership, not general shared mutable filesystem
state. Root uses checked Sendable conformance.

Moving work off MainActor makes UI/revocation responsive but **does not add a
hard syscall timeout or undo completed reads**. Serial worker requests can
wait behind a blocked filesystem; restrict this beta to local folders. No
claim of exhaustive malicious-filesystem race protection. Real NSOpenPanel
grant behavior remains a manual gate: E2's conservative reopening of absolute
ancestor directories may reject a grant the sandbox otherwise permits, and
symlink aliases are intentionally rejected rather than silently canonicalized.
The panel discloses experimental status and fails closed with path-free errors.

No production XPC integration, provider upload, prompt assembly, shell, write,
host auto-install or file-watch/indexing was added. Existing model-requested
Stage 7 file panels are unchanged and separate from this local preview path.

## Verification and next slice

Tests exercise real temporary-folder previews and injected suspended workers:
approval required/denied/expired, exact immutable proposal, local-only draft
isolation, protected-path failure, revocation/revision/rebinding while I/O is
outstanding, Stop/disconnect/registration cancellation, and chat deletion.
Full app suite and Release build are run; no paid APIs or live keys involved.

Manual checks required before release: folder picker and access on a normal
sandboxed build (not test-injected entitlements), grant lifetime and errors,
symlink alias UX, long paths/list/text layout, keyboard/VoiceOver, switch/delete
while reading, Stop/disconnect with slow filesystem. Automated temp-directory
tests do not prove arbitrary user-selected sandbox root access.

Next **E4b**: verify real grants, integrate controlled workspace tools and
explicit context/provider consent plus typed runtime events. Do not silently
reuse local preview approval as permission to send file contents to a model.
Host transport remains the separately tested ping prototype until a bounded,
authenticated production workspace protocol and deployment gates are satisfied.