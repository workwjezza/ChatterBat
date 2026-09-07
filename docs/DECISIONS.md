# ChatterBat — Decisions

Only meaningful, non-obvious decisions and their reasoning are recorded
here. Routine implementation choices are not logged.

## Stage 0

### Used XcodeGen instead of hand-authoring/hand-editing the .xcodeproj

**Decision:** Install XcodeGen (via Homebrew) and define the project in
`project.yml`, generating `ChatterBat.xcodeproj` from it.

**Why:** Hand-editing `project.pbxproj` is fragile, hard to diff/review,
and error-prone when adding targets/settings via scripted edits. XcodeGen
gives a small, readable, version-controllable spec that regenerates a
correct project deterministically. The generated `.xcodeproj` is committed
anyway (not gitignored) so the project remains directly openable in Xcode
without requiring XcodeGen as a hard runtime dependency — XcodeGen is only
needed when `project.yml` changes.

### Kept the generated .xcodeproj under version control

**Decision:** Do not add `ChatterBat.xcodeproj` to `.gitignore`.

**Why:** Some teams gitignore generated Xcode projects and require
`xcodegen generate` before every open. That adds friction for a solo
developer and for the next agent picking this up, who may not have
XcodeGen installed yet. Since XcodeGen output is deterministic and small,
committing it and regenerating only when `project.yml` changes is simpler.

### Left code signing on Automatic/ad hoc rather than a fixed team

**Decision:** Do not set `DEVELOPMENT_TEAM` in `project.yml`; let the app
target build with ad hoc signing.

**Why:** A valid local "Apple Development" codesigning identity exists in
Keychain, but `xcodebuild` refused to provision automatically without an
Xcode-managed signed-in developer account ("No Account for Team…"). Since
Stage 0 has no distribution requirement, ad hoc signing is sufficient and
correct — it's what a plain `xcodebuild build` produces by default, and it
lets the app build, launch, and run unit tests without requiring
interactive Xcode account setup. This is the direct cause of the
`ChatterBatUITests` load failure (see STATUS.md); fixing it requires
interactive Xcode access and is left as a documented manual step rather
than worked around with something that would misrepresent the actual
signing state.

### Kept demo/preview fixtures as a clearly separate, documented layer

**Decision:** `DemoFixtures` lives in `Domain/` with an explicit doc
comment stating it must never be wired into production networking or
persistence paths, rather than, e.g., quietly defaulting `AppViewModel`'s
initializer to always load it with no comment.

**Why:** The brief explicitly warns against preview fixtures silently
replacing real networking in production. Making the constraint visible in
the type's own documentation (not just this file) means a future stage
implementer sees the warning at the point of use, not only in a planning
document they may not re-read.

### Did not implement AppKit-level integrations in Stage 0

**Decision:** Stage 0 uses only SwiftUI (`NavigationSplitView`, `Settings`
scene, `TabView` for settings panes) with no custom `NSViewRepresentable`
wrappers.

**Why:** Nothing in Stage 0's scope (shell navigation, Settings scene,
demo data) requires AppKit. The brief reserves AppKit for "focused native
integration" — introducing it now would be premature.
