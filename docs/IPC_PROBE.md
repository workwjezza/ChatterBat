# E3a — Signed bundled XPC ping feasibility

**E3b update:** separate user-host discovery from sandboxed app and CLI now
passes a temporary launchd/App Group ping matrix. See IPC_STANDALONE_PROBE.md.
Packaged installation, SMAppService, upgrades and durable recovery remain gates.

**Implemented and live-verified: isolated sandboxed app ↔ bundled XPC service.**
**Not verified: separately installed coding companion, CLI service discovery,
launch-agent registration/lifetime, or production distribution.** This is
E3a, not the full E3 host-deployment gate. No production agent wiring.

## Targets and trust

The separate `ChatterBatIPCProbe` scheme builds an authorized sandboxed
client app, a bundled sandboxed `ChatterBatIPCProbeService.xpc`, a same-team
wrong-identity `ChatterBatIPCRejectedProbe` app, and protocol unit tests.
None are dependencies of the normal ChatterBat scheme or embedded in it.
No new third-party framework is required: Foundation NSXPC and Security
requirements use frameworks already present in the project.

The only exported method is ping(Data) → Data. Codable protocol version 1
uses a UUID nonce; replies must match version/nonce/status. Payload processing
rejects more than 1,024 bytes, malformed data and unsupported versions. This
application-level bound does not prevent XPC from first allocating received
Data; this is not transport-wide resource/DoS hardening. Unknown methods have
no exported selector. No workspace, prompt, approval, credential or command
operation exists in this probe.

Both directions set NSXPCConnection.setCodeSigningRequirement before resume:
Apple generic anchor + exact signing identifier + leaf certificate team OU.
Requirements are locally constructed from allowlisted characters and parsed
with SecRequirementCreateWithString before NSXPC receives them. The service
also checks the connection's OS-reported effective UID; the client checks the
replying connection UID. No PID lookup, claimed JSON identity, same-UID-only
trust, private audit-token API or permissive fallback.

This repository's local development team is pinned for the probe. A different
team build must deliberately update probe identity configuration and reverify;
it does not accept a team or identity from a peer message. `--reject-service`
only tightens the expected service ID to a nonmatching value for a negative
test; there is no bypass flag. Apple Development signing is accepted for this
isolated feasibility artifact, not a final production trust policy. Certificate
class/version/revocation, malicious same-ID builds signed by the team, update
and downgrade trust remain part of the distribution threat model.

Apple's SDK marks setCodeSigningRequirement available since macOS 13, within
the project's macOS 14 baseline. The listener-wide requirement API must NOT
be used on serviceListener (SDK says it asserts); this service sets the
requirement on each peer connection before resume instead. The requirement
is enforced on message delivery, not inferred from a successful connection.

## Live results

Build-only Release artifacts verified on this development machine, Xcode
26.6 / current macOS, not a separate physical macOS 14 runtime:

| Probe | Observed result |
|---|---|
| Authorized client + expected service | PROBE_PONG_VERIFIED, exit 0 |
| Same-team different client identifier | PROBE_REQUEST_REJECTED, exit 2 |
| Authorized client requiring wrong service ID | PROBE_REQUEST_REJECTED, exit 2 |

`codesign --verify --strict` passed for both apps and service. Entitlements
were inspected: **App Sandbox only**, no temporary exceptions, no network,
no file grants, no get-task-allow. Hardened runtime/signing are inherited from
project settings. No launchd plist installed or SMAppService registration
performed. Executables were invoked inside their app bundles; launchd manages
the embedded XPC service. System sandbox containers/diagnostic logs may be
created by macOS; no user documents or provider credentials were accessed.

The initial Debug/test run was NOT accepted as sandbox proof: xcodebuild test
injected test-manager Mach lookup and root read-only exceptions. Its negative
paths also exposed Swift 6 main-actor inference in XPC error callbacks, causing
dispatch assertion crashes. Callbacks are now explicitly Sendable and the
reply's connection access is dispatched to the main queue. The final build-only
Release negatives return cleanly; crashes/timeouts are not accepted as passes.
System XPC logs on the failed initial negatives confirmed messages forbidden
by code-signing requirements; final negatives used the same requirements.

## Reproduce

Build the **probe scheme**, Release, to a directory not used for `test`:

```sh
xcodebuild -project /Users/studio-jd/Projects/ChatterBat/ChatterBat.xcodeproj \
  -scheme ChatterBatIPCProbe -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/ChatterBatIPCProbeRelease build
bash /Users/studio-jd/Projects/ChatterBat/IPCProbe/verify.sh \
  /tmp/ChatterBatIPCProbeRelease/Build/Products/Release
```

The verifier rejects unexpected entitlements and checks exact output/exit
codes for all three probes. Each executable has a five-second watchdog.
Run protocol unit tests using the same scheme's test action but **different
DerivedData**, e.g. `/tmp/ChatterBatIPCProbe`. Do not run the matrix against
test-instrumented artifacts. Probe unit tests do not exercise live transport;
the process matrix is the separate integration check.

Logs: `/tmp/ChatterBatIPCProbeTests.log`, `/tmp/ChatterBatIPCProbeRelease.log`,
`/tmp/ChatterBatIPCPingRelease.log`, `/tmp/ChatterBatIPCRejectClientRelease.log`,
`/tmp/ChatterBatIPCRejectServiceRelease.log`. Prior failed Debug probes may
remain in macOS DiagnosticReports. No test data/keys were involved.

## Next E3b gate — do not extrapolate

Bundled service discovery requires no special sandbox lookup entitlement but
does not solve a separately installed host's Mach service visibility. Before
E4 integration, prototype supported signed sandbox-client ↔ companion/CLI
discovery, authenticate both ends, verify unauthorised-client rejection,
install/revoke/update behavior and UI-closure lifetime. Decide packaging and
any necessary supported entitlements explicitly; do not copy a temporary
Mach lookup exception or open an unauthenticated localhost port. No elevated
daemon. Existing workspace reads remain in-process and inaccessible via IPC.

Production eligibility still requires Developer ID/notarization or the
appropriate review route, not just local Apple Development signing. No
Developer ID identity was available in the inspected local identity list;
no certificate creation, provisioning change, notarization or upload done.

References checked (public Apple Markdown pages and installed SDK headers):
- https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)
- https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)
- SDK Foundation NSXPCConnection.h (connection/listener availability and
  serviceListener caveat); previous E1 XPC/ServiceManagement references.