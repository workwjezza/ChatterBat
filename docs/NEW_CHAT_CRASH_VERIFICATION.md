# New-chat crash fix — September 8, 2026

## Root cause and fix

Reproduced by launching the ChatterBat scheme in the Xcode debugger and
pressing the actual New Chat toolbar button using macOS accessibility.
Thread 1 stopped with `EXC_BREAKPOINT (code=1, subcode=0x239ebbb08)` inside
SwiftData, called by `SwiftDataConversationRepository.createConversation`
at `context.insert(persisted)` (line 50 before the fix).
The caller chain was `SidebarView` → `AppViewModel.startNewConversation`
→ repository. No chat API request was involved.

Debugger inspection showed `self.context._container = nil`.
`AppDependencies.live()` constructed a local ModelContainer but retained
only its mainContext through the repository. Retaining that mainContext
did not retain the container on this runtime.

The repository now strongly retains `context.container` as well as the
context. No protocol, call-site, schema, signing, or distribution changes
were necessary. A regression test drops the creation scope, verifies that
the container remains alive, creates/loads a conversation and message,
then releases the repository and checks that the container is released.
That test failed safely before the fix and passed after it.

The older toolchain-specific explanations in STATUS.md and source comments
should not be treated as established causes of this crash. The lifetime
defect also explains why construction inside a helper could behave
differently from tests that keep a local container alive. Relationship and
query changes from previous work were not reversed or independently
re-tested in this focused fix.

## Live verification log

Environment: Xcode 26.6, macOS 26.6.2, arm64, Debug scheme, existing real
SwiftData store and configured Keychain credentials. No credentials were
extracted or written to logs.

1. Launched the fixed app from Xcode (process 65501).
2. Clicked New Chat three times. Each opened without a crash; sidebar
   count reached three and the detail pane showed an empty transcript.
3. Selected Venice / Hermes 3 Llama 3.1 405b. Typed and sent:
   `ChatterBat Venice verification: count from 1 to 30, one number per line. No other text.`
   Observed the generating indicator, followed by the completed 1–30
   response and usage footer. Sidebar preview updated.
4. Created a fourth conversation. Selected OpenRouter / GPT-4o-mini.
   Typed and sent:
   `ChatterBat OpenRouter verification: count from 1 to 50, one number per line. No other text.`
   Captured screenshots during generation showing partial text with the
   spinner/Stop control, followed by the completed response.
5. Selected the Venice conversation in the sidebar; its history reopened.
6. Quit normally using Command-Q. Confirmed process 65501 exited.
7. Relaunched from Xcode (new process 80964). All four sidebar rows remained.
   OpenRouter history loaded at launch. Selected an empty conversation,
   then Venice; the Venice prompt and completed response loaded again.
8. Read-only SQLite inspection of the existing SwiftData store confirmed
   both user prompts and assistant responses persisted, with completed
   status and correct provider/model attribution. Venice ended at 30;
   OpenRouter ended at 50. No store reset or manual data modification.

## Tests

Final run: **230 tests, zero failures**, `xcodebuild test` succeeded.
The original 227 tests plus the lifetime regression and two new error-path
tests ran. The latter cover both providers: malformed/unexpected HTTP-200
bodies fail instead of reporting success; non-JSON HTTP-503 responses
produce a readable provider error. Existing tests also cover invalid
credentials, mid-stream failures, premature disconnection, and retry.
Provider failures were simulated in unit tests, not induced against live
accounts. No networking production change was needed for these cases.

```sh
xcodebuild \
  -project /Users/studio-jd/Projects/ChatterBat/ChatterBat.xcodeproj \
  -scheme ChatterBat -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/ChatterBatCrashVerification \
  -only-testing:ChatterBatTests test
```

## Evidence from this session

Temporary files (not guaranteed to survive system cleanup):

- `/tmp/chatterbat-step1-backtrace.txt` — original Xcode stack and context.
- `/tmp/chatterbat-lifetime-before.log` — failing regression before fix.
- `/tmp/chatterbat-final-tests.log` — final passing suite.
- `/tmp/chatterbat-openrouter-stream-2.png` — partial live response.
- `/tmp/chatterbat-openrouter-stream-5.png` — generation completed.
- `/tmp/chatterbat-venice-completed.png` — completed live Venice response.
- `/tmp/chatterbat-restart-openrouter.png` — history after restart.
- `/tmp/chatterbat-restart-venice.png` — reopened history after restart.
- `/tmp/chatterbat-saved-messages.txt` — targeted read-only store check.

## Remaining observations / scope

- No further crash occurred in the verified flow.
- Current model selection resets after restart (existing behavior). Select
  a model before sending again; persisted history and attribution survive.
- Venice's cost footer was visible live but not after restart; token usage
  survived. Cost persistence was not changed in this crash fix.
- This verifies basic chat and tested API error paths, not comprehensive
  recovery from disk corruption or every persistence failure.
- Four verification conversations remain in the app for inspection.
- Existing user changes to project.yml, project.pbxproj, STATUS.md, and
  DECISIONS.md were left untouched.