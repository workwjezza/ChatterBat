# B1 — Conversation-local state (first Batch B slice)

**B2 update:** bounded concurrent execution is now implemented; descriptions
of the one-global-turn restriction and Stop-as-denial below are historical.
See `CONCURRENT_CHATS.md`. Draft/settings lifetime is still in-memory. Busy
protection and catalog resolution now consider every active/queued chat.

Each conversation now owns an observable session object containing its
draft, selected model/identity, reasoning/provider settings, tool toggle,
Auto mode, Auto policy snapshot and selection notice. The detail view binds
to that specific object; a late editor callback cannot write through an
app-wide selected-chat proxy. SwiftUI view identity follows conversation ID
so transient dialogs, scroll state and native editor undo do not migrate
to a different chat. Draft text survives switching away and returning.

## Lifetime and default semantics

- **Session state is in memory only for B1.** App quit discards unsent
  drafts and per-chat configuration. Transcript persistence and saved
  new-chat defaults remain unchanged. No SwiftData schema migration or
  draft content in UserDefaults/exports was introduced.
- Newly created/imported chats receive independent sessions initialized
  from the saved default; tool use is off and advanced settings start with
  normal defaults. Settings from the previously visible chat never leak.
- Existing loaded conversations receive a default snapshot when attached
  to the app, including ones not yet opened during this launch.
- Pin/unpin/Save Auto policy still update the current chat and the global
  default for future chats. Other existing sessions retain their own model
  and Auto policy. The bar shows the global pin but labels the displayed
  policy as **This chat's Auto**.
- Explicit catalog refresh resolves each session's own saved identity and
  policy, never reapplies a newer global default. The active generation's
  session is skipped; idle transition resolves it afterward. Manual picker
  choices stay independent. Catalog freshness still gates Auto at send.
- Normal chat deletion removes only that session. Deleting the active
  streaming/approval conversation is blocked both in UI and view model.

## Streaming and approval ownership

The single global generation limit is **still enforced**. Another chat can
be opened and drafted while a request runs, but sending waits. The banner
explains this and offers Show active chat. Concurrent execution/queueing,
per-chat Stop and Stop all are B2, not implemented by this slice.

Coordinator requests already capture model, settings and tools. Tests now
exercise that capture while switching sessions, including tool follow-up.
Background transcript changes update sidebar metadata from RootView for
the changed conversation IDs using one repository fetch, without touching
the selected session or draft.

Tool approval is an inline card in its owning conversation rather than a
sheet whose dismissal on navigation implicitly denied the action. Switching
away leaves it pending; returning displays it again. The coordinator binds
UI decisions to conversation + expected tool-call ID and claims the first
decision synchronously, preventing duplicate resolution on remount/repeated
click. Approve has no default Return shortcut. Explicit Approve still opens
the native file picker; no filesystem permissions were expanded. Deny and
the existing Stop-while-awaiting behavior send a denial result as before.
Interrupted approvals still follow existing launch recovery.

Cross-provider confirmation captures draft/settings/tools and verifies the
owning selected conversation and idle execution state before sending. Chat
switches dismiss transient confirmation UI, not the draft. Auto is rechecked
for freshness/eligibility on confirmation. No hidden provider calls added.

## Validation

Fixture tests cover draft/settings/model isolation, captured editor targets,
per-chat Auto policy snapshots, refresh after defaults change, unavailable
identity recovery, existing unopened chats, import/repository creation,
deletion safety/lifetime, metadata updates, deliberate non-persistence,
stream ownership and pending/duplicate/stale/wrong-chat approval decisions.
No paid APIs, real credentials or user data are used in automated tests.

Manual checks before release: type multiline drafts in two chats and switch
repeatedly; edit model/Auto/reasoning/tool settings independently; change a
global pin and inspect an older chat; switch during streaming/approval;
return using the banner; verify inline card layout, explicit denial and
native picker flow; test cross-provider confirmation dismissal, keyboard
focus/undo, VoiceOver and narrow windows. Do not infer these checks from the
unit suite. Durable per-chat settings/draft recovery remain future work.