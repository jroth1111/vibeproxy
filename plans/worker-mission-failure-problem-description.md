# Problem Description: Factory Mission Worker Failures

**Date:** 2026-03-31
**Status:** Partially resolved, ongoing reliability concerns
**Affected systems:** Factory Droid missions, VibeProxy smart router, CLIProxyAPIPlus backend

---

## Summary

Factory mission workers across 4 active projects (songbird4, voc, merchant-warrior2, pi_agent_rust) experienced repeated `worker_failed` events and `Droid process exited unexpectedly (exit code 0)` crashes from March 27-31. The root causes are a chain of interacting failures spanning proxy availability, model routing, circuit breaker logic, and upstream provider health — not a single Droid bug.

---

## Failure Classes

### 1. Proxy Service Downtime (March 28)

**Both VibeProxy (port 8317) and CLIProxyAPIPlus (port 8318) were completely down.**

- `curl` to both ports returned exit code 7 (connection refused)
- All 4 missions failed with "exited unexpectedly (exit code 0)"
- Droid logs show "Connection error." on attempts 1-2 at 02:25:43Z
- Required manual restart of both services

### 2. Duplicate Key Crash Loop (March 29-31)

**The most severe issue. A duplicate key in `modelTierByCanonicalModelID` dictionary literal caused a Swift runtime crash on every smart alias request.**

- Crash: `Swift runtime failure: Dictionary literal contains duplicate keys` at `ThinkingProxy.swift:459`
- Call chain: `processRequest` -> `forwardSmartAliasRequest` -> `attemptSmartAliasCandidate` -> `attemptSmartAliasFallbackRace` -> `rankedSmartAliasFallbackCandidateModels` -> `smartAliasFallbackRankingScore` -> `modelTier(forRequestModel:)` -> lazy init of `modelTierByCanonicalModelID` -> crash
- Impact: 135 restarts on March 30, 49 on March 31 (before rebuild)
- 603 "Socket is not connected" errors (requests killed mid-flight by crash restarts)
- Route health degraded: 4/6 routes stuck in "suspect" status
- Only affected the smart alias path (`proxy-worker-smart-router`); direct model requests worked fine
- This created the illusion of "sometimes working" — direct requests succeeded while worker pool requests crashed

### 3. gpt-5.4(high) Dead Upstream with Silent Rescue

**OpenAI workspace deactivated, but failures were silently rescued to GLM.**

- `gpt-5.4(high)` returns 402 "deactivated_workspace" from OpenAI
- VibeProxy intercepted 500 "auth_not_found" and silently rescued to `glm-5.1-zai` via `shouldFallbackFactoryDirectBindingToWorkerSmartAlias`
- Caller received 200 OK with `"model": "gpt-5.4(high)"` — completely unaware the response came from GLM
- Only hints were in response headers (`X-Factory-Model-Binding: raw_managed_route_rescue`, `X-Resolved-Model: glm-5.1-zai`) that Droid doesn't check
- Made debugging impossible — healthy-looking responses from a completely different model

### 4. gpt-5.4(high) Pinned as Tool-Heavy Primary

**Tool-heavy worker requests were pinned to a dead upstream.**

- Tool-heavy requests (the most common Factory worker pattern) hardcoded `gpt-5.4(high)` as the primary candidate
- Despite 402/500 failures, the smart router kept routing tool-heavy requests there first
- Only after exhausting gpt-5.4(high) retries would it fall through to the healthy pool candidates
- No failover for the pinned model — circuit breaker state was irrelevant

### 5. NVIDIA Race Path Intercepted by Wrong Code Path

**Requests to NVIDIA-hosted models were intercepted by the NVIDIA reasoning check before reaching the direct proxy path.**

- `mimo-v2-pro-opencode` has a non-empty `retryableFailureClasses` policy
- `isNvidiaReasoningChatRequest` returned true and intercepted the request
- Routed through the binary instead of the direct SOCKS5 proxy path
- The direct proxy check at line 4800 was never reached because it was placed *after* the NVIDIA reasoning check
- Fix: moved direct proxy check before NVIDIA reasoning check

### 6. URL Double-v1 Bug

**SOCKS5 proxied requests sent to wrong URL path.**

- Base URL `https://opencode.ai/zen/v1` + path `/v1/chat/completions` produced `https://opencode.ai/zen/v1/v1/chat/completions`
- The `/v1` prefix in the path was not stripped when the base URL already contained `/v1`
- All direct proxied requests to opencode.ai hit 404

### 7. Auth Header and Model Rewrite Missing in Direct Proxy Path

**Direct proxied requests sent empty bearer token and unreplaced model alias.**

- `sendDirectProxiedRequest` injected `Authorization: Bearer ` (empty) when no auth header was present
- The user's opencode config has an actual API key (`sk-gIATyth...`) that the binary normally handles
- Model in request body was not rewritten from alias to canonical (e.g., `mimo-v2-pro-opencode` -> `mimo-v2-pro-free`)
- Opencode received the alias instead of the canonical model name

### 8. Circuit Breaker Dead-end for halfOpen Routes

**Routes in halfOpen state were treated as unavailable, blocking recovery.**

- `isUnavailable` returned `true` for `.halfOpen` routes
- No traffic could reach halfOpen routes to increment recovery successes
- Circuit breaker stuck — could never transition from halfOpen back to closed
- Recovery mechanism was completely non-functional

### 9. Provider Cooldown Ignored in Candidate Selection

**Routes in retry-after cooldown were still selected as failover candidates.**

- `recordRouteFailure` set `providerCooldownsByProviderID` but `nextSmartAliasCandidateTransition` didn't check provider cooldowns
- Only affected ranking (demoted to healthPriority=3), not selection
- If all routes were priority 3 (degraded scenario), provider-cooled routes could be tried before merely suspect routes

### 10. EMA Metrics Reset on Recovery

**Suspect-to-closed transitions discarded all rolling metrics.**

- Recovery from suspect state threw away all accumulated latency and success data
- Route immediately looked like a fresh/unknown route instead of a recovered one
- Next failure would start from scratch rather than from accumulated baseline

### 11. Config Drift Between Factory Settings, Mission Runtime, and Proxy Source

**Three different sources defined conflicting worker models.**

| Source | Worker Model | Provider |
|--------|-------------|----------|
| Factory `settings.json` | `gpt-5.4(high)` | `openai` |
| Mission `runtime-custom-models.json` | `gpt-5.4(high)` | `openai` |
| Proxy source code | `gpt-4.1-mini` (factory-safe alias) | varies |
| Historical BYOK config | `claude-opus-4-6-fast` | `generic-chat-completion-api` |

- `config.ts:61` fallback to `GENERIC_CHAT_COMPLETION_API` for unresolved custom models meant load-order races produced different provider enums
- pi_agent_rust had contamination from older direct provider configurations

### 12. kimi-k2.5-nvidia Timeout Too Aggressive

**45-second `firstResponseDeadline` killed NVIDIA-hosted Kimi K2.5 requests.**

- Kimi K2.5 is a large reasoning model that often takes >45s for first token
- Policy set `firstResponseDeadline: 45` and `attemptTimeout: 90`
- Direct NVIDIA API test showed similar models take 105 seconds for simple queries
- Every request to kimi-k2.5-nvidia timed out and fed failure into the circuit breaker

### 13. Stale Route Health Entries

**Old failure data persisted across restarts, degrading new sessions.**

- `opencode::mimo-v2-pro-free` stuck open from old 429s
- `nvidia::moonshotai/kimi-k2.5` stuck suspect from old timeouts
- No self-heal mechanism to clear stale entries on startup
- New proxy sessions inherited degraded health from historical failures
- Currently: kilocode route is "suspect" with 54% EMA success rate

---

## Concurrency Risks (Ongoing)

### Ephemeral URLSession per Proxied Request
`sendDirectProxiedRequest` creates a new URLSession + SOCKS5 connection for every request and invalidates it after. Under concurrent load (4 agents), dozens of TCP+SOCKS5 tunnels open/close per minute. SOCKS5 proxy may rate-limit or refuse connections.

### Redundant NVIDIA Races
Each concurrent request independently spawns parallel connections to all NVIDIA candidates. If 3 agents hit the smart router simultaneously and all serial candidates fail, 3x2=6 parallel NVIDIA connections are created with no coordination.

### Circuit Breaker Overshoot
Concurrent failures on the same route independently increment the failure score. If 4 requests hit `glm-5.1-zai` simultaneously and it's down, the failure score jumps by 4 instead of 1, keeping the route `open` longer than warranted.

### Concurrency-Blind Failure Attribution
No concurrency tracking per provider. The circuit breaker only sees success/failure with no concept of "this failure happened because we sent too many requests at once." A route can go suspect not because it's unhealthy but because it was oversubscribed. Failover then diverts traffic away, slowing recovery.

### Go Binary Credential Stampede
Under concurrent requests, multiple goroutines independently pick the next credential and retry on failure. If NVIDIA key #3 fails, multiple concurrent requests all retry with key #4 simultaneously instead of distributing across remaining keys.

---

## Fixes Applied

| Commit | Fix |
|--------|-----|
| `65101cd` | Auth header and model rewrite in direct proxied path |
| `037dc3f` | Direct proxy check before NVIDIA reasoning check |
| `1584992` | NVIDIA race, opencode SOCKS5 routing, ZAI migration |
| `ee6f3c0` | Circuit breaker halfOpen dead-end, FailureClass enum, NVIDIA 403/404 recording |
| `fde6cd5` | Cancel registration, route health status, provider cooldown, spec ordering |
| `6666542` | Dead phantom route removal |
| `155b71a` | Unobserved route scoring tier weight |
| `df6b713` | Dead cost preference code removal |
| `317c561` | Unused metrics parameter removal |
| `32bc841` | Worker candidate ordering, health-sensitivity circuit-breaker |
| `fb744a8` | EMA composite score + stickiness |
| `9927cee` | Persist EMA metrics to route-health.json v2 |
| `7b46ef0` | EMA metrics through all circuit state transitions |
| `e1272c8` | NVIDIA candidate racing at all failover depths |
| `0b701f9` | Duplicate-key assertions, URLSession pooling, self-heal tests |

Additional fixes (in uncommitted/working tree):
- Removed `gpt-5.4(high)` as tool-heavy primary (uses health-ranked pool instead)
- Removed silent rescue of `gpt-5.4(high)` failures to worker smart alias (errors now surfaced)
- Updated tests from "verify rescue succeeds" to "verify error is surfaced"

---

### 14. NVIDIA Race Candidates "Context Canceled" on Every Attempt (March 31)

**All 10 error logs from today (March 31, 11:29-11:32) show `kimi-k2.5-nvidia` and `minimax-m2.5-nvidia` requests failing with `context canceled`.**

- Every single error log today is a NVIDIA race candidate timing out with "context canceled"
- Split: 5 kimi-k2.5-nvidia, 5 minimax-m2.5-nvidia — the two NVIDIA race candidates
- This means the serial candidates (glm-5.1-zai, mimo-v2-pro-kilocode, mimo-v2-pro-opencode, minimax-m2.5-opencode) are ALL failing first, then the NVIDIA race also fails
- The serial-first-then-race pipeline means every request traverses the entire candidate list before failing

### 15. Primary Candidate glm-5.1-zai Degraded to "Suspect" (Current)

**The healthz endpoint shows glm-5.1 (the primary serial candidate) at `failure_score: 1, status: suspect`.**

- Also suspect: mimo-v2-pro-free (kilocode) at failure_score:1, minimax-m2.5-free (opencode) at failure_score:1, xiaomi/mimo-v2-pro:free at failure_score:2
- Only minimax-m2.5-nvidia and kimi-k2.5-nvidia are "closed" (healthy)
- The self-heal mechanism is NOT clearing these suspect entries despite no recent failures
- With the primary candidate degraded, the health-ranked pool demotes it, causing erratic routing

### 16. Worker Failures Still Happening After All Fixes (March 30-31)

**Across 5 missions: 188 worker_failed events vs 187 worker_completed events (~50% failure rate).**

Mission breakdown:
| Project | Failed | Completed | Last Failure | Last Completion |
|---------|--------|-----------|--------------|-----------------|
| songbird4 | 58 | 66 | 2026-03-31 00:32 | 2026-03-30 23:40 |
| voc | 59 | 53 | 2026-03-31 00:00 | 2026-03-30 19:54 |
| airbnb-revenue-system | 9 | 14 | 2026-03-31 00:30 | 2026-03-30 23:50 |
| merchant-warrior2 | 50 | 53 | 2026-03-30 23:31 | 2026-03-30 19:28 |
| pi_agent_rust | 12 | 1 | 2026-03-27 01:53 | 2026-03-23 10:46 |

3 of 4 active missions had failures AFTER the crash loop was fixed (after 01:49 March 31), meaning the fixes did not resolve all worker failure modes. The last worker_failed events cluster around 00:00-00:32 on March 31 — just before the proxy was rebuilt and restarted at 11:03.

### 17. Build 640 Crash Reports Still Being Generated (March 31 01:49)

**The last crash report is from 01:49 March 31 — the old build 640 was STILL crashing just hours ago.**

- 4 crash reports on March 31: 00:16, 01:35, 01:36, 01:49
- All from build 640 (the duplicate-key crash build)
- Current running build is 652, started at 11:03AM — so the crash reports are from the old build that was replaced
- But this means the old build was running and crashing for over 12 hours after the duplicate key was identified

---

## Current State

**Running proxy:** Build 652, started 2026-03-31 11:03AM, stable (no crashes)

**Resolved:**
- Duplicate key crash loop fixed (rebuilt from source, build 652)
- Circuit breaker recovery functional (halfOpen no longer dead-end)
- gpt-5.4(high) no longer pinned for tool-heavy requests
- Silent rescue removed — errors surfaced to caller
- NVIDIA candidates raced at all failover depths
- EMA-based ranking with stickiness replacing lexicographic sort
- Self-heal for stale route health entries on startup
- Build 640 replaced with build 652

**Active issues (confirmed from logs right now):**
- glm-5.1-zai (primary candidate) is "suspect" — health-ranked pool will deprioritize it
- 4 of 6 routes are "suspect" — only NVIDIA race candidates are healthy
- All today's error logs are NVIDIA race candidates timing out with "context canceled"
- kimi-k2.5-nvidia timeout still too aggressive (45s `firstResponseDeadline`)
- kilocode route "suspect" (54% EMA success rate from 429 rate limits)
- 188 total worker failures across 5 missions (~50% failure rate)

**Architectural concerns (not yet manifesting as active failures):**
- No concurrency limiting per provider/key
- No concurrency-aware failure attribution
- Ephemeral URLSession per SOCKS5 request (no connection pooling)
- Go binary credential stampede under concurrent load
- Factory model config drift risk remains (three sources of truth)
- 16 test failures in ThinkingProxyPolicySpec (stale assertions from model ordering changes)
