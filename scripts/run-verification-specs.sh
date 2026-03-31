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

run_spec \
    "ThinkingProxyPolicySpec" \
    "Sources/ThinkingProxy.swift" \
    "Sources/ProviderCatalog.swift" \
    "Verification/ThinkingProxyPolicySpec.swift"

echo "✅ All verification specs passed"
