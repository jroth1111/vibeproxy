#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/VibeProxy.app"
APP_BINARY_PATH="$APP_PATH/Contents/MacOS/CLIProxyMenuBar"
VERIFY_APP_BUNDLE_SCRIPT="$SCRIPT_DIR/verify-app-bundle.sh"
LOG_DIR="$HOME/.cli-proxy-api"
STDOUT_LOG="$LOG_DIR/launchd-vibeproxy.out.log"
STDERR_LOG="$LOG_DIR/launchd-vibeproxy.err.log"
FRONTEND_URL="${VIBEPROXY_FRONTEND_URL:-http://127.0.0.1:8317}"
HEALTH_URL="$FRONTEND_URL/healthz"
HEALTH_ATTEMPTS="${VIBEPROXY_LAUNCH_HEALTH_ATTEMPTS:-30}"
HEALTH_INTERVAL_SECONDS="${VIBEPROXY_LAUNCH_HEALTH_INTERVAL_SECONDS:-1}"
HEALTH_BODY="$(mktemp "${TMPDIR:-/tmp}/vibeproxy-launchd-health.XXXXXX")"

if [ ! -d "$APP_PATH" ]; then
    echo "VibeProxy app bundle not found at $APP_PATH" >&2
    exit 1
fi

if [ ! -x "$APP_BINARY_PATH" ]; then
    echo "VibeProxy app binary not found or not executable at $APP_BINARY_PATH" >&2
    exit 1
fi

cleanup() {
    rm -f "$HEALTH_BODY"
}
trap cleanup EXIT

verify_app_bundle() {
    "$VERIFY_APP_BUNDLE_SCRIPT" "$APP_PATH" >/dev/null
}

repair_app_bundle() {
    local expected_framework_rpath="@loader_path/../Frameworks"
    local sparkle_framework="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

    if [ ! -f "$sparkle_framework" ]; then
        return 1
    fi

    if ! otool -l "$APP_BINARY_PATH" | awk '/LC_RPATH/{show=1;next} show&&/path /{print $2;show=0}' | grep -Fxq "$expected_framework_rpath"; then
        echo "Repairing app bundle: restoring missing $expected_framework_rpath rpath on CLIProxyMenuBar" >&2
        install_name_tool -add_rpath "$expected_framework_rpath" "$APP_BINARY_PATH"
    fi

    chmod +x "$APP_BINARY_PATH"
    codesign --force --deep --sign - "$APP_PATH" >/dev/null
}

ensure_launchable_app_bundle() {
    if verify_app_bundle; then
        return 0
    fi

    echo "App bundle verification failed before launch; attempting repair." >&2
    if ! repair_app_bundle; then
        echo "Automatic app bundle repair failed." >&2
        "$VERIFY_APP_BUNDLE_SCRIPT" "$APP_PATH" >&2 || true
        return 1
    fi

    if ! verify_app_bundle; then
        echo "App bundle is still invalid after repair." >&2
        "$VERIFY_APP_BUNDLE_SCRIPT" "$APP_PATH" >&2 || true
        return 1
    fi
}

probe_health() {
    if ! curl -fsS --connect-timeout 3 --max-time 5 -o "$HEALTH_BODY" "$HEALTH_URL" >/dev/null 2>&1; then
        return 1
    fi

    jq -e '
        .frontend.port == 8317
        and .backend.reachable == true
        and ((.provenance.merged_config_fingerprint // "") | length > 0)
    ' "$HEALTH_BODY" >/dev/null
}

mkdir -p "$LOG_DIR"
ensure_launchable_app_bundle

# launchctl restarts this wrapper, not the app bundle itself. Explicitly stop any
# existing repo-local app instance so kickstart produces one authoritative proxy.
existing_pids="$(pgrep -f "$APP_BINARY_PATH" || true)"
if [ -n "$existing_pids" ]; then
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
    done <<< "$existing_pids"
    for _ in $(seq 1 20); do
        if ! pgrep -f "$APP_BINARY_PATH" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
fi

# LaunchServices can open the local app bundle even when the machine has no
# trusted signing identity, whereas launchd direct-exec of the Mach-O inside
# the bundle trips macOS launch constraints on ad-hoc signatures.
/usr/bin/open -n -W \
    --stdin /dev/null \
    --stdout "$STDOUT_LOG" \
    --stderr "$STDERR_LOG" \
    "$APP_PATH" &
open_pid="$!"

healthy=0
for _ in $(seq 1 "$HEALTH_ATTEMPTS"); do
    if probe_health; then
        healthy=1
        break
    fi

    if ! kill -0 "$open_pid" >/dev/null 2>&1; then
        break
    fi

    sleep "$HEALTH_INTERVAL_SECONDS"
done

if [[ "$healthy" != "1" ]]; then
    echo "VibeProxy did not become healthy at $HEALTH_URL after ${HEALTH_ATTEMPTS} attempts" >&2
    if [[ -s "$HEALTH_BODY" ]]; then
        echo "Last health payload:" >&2
        cat "$HEALTH_BODY" >&2
    fi
    kill "$open_pid" 2>/dev/null || true
    current_pids="$(pgrep -f "$APP_BINARY_PATH" || true)"
    if [ -n "$current_pids" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill "$pid" 2>/dev/null || true
        done <<< "$current_pids"
    fi
    wait "$open_pid" 2>/dev/null || true
    exit 1
fi

wait "$open_pid"
