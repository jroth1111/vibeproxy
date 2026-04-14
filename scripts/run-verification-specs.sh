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

PREPARED_SWIFT_SOURCES=()
prepare_stable_sources() {
    local dest_dir="$1"
    shift

    PREPARED_SWIFT_SOURCES=()
    mkdir -p "$dest_dir"

    local index=0
    local relative_path
    for relative_path in "$@"; do
        local copied_path="$dest_dir/${index}_$(basename "$relative_path")"
        if [ "$relative_path" = "Sources/ThinkingProxy.swift" ]; then
            awk '
                $0 == "import ProxyCore" { next }
                /MARK: - ProxyCore Domain Typealiases/ { skipping = 1; next }
                skipping && /MARK: - Original inline types/ { skipping = 0; next }
                !skipping { print }
            ' "$SRC_DIR/$relative_path" > "$copied_path"
        else
            cp "$SRC_DIR/$relative_path" "$copied_path"
        fi
        PREPARED_SWIFT_SOURCES+=("$copied_path")
        index=$((index + 1))
    done
}

run_spec() {
    local name="$1"
    shift

    local output="$TMP_BUILD_DIR/$name"
    prepare_stable_sources "$TMP_BUILD_DIR/$name-sources" "$@"

    echo "▶ Compiling $name"
    swiftc -o "$output" "${PREPARED_SWIFT_SOURCES[@]}"

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

    prepare_stable_sources \
        "$TMP_BUILD_DIR/$name-sources" \
        "Sources/ObjCExceptionCatcher.swift" \
        "Sources/NVIDIAStreamParser.swift" \
        "Sources/NVIDIAStreamEngine.swift" \
        "Sources/NVIDIAStreamSink.swift" \
        "Sources/NVIDIAStreamTransport.swift" \
        "Sources/ThinkingProxy.swift" \
        "Sources/ProviderCatalog.swift" \
        "Verification/ThinkingProxyPolicySpec.swift"

    echo "▶ Compiling $name"
    swiftc \
        -I "$build_dir" \
        -I "$bridge_build_dir" \
        -o "$output" \
        "${PREPARED_SWIFT_SOURCES[@]}" \
        "$bridge_object"

    echo "▶ Running $name"
    "$output"
}

run_meta_ai_web_adapter_spec() {
    local name="MetaAIWebAdapterSpec"
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

    prepare_stable_sources \
        "$TMP_BUILD_DIR/$name-sources" \
        "Sources/ObjCExceptionCatcher.swift" \
        "Sources/NVIDIAStreamParser.swift" \
        "Sources/NVIDIAStreamEngine.swift" \
        "Sources/NVIDIAStreamSink.swift" \
        "Sources/NVIDIAStreamTransport.swift" \
        "Sources/ThinkingProxy.swift" \
        "Sources/ProviderCatalog.swift" \
        "Verification/MetaAIWebAdapterSpec.swift"

    echo "▶ Compiling $name"
    swiftc \
        -I "$build_dir" \
        -I "$bridge_build_dir" \
        -o "$output" \
        "${PREPARED_SWIFT_SOURCES[@]}" \
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
    "NVIDIAStreamParserSpec" \
    "Sources/NVIDIAStreamParser.swift" \
    "Verification/NVIDIAStreamSpecSupport.swift" \
    "Verification/NVIDIAStreamParserSpec.swift"

run_spec \
    "NVIDIAStreamEngineSpec" \
    "Sources/NVIDIAStreamParser.swift" \
    "Sources/NVIDIAStreamTransport.swift" \
    "Sources/NVIDIAStreamEngine.swift" \
    "Sources/NVIDIAStreamSink.swift" \
    "Verification/NVIDIAStreamSpecSupport.swift" \
    "Verification/NVIDIAStreamEngineSpec.swift"

run_spec \
    "NVIDIAStreamTransportSpec" \
    "Sources/NVIDIAStreamTransport.swift" \
    "Sources/NVIDIAStreamSink.swift" \
    "Sources/NVIDIAStreamParser.swift" \
    "Verification/NVIDIAStreamSpecSupport.swift" \
    "Verification/NVIDIAStreamTransportSpec.swift"

run_spec \
    "ZAIAPIKeyStoreSpec" \
    "Sources/ConfigComposer.swift" \
    "Sources/CustomProviders.swift" \
    "Sources/ProviderCatalog.swift" \
    "Sources/ZAIAPIKeyStore.swift" \
    "Verification/ZAIAPIKeyStoreSpec.swift"

run_meta_ai_web_adapter_spec
run_thinking_proxy_policy_spec

echo "✅ All verification specs passed"
