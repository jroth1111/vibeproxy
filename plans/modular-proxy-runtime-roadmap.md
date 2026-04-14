# Modular Proxy Runtime Roadmap

## Status

- Draft
- Intended use: comprehensive architecture plan, implementation contract, and direct input for `bd` task creation

## Objective

Refactor VibeProxy from a monolithic proxy runtime centered on `ThinkingProxy.swift` into a modular, typed runtime with explicit routing, health, execution-planning, telemetry, and Factory-contract services.

The target is not "clean up the big file." The target is to replace the current all-in-one runtime authority with a stronger end-state architecture that:

- preserves the current project's best capabilities
- makes routing decisions explicit and testable
- centralizes runtime authority in typed services
- removes handwritten config scanning and inline route resolution logic
- keeps code-owned routing as the single source of truth

## Why This Plan Exists

Comparison against the headless superseding refactor showed a clear architectural advantage in a few areas:

1. explicit execution planning before execution
2. explicit request-shape analysis
3. a route catalog as a first-class runtime service
4. modular health, credentials, telemetry, and provider boundaries
5. a small runtime nucleus that composes services instead of owning every decision inline

The current project is already stronger than the reference in several important areas and this plan treats those as mandatory non-regression requirements:

- adaptive learned concurrency limits
- NVIDIA streaming transport and multi-stage deadlines
- tight circuit-breaker integration with execution flow
- hedge and race execution behavior
- Factory worker contract, rescue, and drift diagnostics
- rich `/healthz` and `/internal/routes` outputs

This plan adopts the reference's cleaner architecture without discarding the current project's stronger behavior.

## Hard Requirements

1. Routing authority remains code-owned.
   Until cutover, `src/Sources/ThinkingProxy.swift` remains the authoritative routing source. After cutover, that authority moves to a new typed manifest/module in Swift. It must not move into `settings.json`, mission files, or free-form user config.

2. Replacement semantics are strict.
   New modular services do not count as done while the old monolithic path still materially defines runtime behavior. The old authority must be switched off and then deleted.

3. No behavior regression in the strong parts of the current system.
   The refactor is allowed to change internals aggressively. It is not allowed to weaken concurrency learning, streaming robustness, hedge/race behavior, Factory contract logic, or diagnostic richness.

4. Handwritten merged-config scanning must be deleted.
   The inline YAML scanner in `ThinkingProxy.swift` is transitional debt and must not survive the refactor.

5. `/v1/models` must be synthesized locally.
   Backend passthrough is not an acceptable end-state authority for model listing.

6. Request shape and execution plan become explicit runtime objects.
   Compatibility filtering, race grouping, serial ordering, and failover behavior must be planned before execution starts.

7. Policy definitions become typed registries.
   Timeouts, retryable failure classes, streaming constraints, responses support, and provider-specific preflight rules must move out of scattered arrays and helper functions.

8. Telemetry retention must be bounded.
   The runtime must have explicit per-route and global retention caps.

9. Transport complexity must be hidden behind a typed facade.
   The plan does not require collapsing every pool into one implementation, but runtime code must stop depending directly on multiple special-case pools.

## Non-Goals

1. Rewriting the app into Python.
2. Replacing the macOS app shell or menu bar UX.
3. Moving routing ownership into backend config files.
4. Reducing diagnostic richness for the sake of cleaner abstractions.
5. Simplifying transport internals if that weakens streaming or hedge behavior.

## End-State Architecture

The end-state runtime should be organized around these modules:

- `ProxyRuntime`
  Owns startup, shutdown, request routing entrypoints, `/v1/models`, `/healthz`, `/internal/routes`, backend supervision, canaries, and provider adapter composition.

- `ManagedRouteManifest`
  Code-owned declaration of managed providers, canonical models, public aliases, debug aliases, worker pools, and business ordering.

- `GatewayConfig`, `ConfigLoader`, `ConfigMerger`, `ConfigValidator`
  Typed config load/merge/validation with additive user overlays and no handwritten text scanning.

- `RouteCatalog`
  Sole authority for route lookup, alias lookup, canonical-model resolution, backend passthrough route creation, and route diagnostics.

- `RequestShape`, `CompatibilityEvaluator`
  Typed request-surface and payload-shape analysis used before execution begins.

- `ExecutionPlan`, `ExecutionStage`, `AliasExecutionPlanner`
  Explicit planning object that decides serial vs race vs hedge-capable execution stages before execution starts.

- `CredentialPool`
  Single interface for provider readiness, key rotation, disabled state, cooldown windows, and credential diagnostics.

- `RouteHealthStore`, `RouteConcurrencyLimiter`, `AliasObservationStore`, `CanaryCoordinator`
  Health authority with state persistence, learned concurrency, provider cooldowns, route scoring, recent winner/dispatch tracking, retry hints, and canary selection.

- `ModelPolicyRegistry`, `ProviderPolicyRegistry`
  Typed policies for retries, timeouts, streaming constraints, request-surface compatibility, and provider-specific mitigation rules.

- `RouteTelemetryStore`, `DiagnosticsBuilder`
  Bounded telemetry retention and diagnostic payload construction.

- Provider adapters
  `NVIDIAHostedProxy`, `OpenAICompatProxy`, `BackendProxy`, `MetaAIAdapter`

- `FactoryModelBindings`, `FactoryContractResolver`, `FactoryHealthSnapshot`
  Isolated Factory-specific runtime logic and drift reporting.

- `TransportFacade`
  Typed transport owner hiding internal pool details.

- thin listener shell
  `ThinkingProxy` can survive only as the HTTP/NW listener shell if needed; it must stop being the place where runtime authority lives.

## Proposed File/Module Layout

This is the preferred shape after cutover.

- `src/Sources/ProxyCore/Domain/`
- `src/Sources/ProxyCore/Config/`
- `src/Sources/ProxyCore/Routing/`
- `src/Sources/ProxyCore/Health/`
- `src/Sources/ProxyCore/Credentials/`
- `src/Sources/ProxyCore/Telemetry/`
- `src/Sources/ProxyCore/Policies/`
- `src/Sources/ProxyCore/Providers/`
- `src/Sources/ProxyCore/Factory/`
- `src/Sources/ProxyCore/Runtime/`
- `src/Sources/ProxyServer/`

Suggested core files:

- `ProxyCore/Domain/Route.swift`
- `ProxyCore/Domain/AliasDefinition.swift`
- `ProxyCore/Domain/RequestShape.swift`
- `ProxyCore/Domain/ProxyResult.swift`
- `ProxyCore/Domain/AttemptFailure.swift`
- `ProxyCore/Domain/RouteHealthState.swift`
- `ProxyCore/Domain/RouteTelemetryEvent.swift`
- `ProxyCore/Config/ManagedRouteManifest.swift`
- `ProxyCore/Config/GatewayConfig.swift`
- `ProxyCore/Config/ConfigLoader.swift`
- `ProxyCore/Config/ConfigMerger.swift`
- `ProxyCore/Config/ConfigValidator.swift`
- `ProxyCore/Routing/RouteCatalog.swift`
- `ProxyCore/Routing/CompatibilityEvaluator.swift`
- `ProxyCore/Routing/AliasExecutionPlanner.swift`
- `ProxyCore/Routing/ExecutionPlan.swift`
- `ProxyCore/Routing/ModelsIndex.swift`
- `ProxyCore/Health/RouteHealthStore.swift`
- `ProxyCore/Health/RouteConcurrencyLimiter.swift`
- `ProxyCore/Health/AliasObservationStore.swift`
- `ProxyCore/Health/CanaryCoordinator.swift`
- `ProxyCore/Credentials/CredentialPool.swift`
- `ProxyCore/Policies/ModelPolicyRegistry.swift`
- `ProxyCore/Policies/ProviderPolicyRegistry.swift`
- `ProxyCore/Telemetry/RouteTelemetryStore.swift`
- `ProxyCore/Telemetry/DiagnosticsBuilder.swift`
- `ProxyCore/Providers/TransportFacade.swift`
- `ProxyCore/Providers/NVIDIAHostedProxy.swift`
- `ProxyCore/Providers/OpenAICompatProxy.swift`
- `ProxyCore/Providers/BackendProxy.swift`
- `ProxyCore/Providers/MetaAIAdapter.swift`
- `ProxyCore/Runtime/ProxyRuntime.swift`
- `ProxyCore/Runtime/BackendSupervisor.swift`
- `ProxyCore/Factory/FactoryModelBindings.swift`
- `ProxyCore/Factory/FactoryContractResolver.swift`
- `ProxyCore/Factory/FactoryHealthSnapshot.swift`
- `ProxyServer/ProxyServer.swift`

## Roadmap

### 1. Freeze Current Behavior With a Regression Harness [C][V]

#### Goal

Lock down current runtime behavior before moving authority out of `ThinkingProxy.swift`.

#### Scope

1. Add focused verification coverage for:
   - route resolution
   - alias expansion
   - worker-pool ordering
   - request-shape routing behavior
   - compatibility rejection behavior
   - race and hedge decisions
   - learned concurrency limit behavior
   - provider cooldown behavior
   - route-health persistence and migration
   - `/v1/models`
   - `/healthz`
   - `/internal/routes`
   - Factory worker contract snapshots and drift reporting
   - NVIDIA direct route preflight, streaming, and timeout semantics

2. Add snapshot-style tests for diagnostic payload structure where appropriate.

3. Record current intended differences vs accidental behavior so the refactor has an explicit compatibility bar.

#### Deliverables

- new verification specs covering the runtime seams that will move
- documented list of behavior intentionally preserved
- documented list of behavior intentionally changed

#### Dependencies

- none

#### Required deletions/supersession

- none yet

#### Verification

- `./scripts/run-verification-specs.sh`
- targeted spec invocations for each newly extracted service
- manual `curl` checks against local `/v1/models`, `/healthz`, and `/internal/routes`

#### Completion bar

This item is complete only when the current system's routing and diagnostic behavior is preserved well enough that later extractions can be compared against it.

### 2. Introduce a Typed Domain Layer [C][V]

#### Goal

Move runtime concepts out of inline dictionaries, local structs, and ad hoc static helpers into shared domain types.

#### Scope

1. Extract typed domain models for:
   - `Route`
   - `AliasDefinition`
   - `RequestShape`
   - `RequestSurface`
   - `ExecutionPlan`
   - `ExecutionStage`
   - `ExecutionStageMode`
   - `ProxyResult`
   - `AttemptFailure`
   - `RouteHealthState`
   - `RouteTelemetryEvent`

2. Centralize enums and semantic classifications that are currently repeated or implicit.

3. Preserve current naming and semantics where behavior matters, but normalize type boundaries.

#### Deliverables

- shared domain files under `ProxyCore/Domain/`
- existing logic updated to depend on domain types instead of private monolith-local types

#### Dependencies

- item 1

#### Required deletions/supersession

- private monolith-local equivalents that no longer carry independent behavior

#### Verification

- compile/build verification
- domain-type focused specs

#### Completion bar

All future service extraction work must depend on these shared types rather than inventing new local equivalents.

### 3. Replace Inline Config Authority With Typed Managed Config [C][V]

#### Goal

Move config, managed providers, and managed aliases into typed Swift structures with code-owned runtime authority.

#### Scope

1. Create `ManagedRouteManifest.swift` to declare:
   - managed provider definitions
   - canonical models
   - public aliases
   - debug aliases
   - worker pool candidates
   - race groups
   - business ordering

2. Create typed config models for:
   - listen/backend/auth
   - timeouts/retries
   - health
   - routing
   - provider definitions
   - smart aliases
   - policy flags

3. Build `ConfigLoader`, `ConfigMerger`, and `ConfigValidator`.

4. Preserve additive user config semantics where safe:
   - credentials
   - provider enablement
   - safe overlay metadata
   - request timeout/retry knobs

5. Keep routing authority code-owned.
   User config may overlay allowed fields, but may not redefine the authoritative managed worker pool contract silently.

#### Deliverables

- `ManagedRouteManifest`
- typed config structs
- load/merge/validate pipeline

#### Dependencies

- item 2

#### Required deletions/supersession

- eventually replaces the inline route/config authority encoded directly in `ThinkingProxy.swift`

#### Verification

- config composition specs
- validation specs for malformed overlays and reserved provider ids

#### Completion bar

Managed routing rules are declared in one typed Swift location and loaded exactly once through typed config services.

### 4. Build `RouteCatalog` as the Sole Route Authority [C][V]

#### Goal

Centralize route and alias resolution in one service and remove runtime dependence on handwritten merged-config scanning.

#### Scope

1. Implement `RouteCatalog` with support for:
   - direct route resolution
   - smart alias resolution
   - canonical-model lookup
   - route deduplication by route key
   - provider endpoint lookup
   - backend passthrough route synthesis
   - public/debug NVIDIA alias mapping

2. Build catalog diagnostics suitable for `/internal/routes`.

3. Ensure all route resolution goes through the catalog.

4. Support the current alias and provider quirks that are materially part of runtime behavior.

#### Deliverables

- `RouteCatalog.swift`
- migration of runtime lookups onto the catalog

#### Dependencies

- items 2 and 3

#### Required deletions/supersession

- delete the handwritten YAML route/config scanner currently embedded in `ThinkingProxy.swift`
- delete cached runtime route maps that exist only because the monolith reparses merged config text

#### Verification

- route resolution specs
- diagnostics snapshot specs
- manual sanity checks for direct aliases, smart aliases, debug aliases, and Factory-bound aliases

#### Completion bar

No runtime route resolution path materially bypasses `RouteCatalog`.

### 5. Introduce Typed Policy Registries [C][V]

#### Goal

Make model-specific and provider-specific runtime behavior explicit, typed, and testable.

#### Scope

1. Build `ModelPolicyRegistry` for:
   - attempt timeouts
   - first-byte/buffered deadlines
   - retryable failure classes
   - streaming policy
   - tool-choice constraints
   - responses support

2. Build `ProviderPolicyRegistry` for:
   - provider-specific preflight rules
   - provider retry behavior
   - provider-specific mitigation toggles
   - provider compatibility rules

3. Migrate hardcoded mitigation arrays and scattered helper logic into those registries.

4. Keep runtime semantics identical unless a deliberate improvement is approved and documented.

#### Deliverables

- typed policy registry modules
- call sites updated to use typed policy lookup

#### Dependencies

- items 2 and 3

#### Required deletions/supersession

- scattered hardcoded policy arrays and duplicated helper logic where registry ownership replaces them

#### Verification

- policy lookup specs
- compatibility/preflight specs

#### Completion bar

Timeouts, retries, streaming rules, responses support, and provider-specific constraints are no longer scattered across the monolith.

### 6. Unify Credential Ownership Behind `CredentialPool` [C][V]

#### Goal

Move provider credential readiness, selection, and diagnostics into one runtime service.

#### Scope

1. Build `CredentialPool` that merges:
   - inline config keys
   - env-backed keys
   - auth-dir credential files
   - disabled state
   - cooldown state
   - rotation/selection

2. Integrate current custom provider credential behavior and existing auth stores without losing user-facing functionality.

3. Provide typed diagnostics for provider readiness and retry hints.

#### Deliverables

- `CredentialPool.swift`
- runtime integration for provider execution paths

#### Dependencies

- items 2 and 3

#### Required deletions/supersession

- duplicate credential-readiness logic spread across unrelated runtime code

#### Verification

- credential load/save/disable/reenable specs
- runtime readiness diagnostics specs

#### Completion bar

Provider execution no longer depends on multiple unrelated credential-readiness mechanisms.

### 7. Extract Health and Concurrency Into a Dedicated Subsystem [C][V]

#### Goal

Keep the current stronger health behavior while removing it from monolithic static runtime state.

#### Scope

1. Build `RouteHealthStore` that preserves:
   - circuit-breaker state
   - failure score
   - recovery state
   - EMA and rolling metrics
   - persistence versioning and migration
   - retry hints
   - stale-entry healing
   - route latency diagnostics
   - momentum/recovery effects

2. Build `RouteConcurrencyLimiter` that preserves:
   - learned concurrency limits
   - slot acquisition/release
   - slot leak cleanup
   - adaptive limit growth
   - concurrency-429 interpretation

3. Add provider-level cooldown authority as a first-class concept.
   The current project already has some provider cooldown behavior. The extracted system must make it explicit, typed, and easy to inspect.

4. Build `AliasObservationStore` for recent dispatch and recent winner tracking.

5. Build `CanaryCoordinator` for route probe selection and scheduling.

#### Deliverables

- extracted health modules under `ProxyCore/Health/`
- no direct monolith-owned mutable health state remains as runtime authority

#### Dependencies

- items 2 through 6

#### Required deletions/supersession

- static health/concurrency ownership in `ThinkingProxy.swift`

#### Verification

- health store specs
- concurrency limit learning specs
- provider cooldown specs
- canary selection specs
- persistence migration specs

#### Completion bar

The extracted health subsystem preserves current stronger semantics, including learned concurrency and NVIDIA-sensitive behavior.

### 8. Make Request Shape and Compatibility Evaluation Explicit [C][V]

#### Goal

Turn scattered request-shape checks into a first-class planning input.

#### Scope

1. Build `RequestShape.fromRequest(...)` to capture:
   - method
   - path
   - surface
   - stream request state
   - strict tool choice
   - typed content
   - unsupported typed content
   - media-bearing payloads

2. Build `CompatibilityEvaluator` that decides whether a route is eligible for a request shape before execution.

3. Port current compatibility behavior into explicit evaluators:
   - NVIDIA `/responses` restrictions
   - typed content restrictions
   - media restrictions
   - streaming/tool-call restrictions
   - ZAI `/responses` constraints
   - Meta adapter constraints
   - any Factory-specific request-surface constraints that materially affect routing

4. Ensure compatibility rejections are surfaced as compatibility results, not as route health failures.

#### Deliverables

- `RequestShape.swift`
- `CompatibilityEvaluator.swift`

#### Dependencies

- items 2, 4, and 5

#### Required deletions/supersession

- scattered path/body compatibility checks that are not owned by request-shape-aware services

#### Verification

- request-shape specs
- compatibility rejection specs
- no-regression checks for current error messages/reason codes where those are relied on

#### Completion bar

Request compatibility is decided before execution starts and is independently testable.

### 9. Add Explicit `ExecutionPlan` and `ExecutionStage` Routing [C][V]

#### Goal

Plan execution before execution starts and make serial/race/hedge behavior explicit.

#### Scope

1. Build `ExecutionPlan`, `ExecutionStage`, and `ExecutionStageMode`.

2. Build `AliasExecutionPlanner` that:
   - deduplicates candidate routes
   - orders candidates with health input
   - applies compatibility filtering
   - groups raceable routes using explicit race groups
   - decides serial vs race execution staging
   - preserves current health-ranked and business-order semantics

3. Preserve current stronger behavior:
   - hedge/race behavior
   - race downgrades when passthrough streaming makes races unsafe
   - alias exhaustion summaries
   - retry-delay hints
   - recent-winner preference where applicable

4. Make routing decisions introspectable for debugging and diagnostics.

#### Deliverables

- `ExecutionPlan` and planner modules
- runtime execution updated to consume the planner output

#### Dependencies

- items 4, 5, 7, and 8

#### Required deletions/supersession

- inline planning logic embedded in execution methods once the planner becomes authoritative

#### Verification

- planner specs
- race-group specs
- exhaustion-classification specs
- runtime routing trace snapshots

#### Completion bar

Alias routing starts with a plan object and no longer relies on on-the-fly execution branching as the primary source of truth.

### 10. Extract Telemetry and Bound Its Retention [C][V]

#### Goal

Keep the current telemetry richness while making ownership explicit and memory usage bounded.

#### Scope

1. Build `RouteTelemetryStore` with:
   - per-route retention caps
   - global retention cap
   - bounded recent event buffers
   - aggregated summaries
   - route-specific summaries

2. Preserve currently important telemetry fields:
   - request and resolved model
   - failure class
   - upstream status
   - timeout stage
   - first-byte and total latency
   - attempt lane and winner lane
   - request-shape source
   - protocol observations
   - caller and proxy request ids

3. Build `DiagnosticsBuilder` to assemble `/healthz` and `/internal/routes` from service snapshots.

#### Deliverables

- bounded telemetry store
- diagnostics builder

#### Dependencies

- items 2, 4, 7, 8, and 9

#### Required deletions/supersession

- ad hoc telemetry state embedded directly in unrelated runtime logic

#### Verification

- telemetry cap specs
- diagnostics payload snapshot specs

#### Completion bar

Telemetry richness remains, but retention is explicitly bounded and service-owned.

### 11. Build a Typed `TransportFacade` and Extract Provider Adapters [C][V]

#### Goal

Hide transport complexity behind a stable interface and isolate provider-specific execution.

#### Scope

1. Build `TransportFacade` to own:
   - proxied transport access
   - backend transport access
   - buffered/streaming transport distinctions
   - lifecycle and cleanup

2. Preserve current multiple transport behaviors if they are functionally necessary.
   This plan does not require collapsing all pools into one implementation.

3. Build provider adapters:
   - `NVIDIAHostedProxy`
   - `OpenAICompatProxy`
   - `BackendProxy`
   - `MetaAIAdapter`

4. Move provider-specific execution and response handling out of `ThinkingProxy`.

#### Deliverables

- `TransportFacade.swift`
- extracted provider adapters

#### Dependencies

- items 2, 5, 6, and 7

#### Required deletions/supersession

- direct dependence on multiple transport pools from generic routing code

#### Verification

- provider adapter specs
- streaming behavior checks
- transport lifecycle checks

#### Completion bar

Generic runtime code depends on a typed transport facade and provider adapters, not on transport pool internals.

### 12. Introduce `ProxyRuntime` as the Runtime Nucleus [C][V]

#### Goal

Replace split ownership across `ThinkingProxy`, `ServerManager`, and `AppDelegate` with one composed runtime authority.

#### Scope

1. Build `ProxyRuntime` that owns:
   - config load
   - catalog
   - policies
   - credentials
   - health
   - planner
   - telemetry
   - model index
   - provider adapters
   - backend supervisor
   - canary coordinator

2. Move `/v1/models`, `/healthz`, `/internal/routes`, and model-addressed POST routing into runtime methods.

3. Preserve backend model caching with explicit ownership.

4. Replace readiness polling with direct runtime lifecycle management where possible.

#### Deliverables

- `ProxyRuntime.swift`
- `BackendSupervisor.swift`

#### Dependencies

- items 3 through 11

#### Required deletions/supersession

- split runtime authority between listener, server manager, and app delegate

#### Verification

- runtime integration specs
- manual startup/shutdown tests
- endpoint parity checks

#### Completion bar

All proxy runtime authority lives in `ProxyRuntime`, not in the macOS shell or listener.

### 13. Extract Factory Contract Logic Into Its Own Subsystem [C][V]

#### Goal

Preserve the current strong Factory contract behavior while removing it from generic routing code.

#### Scope

1. Build `FactoryModelBindings` for:
   - authoritative worker model bindings
   - rescue aliases
   - route-model reverse mapping
   - settings-derived bindings

2. Build `FactoryContractResolver` for:
   - worker role contract resolution
   - request-shape-specific candidate analysis
   - drift detection
   - accepted/rescued model id logic
   - effective route model/provider projection

3. Build `FactoryHealthSnapshot` for diagnostics assembly.

4. Preserve current health and drift outputs currently exposed via `/healthz`.

#### Deliverables

- extracted Factory modules
- runtime integration through an explicit Factory subsystem boundary

#### Dependencies

- items 4, 7, 8, 9, 10, and 12

#### Required deletions/supersession

- Factory-specific authority embedded directly into generic proxy execution logic

#### Verification

- Factory contract specs
- snapshot drift specs
- manual healthz inspection for Factory fields

#### Completion bar

Factory-specific runtime behavior is isolated but not weakened.

### 14. Rebuild Endpoint Handling on the New Runtime [C][V]

#### Goal

Switch live endpoint behavior to the new runtime and supersede old implementations.

#### Scope

1. Move `/v1/models` to the locally synthesized `ModelsIndex`.

2. Move `/healthz` and `/internal/routes` to `DiagnosticsBuilder`.

3. Move model-addressed POST execution to `ProxyRuntime.routeRequest`.

4. Keep raw backend fallback behavior only as an explicit runtime-owned path.

5. Keep non-provider management forwarding separate from core proxy routing.

#### Deliverables

- runtime-owned endpoint handling

#### Dependencies

- items 4 through 13

#### Required deletions/supersession

- backend-owned model-list authority
- endpoint-specific monolith logic once the new runtime path is active

#### Verification

- manual endpoint checks
- regression harness parity

#### Completion bar

The new runtime materially owns all public endpoint behavior.

### 15. Delete Legacy Runtime Authority [C][V]

#### Goal

Finish the replacement by removing the monolithic runtime path once the new services are authoritative.

#### Scope

1. Delete or drastically reduce:
   - handwritten config scanning
   - static global health state
   - inline route catalog logic
   - inline planner logic
   - inline telemetry state
   - inline Factory contract authority

2. Reduce `ThinkingProxy` to:
   - listener
   - request decoding/encoding
   - delegation into `ProxyRuntime`

3. Remove dead helper code, stale caches, and compatibility shims that only existed for the transition.

#### Deliverables

- legacy authority removed
- `ThinkingProxy.swift` small and transport-oriented, or replaced by a new smaller listener file

#### Dependencies

- item 14

#### Required deletions/supersession

- this item is itself the deletion boundary

#### Verification

- missing-path audit to confirm deleted components are no longer runtime-authoritative
- regression harness
- endpoint/manual checks

#### Completion bar

The old monolithic authority is not merely bypassed; it is gone.

### 16. Final Cleanup, Documentation, and Operational Alignment [C][V]

#### Goal

Finish the refactor as a coherent end-state rather than leaving operational drift behind.

#### Scope

1. Update docs and instructions to name the new routing source of truth explicitly.

2. Update scripts and verification entrypoints to target the new modules and runtime.

3. Remove obsolete comments, transition docs, and temporary compatibility notes.

4. Add a concise architecture note documenting:
   - source of truth
   - runtime composition
   - verification entrypoints
   - Factory subsystem boundary

#### Deliverables

- updated docs
- updated verification scripts if needed

#### Dependencies

- item 15

#### Required deletions/supersession

- outdated docs claiming `ThinkingProxy.swift` is the long-term route authority

#### Verification

- docs inspection
- operational script checks

#### Completion bar

The repo documents the actual end-state architecture rather than the pre-refactor one.

## Sequencing and Parallelization

This plan is intended to be executed as bounded fronts, not as a single serial mega-branch.

### Frontier Set A: Foundations

- item 1
- item 2
- item 3

These establish the test harness, shared types, and config authority.

### Frontier Set B: Core Services

- item 4
- item 5
- item 6
- item 7

These can run partly in parallel once items 2 and 3 exist.

### Frontier Set C: Planning and Diagnostics

- item 8
- item 9
- item 10

These depend on the core services.

### Frontier Set D: Runtime and Provider Integration

- item 11
- item 12
- item 13

These integrate the modular services into a working runtime.

### Frontier Set E: Cutover and Deletion

- item 14
- item 15
- item 16

These are the replacement boundary and cleanup stage.

## Suggested `bd` Breakdown

The numbered roadmap above is intentionally bead-friendly. The recommended breakdown is:

1. one parent bead per roadmap item
2. one child bead per major sub-deliverable within that item
3. explicit dependencies following the roadmap order

Suggested parent beads:

1. Freeze runtime behavior with regression harness
2. Introduce typed proxy domain layer
3. Build managed config and route manifest
4. Build `RouteCatalog` and delete handwritten route scanning
5. Introduce typed policy registries
6. Build unified `CredentialPool`
7. Extract route health and concurrency subsystem
8. Build request-shape and compatibility subsystem
9. Build execution planner and stage model
10. Extract telemetry and diagnostics with bounded retention
11. Build transport facade and provider adapters
12. Introduce `ProxyRuntime`
13. Extract Factory contract subsystem
14. Cut endpoints over to modular runtime
15. Delete legacy monolithic runtime authority
16. Finish cleanup and documentation

Suggested dependency chain:

- `1 -> 2 -> 3`
- `3 -> 4`
- `2,3 -> 5`
- `2,3 -> 6`
- `2,3,5,6 -> 7`
- `2,4,5 -> 8`
- `4,5,7,8 -> 9`
- `4,7,8,9 -> 10`
- `5,6,7 -> 11`
- `4,5,6,7,8,9,10,11 -> 12`
- `4,7,8,9,10,12 -> 13`
- `10,12,13 -> 14`
- `14 -> 15`
- `15 -> 16`

Good parallel cuts after item 3:

- route catalog front
- policy/shape front
- credential front
- health/concurrency front

Good parallel cuts after item 9:

- telemetry/diagnostics front
- provider adapter front
- Factory contract front

## Acceptance Criteria

The overall refactor is complete only when all of the following are true.

1. `RequestShape` exists and route compatibility is evaluated before execution begins.
2. alias execution starts with an explicit `ExecutionPlan`
3. `RouteCatalog` is the sole route-resolution authority
4. managed provider and alias authority is code-owned and typed
5. handwritten merged-config scanning is deleted
6. model and provider policy definitions are typed and centralized
7. credential readiness and rotation go through `CredentialPool`
8. health, concurrency, recent alias winners, and canary selection are service-owned
9. telemetry retention has explicit per-route and global caps
10. transport ownership is behind a typed facade
11. `ProxyRuntime` materially owns startup, shutdown, routing, `/v1/models`, `/healthz`, and `/internal/routes`
12. Factory worker contract logic is extracted into its own subsystem
13. `/v1/models` is synthesized locally, not forwarded through backend authority
14. current strong behaviors are preserved:
    - learned concurrency
    - NVIDIA streaming deadlines
    - hedge/race behavior
    - circuit-breaker integration
    - Factory drift and contract diagnostics
15. legacy monolithic runtime authority is deleted or reduced to a thin listener shell

## Verification Matrix

For each roadmap item, record:

- implementation evidence
- verification method
- exact command/checks used
- result
- residual gap

Mandatory final verification:

1. `./scripts/run-verification-specs.sh`
2. targeted tests for extracted services
3. local app/proxy startup
4. `curl http://127.0.0.1:8317/healthz`
5. `curl http://127.0.0.1:8317/internal/routes`
6. `curl http://127.0.0.1:8317/v1/models`
7. request-shape-specific manual checks for:
   - chat completions
   - responses
   - typed content
   - strict tool choice
   - streaming tool calls
8. Factory worker contract and drift inspection via `/healthz`

## Explicit Non-Regression Notes

These points came directly from comparison work and must remain visible during implementation.

1. The current project already has adaptive learned concurrency. The refactor must preserve it, not replace it with a weaker fixed-limit model.
2. The current project already has request-shape-aware behavior, but it is fragmented. The refactor must centralize it, not invent a reduced approximation.
3. The current project's NVIDIA streaming engine is stronger than the reference and must remain the quality bar.
4. The current project's circuit-breaker execution coupling is stronger than the reference and must remain the quality bar.
5. The current project's hedge and race behavior is stronger than the reference and must remain the quality bar.
6. The current project's Factory worker contract and drift logic is stronger than the reference and must remain the quality bar.

## Stop Conditions

This roadmap is not complete when the new modules merely exist. It is complete when:

- the new modular runtime is the active authority
- the old monolithic authority no longer materially defines runtime behavior
- verification proves parity or documented intentional improvements
- docs and scripts point at the end-state architecture

