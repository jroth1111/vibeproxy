#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT_DIR/src"
TMP_BASE="${TMPDIR:-/tmp}"
mkdir -p "$TMP_BASE"
TMP_BUILD_DIR="$(mktemp -d "$TMP_BASE/vibeproxy-verification.XXXXXX")"

cleanup() {
    rm -rf "$TMP_BUILD_DIR"
}
trap cleanup EXIT

run_spec() {
    local name="$1"
    shift

    local output="$TMP_BUILD_DIR/$name"
    local -a swift_sources=()
    for relative_path in "$@"; do
        swift_sources+=("$SRC_DIR/$relative_path")
    done

    echo "▶ Compiling $name"
    swiftc -o "$output" "${swift_sources[@]}"

    echo "▶ Running $name"
    "$output"
}

run_thinking_proxy_policy_spec() {
    local name="ThinkingProxyPolicySpec"
    local output="$TMP_BUILD_DIR/$name"
    local build_dir="$SRC_DIR/.build/debug"
    local bridge_build_dir="$build_dir/CLIProxyObjCBridge.build"
    local bridge_object="$bridge_build_dir/CLIProxyCatchException.m.o"

    if [ ! -f "$bridge_object" ]; then
        echo "▶ Building package prerequisites for $name"
        (
            cd "$SRC_DIR"
            swift build -c debug >/dev/null
        )
    fi

    echo "▶ Compiling $name"
    swiftc \
        -I "$build_dir" \
        -I "$bridge_build_dir" \
        -o "$output" \
        "$SRC_DIR/Sources/ObjCExceptionCatcher.swift" \
        "$SRC_DIR/Sources/ThinkingProxy.swift" \
        "$SRC_DIR/Sources/ProviderCatalog.swift" \
        "$SRC_DIR/Verification/ThinkingProxyPolicySpec.swift" \
        "$bridge_object"

    echo "▶ Running $name"
    "$output"
}

run_spec \
    "ConfigComposerSpec" \
    "Sources/ConfigComposer.swift" \
    "Sources/CustomProviders.swift" \
    "Sources/ProviderCatalog.swift" \
    "Verification/ConfigComposerSpec.swift"

run_spec \
    "CustomProviderCredentialStoreSpec" \
    "Sources/ConfigComposer.swift" \
    "Sources/CustomProviders.swift" \
    "Sources/ProviderCatalog.swift" \
    "Sources/CustomProviderCredentialStore.swift" \
    "Verification/CustomProviderCredentialStoreSpec.swift"

run_spec \
    "ConfigInputFingerprintSpec" \
    "Sources/ConfigInputFingerprint.swift" \
    "Verification/ConfigInputFingerprintSpec.swift"

run_spec \
    "ZAIAPIKeyStoreSpec" \
    "Sources/ConfigComposer.swift" \
    "Sources/CustomProviders.swift" \
    "Sources/ProviderCatalog.swift" \
    "Sources/ZAIAPIKeyStore.swift" \
    "Verification/ZAIAPIKeyStoreSpec.swift"

run_thinking_proxy_policy_spec

echo "✅ All verification specs passed"
