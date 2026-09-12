#!/bin/bash
# Run against build-only Release products, NEVER xcodebuild test artifacts.
set -eu
products="${1:?Pass the absolute Release products directory}"
case "$products" in /*) ;; *) echo "Absolute path required" >&2; exit 1 ;; esac
for name in ChatterBatIPCProbe.app ChatterBatIPCRejectedProbe.app ChatterBatIPCProbeService.xpc; do
    artifact="$products/$name"
    /usr/bin/codesign --verify --strict "$artifact"
    entitlements=$(/usr/bin/codesign -d --entitlements - "$artifact" 2>/dev/null)
    # Build-only probe targets have exactly one entitlement. Fail closed if
    # tests, tooling or signing configuration have injected extra authority.
    if [ "$(printf '%s' "$entitlements" | /usr/bin/grep -c '\[Key\]')" -ne 1 ] ||
       ! printf '%s' "$entitlements" | /usr/bin/grep -q 'com.apple.security.app-sandbox'; then
        echo "Unexpected probe entitlements: $name" >&2
        exit 1
    fi
done
run_probe() {
    expected_code="$1"
    expected_output="$2"
    shift 2
    set +e
    output=$("$@" 2>&1)
    code=$?
    set -e
    printf '%s (exit %s)\n' "$output" "$code"
    [ "$code" -eq "$expected_code" ] && [ "$output" = "$expected_output" ]
}
run_probe 0 PROBE_PONG_VERIFIED "$products/ChatterBatIPCProbe.app/Contents/MacOS/ChatterBatIPCProbe"
run_probe 2 PROBE_REQUEST_REJECTED "$products/ChatterBatIPCRejectedProbe.app/Contents/MacOS/ChatterBatIPCRejectedProbe"
run_probe 2 PROBE_REQUEST_REJECTED "$products/ChatterBatIPCProbe.app/Contents/MacOS/ChatterBatIPCProbe" --reject-service
echo "PROBE_MATRIX_PASSED"