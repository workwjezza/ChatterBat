# A3 — Model capability filters and task presets

Open Models… / Command-K. Combine All/Venice/OpenRouter, Favorites only,
search and the new Tool calling, Reasoning and Image understanding toggles.
Requirements intersect (AND); only provider-reported support matches.
Unknown models remain available with that requirement off, and are never
relabeled unsupported just because a filter excluded them.

All sections use the same rule, including Recent (which previously bypassed
provider/favorites filtering). Matching counts count unique catalog rows,
not repeated appearances in Recent and provider sections. Reset filters
clears only browsing controls; it preserves favorites, recents and catalog.
Filters last for the shared picker's app session, not across relaunch.

## Task presets

- **All tasks:** no extra requirements.
- **Coding:** explicitly heuristic shortlist requiring reported reasoning.
  The Reasoning toggle shows checked/locked while this preset is active.
  Add Tool calling separately if desired. Neither capability establishes
  coding quality or enables tools/terminal execution. Other models may code
  well; choose All tasks to remove the preset requirement.
- **Ideating:** guidance only, no creativity ranking or extra filtering.
- **Historical references:** guidance only, no accuracy ranking or extra
  filtering. Verify primary sources; this does not retrieve citations.
- **Web browsing / Image editing:** labeled not available yet. Selecting
  either shows an explanatory unavailable state rather than fake matches.
  Tool calling is not web access; image input is not image editing.

Independent capability choices survive preset changes. Presets never add
prompts, pick a model, alter saved defaults, enable runtime features, invoke
a model, or narrow Auto's eligible favorites. The picker footer explains
that Auto uses its separately saved policy from the bookmark bar.

## Capability provenance and UI

Each row has an info popover and accessibility value listing Reported
supported / Reported unsupported / Unknown for all three capabilities.
Metadata can be cached; catalog failure/time disclosure remains visible.
Image understanding is currently catalog metadata only: ChatterBat's
attachment pipeline is not implemented yet. No new provider fields/endpoints
or third-party libraries are introduced.

Selection, capability details and favorite actions are sibling buttons,
removing the earlier nested-button structure. Favorite accessibility labels
include the model and service. Picker dimensions are now 640 × 660 to allow
the new controls, explanation, results and catalog footer.

OpenRouter decoding now treats missing/null/malformed supported_parameters
or architecture.input_modalities as Unknown. An explicitly supplied valid
list that omits a capability still means Reported unsupported. A partial
architecture object no longer incorrectly asserts lack of image support.

## Verification

Fixture-only tests cover supported/unknown/unsupported values, combined
filters, provider identity, case-insensitive trimmed search, Recent order,
reset behavior, coding heuristic, guidance/unavailable presets, unchanged
Auto/bookmark pools, cached results, and malformed/empty provider metadata.
No paid API calls or credentials are used. See STATUS.md for final results.

Manual release checks remain: picker fit on supported displays, long model
names/rates, result-list space for each preset, light/dark mode, keyboard
navigation, info-popover dismissal, VoiceOver and independently reachable
selection/info/favorite controls. Automated tests do not establish visual
or assistive-technology correctness. Web/image workflows remain deferred
to the corresponding roadmap tracks, not implemented by these presets.