#!/bin/bash

set -euo pipefail

APP_DIR="${1:-}"

if [ -z "$APP_DIR" ]; then
    echo "usage: $0 /path/to/VibeProxy.app" >&2
    exit 64
fi

EXECUTABLE_PATH="$APP_DIR/Contents/MacOS/CLIProxyMenuBar"
SPARKLE_BINARY_PATH="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
EXPECTED_SPARKLE_LOAD_PATH="@rpath/Sparkle.framework/Versions/B/Sparkle"
EXPECTED_FRAMEWORK_RPATH="@loader_path/../Frameworks"

fail() {
    echo "❌ $1" >&2
    exit 1
}

[ -d "$APP_DIR" ] || fail "App bundle not found at $APP_DIR"
[ -x "$EXECUTABLE_PATH" ] || fail "Main executable missing at $EXECUTABLE_PATH"
[ -f "$SPARKLE_BINARY_PATH" ] || fail "Bundled Sparkle binary missing at $SPARKLE_BINARY_PATH"

otool -L "$EXECUTABLE_PATH" | grep -Fq "$EXPECTED_SPARKLE_LOAD_PATH" || \
    fail "CLIProxyMenuBar no longer links Sparkle via $EXPECTED_SPARKLE_LOAD_PATH"

otool -l "$EXECUTABLE_PATH" | awk '/LC_RPATH/{show=1;next} show&&/path /{print $2;show=0}' | grep -Fxq "$EXPECTED_FRAMEWORK_RPATH" || \
    fail "CLIProxyMenuBar is missing the $EXPECTED_FRAMEWORK_RPATH runtime search path required to load Sparkle from the app bundle"

codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null

echo "✅ App bundle verification passed"
