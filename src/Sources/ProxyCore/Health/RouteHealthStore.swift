import Foundation

public struct ConcurrencySnapshot {
    public let inflight: Int
    public let limit: Int
    public init(inflight: Int, limit: Int) {
        self.inflight = inflight
        self.limit = limit
    }
}

public struct RouteHealthMutationResult {
    public let previousStatus: RouteHealthStatus
    public let nextStatus: RouteHealthStatus
    public let enrichedTelemetryEvent: RouteTelemetryEvent?
    public let needsPersist: Bool
    public let updatedCooldownUntil: Date?

    public init(
        previousStatus: RouteHealthStatus,
        nextStatus: RouteHealthStatus,
        enrichedTelemetryEvent: RouteTelemetryEvent?,
        needsPersist: Bool,
        updatedCooldownUntil: Date? = nil
    ) {
        self.previousStatus = previousStatus
        self.nextStatus = nextStatus
        self.enrichedTelemetryEvent = enrichedTelemetryEvent
        self.needsPersist = needsPersist
        self.updatedCooldownUntil = updatedCooldownUntil
    }
}

public struct RouteSuccessResult {
    public let mutationResult: RouteHealthMutationResult
    public let smartAliasInfo: SmartAliasSuccessInfo?

    public init(
        mutationResult: RouteHealthMutationResult,
        smartAliasInfo: SmartAliasSuccessInfo?
    ) {
        self.mutationResult = mutationResult
        self.smartAliasInfo = smartAliasInfo
    }
}

public struct SmartAliasSuccessInfo {
    public let requestedAlias: String
    public let winningRequestModel: String
    public let timestamp: Date
    public let requestShape: String?
    public let callerRequestID: String?
    public let callerSessionID: String?

    public init(
        requestedAlias: String,
        winningRequestModel: String,
        timestamp: Date,
        requestShape: String?,
        callerRequestID: String?,
        callerSessionID: String?
    ) {
        self.requestedAlias = requestedAlias
        self.winningRequestModel = winningRequestModel
        self.timestamp = timestamp
        self.requestShape = requestShape
        self.callerRequestID = callerRequestID
        self.callerSessionID = callerSessionID
    }
}

public final class RouteHealthStore {
    private var circuitStatesByRouteHealthKey: [String: RouteCircuitState] = [:]
    private var cooldownsByRouteHealthKey: [String: Date] = [:]
    private var recentFailureTimestampsByRoute: [String: [Date]] = [:]
    private var routeHealthDirty: Bool = false
    private let queue = DispatchQueue(label: "io.automaze.vibeproxy.route-health-store")

    // MARK: - Config Constants

    public let failureDedupWindow: TimeInterval = 0.2
    public let adaptiveFailureEscalationWindow: TimeInterval = 30 * 60
    public let adaptiveFailureCooldownMaxMultiplier = 8
    public let routeRollingWindow = 8
    public let routeFailureScoreDecayInterval: TimeInterval = 180
    public let concurrency429RepeatWindow: TimeInterval = 10 * 60
    public let concurrency429Deferral: TimeInterval = 15
    public let repeatedConcurrency429Deferral: TimeInterval = 60
    public let singleFlightConcurrency429Deferral: TimeInterval = 5
    public let repeatedSingleFlightConcurrency429Deferral: TimeInterval = 15

    public var disableFailureDedupForTesting = false

    public init() {}

    // MARK: - Circuit State Queries

    public func circuitState(forRouteHealthKey key: String) -> RouteCircuitState? {
        queue.sync { circuitStatesByRouteHealthKey[key] }
    }

    public func setCircuitState(_ state: RouteCircuitState, forRouteHealthKey key: String) {
        queue.sync { circuitStatesByRouteHealthKey[key] = state }
    }

    public func removeCircuitState(forRouteHealthKey key: String) {
        queue.sync { circuitStatesByRouteHealthKey.removeValue(forKey: key) }
    }

    public func allCircuitStates() -> [String: RouteCircuitState] {
        queue.sync { circuitStatesByRouteHealthKey }
    }

    public func setAllCircuitStates(_ states: [String: RouteCircuitState]) {
        queue.sync { circuitStatesByRouteHealthKey = states }
    }

    public func circuitStateCount() -> Int {
        queue.sync { circuitStatesByRouteHealthKey.count }
    }

    // MARK: - Cooldown Queries

    public func cooldown(forRouteHealthKey key: String) -> Date? {
        queue.sync { cooldownsByRouteHealthKey[key] }
    }

    public func setCooldown(_ date: Date, forRouteHealthKey key: String) {
        queue.sync { cooldownsByRouteHealthKey[key] = date }
    }

    public func clearCooldown(forRouteHealthKey key: String) {
        queue.sync { cooldownsByRouteHealthKey.removeValue(forKey: key) }
    }

    public func allCooldowns() -> [String: Date] {
        queue.sync { cooldownsByRouteHealthKey }
    }

    public func activeCooldowns(at now: Date) -> [String: Date] {
        queue.sync {
            cooldownsByRouteHealthKey.filter { $0.value > now }
        }
    }

    // MARK: - Availability

    public func isRouteAvailable(_ key: String, at now: Date) -> Bool {
        queue.sync {
            if let cooldown = cooldownsByRouteHealthKey[key], now < cooldown { return false }
            if let state = circuitStatesByRouteHealthKey[key] { return !state.isUnavailable(at: now) }
            return true
        }
    }

    public func isRouteUnavailable(_ key: String, at now: Date) -> Bool {
        queue.sync {
            circuitStatesByRouteHealthKey[key]?.isUnavailable(at: now) ?? false
        }
    }

    // MARK: - Health Status Query

    public func healthStatus(forRouteHealthKey key: String) -> RouteHealthStatus {
        queue.sync {
            circuitStatesByRouteHealthKey[key]?.status ?? .closed
        }
    }

    public func nonClosedHealthStatus(forRouteHealthKey key: String) -> RouteHealthStatus? {
        queue.sync {
            guard let state = circuitStatesByRouteHealthKey[key] else { return nil }
            return state.status == .closed ? nil : state.status
        }
    }

    // MARK: - Rolling Metrics

    public func rollingMetrics(forRouteHealthKey key: String) -> RouteRollingMetrics? {
        queue.sync {
            circuitStatesByRouteHealthKey[key]?.rollingMetrics
        }
    }

    // MARK: - Snapshot Queries

    public func unavailableRouteMetrics(at now: Date) -> [RouteRollingMetrics] {
        queue.sync {
            circuitStatesByRouteHealthKey.values
                .filter { $0.isUnavailable(at: now) }
                .map(\.rollingMetrics)
        }
    }

    public func routeHealthKeys() -> [String] {
        queue.sync {
            Array(circuitStatesByRouteHealthKey.keys)
        }
    }

    // MARK: - Failure Recording

    public func recordFailure(
        routeHealthKey: String,
        providerID: String,
        telemetryEvent: RouteTelemetryEvent?,
        at now: Date,
        forcedOpenUntil: Date?,
        healthSensitivity: HealthSensitivity?,
        policy: RouteCircuitBreakerPolicy,
        concurrency: ConcurrencySnapshot
    ) -> RouteHealthMutationResult {
        queue.sync {
            let current = circuitStatesByRouteHealthKey[routeHealthKey]
            let failureBurst = noteFailureBurstLocked(routeHealthKey: routeHealthKey, at: now)
            let normalizedFailureClass = telemetryEvent?.failureClass?.lowercased()

            // Overload 429s — preserve telemetry, no state change
            if normalizedFailureClass == "classified_429_overload" {
                let currentStatus = current?.status ?? .closed
                let enriched = telemetryEvent.map {
                    RouteHealthCalculator.enrichTelemetryEvent($0, from: currentStatus, to: currentStatus)
                }
                return RouteHealthMutationResult(
                    previousStatus: currentStatus,
                    nextStatus: currentStatus,
                    enrichedTelemetryEvent: enriched,
                    needsPersist: false
                )
            }

            // Concurrency 429s — preserve circuit state, update cooldown
            if normalizedFailureClass == "classified_429_concurrency" {
                let currentStatus = current?.status ?? .closed
                let enriched = telemetryEvent.map {
                    RouteHealthCalculator.enrichTelemetryEvent($0, from: currentStatus, to: currentStatus)
                }
                let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
                let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                    current: current?.nvidiaInferenceProbe,
                    route: route,
                    telemetryEvent: enriched
                )
                let preservedState = RouteHealthCalculator.routeCircuitState(
                    current ?? RouteCircuitState(
                        status: .closed, failureScore: 0, recoverySuccesses: 0,
                        openUntil: nil, lastScoreUpdatedAt: now, lastTelemetryEvent: nil,
                        rollingMetrics: .empty, emaMetrics: .empty, recoveredAt: nil
                    ),
                    replacingLastTelemetryEvent: enriched,
                    replacingNVIDIAInferenceProbe: probeState
                )
                circuitStatesByRouteHealthKey[routeHealthKey] = preservedState
                routeHealthDirty = true
                let cooldownUntil = adaptiveConcurrencyDeferralUntilLocked(
                    routeHealthKey: routeHealthKey,
                    currentState: current,
                    existingCooldownUntil: cooldownsByRouteHealthKey[routeHealthKey],
                    telemetryEvent: enriched,
                    forcedOpenUntil: forcedOpenUntil,
                    concurrency: concurrency,
                    now: now
                )
                if let cooldownUntil, now < cooldownUntil {
                    cooldownsByRouteHealthKey[routeHealthKey] = cooldownUntil
                }
                return RouteHealthMutationResult(
                    previousStatus: currentStatus,
                    nextStatus: currentStatus,
                    enrichedTelemetryEvent: enriched,
                    needsPersist: true,
                    updatedCooldownUntil: cooldownUntil
                )
            }

            // Transport timeouts — preserve circuit state, update telemetry
            if let fc = normalizedFailureClass, fc.hasPrefix("transport_timeout") {
                let currentStatus = current?.status ?? .closed
                let enriched = telemetryEvent.map {
                    RouteHealthCalculator.enrichTelemetryEvent($0, from: currentStatus, to: currentStatus)
                }
                let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
                let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                    current: current?.nvidiaInferenceProbe,
                    route: route,
                    telemetryEvent: enriched
                )
                let preservedState = RouteHealthCalculator.routeCircuitState(
                    current ?? RouteCircuitState(
                        status: .closed, failureScore: 0, recoverySuccesses: 0,
                        openUntil: nil, lastScoreUpdatedAt: now, lastTelemetryEvent: nil,
                        rollingMetrics: .empty, emaMetrics: .empty, recoveredAt: nil
                    ),
                    replacingLastTelemetryEvent: enriched,
                    replacingNVIDIAInferenceProbe: probeState
                )
                circuitStatesByRouteHealthKey[routeHealthKey] = preservedState
                routeHealthDirty = true
                return RouteHealthMutationResult(
                    previousStatus: currentStatus,
                    nextStatus: currentStatus,
                    enrichedTelemetryEvent: enriched,
                    needsPersist: true
                )
            }

            // 5xx failures — shorter open window
            if let fc = normalizedFailureClass, fc.hasPrefix("classified_5") {
                let currentStatus = current?.status ?? .closed
                var nextState = RouteHealthCalculator.nextRouteCircuitState(
                    current: current,
                    afterFailureAt: now,
                    routeHealthKey: routeHealthKey,
                    telemetryEvent: telemetryEvent,
                    burstDeduplicated: failureBurst.burstDeduplicated,
                    policy: policy,
                    forcedOpenUntil: forcedOpenUntil,
                    healthSensitivity: healthSensitivity,
                    concurrency: concurrency,
                    rollingWindow: routeRollingWindow,
                    decayInterval: routeFailureScoreDecayInterval
                )
                let short5xxOpenDuration: TimeInterval = 60
                if nextState.status == .open {
                    let shortOpenUntil = now.addingTimeInterval(short5xxOpenDuration)
                    if let existingOpen = nextState.openUntil, existingOpen > shortOpenUntil {
                        nextState = RouteCircuitState(
                            status: nextState.status,
                            failureScore: nextState.failureScore,
                            recoverySuccesses: nextState.recoverySuccesses,
                            openUntil: shortOpenUntil,
                            lastScoreUpdatedAt: nextState.lastScoreUpdatedAt,
                            lastTelemetryEvent: nextState.lastTelemetryEvent,
                            rollingMetrics: nextState.rollingMetrics,
                            emaMetrics: nextState.emaMetrics,
                            recoveredAt: nextState.recoveredAt,
                            lastSuccessAt: nextState.lastSuccessAt,
                            lastLiveSuccessAt: nextState.lastLiveSuccessAt,
                            lastSuccessRequestID: nextState.lastSuccessRequestID,
                            lastFailureAt: nextState.lastFailureAt,
                            lastFailureClass: nextState.lastFailureClass,
                            nvidiaInferenceProbe: nextState.nvidiaInferenceProbe
                        )
                    }
                }
                let enriched = telemetryEvent.map {
                    RouteHealthCalculator.enrichTelemetryEvent($0, from: currentStatus, to: nextState.status)
                }
                let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
                let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                    current: current?.nvidiaInferenceProbe,
                    route: route,
                    telemetryEvent: enriched
                )
                nextState = RouteHealthCalculator.routeCircuitState(
                    nextState,
                    replacingLastTelemetryEvent: enriched,
                    replacingNVIDIAInferenceProbe: probeState
                )
                circuitStatesByRouteHealthKey[routeHealthKey] = nextState
                routeHealthDirty = true
                return RouteHealthMutationResult(
                    previousStatus: currentStatus,
                    nextStatus: nextState.status,
                    enrichedTelemetryEvent: enriched,
                    needsPersist: true
                )
            }

            // Malformed success bodies — degrade to suspect, never open
            if let fc = normalizedFailureClass,
               fc == "empty_content" || fc == "reasoning_only_content_missing" {
                let currentStatus = current?.status ?? .closed
                let targetStatus: RouteHealthStatus = currentStatus == .closed ? .suspect : currentStatus
                let enriched = telemetryEvent.map {
                    RouteHealthCalculator.enrichTelemetryEvent($0, from: currentStatus, to: targetStatus)
                }
                let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
                let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                    current: current?.nvidiaInferenceProbe,
                    route: route,
                    telemetryEvent: enriched
                )
                let preservedState = RouteCircuitState(
                    status: targetStatus,
                    failureScore: current?.failureScore ?? 0,
                    recoverySuccesses: current?.recoverySuccesses ?? 0,
                    openUntil: current?.openUntil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: enriched,
                    rollingMetrics: current?.rollingMetrics ?? .empty,
                    emaMetrics: current?.emaMetrics ?? .empty,
                    recoveredAt: current?.recoveredAt,
                    lastSuccessAt: current?.lastSuccessAt,
                    lastLiveSuccessAt: current?.lastLiveSuccessAt,
                    lastSuccessRequestID: current?.lastSuccessRequestID,
                    lastFailureAt: now,
                    lastFailureClass: telemetryEvent?.failureClass,
                    nvidiaInferenceProbe: probeState
                )
                circuitStatesByRouteHealthKey[routeHealthKey] = preservedState
                routeHealthDirty = true
                return RouteHealthMutationResult(
                    previousStatus: currentStatus,
                    nextStatus: targetStatus,
                    enrichedTelemetryEvent: enriched,
                    needsPersist: true
                )
            }

            // Network errors — preserve circuit state, update cooldown
            if let fc = normalizedFailureClass, fc == "network_error" {
                let currentStatus = current?.status ?? .closed
                let enriched = telemetryEvent.map {
                    RouteHealthCalculator.enrichTelemetryEvent($0, from: currentStatus, to: currentStatus)
                }
                let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
                let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                    current: current?.nvidiaInferenceProbe,
                    route: route,
                    telemetryEvent: enriched
                )
                let preservedState = RouteHealthCalculator.routeCircuitState(
                    current ?? RouteCircuitState(
                        status: .closed, failureScore: 0, recoverySuccesses: 0,
                        openUntil: nil, lastScoreUpdatedAt: now, lastTelemetryEvent: nil,
                        rollingMetrics: .empty, emaMetrics: .empty, recoveredAt: nil
                    ),
                    replacingLastTelemetryEvent: enriched,
                    replacingNVIDIAInferenceProbe: probeState
                )
                circuitStatesByRouteHealthKey[routeHealthKey] = preservedState
                routeHealthDirty = true
                let cooldownUntil = adaptiveConcurrencyDeferralUntilLocked(
                    routeHealthKey: routeHealthKey,
                    currentState: current,
                    existingCooldownUntil: cooldownsByRouteHealthKey[routeHealthKey],
                    telemetryEvent: enriched,
                    forcedOpenUntil: forcedOpenUntil,
                    concurrency: concurrency,
                    now: now
                )
                if let cooldownUntil, now < cooldownUntil {
                    cooldownsByRouteHealthKey[routeHealthKey] = cooldownUntil
                }
                return RouteHealthMutationResult(
                    previousStatus: currentStatus,
                    nextStatus: currentStatus,
                    enrichedTelemetryEvent: enriched,
                    needsPersist: true,
                    updatedCooldownUntil: cooldownUntil
                )
            }

            // General failure path
            var nextState = RouteHealthCalculator.nextRouteCircuitState(
                current: current,
                afterFailureAt: now,
                routeHealthKey: routeHealthKey,
                telemetryEvent: telemetryEvent,
                burstDeduplicated: failureBurst.burstDeduplicated,
                policy: policy,
                forcedOpenUntil: forcedOpenUntil,
                healthSensitivity: healthSensitivity,
                concurrency: concurrency,
                rollingWindow: routeRollingWindow,
                decayInterval: routeFailureScoreDecayInterval
            )
            if nextState.status == .open,
               let adaptiveOpenUntil = RouteHealthCalculator.adaptiveFailureOpenUntil(
                    currentOpenUntil: nextState.openUntil,
                    recentFailureCount: failureBurst.recentFailureCount,
                    now: now,
                    policy: policy,
                    escalationWindow: adaptiveFailureEscalationWindow,
                    maxMultiplier: adaptiveFailureCooldownMaxMultiplier
               ) {
                nextState = RouteCircuitState(
                    status: nextState.status,
                    failureScore: nextState.failureScore,
                    recoverySuccesses: nextState.recoverySuccesses,
                    openUntil: adaptiveOpenUntil,
                    lastScoreUpdatedAt: nextState.lastScoreUpdatedAt,
                    lastTelemetryEvent: nextState.lastTelemetryEvent,
                    rollingMetrics: nextState.rollingMetrics,
                    emaMetrics: nextState.emaMetrics,
                    recoveredAt: nextState.recoveredAt,
                    lastSuccessAt: nextState.lastSuccessAt,
                    lastLiveSuccessAt: nextState.lastLiveSuccessAt,
                    lastSuccessRequestID: nextState.lastSuccessRequestID,
                    lastFailureAt: nextState.lastFailureAt,
                    lastFailureClass: nextState.lastFailureClass,
                    nvidiaInferenceProbe: nextState.nvidiaInferenceProbe
                )
            }
            let previousStatus = current?.status ?? .closed
            let enriched = telemetryEvent.map {
                RouteHealthCalculator.enrichTelemetryEvent($0, from: previousStatus, to: nextState.status)
            }
            let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
            let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                current: current?.nvidiaInferenceProbe,
                route: route,
                telemetryEvent: enriched
            )
            nextState = RouteHealthCalculator.routeCircuitState(
                nextState,
                replacingLastTelemetryEvent: enriched,
                replacingNVIDIAInferenceProbe: probeState
            )
            circuitStatesByRouteHealthKey[routeHealthKey] = nextState
            let cooldownUntil = adaptiveConcurrencyDeferralUntilLocked(
                routeHealthKey: routeHealthKey,
                currentState: current,
                existingCooldownUntil: cooldownsByRouteHealthKey[routeHealthKey],
                telemetryEvent: enriched,
                forcedOpenUntil: forcedOpenUntil,
                concurrency: concurrency,
                now: now
            )
            if let cooldownUntil, now < cooldownUntil {
                cooldownsByRouteHealthKey[routeHealthKey] = cooldownUntil
            }
            routeHealthDirty = true
            return RouteHealthMutationResult(
                previousStatus: previousStatus,
                nextStatus: nextState.status,
                enrichedTelemetryEvent: enriched,
                needsPersist: true,
                updatedCooldownUntil: cooldownUntil
            )
        }
    }

    // MARK: - Success Recording

    public func recordSuccess(
        routeHealthKey: String,
        providerID: String,
        telemetryEvent: RouteTelemetryEvent?,
        at now: Date,
        policy: RouteCircuitBreakerPolicy,
        requestModel: String
    ) -> RouteSuccessResult {
        queue.sync {
            let current = circuitStatesByRouteHealthKey[routeHealthKey]
            let nextState = RouteHealthCalculator.nextRouteCircuitStateAfterSuccess(
                current: current,
                telemetryEvent: telemetryEvent,
                at: now,
                policy: policy,
                rollingWindow: routeRollingWindow,
                decayInterval: routeFailureScoreDecayInterval
            )
            let previousStatus = current?.status ?? .closed
            let enriched = telemetryEvent.map {
                RouteHealthCalculator.enrichTelemetryEvent($0, from: previousStatus, to: nextState.status)
            }
            let route = RouteIdentity(providerID: providerID, canonicalModelID: routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey)
            let probeState = RouteHealthCalculator.updatedNVIDIAInferenceProbeState(
                current: current?.nvidiaInferenceProbe,
                route: route,
                telemetryEvent: enriched
            )
            let finalState = RouteHealthCalculator.routeCircuitState(
                nextState,
                replacingLastTelemetryEvent: enriched,
                replacingNVIDIAInferenceProbe: probeState
            )
            circuitStatesByRouteHealthKey[routeHealthKey] = finalState
            routeHealthDirty = true

            let smartAliasInfo: SmartAliasSuccessInfo?
            if let telemetryEvent,
               telemetryEvent.source == "smart_alias",
               let requestedAlias = telemetryEvent.requestedAlias {
                let winningRequestModel = telemetryEvent.finalWinnerRequestModel ?? requestModel
                smartAliasInfo = SmartAliasSuccessInfo(
                    requestedAlias: requestedAlias,
                    winningRequestModel: winningRequestModel,
                    timestamp: telemetryEvent.timestamp,
                    requestShape: telemetryEvent.requestShape,
                    callerRequestID: telemetryEvent.callerRequestID,
                    callerSessionID: telemetryEvent.callerSessionID
                )
            } else {
                smartAliasInfo = nil
            }

            let mutationResult = RouteHealthMutationResult(
                previousStatus: previousStatus,
                nextStatus: finalState.status,
                enrichedTelemetryEvent: enriched,
                needsPersist: true
            )
            return RouteSuccessResult(
                mutationResult: mutationResult,
                smartAliasInfo: smartAliasInfo
            )
        }
    }

    // MARK: - Cooldown Updates

    public func recordAvailabilityDeferral(
        routeHealthKey: String,
        until deferredUntil: Date,
        at now: Date
    ) {
        queue.sync {
            let current = cooldownsByRouteHealthKey[routeHealthKey]
            if current == nil || deferredUntil > current! {
                cooldownsByRouteHealthKey[routeHealthKey] = deferredUntil
                routeHealthDirty = true
            }
        }
    }

    // MARK: - Serialization

    public func serializeState() -> [String: RouteCircuitState] {
        queue.sync { circuitStatesByRouteHealthKey }
    }

    public func serializeCooldowns() -> [String: Date] {
        queue.sync { cooldownsByRouteHealthKey }
    }

    public func loadSerializedState(
        _ states: [String: RouteCircuitState],
        cooldowns: [String: Date] = [:]
    ) {
        queue.sync {
            circuitStatesByRouteHealthKey = states
            cooldownsByRouteHealthKey = cooldowns
        }
    }

    public func isDirty() -> Bool {
        queue.sync { routeHealthDirty }
    }

    public func clearDirty() {
        queue.sync { routeHealthDirty = false }
    }

    // MARK: - Reset

    public func clearAll() {
        queue.sync {
            circuitStatesByRouteHealthKey = [:]
            cooldownsByRouteHealthKey = [:]
            recentFailureTimestampsByRoute = [:]
            routeHealthDirty = false
        }
    }

    public func resetForTesting() {
        clearAll()
    }

    // MARK: - Internal: Failure Burst Tracking

    private struct FailureBurstInfo {
        let recentFailureCount: Int
        let burstDeduplicated: Bool
    }

    private func noteFailureBurstLocked(routeHealthKey: String, at now: Date) -> FailureBurstInfo {
        var timestamps = recentFailureTimestampsByRoute[routeHealthKey] ?? []
        timestamps.removeAll { now.timeIntervalSince($0) > adaptiveFailureEscalationWindow }

        if !disableFailureDedupForTesting,
           let last = timestamps.last,
           now.timeIntervalSince(last) <= failureDedupWindow {
            recentFailureTimestampsByRoute[routeHealthKey] = timestamps
            return FailureBurstInfo(recentFailureCount: timestamps.count, burstDeduplicated: true)
        }

        timestamps.append(now)
        recentFailureTimestampsByRoute[routeHealthKey] = timestamps
        return FailureBurstInfo(recentFailureCount: timestamps.count, burstDeduplicated: false)
    }

    // MARK: - Internal: Adaptive Concurrency Deferral

    private func adaptiveConcurrencyDeferralUntilLocked(
        routeHealthKey: String,
        currentState: RouteCircuitState?,
        existingCooldownUntil: Date?,
        telemetryEvent: RouteTelemetryEvent?,
        forcedOpenUntil: Date?,
        concurrency: ConcurrencySnapshot,
        now: Date
    ) -> Date? {
        var deferredUntil = [existingCooldownUntil, forcedOpenUntil].compactMap { $0 }.max()

        guard let telemetryEvent,
              telemetryEvent.failureClass?.lowercased() == "classified_429_concurrency" else {
            return deferredUntil
        }

        if deferredUntil != nil {
            return deferredUntil
        }

        let inflightAtRequest = telemetryEvent.inflightAtRequest ?? concurrency.inflight
        let repeatedConcurrencyFailure =
            currentState?.lastTelemetryEvent.map { lastTelemetryEvent in
                guard lastTelemetryEvent.failureClass?.lowercased() == "classified_429_concurrency" else {
                    return false
                }
                return now.timeIntervalSince(lastTelemetryEvent.timestamp) <= concurrency429RepeatWindow
            } ?? false

        let minimumDeferral: TimeInterval
        if inflightAtRequest <= 1 {
            if deferredUntil != nil {
                return deferredUntil
            }
            minimumDeferral = repeatedConcurrencyFailure
                ? repeatedSingleFlightConcurrency429Deferral
                : singleFlightConcurrency429Deferral
        } else {
            minimumDeferral = repeatedConcurrencyFailure
                ? repeatedConcurrency429Deferral
                : concurrency429Deferral
        }

        let adaptiveUntil = now.addingTimeInterval(minimumDeferral)
        if deferredUntil == nil || adaptiveUntil > deferredUntil! {
            deferredUntil = adaptiveUntil
        }
        return deferredUntil
    }
}
