# E3b — Separate user host, sandboxed client and CLI feasibility

Implemented and live-tested as **isolated ping-only probes**, not a packaged
coding companion or production IPC integration. Normal ChatterBat has no new
entitlement, linked helper, listener, workspace IPC or credential sharing.

## Supported discovery mechanism

Apple's App Groups entitlement documentation explicitly permits macOS
sandboxed ↔ nonsandboxed IPC using a service named
`<group identifier>.<unique name>`. macOS team-prefixed groups do not require
Developer website registration. This probe uses:

- Group: `AM3FXP5BXT.com.chatterbat.ipcprobe`
- Mach service/launchd label: `AM3FXP5BXT.com.chatterbat.ipcprobe.ping`
- Host signing identity: `com.chatterbat.ipcprobe.host`
- Sandboxed client identity: `com.chatterbat.ipcprobe.standalone`
- CLI identity: `com.chatterbat.ipcprobe.cli`

The host and CLI have only the App Group entitlement and run as normal user
processes, intentionally not sandboxed. Both app clients have only App Sandbox
and that App Group. No temporary exceptions, network or file entitlements,
get-task-allow, root helper, shared Keychain query or group-container access
is added. Group membership allows discovery; it is **not** authorization.

The host listener enforces an OR of two complete signing requirements (Apple
anchor + team + exact app/CLI identifier), plus per-peer UID validation and a
per-connection requirement. Client connections pin the exact host signing
identity/team and check OS UID on reply. The rejected app has the same group
and signing team but a different identifier, proving group/team membership
alone is insufficient. The same bounded versioned nonce ping from E3a is used;
no filesystem, process execution, approval or secret RPC is exported.

Command-line targets need explicit codesign identifiers: PRODUCT_BUNDLE_IDENTIFIER
alone left the bare host signed as its executable name on this toolchain. The
initial positive run correctly rejected it. OTHER_CODE_SIGN_FLAGS now sets
the intended identifier for host/CLI; peer requirements were not weakened.

## Lifecycle experiment and cleanup

`IPCProbe/verify-standalone.sh` accepts a build-only Release products path.
It checks strict signatures and exact signed entitlement dictionaries before
temporarily creating a launchd plist in a fresh /tmp directory. It bootstraps
only `gui/<current uid>` with ProgramArguments pointing to the built host,
MachServices registration and RunAtLoad. It never writes Library/LaunchAgents,
uses sudo, edits system services or calls SMAppService.

The script refuses to replace an existing job with this label. An EXIT/INT/
TERM trap boots out the registration and verifies removal before removing
its temporary directory. Cleanup failure retains files and prints the exact
target for manual bootout. SIGKILL/machine loss cannot run shell traps; after
an interrupted run check the service explicitly before rerunning. Subsequent
runs fail rather than taking over an existing registration.

Live matrix on this development Mac:

| Check | Observed |
|---|---|
| Sandboxed app → separate host | Verified pong, exit 0 |
| CLI → same host after app exits | Verified pong, exit 0; same host PID |
| Same-group/team wrong client ID | Clean connection interruption, exit 2; XPC log says check-in dropped for code-signing requirement |
| Authorized CLI after rejection | Verified pong, host still healthy |
| App and CLI requiring wrong host ID | Rejected, exit 2 |
| launchctl kickstart -k host | CLI reconnects/pongs; host PID changed |
| launchctl bootout | Job absent; new CLI request fails with exit 2 |
| Final state | No probe launchd registration remains |

Foundation can surface policy rejection via error, interruption or invalidation
callbacks. The verifier permits only those known markers with exit 2; timeout,
crash, invalid response and pong are failures for a negative test. A clean
connection error alone does not prove authentication: the positive baseline,
same-group wrong-ID control and XPC policy-rejection log provide that evidence.
Service absence after bootout is tested as absence, not authentication failure.

The host surviving a short gap after client process exit is basic process
lifecycle evidence, not durable task survival, sleep/logout recovery or crash
replay. Restart test reconnects with a new client; it does not implement
automatic reconnect/event replay in ChatterBat.

## Reproduce

```sh
xcodebuild -project /Users/studio-jd/Projects/ChatterBat/ChatterBat.xcodeproj \
  -scheme ChatterBatIPCStandaloneProbe -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/ChatterBatStandaloneRelease build
bash /Users/studio-jd/Projects/ChatterBat/IPCProbe/verify-standalone.sh \
  /tmp/ChatterBatStandaloneRelease/Build/Products/Release
launchctl print gui/$(id -u)/AM3FXP5BXT.com.chatterbat.ipcprobe.ping
```

The last command should fail because the test job has been removed. The
verifier uses the developer machine's Apple/Xcode Python for plist creation /
inspection; Python is test tooling only, not an app/host runtime dependency.
Do not use test-instrumented artifacts: xcodebuild test may inject exceptions.
App and CLI have five-second per-request watchdogs. Test-only /tmp artifacts,
sandbox/App Group metadata or system logs may remain; no user data is touched.

Logs: `/tmp/ChatterBatStandaloneRelease.log`,
`/tmp/ChatterBatStandaloneMatrix.log`, `/tmp/ChatterBatE3bProbeTests.log`,
`/tmp/ChatterBatE3bAppTests.log`, `/tmp/ChatterBatE3bAppRelease.log`.

## What remains before production

- A companion app/package and supported user-facing SMAppService enable /
  disable/status flow; the temporary launchctl job is not a production installer.
- Developer ID/notarization/provisioning review, exact production entitlement
  scope and trust requirements. Current local Apple Development signing is
  not App Store approval or distribution readiness.
- Upgrade/replacement/downgrade identity, revocation, uninstall and moved-bundle
  behavior. A kickstart of the same executable does not test software upgrades.
- Actual macOS 14 runtime verification (APIs support baseline per SDK, but
  execution occurred on the current development OS), different-user rejection,
  reboot/login/logout, resource limits and hostile-client robustness.
- E4 production protocol design, workspace grant/approval UI, safe off-UI
  execution and provider-disclosure controls. E2 reads remain unwired.
- G durable tasks/events, replay/idempotency and lifecycle recovery; H mobile
  auth/transport later. No command or workspace authority is implied by ping.

E3b's development feasibility goal is met. These deployment/security gates
remain explicit; do not install this probe as the user's actual coding backend.

Reference checked September 8, 2026:
https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups
(public Markdown: team-prefix macOS group format, sandboxed/nonsandboxed IPC,
Mach/XPC service naming). Local launchctl bootstrap/bootout/kickstart help and
Foundation NSXPCConnection headers were also inspected.