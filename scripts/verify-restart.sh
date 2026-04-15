#!/bin/bash

# Restart verification runbook — validates a full VibeProxy restart cycle.
# Usage: ./scripts/verify-restart.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STEP=0
PASS=0
FAIL=0

step() {
    STEP=$((STEP + 1))
    printf "\n[%d] %s\n" "$STEP" "$1"
}

ok() {
    PASS=$((PASS + 1))
    echo "  ✅ PASS"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  ❌ FAIL: $1"
}

# ── Step 1: Run verification specs ──────────────────────────────────────
step "Run verification specs"
if "$ROOT_DIR/scripts/run-verification-specs.sh" >/dev/null 2>&1; then
    ok
else
    fail "verification specs failed — run ./scripts/run-verification-specs.sh for details"
fi

# ── Step 2: Build app bundle ────────────────────────────────────────────
step "Build app bundle"
if "$ROOT_DIR/create-app-bundle.sh" >/dev/null 2>&1; then
    ok
else
    fail "app bundle build failed"
fi

# ── Step 3: Restart launchd service ─────────────────────────────────────
step "Restart launchd service"
launchctl kickstart -k "gui/$(id -u)/com.vibeproxy.repo" 2>/dev/null && ok || fail "launchctl kickstart failed"

# ── Step 4: Wait for healthz 200 ────────────────────────────────────────
step "Wait for healthz 200 (up to 30s)"
HEALTH_URL="http://127.0.0.1:8317/healthz"
WAITED=0
HEALTHY=false
while [ "$WAITED" -lt 30 ]; do
    if curl -sf -o /dev/null "$HEALTH_URL" 2>/dev/null; then
        HEALTHY=true
        break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done
if $HEALTHY; then
    ok
else
    fail "healthz did not return 200 within 30s"
fi

# ── Step 5: Factory worker preflight ────────────────────────────────────
step "Factory worker preflight"
if "$ROOT_DIR/scripts/factory-worker-preflight.sh" >/dev/null 2>&1; then
    ok
else
    fail "factory worker preflight failed"
fi

# ── Step 6: Verify factory_worker.ready == true ─────────────────────────
step "Verify factory_worker.ready == true"
if $HEALTHY; then
    READY=$(curl -sf "$HEALTH_URL" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('factory_worker',{}).get('ready','false'))" 2>/dev/null || echo "false")
    if [ "$READY" = "true" ]; then
        ok
    else
        fail "factory_worker.ready = $READY"
    fi
else
    fail "skipped — healthz not reachable"
fi

# ── Step 7: Check for terminal failures in current PID telemetry ────────
step "Check telemetry for terminal failures in current PID"
if $HEALTHY; then
    FAILURE_COUNT=$("$ROOT_DIR/scripts/route-telemetry-summary.py" --pid current --json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(d.get('failure_distribution',{}).values()))" 2>/dev/null || echo "unknown")
    if [ "$FAILURE_COUNT" = "0" ]; then
        ok
    else
        fail "found $FAILURE_COUNT terminal failures in current PID window"
    fi
else
    fail "skipped — healthz not reachable"
fi

# ── Summary ─────────────────────────────────────────────────────────────
printf "\n══════════════════════════════════════\n"
printf "Restart verification: %d passed, %d failed (of %d steps)\n" "$PASS" "$FAIL" "$STEP"
printf "══════════════════════════════════════\n"

[ "$FAIL" -eq 0 ]
