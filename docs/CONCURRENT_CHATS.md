# B2 — Concurrent chats and bounded admission

## Usage

The sidebar Execution section defaults to **2 concurrent chat turns**.
Choose 1–4 for this app session. Up to **8 additional chats** wait FIFO.
Changing the limit does not cancel admitted work: lowering it waits for
existing turns to finish; raising it admits queued work. More concurrency
can increase provider spend/rate-limit pressure; it is not a billing cap.

Each conversation may own one active or queued turn. Open another chat to
send independently. While slots are occupied, the composer shows a Queue
action and explains admission; a full queue disables sending and preserves
the draft. Accepted queued prompts appear in their own transcript, with
queue position in the sidebar/detail. Model/settings edits are disabled
only for that busy conversation, not for unrelated chats.

Stop/Escape affects the visible chat. The sidebar context menu can stop a
background chat, and Stop all cancels every queued/active turn. A queued
cancel never calls the provider. An active cancel retains its slot and
blocks replacement/deletion until asynchronous cleanup finishes. This
prevents late stream cleanup from affecting a replacement request. Provider
billing can continue after local cancellation.

## Queue contract

- Capture model, prompt/context, applicable settings and tools at submission.
  Do not re-read another chat's mutable selection at dispatch.
- Load the credential at dispatch, not while queued; missing/disconnected
  credentials produce a visible failure with no provider request.
- Auto submissions carry a local validator over their captured policy and
  prompt/context budget. At dispatch, stale/failed catalogs, changed privacy,
  unavailable candidates or a different choice fail visibly without a
  provider call, reroute or automatic retry. Refresh and explicitly send again.
- Queue count and duplicate-chat admission are bounded before appending any
  transcript message. A rejected send returns false and does not clear the UI
  draft. Submitted prompts remain in history after cancellation/failure.
- Queue/execution state is in memory only. Pending assistant records use the
  existing unfinished `.streaming` persistence status (not a schema change),
  while live UI distinguishes Queued from Generating. Exports therefore do
  not encode queue position. On relaunch unfinished queued/active records
  become interrupted, never resumed automatically.
- B1 per-chat drafts/settings remain in memory until quit. Saved new-chat
  defaults and completed transcript/usage history remain durable.

## Tools and permissions

Waiting for approval holds that chat's concurrency slot. Other available
slots continue; if every slot waits for approval, approve/deny/stop a turn
to make progress. Tool follow-up stays in its existing slot with captured
model/settings/context. Unknown or unoffered tools never run.

**Deny** deliberately sends a tool-denial follow-up, preserving the existing
tool conversation behavior. **Stop** now terminates the turn locally and
does not start a denial follow-up. Stop all suppresses queue draining while
cancelling, so it cannot accidentally dispatch waiting work.

Approved native file panels are serialized: one may be open at a time;
other approved tasks wait cancellably. Cancelling the real presenter asks
AppKit to close its panel. The executor checks cancellation before and after
panel selection, so a late URL is not read or uploaded after cancellation.
A custom presenter that ignores cancellation may keep its task in Stopping
until it returns; the occupied slot remains visible rather than claiming
execution ended. Physical panel-close behavior remains a manual test gate.

UI actions use per-chat state/IDs. A legacy aggregate generationState and
single-turn Stop overload remain for older tests/callers; the latter is a
no-op when more than one turn exists, never an arbitrary global stop.

## Verification

Controlled-stream tests release events explicitly to verify simultaneous
streams, independent cancellation, late output, FIFO/queue capacity,
immediate cancellation, replacement safety, admission limit changes, prompt/
settings/tools snapshots, failure/retry independence, dispatch validation,
removed credentials, pending approvals, Stop all, serialized panel waits,
late panel selection, all-busy deletion guards, per-chat persisted usage,
and interrupted recovery without resume. No real provider calls/credentials.

Manual release checks: run two real streams and queue a third; cancel each
type; lower/raise the limit; switch chats during tool approval; test native
panel cancellation and a second waiting approval; inspect queued/full states,
long labels, VoiceOver/keyboard focus, sidebar controls, and relaunch recovery.
Fixtures and builds do not establish provider rate-limit behavior or visual
correctness. No shell execution, browser automation or remote host is added.