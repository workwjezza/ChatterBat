# A2 — Model bookmarks and saved defaults

**B1 update:** current selection/settings are now conversation-local for the
app lifetime; older app-wide descriptions below are historical. New-chat
defaults still persist. Each existing chat keeps its policy snapshot when
another chat saves a new default. See `SESSION_STATE.md` for precise lifetime,
switching and approval behavior (per-chat drafts/settings are not durable yet).

## Usage

1. Open **Models…** (or Command-K), load your configured catalogs, and star
   models. The bar lists all favorites independent of picker filters.
2. Click a favorite chip to pin it for new chats and select it now. Click
   that pin again, or click **Auto**, to return the default to Auto.
3. Configure Auto explicitly: select a model in the picker, set any desired
   OpenRouter privacy controls in Advanced Settings, then click **Save Auto
   policy from current model**. This saves and enables Auto, replacing the
   previous policy. Pinning a different model never overwrites that policy.
4. On relaunch click **Refresh** or open the picker. Identities and policy
   survive; model metadata is resolved against a current catalog, not disk.
   No hidden catalog/inference call runs merely to restore the preference.

The bar shows the default; the toolbar shows the current selection. Picking
a temporary model changes only the current selection. New Chat restores the
saved default. Current selection/settings are still **app-wide**, not yet
isolated per conversation; that is Batch B. No schema migration was added.

## Safety and semantics

- A favorite, pinned default and saved Auto policy are independent. Removing
  a star does not silently unpin; that pin remains visible and removable.
- Unavailable favorites remain visible. An unavailable pin can be unpinned;
  other unavailable chips cannot be newly pinned. No guessed replacement.
- All direct selection/policy actions are disabled during a generation or
  tool-approval wait. New Chat still works; any running coordinator request
  retains its already-captured model/settings and is not changed by this.
- Auto without a saved policy shows setup and cannot send. Saving requires
  current known nonnegative input/output prices and excludes server routers.
- The policy freezes service, anchor identity, privacy label and separate
  listed input/output rate ceilings, not a guaranteed bill or dollar cap.
  Current candidate capabilities/prices still come from a fresh catalog.
- Price increases cannot enlarge the saved ceiling. A changed anchor privacy
  label, missing anchor, failed/loading or >=15-minute-old catalog blocks
  Auto. The user must refresh or explicitly save a revised policy.
- Saved OpenRouter data-collection/ZDR/fallback restrictions are applied to
  actual outgoing settings while Auto is on, retaining any stricter current
  controls. The bar exposes these saved values. Advanced Settings edits the
  current controls; loosening saved Auto restrictions requires saving again.
- Cross-provider disclosure remains. Auto is rechecked on confirmation if
  the catalog has aged while the disclosure was open.
- Versioned JSON in a dedicated UserDefaults key holds only non-secret
  identities and policy. Invalid/future data fails closed to unconfigured
  Auto. Provider keys, history, and catalog metadata are never stored there.

## Verification and manual checks

Automated coverage uses isolated UserDefaults suites, fake credentials and
fixture catalogs. It covers pin/Auto relaunch, new-chat defaults, temporary
selection, busy guards, unavailable/unstarred pins, corrupt/future records,
unknown prices, fixed ceilings, privacy drift, stricter current privacy,
catalog failure/recovery and bookmark independence from picker filters.

Before release manually check narrow/wide window layout, horizontal bar
scrolling, long model names, light/dark mode, keyboard navigation/VoiceOver,
pin/unpin with real catalogs, relaunch/Refresh, and cross-provider disclosure.
No paid API calls or interactive UI checks were performed for this slice.