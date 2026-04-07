#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/VibeProxy.app"
APP_BINARY_PATH="$APP_PATH/Contents/MacOS/CLIProxyMenuBar"
LOG_DIR="$HOME/.cli-proxy-api"
STDOUT_LOG="$LOG_DIR/launchd-vibeproxy.out.log"
STDERR_LOG="$LOG_DIR/launchd-vibeproxy.err.log"

if [ ! -d "$APP_PATH" ]; then
    echo "VibeProxy app bundle not found at $APP_PATH" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"

# launchctl restarts this wrapper, not the app bundle itself. Explicitly stop any
# existing repo-local app instance so kickstart produces one authoritative proxy.
existing_pids="$(pgrep -f "$APP_BINARY_PATH" || true)"
if [ -n "$existing_pids" ]; then
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
    done <<< "$existing_pids"
    sleep 1
fi

# LaunchServices can open the local app bundle even when the machine has no
# trusted signing identity, whereas launchd direct-exec of the Mach-O inside
# the bundle trips macOS launch constraints on ad-hoc signatures.
exec /usr/bin/open -n -W \
    --stdin /dev/null \
    --stdout "$STDOUT_LOG" \
    --stderr "$STDERR_LOG" \
    "$APP_PATH"
