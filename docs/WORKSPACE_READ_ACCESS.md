# E2 — Explicit workspace registry and bounded read-only execution

**E4a update:** an experimental local-only desktop preview now uses async
registration/reads through a serial worker actor and post-I/O revocation
checks. See WORKSPACE_PREVIEW.md. No provider or model-tool wiring yet.
Synchronous/unwired descriptions below describe the original E2 slice.

Implemented as an **in-process, unwired prototype**. No production model tool
can call this yet. No host executable, CLI, registration UI, security-scoped
bookmark storage, new entitlement, network listener, file write or command
runner is introduced. Existing panel-based Stage 7 tools are unchanged.

## Authorization boundary

WorkspaceReadRegistry is owned by a trusted host/control path, not a model.
Human-selected roots become opaque workspace IDs with read-only scope and
revision 1. Sessions must be explicitly bound to an ID. Callers cannot supply
an alternate scope to execute: the registry looks it up and consumes an E1
single-use approval against the exact action/session/workspace/revision.

Every read/list requires a ticket and an explicit decision. A missing, pending,
denied, expired or mismatched approval never reads. File I/O failures consume
the ticket, requiring fresh approval on retry. Rebinding/unbinding cancels
session approvals; revision invalidation cancels all workspace approvals.
Revocation removes bindings, approvals and the retained root handle. New
registration gets a fresh ID rather than reviving old proposals. At most 32
roots are retained. Registry and tickets do not persist across app instances.

These methods are **not authenticated RPC**. E3 must establish client trust;
E4 must supply human setup/approval UI before the model sees these tools.
Registering a URL does not acquire an OS sandbox grant. The process must
already have access; real user-selected bookmark/host transfer remains gated.

## File-access mechanics

- Open and retain a read-only directory descriptor, with close-on-exec.
- Root must be an absolute local file URL, not `/`. Reject symlinks in every
  root component, rather than silently resolving the grant elsewhere. A
  future human setup UI must explain/canonicalize known aliases explicitly.
  Tests canonicalize only their trusted temp parent (`/var` is a Mac alias).
- Validate relative syntax; reject absolute, parent/dot/empty components,
  control characters and backslashes. Limit traversal depth to 64.
- Traverse one component at a time with openat + O_NOFOLLOW, directory checks
  and retained parent handles. Check fstatat without following links before
  opening and compare fstat identity afterward. O_NONBLOCK avoids FIFO waits.
- Reject non-regular files for reads; reject files with link count other than
  one; reject different-device descendants. Directory listing omits symlinks,
  multiply linked files, cross-device entries and special files.
- Reopen/check the registered root identity and parent-to-child identities
  before/after I/O. F_GETPATH checks actual filesystem spelling and rooted
  ancestry as an additional check, not the sole containment mechanism.
- Compare size, link count, modification time and change time around reads;
  reject detected changes and return no partial content. Test hooks inject
  rename/symlink/rewrite mutations after handles open but before I/O.
- Errors are typed and path-free. Successful results carry only requested
  relative names plus content; source content itself may of course contain
  paths or secrets. There is no content redaction or provider upload here.

## Bounded output and deny rules

Text reads are capped at **200,000 bytes**, using 8 KiB chunks and at most one
extra byte to detect growth. Oversized data is rejected, not silently clipped.
Require valid UTF-8 without NUL. Empty text is valid. No whole-file mapping.

Listings scan at most **1,000 entries** (plus the sentinel entry detecting the
limit), with at most **64,000 output bytes**. Sort the collected subset and
return `hasOmissions` when filtered or capped. This is not a guaranteed first
alphabetical page: filesystem enumeration order decides the bounded subset.
Directory iteration uses a fresh file description, so repeated reads do not
share or exhaust the registry root's offset. Descriptors close on every exit.

Case-insensitive, Unicode-canonical deny rules apply to both requested and
resolved names: hidden components, node_modules/build/DerivedData/vendor/dist,
credentials/secrets, and .pem/.key/.p12/.pfx/.mobileprovision suffixes. This
deliberately overblocks some legitimate code; explicit policy refinement is
future work. It is **not** a .gitignore parser or complete secret detector.
Arbitrarily named secret-bearing files are not automatically detected.

## Limits / remaining security work

- This is **not an OS sandbox** or a snapshot of a hostile mutable filesystem.
  Handle traversal, identity checks and timestamps reject tested race cases,
  but cannot prove an adversarial process never moved/replaced/restored data
  between checks. Special-file replacement between precheck and open can
  still cause an open before the postcheck rejects it; no read occurs after
  a failing type check. Don't grant a malicious repository system authority.
- Cross-device checks do not establish same-device mount isolation. No volume
  mounting or synthetic device creation was done in tests. Socket/device
  types are rejected by the regular-file allowlist, not live device tests.
- Root path verification adds filesystem operations and may reject aliases or
  sandbox configurations that a direct granted URL could read. Test real
  user-selected roots under production entitlements before integration.
- Execution is synchronous and main-actor serialized in this unwired slice.
  Cancellation checks run before/chunkwise/after reads, but nonblocking open
  does not impose a wall-clock timeout on regular/network filesystem I/O.
  Same-actor revoke waits for synchronous I/O to finish and cannot undo prior
  reads. Move execution off UI with a defined revocation/timeout contract
  before exposing slow/network roots or integrating background tasks.
- No provider disclosure or upload permission is implied by local read
  approval. E4 must preview context and enforce budget/provider consent.
- No durable session grants, workspace switching UI, semantic search, write
  precondition checking or command execution is provided by this slice.

## Validation

Tests use real disposable directories and approved fixture calls, never user
repos/keys. Coverage: exact/single-use read, pending/denied/unbound access,
revision/revoke/rebind, repeated/empty/sorted listing, protected paths,
absolute/traversal rejection, root/intermediate/final symlinks, hard links,
FIFO, wrong types, missing/permission-denied files, UTF-8/NUL/empty text,
read byte boundary, entry/list-byte bounds, root replacement, deterministic
directory rename and file mutation races, Unicode names, descriptor closure /
close-on-exec, registry capacity, approval mismatch/unbind and cancellation.
Permission-denied assertions are skipped when running as root; normal local
tests run as the developer user. No test claims exhaustive TOCTOU resistance.

API reference inspected locally: Xcode macOS SDK sys/fcntl.h, sys/stat.h,
dirent.h and `man 2 open`. Only established Darwin openat/O_NOFOLLOW,
O_DIRECTORY/O_NONBLOCK/O_CLOEXEC, fstat/fstatat, readdir and F_GETPATH APIs
used. Newer O_RESOLVE_BENEATH/O_UNIQUE flags seen in local docs were not
adopted without a verified macOS 14 availability contract.

Next: **E3 signed local IPC feasibility with harmless ping only**, then E4
workspace/UI/runtime integration after the remaining filesystem/OS-grant
gates. E2 is not permission to enable shell or automatic editing.