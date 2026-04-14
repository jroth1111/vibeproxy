# VibeProxy Failure Mitigation & Improvement Plan

**Date:** 2026-04-14  
**Status:** Ready for execution  
**Scope:** Smart-router worker reliability, upstream pressure handling, telemetry clarity, Droid correlation, and operator verification

---

## Objective

Make worker routing degrade gracefully under provider pressure, keep live routing observable from `healthz`, and let operators distinguish:

- proxy logic bugs
- upstream provider instability
- Droid/runtime failures outside the proxy

The source of truth for worker routing remains:

- `src/Sources/ThinkingProxy.swift`

---

## Current State Summary

### What was just fixed

- Smart-router terminal delivery could be suppressed after request cancellation, causing recoverable worker requests to look exhausted.
- NVIDIA fallback-race handling could recurse into bad exhaustion behavior and retry exhausted pools too broadly.
- Route telemetry summaries misclassified `gpt-*` traffic as `unknown` instead of `openai`.
- Verification had drifted toward a stray local `ProxyCore` split instead of compiling against the real proxy source path.

### What is healthy now

- Live proxy health endpoint returns `200`.
- Worker route is currently `glm-5.1-ollama-pro` for active worker request shapes.
- Current live PID shows clean post-restart traffic with no fresh proxy-side failures.
- Droid is again executing worker requests successfully.
- The previously failing mission shows old `worker_failed` events, then successful recovery after restart.

### What is still not a local proxy bug

- ZAI `429_concurrency`, `429_window`, retryable `400 network_error`, and occasional `500`.
- Ollama `429_window`, `503`, `empty_content`, and `reasoning_only_content_missing`.
- Direct `glm5-nvidia` first-byte timeout / slow completion behavior.
- Older Droid `worker_failed` events caused by runtime exits rather than route-selection bugs.

---

## Plan Structure

This plan is organized into four execution tracks:

1. Protect the fixed worker routing path
2. Make upstream pressure degrade predictably
3. Improve health, telemetry, and cross-system correlation
4. Operationalize verification and incident response

---

## Track 1: Protect the Fixed Worker Routing Path

### 1.1 Lock in smart-router terminal delivery behavior

**Goal:** Prevent any future regression where a winning fallback or terminal retryable outcome is dropped after cancellation state changes.

**Actions**

- Add regression tests for terminal smart-alias outcomes after intermediate candidate cancellation.
- Add coverage for:
  - terminal success after failover
  - terminal `429_window`
  - terminal generic unavailable
  - terminal `send_error`
  - typed high-tool worker failover chains
- Keep the current request-controller ownership behavior as the required end-state:
  - clear current cancel before terminal delivery
  - cancel only after the terminal result is committed

**Primary code**

- `src/Sources/ThinkingProxy.swift`

**Verification**

- `./scripts/run-verification-specs.sh`
- targeted `ThinkingProxyPolicySpec` coverage for cancellation and terminal delivery paths

### 1.2 Lock in race and exhaustion semantics

**Goal:** Ensure NVIDIA races never collapse into false exhaustion or misclassified loop retries.

**Actions**

- Add regression coverage proving exhausted-pool loop retries happen only when exhaustion is true capacity exhaustion.
- Add regression coverage proving deferred candidates are preserved after a raced NVIDIA pair does not cleanly resolve the request.
- Keep race recursion disabled once a race collapses back into serial candidate handling.

**Primary code**

- `src/Sources/ThinkingProxy.swift`

**Verification**

- policy spec for:
  - raced NVIDIA pair
  - deferred non-NVIDIA serial fallback
  - empty candidate set after real exhaustion only

### 1.3 Add exact replay-spec coverage for the incident request shape

**Goal:** Preserve the exact worker request shape that triggered the failure as a permanent regression check.

**Replay shape**

- assistant content array including:
  - `input_text`
  - `summary_text`
  - `reasoning`
  - `metadata_marker`
- followed by a user turn asking for `Return exactly OK`

**Actions**

- Add a spec or replay harness covering:
  - direct `muse-spark`
  - direct `glm5-nvidia`
  - worker alias `custom:Proxy-Worker-Smart-Router-8`
- Assert:
  - direct `muse-spark` returns `OK`
  - direct `glm5-nvidia` classifies slow-first-byte correctly
  - worker alias returns a delivered result instead of exhaustion

---

## Track 2: Make Upstream Pressure Degrade Predictably

### 2.1 Normalize provider-specific failure policy

**Goal:** Treat common upstream pressure as controlled failover input, not as ambiguous failure noise.

**Actions**

- Split worker failover policy by failure class:
  - `classified_429_window`: cooldown and fall through
  - `classified_429_concurrency`: short bounded retry or fall through without over-penalizing route health
  - `classified_5xx`: immediate failover
  - malformed `200` body (`empty_content`, `reasoning_only_content_missing`): mark suspect and fail over
  - retryable `400 network_error`: retryable provider signal, not a preflight or model mismatch
- Keep direct NVIDIA first-byte timeout classified explicitly as timeout-policy behavior.

**Desired outcome**

- Upstream pressure stays visible in telemetry.
- Worker requests recover onto healthy siblings whenever the pool still has a valid route.
- Operators can tell “provider overloaded” from “proxy broken.”

### 2.2 Bias worker routing toward currently healthy lanes by request shape

**Goal:** Make the worker pool choose the healthiest viable candidate for the exact incoming request shape, especially for typed multi-tool traffic.

**Actions**

- Keep request-shape-specific dispatchability authoritative in `healthz`.
- Strengthen observed-winner and dispatchable-lane preference for:
  - `multi_tool_typed_content`
  - `streaming_multi_tool_typed_content`
- Avoid promoting half-open or probe-only winners over healthy dispatchable siblings.

**Desired outcome**

- Typed multi-tool worker traffic keeps landing on `glm-5.1-ollama-pro` while ZAI remains degraded.
- Healthy live winners outweigh synthetic probe noise.

### 2.3 Add `minimax-m2.7-nvidia` as a worker-pool candidate

**Goal:** Add a second NVIDIA-backed Minimax lane so the worker pool has a stronger fallback option when Ollama or ZAI paths are degraded.

**Design stance**

- NVIDIA inference must be treated as a hostile or unreliable transport surface.
- `minimax-m2.7-nvidia` should not be added as a thin provider alias.
- The route is only acceptable if it ships with explicit proxy-side mitigations that make behavior deterministic, observable, and fail-soft under bad upstream behavior.
- The objective is not to assume NVIDIA becomes good; the objective is to make the proxy resilient enough that NVIDIA unreliability does not break worker correctness.

**Current discovery from manual validation on 2026-04-14**

- `minimax-m2.7-nvidia` is not implemented in the current routing source of truth.
- `src/Sources/ThinkingProxy.swift` currently exposes `minimax-m2.7-ollama-pro` but no `minimax-m2.7-nvidia`.
- `healthz` currently reports `minimax-m2.7-ollama-pro` as a live route and reports `minimax-m2.7-nvidia` as absent.
- A live direct replay to `minimax-m2.7-nvidia` returned `502` with `unknown provider for model minimax-m2.7-nvidia`.
- A control replay to `custom:Proxy-Worker-Smart-Router-8` still succeeded and resolved onto `glm-5.1-ollama-pro`, so the missing NVIDIA Minimax route is not currently harming worker availability.
- The existing Minimax lane that is validated today is `minimax-m2.7-ollama-pro`, which is already winning fresh typed worker traffic in live logs.

**Actions**

- Add `minimax-m2.7-nvidia` to the configured provider/model catalog.
- Add `minimaxai/minimax-m2.7` as the canonical NVIDIA route identity for that model.
- Decide the exact worker-pool placement by request shape:
  - include it for string-content and tool-bearing worker traffic where NVIDIA routes are already eligible
  - include it for typed-content worker traffic only after full manual live validation proves request normalization and provider behavior are compatible
- Extend smart-router ranking and fallback policy so `minimax-m2.7-nvidia` is treated as a first-class sibling to `glm5-nvidia` and `kimi-k2.5-nvidia`, not as an ad hoc terminal fallback.
- Add direct replay coverage and worker-alias coverage for `minimax-m2.7-nvidia`.
- Require a manual live validation pass before changing default routing authority for any worker request-shape bucket.
- Add route-health, timeout, and telemetry coverage so the new route appears correctly in:
  - `healthz`
  - route telemetry summaries
  - last-2-hour provider/model distribution reports

**Required NVIDIA mitigation package**

- Eligibility and normalization:
  - hard-gate unsupported request shapes
  - keep request-shape-specific enablement for plain, tool-bearing, typed, and streaming traffic
  - normalize mixed-content and tool-bearing payloads into the narrow NVIDIA-safe shape before dispatch
- Output correctness enforcement:
  - validate every `200` response against the request contract
  - treat malformed success bodies, missing visible content, broken tool calls, and invalid arguments as route failures, not successes
  - apply repair prompts or schema-aware retries only when the proxy can do so deterministically
- Transport and timeout hardening:
  - use the proven NVIDIA transport path with explicit first-byte, buffered-response, and inter-chunk budgets
  - distinguish slow-first-byte, chunk-gap, and buffered-response failures explicitly
  - keep downstream keepalives and partial-stream stall detection enabled
- Health and isolation:
  - isolate `minimax-m2.7-nvidia` on its own route-health key and metrics lane
  - keep its timeouts, malformed outputs, and `429` pressure from poisoning sibling NVIDIA or Ollama routes
  - use conservative concurrency, bounded retries, rapid quarantine, and sibling failover when the route degrades
- Rollout and observability:
  - expose the route distinctly in `healthz` and route telemetry
  - require probe and low-volume live evidence before promotion
  - ship it in a non-default position first and only promote it if it reduces, rather than increases, worker terminal failures
- Common hardening allowed:
  - sticky cooldowns
  - jittered retry delays
  - hedged probes
  - stricter preflight rejection
  - response-shape feature flags
  - canary-only rollout gates
  - automatic demotion on repeated bad-output or timeout sequences

**Promotion rules**

- `minimax-m2.7-nvidia` may be implemented before it is trusted.
- `minimax-m2.7-nvidia` may be trusted for plain-chat or tool-string traffic before it is trusted for typed-content traffic.
- `minimax-m2.7-nvidia` must not become a preferred typed worker lane until it proves:
  - stable direct buffered behavior
  - stable direct streaming behavior
  - valid tool-call behavior
  - valid mixed-content behavior
  - acceptable timeout profile under live load
  - clean failover behavior when NVIDIA misbehaves

**Verification**

- manual direct replay against `minimax-m2.7-nvidia`
- manual worker alias replay proving the route can be selected and delivered
- manual mixed-content replay using the incident transcript shape
- manual timeout/failover replay proving slow or malformed upstream behavior is classified correctly
- `healthz` check showing the route in the appropriate candidate pools
- telemetry summary showing `nvidia / minimax-m2.7-nvidia` as a distinct provider/model lane

**Manual validation gate**

- Manual validation is blocked until the route exists in source and appears in `healthz`.
- Do not claim `minimax-m2.7-nvidia` ready for worker typed-content routing until it has passed:
  - direct buffered replay
  - direct streaming replay
  - worker alias replay
  - mixed-content typed replay
  - tool-bearing replay
  - timeout / slow-first-byte replay
  - fresh-log correlation in proxy, Droid, and mission surfaces
  - malformed-success-body replay proving the route is rejected and failed over correctly
  - concurrency-pressure replay proving route-health isolation and bounded retry behavior

### 2.4 Add a formal provider-pressure mode

**Goal:** Keep the worker marked ready when the pool is still usable, while making degraded provider conditions obvious.

**Actions**

- Add an explicit worker-pressure summary derived from route health by request shape.
- Surface whether degradation is:
  - quota-window pressure
  - concurrency pressure
  - upstream malformed-output pressure
  - direct-timeout pressure

**Desired outcome**

- `ready:true` does not hide that the pool is operating on a reduced set of healthy routes.

---

## Track 3: Improve Health, Telemetry, and Cross-System Correlation

### 3.1 Expand terminal outcome telemetry

**Goal:** Make every terminal worker result reconstructable without manual log archaeology.

**Actions**

- Include these fields in terminal route telemetry:
  - first selected candidate
  - failover chain
  - final winning candidate
  - terminal failure class
  - whether result was delivered, retried, or exhausted
- Add a terminal outcome marker for:
  - `success`
  - `retryable_quota`
  - `retryable_concurrency`
  - `provider_5xx`
  - `proxy_unavailable`
  - `runtime_exit`

### 3.2 Improve `healthz` operator signal

**Goal:** Let one `curl` explain worker readiness, route health, and current effective route by request shape.

**Actions**

- Keep and strengthen:
  - `factory_worker.ready`
  - `effective_route_model`
  - `effective_route_model_source`
  - per-shape `dispatchable_candidate_models`
- Add:
  - worker-pressure summary
  - last terminal worker outcome summary
  - last live worker winner and last dispatched winner side by side for every important request-shape bucket

### 3.3 Correlate proxy, Droid, and mission failures

**Goal:** Make `worker_failed` triage mechanical instead of forensic.

**Actions**

- Introduce a shared correlation field across:
  - proxy route telemetry
  - Droid worker request logs
  - mission progress logs
- When a mission emits `worker_failed`, attempt automatic classification:
  - proxy terminal failure present
  - proxy healthy / Droid runtime exit
  - upstream provider pressure with later recovery

**Desired outcome**

- A fresh `worker_failed` can be attributed in one pass as either proxy, upstream, or runtime.

### 3.4 Keep telemetry reporting source-truth aligned

**Goal:** Prevent analysis tools from drifting away from what the proxy actually does.

**Actions**

- Keep route summary logic consistent with `ThinkingProxy.swift` provider identities.
- Add checks that summary output classifies at least:
  - `gpt-*` as `openai`
  - `*-ollama-pro` as `ollama-pro`
  - `*-nvidia` as `nvidia`
  - `muse-spark` as `meta-web`
  - `*-zai` and `glm-5.1` canonical ZAI routes as `zai`

---

## Track 4: Operationalize Verification and Incident Response

### 4.1 Codify the restart verification runbook

**Goal:** Make rebuild-and-restart verification consistent and cheap.

**Runbook**

1. `CARGO_TARGET_DIR=.verify-target TMPDIR=$PWD/.verify-tmp ./scripts/run-verification-specs.sh`
2. `./create-app-bundle.sh`
3. `launchctl kickstart -k gui/$(id -u)/com.vibeproxy.repo`
4. `./scripts/factory-worker-preflight.sh`
5. `curl -sS -D - http://127.0.0.1:8317/healthz`
6. inspect fresh proxy, Droid, and mission logs
7. summarize current live PID traffic only

**Desired outcome**

- No restart is considered valid until worker preflight, `healthz`, and current-PID telemetry all agree.

### 4.2 Add an incident summary command

**Goal:** Replace ad hoc shell archaeology with one repeatable report.

**Actions**

- Add a script that outputs:
  - current live PID
  - last 2 hours winner distribution
  - attempted-lane distribution
  - non-200 distribution
  - current worker effective route
  - mission `worker_failed` count in the same window

**Desired outcome**

- The operator can answer “what is actually happening right now?” from one command.

### 4.3 Keep verification harnesses tied to real source paths

**Goal:** Prevent test harnesses from silently validating stale local abstractions.

**Actions**

- Keep `scripts/run-verification-specs.sh` compiling from the real `ThinkingProxy.swift` source path.
- Allow only minimal source sanitization needed for test compilation.
- Reject future verifier drift toward local-only source splits or scaffolding.

---

## Proposed Milestones

### Milestone A: Routing Reliability Guardrails

- terminal-delivery regression coverage added
- race/exhaustion regression coverage added
- mixed typed-content replay-spec added

### Milestone B: Upstream Pressure Behavior

- failure-class-specific worker policy reviewed and hardened
- request-shape route preference improved
- provider-pressure summary exposed in `healthz`

### Milestone C: Cross-System Observability

- terminal outcome telemetry expanded
- proxy/Droid/mission correlation field added
- 2-hour incident summary script added

### Milestone D: Runbook and Operator Tooling

- restart verification runbook documented and scriptable
- live-PID-only summary path standardized
- failure attribution playbook documented

---

## Acceptance Criteria

This plan is complete when all of the following are true:

- No current-PID worker traffic can regress into dropped terminal delivery after valid failover.
- `healthz` shows accurate worker readiness and effective route by request shape.
- Direct slow `glm5-nvidia` requests are classified as timeout-policy or upstream slowness, not proxy hang.
- `worker_failed` incidents can be attributed to proxy logic, upstream behavior, or Droid/runtime exits with explicit evidence.
- The last-2-hour routing summary can be generated exactly from one repeatable command.
- Verification scripts compile against the real proxy source-of-truth path.

---

## Verification Checklist

- `CARGO_TARGET_DIR=.verify-target TMPDIR=$PWD/.verify-tmp ./scripts/run-verification-specs.sh`
- `./create-app-bundle.sh`
- `launchctl kickstart -k gui/$(id -u)/com.vibeproxy.repo`
- `./scripts/factory-worker-preflight.sh`
- `curl -sS -D - http://127.0.0.1:8317/healthz`
- proxy log check against current live PID only
- Droid log check for fresh worker execution
- mission log check for fresh `worker_failed` vs `worker_completed`
- 2-hour telemetry summary by provider/model/failure class

---

## Notes

- Routing source of truth remains `src/Sources/ThinkingProxy.swift`.
- Factory `settings.json` and mission runtime model files are runtime inputs, not routing authority.
- Old proxy PIDs must never be reported as current state once a new PID is live.
- Upstream provider pressure must remain visible as upstream pressure, not collapsed into generic proxy blame.
