#!/bin/bash
# Temporary current-user launchd registration, ping only. No sudo/install.
set -euo pipefail
products="${1:?Pass absolute build-only Release products directory}"
case "$products" in /*) ;; *) echo "Absolute products path required" >&2; exit 1 ;; esac
label=AM3FXP5BXT.com.chatterbat.ipcprobe.ping
domain="gui/$(id -u)"
target="$domain/$label"
if /bin/launchctl print "$target" >/dev/null 2>&1; then
    echo "Refusing to replace an existing probe registration: $target" >&2
    exit 1
fi
work=$(mktemp -d /tmp/ChatterBatStandaloneProbe.XXXXXX)
registered=0
cleanup() {
    local code=$?
    trap - EXIT
    if [ "$registered" -eq 1 ]; then
        if ! /bin/launchctl bootout "$target"; then
            echo "CLEANUP FAILED: bootout $target manually; files retained at $work" >&2
            exit 1
        fi
    fi
    if /bin/launchctl print "$target" >/dev/null 2>&1; then
        echo "CLEANUP FAILED: service remains; files retained at $work" >&2
        exit 1
    fi
    rm -rf "$work"
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Parse actual signed entitlements, not the source plist. Test-injected
# authority must cause failure. Inspect host, CLI and both sandbox clients.
for name in ChatterBatIPCProbeHost ChatterBatIPCProbeCLI ChatterBatIPCStandaloneProbe.app ChatterBatIPCStandaloneRejectedProbe.app; do
    /usr/bin/codesign --verify --strict "$products/$name"
    /usr/bin/codesign -d --entitlements :- "$products/$name" > "$work/entitlements.plist" 2>/dev/null
    /usr/bin/python3 - "$work/entitlements.plist" "$name" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as file:
    actual = plistlib.load(file)
expected = {'com.apple.security.application-groups': ['AM3FXP5BXT.com.chatterbat.ipcprobe']}
if sys.argv[2].endswith('.app'):
    expected['com.apple.security.app-sandbox'] = True
if actual != expected:
    raise SystemExit('Unexpected signed entitlements for ' + sys.argv[2])
PY
done

/usr/bin/python3 - "$work/agent.plist" "$products/ChatterBatIPCProbeHost" "$label" "$work" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({'Label': sys.argv[3], 'ProgramArguments': [sys.argv[2]],
                  'MachServices': {sys.argv[3]: True}, 'RunAtLoad': True,
                  'StandardOutPath': sys.argv[4] + '/host.out',
                  'StandardErrorPath': sys.argv[4] + '/host.err'}, file)
PY
/bin/launchctl bootstrap "$domain" "$work/agent.plist"
registered=1
/bin/launchctl print "$target" > "$work/registered.txt"

run_probe() {
    local expected_code="$1" expected_output="$2" code output
    shift 2
    set +e
    output=$("$@" 2>&1)
    code=$?
    set -e
    printf '%s (exit %s)\n' "$output" "$code"
    [ "$code" -eq "$expected_code" ] || return 1
    if [ "$expected_output" = CONNECTION_FAILURE ]; then
        case "$output" in
            PROBE_REQUEST_REJECTED|PROBE_CONNECTION_INTERRUPTED|PROBE_CONNECTION_REJECTED_OR_INVALIDATED) ;;
            *) return 1 ;;
        esac
    else
        [ "$output" = "$expected_output" ]
    fi
}
app="$products/ChatterBatIPCStandaloneProbe.app/Contents/MacOS/ChatterBatIPCStandaloneProbe"
bad="$products/ChatterBatIPCStandaloneRejectedProbe.app/Contents/MacOS/ChatterBatIPCStandaloneRejectedProbe"
cli="$products/ChatterBatIPCProbeCLI"
run_probe 0 PROBE_PONG_VERIFIED "$app"
pid_before=$(/bin/launchctl print "$target" | awk '/^[[:space:]]*pid = / {print $3; exit}')
[ -n "$pid_before" ]
sleep 1
run_probe 0 PROBE_PONG_VERIFIED "$cli"
pid_after=$(/bin/launchctl print "$target" | awk '/^[[:space:]]*pid = / {print $3; exit}')
[ "$pid_before" = "$pid_after" ]
echo "HOST_SURVIVED_CLIENT_EXIT"
run_probe 2 CONNECTION_FAILURE "$bad"
run_probe 0 PROBE_PONG_VERIFIED "$cli"
run_probe 2 CONNECTION_FAILURE "$app" --reject-service
run_probe 2 CONNECTION_FAILURE "$cli" --reject-service
/bin/launchctl kickstart -k "$target"
run_probe 0 PROBE_PONG_VERIFIED "$cli"
pid_restarted=$(/bin/launchctl print "$target" | awk '/^[[:space:]]*pid = / {print $3; exit}')
[ -n "$pid_restarted" ] && [ "$pid_restarted" != "$pid_after" ]
echo "HOST_RESTART_RECONNECTED"
/bin/launchctl bootout "$target"
registered=0
if /bin/launchctl print "$target" >/dev/null 2>&1; then exit 1; fi
run_probe 2 CONNECTION_FAILURE "$cli"
echo "SERVICE_REMOVED_AND_UNREACHABLE"
echo "STANDALONE_PROBE_MATRIX_PASSED"