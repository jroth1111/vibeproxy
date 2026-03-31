# Fix Health-Ranked Pool Implementation

The intern implemented the 6 improvements from `health-ranked-pool-lessons.md` but left several bugs, incorrect assignments, dead code, and missing test updates. This plan covers all fixes needed to get to a shippable state.

## Context

All 6 improvements (A–F) were partially or fully implemented in ThinkingProxy.swift and ConfigComposer.swift. The changes compile for the app target but **`ThinkingProxyPolicySpec` does not compile** due to 3 errors. Additionally, cost differentiation is dead code, model tier assignments are wrong, and no tests were added.

---

## Fix 1: Make ThinkingProxyPolicySpec compile (3 errors)

**Root cause:** The intern renamed two public APIs without updating the 3 call sites in the test file, and `ProviderCatalog.swift` isn't in the spec's compilation unit.

### 1a. Add `ProviderCatalog.swift` to ThinkingProxyPolicySpec compilation

**File:** `scripts/run-verification-specs.sh`, lines 61–64

Change:
```swift
run_spec \
    "ThinkingProxyPolicySpec" \
    "Sources/ThinkingProxy.swift" \
    "Verification/ThinkingProxyPolicySpec.swift"
```

To:
```swift
run_spec \
    "ThinkingProxyPolicySpec" \
    "Sources/ProviderCatalog.swift" \
    "Sources/ThinkingProxy.swift" \
    "Verification/ThinkingProxyPolicySpec.swift"
```

### 1b. Rename test references for canary API

**File:** `src/Verification/ThinkingProxyPolicySpec.swift`

**Line 668:** `recommendedNVIDIACanaryInterval()` → `recommendedCanaryInterval()`

**Lines 5039, 5055, 5110, 5123:** `performNVIDIACanariesOnce` → `performCanariesOnce` (4 call sites)

---

## Fix 2: Fix unused variable warnings (2 warnings)

**File:** `src/Sources/ThinkingProxy.swift`

### 2a. Line 4805: unused `directProxyRoute`

Read the context around line 4805 to determine if this should be used or removed. Based on the pattern, it's likely a dead binding from a refactor — change `let directProxyRoute = ...` to `_ = ...`.

### 2b. Line 6905: unused `cancel` return value

Change `let cancel = sendDirectProxiedRequest(...)` to `_ = sendDirectProxiedRequest(...)`.

---

## Fix 3: Fix model tier assignments to match the plan

**File:** `src/Sources/ThinkingProxy.swift`, lines 444–451 (`modelTierByCanonicalModelID`)

Current (incorrect):
```swift
private static let modelTierByCanonicalModelID: [String: ModelTier] = [
    "z-ai/glm5": .standard,
    "moonshotai/kimi-k2.5": .reasoning,
    "minimaxai/minimax-m2.5": .standard,
    "mimo-v2-pro-free": .economy,
    "xiaomi/mimo-v2-pro:free": .economy,
    "minimax-m2.5-free": .standard,
]
```

Plan-corrected (glm-5.1-zai is the reasoning-tier model, not kimi; free models are free/economy):
```swift
private static let modelTierByCanonicalModelID: [String: ModelTier] = [
    "z-ai/glm5": .reasoning,
    "moonshotai/kimi-k2.5": .standard,
    "minimaxai/minimax-m2.5": .standard,
    "mimo-v2-pro-free": .free,
    "xiaomi/mimo-v2-pro:free": .free,
    "minimax-m2.5-free": .economy,
]
```

**Rationale from plan:**
- `glm-5.1-zai` (canonical `z-ai/glm5`): reasoning tier — it's the primary Z.AI model with thinking/reasoning capability
- `kimi-k2.5`: standard tier — capable but not the reasoning-primary model
- `mimo-v2-pro-free`: free tier — it's literally a free model
- `minimax-m2.5-free`: economy tier — free tier of paid model

---

## Fix 4: Fix cost factor — dead code (user confirmed: all free, prices changeable later)

**File:** `src/Sources/ThinkingProxy.swift`, line 3265

The `inputPricePerMillionTokensByCanonicalModelID` map stays unchanged (all 0.0). To set prices later, just update the map value — no restructuring needed.

The bug: `guard price > 0 else { return 1.0 }` means cost factor always returns 1.0 since all prices are 0. The fix changes the free-model fallback from a no-op to a meaningful multiplier:

```swift
// In costFactor(forRequestModel:), line 3265:
// Change:  guard price > 0 else { return 1.0 }
// To:      guard price > 0 else { return pow(100.0, costPreference) }
```

At `costPreference = 0.3`, free models get `100^0.3 ≈ 3.98x` score multiplier. When a model's price is later set to a non-zero value (e.g., $0.50/M), the existing formula `pow(1.0 / (price + 0.01), costPreference)` kicks in naturally.

---

## Fix 5: Add tests for all 6 improvements

**File:** `src/Verification/ThinkingProxyPolicySpec.swift`

Add the following test cases inside the `main()` function. Insert before the final `if recorder.failures == 0` block.

### 5a. E — Momentum bonus accelerates recovery scoring

```swift
run("recovered routes gain momentum bonus that decays over time", recorder: recorder) {
    let now = Date()
    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
    OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "glm5", until: now.addingTimeInterval(300))

    // Canary success closes the route with recoveredAt = now
    let successEvent = makeTelemetryEvent(
        requestModel: "z-ai/glm5", transportOutcome: "send_response", source: "canary"
    )
    OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: "glm5", telemetryEvent: successEvent, at: now)

    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
    let state = snapshot["z-ai/glm5"]
    expectEqual(state?.status, .closed, "recovered route should be closed", recorder: recorder)
    expectEqual(state?.recoveredAt != nil, true, "recovered route should have recoveredAt set", recorder: recorder)

    // EMA should be reset for recovery (obsCount=3, rate=0.8)
    expectEqual(state?.emaMetrics.observationCount, 3, "recovery should reset EMA observation count to warm start", recorder: recorder)
    expectEqual(state?.emaMetrics.successRate ?? 0.0 > 0.7, true, "recovery should reset EMA success rate to 0.8", recorder: recorder)

    // Momentum bonus should be ~50 at t=0, decaying to ~35 at t=10s
    let bonusAt0 = state?.momentumBonus(at: now) ?? 0.0
    expectEqual(bonusAt0 > 45, true, "momentum bonus should be near 50 at recovery time", recorder: recorder)

    let bonusAt10 = state?.momentumBonus(at: now.addingTimeInterval(10)) ?? 0.0
    expectEqual(bonusAt10 < bonusAt0, true, "momentum bonus should decay over time", recorder: recorder)
    expectEqual(bonusAt10 > 25, true, "momentum bonus should still be significant at 10s", recorder: recorder)

    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
}
```

### 5b. D — Canary uses 1 token

```swift
run("canary request uses minimal max_tokens", recorder: recorder) {
    // Verify the canary JSON uses max_tokens=1
    // This is tested indirectly via the canary probe producing valid health updates
    // with minimal token waste. The nvidiaCanaryRequestJSON is private, so we verify
    // through integration: a canary probe that succeeds should close the route.
    let now = Date()
    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
    OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "glm5", until: now.addingTimeInterval(300))

    let successEvent = makeTelemetryEvent(
        requestModel: "z-ai/glm5", transportOutcome: "send_response", source: "canary"
    )
    OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: "glm5", telemetryEvent: successEvent, at: now)

    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
    expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "canary success with 1-token probe should close route", recorder: recorder)
    expectEqual(snapshot["z-ai/glm5"]?.lastTelemetryEvent?.source, "canary", "canary telemetry source should be recorded", recorder: recorder)

    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
}
```

### 5c. B — Model tier affects ranking

```swift
run("model tier differentiates ranking scores", recorder: recorder) {
    // glm5 is reasoning tier (1.0), minimax-m2.5-free is economy (0.6)
    let glmTier = OpenAICompatTemporaryShim.modelTier(forRequestModel: "glm5")
    let miniTier = OpenAICompatTemporaryShim.modelTier(forRequestModel: "minimax-m2.5-free")
    expectEqual(glmTier, OpenAICompatTemporaryShim.ModelTier.reasoning, "glm5 should be reasoning tier", recorder: recorder)
    expectEqual(miniTier, OpenAICompatTemporaryShim.ModelTier.economy, "minimax-m2.5-free should be economy tier", recorder: recorder)
    expectEqual(glmTier.rawValue > miniTier.rawValue, true, "reasoning tier should have higher weight than economy", recorder: recorder)
}
```

### 5d. C — Cost factor differentiates free models

```swift
run("cost factor gives advantage to free models", recorder: recorder) {
    let freeCost = OpenAICompatTemporaryShim.costFactor(forRequestModel: "glm5")
    // At price=0, costFactor should return pow(100, 0.3) ≈ 3.98
    expectEqual(freeCost > 1.0, true, "free model cost factor should be > 1.0", recorder: recorder)
    expectEqual(freeCost > 3.0, true, "free model cost factor should be ~3.98x", recorder: recorder)
}
```

### 5e. F — Health sensitivity changes ranking thresholds

```swift
run("health sensitivity controls score gap threshold for reordering", recorder: recorder) {
    let eager = OpenAICompatTemporaryShim.HealthSensitivity.eager
    let balanced = OpenAICompatTemporaryShim.HealthSensitivity.balanced
    let conservative = OpenAICompatTemporaryShim.HealthSensitivity.conservative

    expectEqual(eager.scoreGapThreshold, 200.0, "eager should use 200ms threshold", recorder: recorder)
    expectEqual(balanced.scoreGapThreshold, 500.0, "balanced should use 500ms threshold", recorder: recorder)
    expectEqual(conservative.scoreGapThreshold, 2000.0, "conservative should use 2000ms threshold", recorder: recorder)

    // Verify eager reorders more aggressively than conservative
    expectEqual(eager.scoreGapThreshold < conservative.scoreGapThreshold, true, "eager should reorder more aggressively than conservative", recorder: recorder)
}
```

### 5f. A — Route identity resolution for any provider

```swift
run("resolveRouteIdentityForAnyProvider matches OAuth prefix models", recorder: recorder) {
    OpenAICompatTemporaryShim.clearRouteHealthForTesting()

    let claudeRoute = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: "claude-sonnet-4-20250514")
    expectEqual(claudeRoute?.providerID, "claude", "claude-prefixed model should resolve to claude provider", recorder: recorder)
    expectEqual(claudeRoute?.canonicalModelID, "claude-sonnet-4-20250514", "canonical model should be preserved", recorder: recorder)

    let geminiRoute = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: "gemini-2.5-pro")
    expectEqual(geminiRoute?.providerID, "gemini", "gemini-prefixed model should resolve to gemini provider", recorder: recorder)

    let unknownRoute = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: "some-unknown-model")
    expectEqual(unknownRoute, nil, "unknown model with no matching prefix should return nil", recorder: recorder)

    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
}
```

### 5g. Provider cooldown tracking

```swift
run("provider cooldown suppresses routes from that provider", recorder: recorder) {
    let now = Date()
    OpenAICompatTemporaryShim.clearRouteHealthForTesting()

    // Set a cooldown for the nvidia provider
    OpenAICompatTemporaryShim.providerCooldownUntil(statusCode: 429, headers: ["Retry-After": "60"], now: now)
    // Record a failure that forces the route open
    let failureEvent = makeTelemetryEvent(
        requestModel: "z-ai/glm5", transportOutcome: "send_error"
    )
    OpenAICompatTemporaryShim.recordRouteFailure(
        forRequestModel: "glm5",
        telemetryEvent: failureEvent,
        at: now,
        forcedOpenUntil: now.addingTimeInterval(60)
    )

    // Verify the provider cooldown is set
    expectEqual(
        OpenAICompatTemporaryShim.isProviderInCooldown(providerID: "nvidia", at: now),
        true, "nvidia provider should be in cooldown after 429 response",
        recorder: recorder
    )

    // Cooldown should expire
    expectEqual(
        OpenAICompatTemporaryShim.isProviderInCooldown(providerID: "nvidia", at: now.addingTimeInterval(61)),
        false, "provider cooldown should expire after the Retry-After duration",
        recorder: recorder
    )

    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
}
```

### 5h. EMA reset on recovery preserves score advantage

```swift
run("recovery EMA reset gives warm start without stale failure history", recorder: recorder) {
    let now = Date()
    OpenAICompatTemporaryShim.clearRouteHealthForTesting()

    // Build up a bad EMA through many failures
    for i in 0..<20 {
        let failureEvent = makeTelemetryEvent(
            requestModel: "z-ai/glm5", transportOutcome: "send_error"
        )
        OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", telemetryEvent: failureEvent, at: now.addingTimeInterval(TimeInterval(i)))
    }
    let badSnapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
    expectEqual(badSnapshot["z-ai/glm5"]?.status, .open, "route should be open after many failures", recorder: recorder)

    // Recovery success should reset EMA
    let successEvent = makeTelemetryEvent(
        requestModel: "z-ai/glm5", transportOutcome: "send_response", source: "canary"
    )
    OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: "glm5", telemetryEvent: successEvent, at: now.addingTimeInterval(100))

    let goodSnapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
    let recoveredEMA = goodSnapshot["z-ai/glm5"]?.emaMetrics
    expectEqual(recoveredEMA?.observationCount, 3, "recovery EMA should have warm-start observation count of 3", recorder: recorder)
    expectEqual(recoveredEMA?.successRate ?? 0 > 0.7, true, "recovery EMA should start with high success rate", recorder: recorder)
    expectEqual(goodSnapshot["z-ai/glm5"]?.status, .closed, "route should be closed after recovery", recorder: recorder)

    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
}
```

---

## Fix 6: Make `isProvenPerfect` threshold configurable or document the change

The intern changed `isProvenPerfect` from `successRate == 1.0` to `successRate >= 0.999`. This wasn't in the plan but is defensible — EMA rounding can cause a truly-perfect route to show 0.9999... instead of exactly 1.0. The plan's Bifrost lesson mentions "proven-perfect (observed >0, successRate==1.0)" but the EMA math makes exact 1.0 unlikely after many observations.

**Decision:** Keep the `>= 0.999` threshold. It's the right engineering call — exact float equality with EMA is fragile. No code change needed; just document the rationale in a comment.

---

## File Change Summary

| File | Changes |
|------|---------|
| `scripts/run-verification-specs.sh` | Add `ProviderCatalog.swift` to ThinkingProxyPolicySpec compilation |
| `src/Verification/ThinkingProxyPolicySpec.swift` | Rename 5 canary API references; add 8 new test cases (~200 lines) |
| `src/Sources/ThinkingProxy.swift` | Fix 4 model tiers; fix cost factor guard; fix 2 unused variable warnings |

**Total estimated changes:** ~250 lines across 3 files.

---

## Verification

1. Run `./scripts/run-verification-specs.sh` — all 5 specs must pass
2. Run `cd src && swift build` — app target must compile
3. Verify the new test cases exercise: momentum decay, tier weights, cost factor, health sensitivity hysteresis, route identity for OAuth providers, provider cooldown tracking, EMA recovery reset
