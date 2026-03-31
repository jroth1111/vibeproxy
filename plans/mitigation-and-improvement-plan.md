# VibeProxy Mitigation & Improvement Plan

**Date:** 2026-03-31
**Status:** Ready for execution
**Scope:** Fix active issues, harden concurrency, align config sources, restore test suite

---

## Phase 1: Active Issue Mitigation (Immediate)

### 1.1 Fix Config Drift — Worker Model Not in Candidate Pool

**Problem:** Factory effective route model `gpt-5.4(high)` is NOT in the proxy's worker candidate pool. The healthz endpoint confirms: `config_drift.route_in_pool: false`. Worker requests to `gpt-5.4(high)` bypass smart alias failover entirely.

**Root cause:** `settings.json` defines `workerModel: "custom:Proxy-Worker-Smart-Router-8"` which resolves to route model `proxy-worker-smart-router`. The healthz check compares the *validation* route model (`gpt-5.4(high)`) against the worker candidate pool (which contains `glm-5.1-zai`, `mimo-v2-pro-opencode`, etc.). The validation model is a different concern than the worker routing — but the drift warning still indicates misconfiguration.

**Fix:**
- Verify that `custom:GPT-5.4-High-Proxy-2` (which maps to `gpt-5.4(high)`) is intentionally a *validation* model, not a *worker* model. If so, the drift warning is a false positive for the validation role but a real problem if Factory sends worker requests to it.
- Run `sync-factory-worker-contract.sh --check` to see exact drift
- Ensure all mission `runtime-custom-models.json` files have the canonical `customModels` array
- Update the 4 project `settings.json` files (songbird4, voc, merchant-warrior2, pi_agent_rust) to match global config

**Files:**
- `~/.factory/settings.json`
- `~/.factory/missions/*/runtime-custom-models.json` (6 files)
- `~/CascadeProjects/{songbird4,voc,merchant-warrior2,pi_agent_rust}/.factory/settings.json` (4 files)

**Command:** `./scripts/sync-factory-worker-contract.sh`

### 1.2 Fix Worker Ready State

**Problem:** `factory_worker.ready: false` — even though the worker model ID resolves correctly, the proxy considers it not ready.

**Investigation:** The `ready` flag is likely computed from route health + validation. With `glm-5.1` stuck in `suspect` status and the primary candidate degraded, the worker pool may not declare ready.

**Fix:**
- Run `factory-worker-preflight.sh` to get detailed failure reason
- If the issue is route health, the self-heal in `healStaleSuspectRoutesLocked()` should clear suspect routes older than 5 minutes. Verify the self-heal is running on the current build.
- If stale entries persist despite self-heal, manually clear `route-health.json` (`~/.cli-proxy-api/route-health.json`) and restart proxy

### 1.3 Fix Suspect Route Self-Heal

**Problem:** `glm-5.1` and other routes remain in `suspect` status despite `failure_score: 0`. The self-heal mechanism (`healStaleSuspectRoutesLocked()`) uses a 300s (5 min) stale threshold from `lastRouteHealthActivityDate`. If activity is recent, routes won't heal.

**Investigation path:**
- Check if `lastRouteHealthActivityDate` is being updated on every request (even successful ones) or only on failures
- If success also updates the timestamp, a healthy route receiving traffic will never become "stale" and won't self-heal from suspect→closed

**Fix (if needed):** Update `recordRouteSuccess` to NOT update `lastRouteHealthActivityDate` (only failures should refresh the stale clock), OR change the self-heal to compare against `lastFailureDate` instead of `lastRouteHealthActivityDate`.

**File:** `src/Sources/ThinkingProxy.swift` lines ~2130-2161 (success recording), ~3262-3301 (self-heal)

### 1.4 Fix CLIProxyAPIPlus Health Endpoint

**Problem:** Port 8318 returns 404 on `/healthz`. The monitor script considers this "unexpected" but still marks it healthy.

**Investigation:** The Go binary `cli-proxy-api-plus` may not expose `/healthz`. Check if this is expected behavior (the backend may use a different health path, or health is proxied through VibeProxy on 8317).

**Fix:** Update `monitor-proxy-health.sh` to use the correct health path, or accept 404 as healthy for CLIProxyAPIPlus since VibeProxy's healthz already reports backend reachability (`backend.reachable: true`).

---

## Phase 2: Test Suite Restoration

### 2.1 Fix 16 Stale Test Assertions

**Problem:** 16 test failures in `ThinkingProxyPolicySpec.swift` due to model ordering changes from recent commits.

**Approach:**
1. Run `make test` to get the exact list of 16 failing tests
2. For each failure, compare the test's expected values against current `ThinkingProxy.swift` behavior
3. Update assertions to match current model ordering, candidate lists, and circuit breaker behavior

**Key areas likely affected:**
- Worker candidate ordering (EMA-based ranking replaced lexicographic sort)
- Health-sensitivity thresholds (eager=0.5x, balanced=1x, conservative=2x)
- Circuit breaker halfOpen now returns `isUnavailable: false`
- Provider cooldown skip logic
- Model tier weights for ranking

**File:** `src/Verification/ThinkingProxyPolicySpec.swift`

**Command:** `make test` (or `./scripts/run-verification-specs.sh`)

---

## Phase 3: Concurrency Hardening

### 3.1 Pool Ephemeral URLSession Instances

**Problem:** `sendBufferedProxyRequest` (line 7576) and `forwardNvidiaReasoningRequestWithRetry` (line 8296) create new `URLSession(configuration: .ephemeral)` per request. Under concurrent load (4 agents), dozens of TCP connections open/close per minute.

**Fix:** Extend the existing session pool (`proxiedSessionPool` at line 4712) to also cover buffered proxy and NVIDIA reasoning paths. Create a generic `acquireSession(key:configuration:)` method that both paths can use.

**File:** `src/Sources/ThinkingProxy.swift` lines ~4711-4819, 7576, 8296

### 3.2 Add Concurrency-Aware Failure Attribution

**Problem:** Circuit breaker sees success/failure but has no concept of "this failure happened because we sent too many requests at once." A route can go suspect from oversubscription rather than actual unhealthiness.

**Fix:**
- Track concurrent inflight requests per route (partially done via `RouteConcurrencyPermit`)
- On failure, if `inflight >= concurrency_limit`, reduce failure penalty (e.g., penalty = 0 for concurrent-overflow failures)
- Only apply full failure penalty when inflight is within normal limits

**File:** `src/Sources/ThinkingProxy.swift` lines ~2081-2127 (`recordRouteFailure`), ~3018-3036 (`failurePenalty`)

### 3.3 Fix Circuit Breaker Overshoot

**Problem:** Concurrent failures on the same route independently increment the failure score. If 4 requests hit the same failing route simultaneously, the score jumps by 4 instead of 1.

**Fix:** The existing `routeHealthQueue.sync` serialization should prevent this. Verify that `recordRouteFailure` is called within `routeHealthQueue.sync {}` for all call sites. If there are callers outside the sync block, fix them.

**File:** `src/Sources/ThinkingProxy.swift` line ~2092 (already inside `routeHealthQueue.sync`)

### 3.4 Credential Distribution Under Concurrency

**Problem:** Multiple goroutines in the Go binary independently pick the next credential and retry on failure. If key #3 fails, multiple concurrent requests all retry with key #4 simultaneously.

**Fix:** This is in the Go binary (`cli-proxy-api-plus`), not the Swift proxy. Investigate whether the Go binary has a credential rotation mutex. If not, add atomic round-robin or per-request credential assignment.

**Scope:** Out of scope for Swift proxy changes — requires Go binary modification.

---

## Phase 4: Resilience Improvements

### 4.1 Kimi K2.5 Timeout Validation

**Problem (originally):** 45-second `firstResponseDeadline` killed NVIDIA-hosted Kimi K2.5 requests.

**Current state:** Timeout has been increased to 120s (`firstResponseDeadline: 120`) in the current code. Verify this is sufficient by running a test request.

**Action:** Run `run-nvidia-live-matrix.sh` to validate current timeouts against live NVIDIA endpoints.

### 4.2 Route Health Startup Hardening

**Problem (originally):** Stale route health entries persisted across restarts, degrading new sessions.

**Current state:** Self-heal mechanism (`healStaleSuspectRoutesLocked`) is implemented with 300s stale threshold. Provider cooldowns are capped at 3600s on restore.

**Improvement:** Add a startup log line that reports all loaded route health entries and their staleness, making debugging easier.

**File:** `src/Sources/ThinkingProxy.swift` line ~3187 (`loadPersistedRouteHealthIfNeededLocked`)

### 4.3 Config Drift Monitoring

**Problem:** Three config sources (factory settings, mission runtime, proxy code) can diverge silently.

**Improvement:** Add a periodic healthz field that reports config drift severity with a human-readable diff, not just a count.

**File:** `src/Sources/ThinkingProxy.swift` healthz endpoint (~line 9281)

### 4.4 Worker Failure Rate Dashboard

**Problem:** No visibility into per-mission worker failure rates without parsing raw logs.

**Improvement:** Add worker failure/completion counters to the healthz endpoint, broken down by mission ID.

---

## Phase 5: Cleanup

### 5.1 Remove Dead Code

The problem doc mentions:
- Dead cost preference code (commit df6b713)
- Unused metrics parameter (commit 317c561)
- Dead phantom route removal (commit 6666542)

Verify these are already committed and no dead code remains.

### 5.2 Fix daemon.log Pull Failures

The beads daemon log shows repeated `git pull failed: fatal: couldn't find remote ref temporary-vibeproxy-nvidia-fix`. This branch reference is stale. Fix by updating the beads config or removing the stale remote tracking branch.

**Command:** `git branch -dr origin/temporary-vibeproxy-nvidia-fix` or update `.beads/config.yaml`

---

## Execution Order

| Priority | Phase | Effort | Risk |
|----------|-------|--------|------|
| P0 | 1.1 Config drift sync | Low | Low |
| P0 | 1.2 Worker ready state | Low | Low |
| P0 | 1.3 Suspect route self-heal | Medium | Low |
| P0 | 2.1 Fix test failures | High | Low |
| P1 | 1.4 CLIProxyAPIPlus health | Low | Low |
| P1 | 3.1 Pool ephemeral sessions | Medium | Medium |
| P1 | 3.2 Concurrency-aware failure | Medium | Medium |
| P2 | 3.3 Circuit breaker overshoot | Low | Low |
| P2 | 3.4 Credential distribution | High | High |
| P2 | 4.1 Kimi timeout validation | Low | Low |
| P2 | 4.2 Startup logging | Low | Low |
| P2 | 4.3 Config drift monitoring | Medium | Low |
| P2 | 4.4 Worker failure dashboard | Medium | Low |
| P3 | 5.1 Dead code cleanup | Low | Low |
| P3 | 5.2 Beads daemon fix | Low | Low |

---

## Verification

After each phase:
1. Run `./scripts/monitor-proxy-health.sh` — all proxies healthy
2. Run `./scripts/factory-worker-preflight.sh` — all validations pass
3. Run `make test` — all tests pass
4. Run `./scripts/sync-factory-worker-contract.sh --check` — zero drift
5. Run `curl -s http://127.0.0.1:8317/healthz | jq` — check route_health, config_drift, factory_worker.ready
