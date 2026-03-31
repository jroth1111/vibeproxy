# Health-Ranked Pool: Lessons from GitHub Projects

## Context

VibeProxy already has a sophisticated circuit breaker system for NVIDIA-hosted routes (`ThinkingProxy.swift` ~8800 lines), with EMA-based composite scoring, smart alias failover, and a canary loop. However, the health system has significant gaps: no health tracking for OAuth providers (Claude, Gemini, Codex), no model intelligence ranking, no free-tier rate limit awareness, and no cost dimension in scoring. This plan synthesizes lessons from 5 production-grade LLM gateways and maps them to concrete improvements.

---

## What We're Learning From Each Project

### 1. pLLM (andreimerfu/pllm) — Health-Scored Pools with Zero Token Waste

**Key insight:** Health is determined passively from real traffic, not active probes. The only "active" check is a lightweight connectivity ping (no LLM inference), so zero tokens are wasted on health monitoring.

**Applicable patterns:**
- **Piecewise-linear P95 latency → 0–100 score** (pLLM uses 6 tiers). VibeProxy's EMA-based `compositeScore` (`successRate² * 1000 - averageLatencyMs`) is functionally similar but unintuitive — a normalized 0–100 score would be easier to reason about and display.
- **3-level failover:** instance retry → model fallback → fallback chain. VibeProxy already has this structure in the smart alias system (candidate retry → ranked fallback → forced probe), but it's NVIDIA-only.
- **Lock-free atomics** for health state (Go `atomic.Bool` / `atomic.Int32`). VibeProxy uses a serial dispatch queue (`routeHealthQueue.sync {}`) which is correct for Swift but the state mutations could be made more granular.
- **Redis as optional distributed state** with graceful in-memory fallback. Not needed for a single macOS app, but the pattern of making distributed state optional is good design.

**What NOT to copy:** pLLM's 30-second recovery cooldown is too aggressive for VibeProxy's use case. VibeProxy's 300-second cooldown is better for provider-level outages that typically last minutes, not seconds.

---

### 2. cp50/ai-gateway — Threshold-Based Quality-Aware Routing

**Key insight:** Different route types get different switching thresholds. "Reasoning" routes are sticky (never downgrade a zero-failure reasoning model just because a cheap model has lower latency). This directly addresses the user's concern that "some models are better than others in terms of intelligence."

**Applicable patterns:**
- **Route-type-specific switching thresholds.** cp50 uses 300ms for cheap routes (eager switching) and 2500ms for reasoning routes (conservative). VibeProxy's smart aliases should have per-alias health sensitivity settings.
- **Sticky-on-zero-failures for quality routes.** If a high-quality model has zero failures, it should never be downgraded to a lower-tier model solely on latency. This prevents a fast-but-dumb free model from outranking a paid model that's merely slower.
- **Welford's online algorithm** for running latency mean (O(1) space, no arrays). VibeProxy's EMA (alpha=0.2) achieves the same goal with a different formula — both are valid, but Welford's has better mathematical properties for unbounded observation counts.
- **Two-phase quality gate:** health-aware routing first, then confidence escalation. If the cheap model's output is weak, re-ask with the reasoning model. VibeProxy could implement this for smart alias requests — if the first candidate returns a short/empty/hedging response, silently retry with a higher-tier model.

**What NOT to copy:** cp50's intent classification (keyword matching for "analyze", "architecture") is too simplistic for production. VibeProxy's model-per-request approach (user explicitly chooses model or smart alias) is better.

---

### 3. llmproxy (fabriziosalmi) — Composite Score with Cost Factor

**Key insight:** The routing score formula `(success² / latency) × cost_factor` explicitly factors in cost. This is critical for the user's requirement that "some models are free up to a rate limit" — free models should have a massive score advantage when healthy.

**Applicable patterns:**
- **Cost-weighted scoring.** The `cost_factor = 1 / (input_price + 0.01)` gives free models a 100x advantage. The `cost_weight` exponent (default 0.3) lets the user dial cost preference from "ignore" (0.0) to "dominant" (1.0). VibeProxy's `compositeScore` should add a cost dimension.
- **EMA-smoothed stats (alpha=0.2)** — VibeProxy already uses the same alpha. Consistent.
- **Budget-triggered auto-downgrade.** When daily spend hits a limit, automatically route to local/free models. VibeProxy should track per-provider spend and auto-downgrade free-tier models when their rate limit is exhausted.
- **Three-tier selection:** priority mode (admin override) → smart weighted (score-based) → round-robin (cold start). VibeProxy's smart aliases already have a similar structure but lack the explicit priority override.
- **Priority steering mode** — admin can override health-based ranking with manual priority. VibeProxy's ConfigComposer could expose per-candidate priority weights.

**What NOT to copy:** llmproxy's active probing every 60 seconds with 1-token requests still wastes tokens. pLLM's passive-only approach is better for VibeProxy's use case.

---

### 4. Bifrost (maximhq) — 4-State Health Machine with Momentum Recovery

**Key insight:** Bifrost's `Healthy → Degraded → Failed → Recovering` state machine with momentum-based weight recovery is the most sophisticated health model observed. The "Recovering" state with momentum bias enables fast weight restoration (90% penalty reduction in 30 seconds) without flapping.

**Applicable patterns:**
- **4-state model vs VibeProxy's 4-state model.** VibeProxy has `closed → suspect → open → half_open`. The mapping is: closed≈Healthy, suspect≈Degraded, open≈Failed, half_open≈Recovering. The semantics are nearly identical. VibeProxy's model is already good here.
- **Error rate thresholds** (2% → Degraded, 5% → Failed). VibeProxy uses failure count (4 consecutive) rather than rate. Rate-based is more resilient to intermittent errors but requires a sliding window. For VibeProxy's low-volume per-route traffic, count-based is more practical.
- **Multi-factor weight formula:** `Score = (P_error × 0.5) + (P_latency × 0.2) + (P_util × 0.05) − M_momentum`. VibeProxy's `compositeScore = successRate² * 1000 - averageLatencyMs` combines error and latency but lacks utilization and momentum dimensions.
- **Exploration probability (25%).** Even Failed/Recovering routes receive some traffic to detect recovery. VibeProxy's canary loop does this for quarantined NVIDIA routes, but exploration should be probabilistic during normal routing, not just serial canary probing.
- **Gossip protocol for cross-node sync.** Not applicable to a single macOS app, but the pattern of decoupling health state from routing state is good architecture.

**What NOT to copy:** Bifrost's enterprise-only health features (gossip, dynamic weight recalculation every 5s) are overkill for a desktop proxy. The open-source core's simpler weighted random selection is sufficient.

---

### 5. LiteLLM (BerriAI/litellm) — Shared Health Checks with Token Efficiency

**Key insight:** In multi-pod deployments, only ONE pod runs health checks per interval via Redis distributed locks. With 10 pods and 50 models, this eliminates 450 redundant API calls per interval. Even in single-instance mode, `max_tokens=1` probes and background caching prevent token waste.

**Applicable patterns:**
- **Per-model `disable_background_health_check` flag.** VibeProxy should let users opt specific models out of canary probing.
- **`max_tokens=1` for health probes.** VibeProxy's canary already uses `max_tokens=32` — should drop to 1.
- **DB write deduplication** (only persist on status change or 1-hour expiry). VibeProxy persists `route-health.json` on every state change — could batch writes.
- **Health-check-driven routing** (`enable_health_check_routing: true`). Proactively excludes deployments that failed background health checks before request routing, rather than waiting for request failures. VibeProxy's smart alias system already does this (open circuits are skipped), but it could be more aggressive about excluding degraded-but-not-open routes.
- **Bounded concurrency** for health checks (FIRST_COMPLETED wait-loop). Prevents overwhelming providers with simultaneous probes.

**What NOT to copy:** LiteLLM's synchronous `/health` endpoint that runs live API calls on every HTTP request is expensive. VibeProxy's approach of returning cached state is better.

---

## Concrete Improvements for VibeProxy

### A. Extend Health Tracking to All Providers (not just NVIDIA)

**Current state:** Circuit breaker and health tracking only apply to routes resolved via `openai-compatibility` config. OAuth providers (Claude via `claude-api-key`, Gemini, Codex) have zero health tracking.

**Plan (full scope — all providers):**
1. Generalize `routeIdentityForHealthTracking()` to resolve routes for all provider types: `openai-compatibility` (NVIDIA), `claude-api-key` (Claude), and any future OAuth providers. The route key should be `providerType::modelID` regardless of provider backend.
2. Record successes/failures for OAuth provider responses in the same `routeCircuitStatesByRouteHealthKey` dictionary. Hook into the response processing path where HTTP status codes and response bodies are evaluated.
3. Rename the canary loop from `startNVIDIACanaryLoop` to `startCanaryLoop` and extend it to probe quarantined routes from any provider type. Use a minimal 1-token request with a 10s timeout. For OAuth providers, use a simple chat completion probe compatible with their API shape.
4. Track OAuth provider health passively from real traffic (pLLM pattern) — no active probes needed unless a route is quarantined. Passive detection means recording success/failure on every real request as a side-effect.
5. The `providerCooldownUntil` tracking should be per-provider (not per-route as it currently is), so a 429 from Claude excludes all Claude routes, not just the specific model.

**Files:** `ThinkingProxy.swift` (route resolution, canary loop, provider cooldown), `ConfigComposer.swift` (route identity generation for OAuth providers), `ServerManager.swift` (provider-level cooldown state).

---

### B. Add Model Intelligence Tier to Composite Score

**Current state:** `compositeScore = successRate² * 1000 - averageLatencyMs`. No concept of model quality.

**Plan:**
1. Add a `ModelTier` enum: `.reasoning`, `.standard`, `.economy`, `.free`.
2. Ship hardcoded defaults for known models (e.g., `glm-5.1-zai` → `.reasoning`, `kimi-k2.5-nvidia` → `.standard`, `mimo-v2-pro-kilocode` → `.free`). Allow user override via config YAML field `model-tier` per model entry. If not in config, hardcoded default applies.
3. Add a tier weight multiplier to the composite score: reasoning=1.0, standard=0.8, economy=0.6, free=0.4. This means a healthy free model is always scored below a healthy paid model, all else being equal.
4. Implement cp50's sticky-on-zero-failures pattern: if a reasoning-tier model has zero failures and has served requests, never downgrade it to a lower-tier model on latency alone.
5. Add per-alias `healthSensitivity` (like cp50's thresholds): reasoning aliases require a larger score gap before switching; economy aliases switch eagerly.

**Files:** `ThinkingProxy.swift` (compositeScore, rankedSmartAliasFallbackCandidateModels), `ConfigComposer.swift` (model tier defaults + config override).

---

### C. Add Cost/Free-Tier Dimension to Scoring

**Current state:** No cost awareness. Free and paid models scored identically.

**Plan:**
1. Add `inputPricePerMillionTokens` to provider config (float, 0.0 for free tiers).
2. Extend composite score: `compositeScore = (successRate² * 1000 - averageLatencyMs) × costFactor` where `costFactor = 1.0 / (pricePerMTok + 0.01)` (llmproxy formula). This gives free models a ~100x score advantage.
3. Add a `costWeight` user preference (0.0–1.0, default 0.3) to control how much cost influences ranking.
4. Track per-provider rate limit budgets. When a free-tier provider returns 429, record the `Retry-After` window and exclude that provider from routing until the window expires (already partially done via `providerCooldownUntil` but needs to be per-provider, not per-route).

**Files:** `ThinkingProxy.swift` (compositeScore), `ConfigComposer.swift` (provider cost metadata), `CustomProviders.swift` (cost field for custom providers).

---

### D. Reduce Canary Token Waste

**Current state:** Canary probes send `max_tokens: 32` with prompt "Return exactly: OK".

**Plan:**
1. Drop `max_tokens` from 32 to 1 (LiteLLM pattern).
2. Shorten probe prompt to `"OK"` (2 tokens instead of 5).
3. Add per-model `disableCanaryProbe` flag to opt out models that shouldn't be probed.
4. Implement adaptive canary intervals based on how long a route has been quarantined: recently-opened routes probed every 30s, long-quarantined routes probed every 5 minutes (backoff).

**Files:** `ThinkingProxy.swift` (canary loop, `runNVIDIACanary`).

---

### E. Add Composite Score Momentum for Faster Recovery

**Current state:** When a route recovers from `open` → `closed`, its EMA success rate is still degraded from past failures. It takes many successful requests to rebuild the score.

**Plan:**
1. Implement Bifrost's momentum bias: on recovery, apply a bonus that decays over time. `momentumBonus = baseBonus × decay^(secondsSinceRecovery)`. This accelerates weight restoration without permanently biasing the score.
2. Reset `failureScore` to 0 on successful recovery (already done in `nextRouteCircuitStateAfterSuccess`).
3. Consider resetting EMA on recovery (set `observationCount` to a small number like 3, `successRate` to 0.8) so the route can quickly prove itself without being dragged down by stale failure history.

**Files:** `ThinkingProxy.swift` (EMA metrics, circuit breaker success handler).

---

### F. Per-Alias Configuration for Health Sensitivity

**Current state:** All smart aliases use the same circuit breaker policy (`failureThreshold: 4, cooldown: 300, recoverySuccessThreshold: 1`).

**Plan:**
1. Add optional per-alias config fields:
   - `health-sensitivity`: `eager` (switch on small gap, for economy/free routes) | `balanced` (default) | `conservative` (require large gap, for reasoning routes)
   - `circuit-breaker-threshold`: override the default 4-failure threshold
   - `recovery-cooldown`: override the default 300s cooldown
2. Map sensitivity to switching thresholds: eager=200ms gap, balanced=500ms gap, conservative=2000ms gap (cp50 pattern).
3. Use these in `rankedSmartAliasFallbackCandidateModels()` to adjust how aggressively candidates are reordered.

**Files:** `ThinkingProxy.swift` (ranking, circuit breaker policy), `ConfigComposer.swift` (alias config schema).

---

## Implementation Order (Priority)

1. **E. Composite Score Momentum** — Smallest change, biggest recovery improvement. ~50 lines.
2. **D. Reduce Canary Token Waste** — Quick win, saves tokens immediately. ~20 lines.
3. **B. Model Intelligence Tier** — Core differentiator, addresses "some models are smarter." ~150 lines.
4. **C. Cost/Free-Tier Dimension** — Addresses "some models are free." ~100 lines.
5. **F. Per-Alias Health Sensitivity** — Enables cp50-style threshold tuning. ~80 lines.
6. **A. Extend Health to All Providers** — Largest change, most architectural impact. ~300 lines.

---

## Anti-Patterns Observed (What NOT to Do)

| Anti-Pattern | Found In | Why It's Bad |
|---|---|---|
| Active LLM probes every 60s for every model | llmproxy, LiteLLM (default) | Wastes 600+ tokens/hour for healthy endpoints |
| Keyword-based intent classification | cp50/ai-gateway | Too simplistic, produces false positives |
| Synchronous health checks on every request | LiteLLM (without background mode) | Adds latency to every request |
| Rate-based thresholds for low-traffic routes | Bifrost | With 1 req/min per route, a 2% error rate is meaningless — count-based is better |
| Single global cooldown for all providers | VibeProxy current | Free-tier and paid-tier providers have different failure modes and recovery times |

---

## Key Metrics to Watch After Implementation

| Metric | Current | Target |
|---|---|---|
| Canary tokens/hour | ~576 (32 tokens × 6 probes × 3 routes) | ~36 (1 token × 6 probes × 6 routes) |
| Time for recovered route to regain full traffic | ~15 successful requests (EMA rebuild) | ~3 successful requests (momentum reset) |
| Free-tier model utilization | Uncontrolled (can hit 429s) | Budget-tracked, auto-excluded at limit |
| OAuth provider health visibility | None | Full circuit breaker + canary |
| Model quality awareness | None | Tier-weighted scoring with sticky reasoning models |
