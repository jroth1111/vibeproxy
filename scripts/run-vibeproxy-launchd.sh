#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$REPO_ROOT/VibeProxy.app"

if [ ! -d "$APP_PATH" ]; then
    echo "VibeProxy app bundle not found at $APP_PATH" >&2
    exit 1
fi

# LaunchServices can open the local app bundle even when the machine has no
# trusted signing identity, whereas launchd direct-exec of the Mach-O inside
# the bundle trips macOS launch constraints on ad-hoc signatures.
exec /usr/bin/open -W "$APP_PATH"
