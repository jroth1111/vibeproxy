import Foundation

public enum RouteHealthCalculator {

    // MARK: - Failure Path

    public static func nextRouteCircuitState(
        current: RouteCircuitState?,
        afterFailureAt now: Date,
        routeHealthKey: String,
        telemetryEvent: RouteTelemetryEvent?,
        burstDeduplicated: Bool,
        policy: RouteCircuitBreakerPolicy,
        forcedOpenUntil: Date? = nil,
        healthSensitivity: HealthSensitivity? = nil,
        concurrency: ConcurrencySnapshot,
        rollingWindow: Int,
        decayInterval: TimeInterval
    ) -> RouteCircuitState {
        let failurePenalty = failurePenalty(
            for: telemetryEvent,
            routeHealthKey: routeHealthKey,
            burstDeduplicated: burstDeduplicated,
            concurrency: concurrency
        )
        let lastTelemetryEvent = telemetryEvent ?? current?.lastTelemetryEvent
        let nextRollingMetrics = updatedRollingMetrics(
            current: current?.rollingMetrics,
            telemetryEvent: telemetryEvent,
            rollingWindow: rollingWindow
        )
        let nextEMA = (current?.emaMetrics ?? .empty).updated(
            isSuccess: false,
            latencyMs: nil
        )
        let decayedFailureScore = decayedFailureScore(
            current?.failureScore ?? 0,
            lastUpdatedAt: current?.lastScoreUpdatedAt,
            now: now,
            decayInterval: decayInterval
        )
        let failureThreshold = effectiveFailureThreshold(
            policy: policy,
            healthSensitivity: healthSensitivity
        )
        let effectiveForcedOpenUntil = [current?.openUntil, forcedOpenUntil]
            .compactMap { $0 }
            .filter { $0 > now }
            .max()
        let nextLastSuccessAt = current?.lastSuccessAt
        let nextLastLiveSuccessAt = current?.lastLiveSuccessAt
        let nextLastSuccessRequestID = current?.lastSuccessRequestID
        let nextLastFailureAt = telemetryEvent != nil ? now : current?.lastFailureAt
        let nextLastFailureClass = telemetryEvent?.failureClass ?? current?.lastFailureClass

        if let effectiveForcedOpenUntil {
            return RouteCircuitState(
                status: .open,
                failureScore: failureThreshold,
                recoverySuccesses: 0,
                openUntil: effectiveForcedOpenUntil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        }

        switch current?.status ?? .closed {
        case .closed, .suspect:
            if failurePenalty == 0 {
                return RouteCircuitState(
                    status: current?.status ?? .closed,
                    failureScore: decayedFailureScore,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: current?.recoveredAt,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            let nextFailureScore = min(
                failureThreshold,
                decayedFailureScore + failurePenalty
            )
            if nextFailureScore >= failureThreshold {
                return RouteCircuitState(
                    status: .open,
                    failureScore: failureThreshold,
                    recoverySuccesses: 0,
                    openUntil: now.addingTimeInterval(policy.cooldown),
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: nil,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .suspect,
                failureScore: nextFailureScore,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .open, .halfOpen:
            if failurePenalty == 0 {
                return RouteCircuitState(
                    status: current?.status ?? .closed,
                    failureScore: current?.failureScore ?? 0,
                    recoverySuccesses: current?.recoverySuccesses ?? 0,
                    openUntil: current?.openUntil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: current?.recoveredAt,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .open,
                failureScore: failureThreshold,
                recoverySuccesses: 0,
                openUntil: now.addingTimeInterval(policy.cooldown),
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        }
    }

    // MARK: - Success Path

    public static func nextRouteCircuitStateAfterSuccess(
        current: RouteCircuitState?,
        telemetryEvent: RouteTelemetryEvent?,
        at now: Date,
        policy: RouteCircuitBreakerPolicy,
        rollingWindow: Int,
        decayInterval: TimeInterval
    ) -> RouteCircuitState {
        let lastTelemetryEvent = telemetryEvent ?? current?.lastTelemetryEvent
        let nextRollingMetrics = updatedRollingMetrics(
            current: current?.rollingMetrics,
            telemetryEvent: telemetryEvent,
            rollingWindow: rollingWindow
        )
        let nextEMA = (current?.emaMetrics ?? .empty).updated(
            isSuccess: true,
            latencyMs: telemetryEvent?.firstByteLatencyMilliseconds
        )
        let decayedScore = decayedFailureScore(
            current?.failureScore ?? 0,
            lastUpdatedAt: current?.lastScoreUpdatedAt,
            now: now,
            decayInterval: decayInterval
        )
        let reducedScore = max(0, decayedScore - 1)
        let countsAsLiveTraffic = routeSuccessCountsAsLiveTraffic(telemetryEvent)
        let nextLastSuccessAt: Date? = now
        let nextLastLiveSuccessAt: Date? = countsAsLiveTraffic ? now : current?.lastLiveSuccessAt
        let nextLastSuccessRequestID = telemetryEvent?.proxyRequestID ?? current?.lastSuccessRequestID
        let nextLastFailureAt = current?.lastFailureAt
        let nextLastFailureClass: String? = nil

        switch current?.status ?? .closed {
        case .closed:
            return RouteCircuitState(
                status: .closed,
                failureScore: 0,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .suspect:
            if reducedScore > 0 || shouldRemainSuspectAfterSuccess(metrics: nextRollingMetrics) {
                return RouteCircuitState(
                    status: .suspect,
                    failureScore: reducedScore,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: nil,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .closed,
                failureScore: 0,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .open:
            if policy.recoverySuccessThreshold <= 1 {
                return RouteCircuitState(
                    status: .closed,
                    failureScore: 0,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: now,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .halfOpen,
                failureScore: 0,
                recoverySuccesses: 1,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .halfOpen:
            let nextRecoverySuccesses = (current?.recoverySuccesses ?? 0) + 1
            if nextRecoverySuccesses >= policy.recoverySuccessThreshold {
                return RouteCircuitState(
                    status: .closed,
                    failureScore: 0,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: now,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .halfOpen,
                failureScore: 0,
                recoverySuccesses: nextRecoverySuccesses,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        }
    }

    // MARK: - NVIDIA Inference Probe

    public static func updatedNVIDIAInferenceProbeState(
        current: NVIDIAInferenceProbeState?,
        route: RouteIdentity,
        telemetryEvent: RouteTelemetryEvent?
    ) -> NVIDIAInferenceProbeState? {
        guard route.providerID == "nvidia" || route.providerID == "nvidia-minimax" else { return nil }
        guard let telemetryEvent, telemetryEvent.source == "canary" else {
            return current
        }

        let isSuccess = telemetryEventRepresentsHealthySuccess(telemetryEvent)

        return NVIDIAInferenceProbeState(
            lastProbeAt: telemetryEvent.timestamp,
            lastStatus: isSuccess ? .success : .failure,
            lastSuccessAt: isSuccess ? telemetryEvent.timestamp : current?.lastSuccessAt,
            lastFailureAt: isSuccess ? current?.lastFailureAt : telemetryEvent.timestamp,
            lastFailureClass: isSuccess ? nil : telemetryEvent.failureClass,
            lastTimeoutStage: telemetryEvent.timeoutStage,
            lastUpstreamHTTPStatus: telemetryEvent.upstreamHTTPStatus,
            lastTransportOutcome: telemetryEvent.transportOutcome,
            lastFirstByteLatencyMilliseconds: telemetryEvent.firstByteLatencyMilliseconds,
            lastTotalLatencyMilliseconds: telemetryEvent.totalLatencyMilliseconds
        )
    }

    // MARK: - State Replacement

    public static func routeCircuitState(
        _ state: RouteCircuitState,
        replacingLastTelemetryEvent telemetryEvent: RouteTelemetryEvent?,
        replacingNVIDIAInferenceProbe nvidiaInferenceProbe: NVIDIAInferenceProbeState? = nil
    ) -> RouteCircuitState {
        RouteCircuitState(
            status: state.status,
            failureScore: state.failureScore,
            recoverySuccesses: state.recoverySuccesses,
            openUntil: state.openUntil,
            lastScoreUpdatedAt: state.lastScoreUpdatedAt,
            lastTelemetryEvent: telemetryEvent,
            rollingMetrics: state.rollingMetrics,
            emaMetrics: state.emaMetrics,
            recoveredAt: state.recoveredAt,
            lastSuccessAt: state.lastSuccessAt,
            lastLiveSuccessAt: state.lastLiveSuccessAt,
            lastSuccessRequestID: state.lastSuccessRequestID,
            lastFailureAt: state.lastFailureAt,
            lastFailureClass: state.lastFailureClass,
            nvidiaInferenceProbe: nvidiaInferenceProbe ?? state.nvidiaInferenceProbe
        )
    }

    // MARK: - Telemetry Enrichment

    public static func enrichTelemetryEvent(
        _ event: RouteTelemetryEvent,
        from previousStatus: RouteHealthStatus,
        to nextStatus: RouteHealthStatus,
        winnerAttemptLane: Int? = nil
    ) -> RouteTelemetryEvent {
        RouteTelemetryEvent(
            timestamp: event.timestamp,
            requestModel: event.requestModel,
            requestedAlias: event.requestedAlias,
            canonicalModelID: event.canonicalModelID,
            transportOutcome: event.transportOutcome,
            healthTransition: healthTransitionLabel(from: previousStatus, to: nextStatus),
            attemptLane: event.attemptLane,
            winnerAttemptLane: winnerAttemptLane ?? event.winnerAttemptLane,
            failoverDepth: event.failoverDepth,
            finalWinnerRequestModel: event.finalWinnerRequestModel,
            failureClass: event.failureClass,
            timeoutStage: event.timeoutStage,
            upstreamHTTPStatus: event.upstreamHTTPStatus,
            retryCount: event.retryCount,
            source: event.source,
            firstByteLatencyMilliseconds: event.firstByteLatencyMilliseconds,
            totalLatencyMilliseconds: event.totalLatencyMilliseconds,
            inflightAtRequest: event.inflightAtRequest,
            proxyRequestID: event.proxyRequestID,
            callerRequestID: event.callerRequestID,
            callerSessionID: event.callerSessionID,
            requestShape: event.requestShape,
            negotiatedApplicationProtocol: event.negotiatedApplicationProtocol,
            errorBodySnippet: event.errorBodySnippet
        )
    }

    // MARK: - Failure Penalty

    public static func failurePenalty(
        for telemetryEvent: RouteTelemetryEvent?,
        routeHealthKey: String,
        burstDeduplicated: Bool,
        concurrency: ConcurrencySnapshot
    ) -> Double {
        guard let failureClass = telemetryEvent?.failureClass?.lowercased() else {
            return burstDeduplicated ? 0 : 1
        }

        if failureClass.hasPrefix("classified_429") {
            return 0
        }

        let basePenalty: Double
        if failureClass.hasPrefix("transport_timeout"),
           telemetryEvent?.timeoutStage == .firstResponse {
            basePenalty = 3
        } else if failureClass == "transport_error" ||
            failureClass == "missing_response_material" ||
            failureClass.hasPrefix("classified_5") {
            basePenalty = 2
        } else {
            basePenalty = 1
        }

        if burstDeduplicated {
            return 0
        }

        let inflightAtRequest = telemetryEvent?.inflightAtRequest ?? concurrency.inflight
        if inflightAtRequest >= concurrency.limit {
            return basePenalty * 0.25
        }

        return basePenalty
    }

    // MARK: - Score Decay

    public static func decayedFailureScore(
        _ failureScore: Double,
        lastUpdatedAt: Date?,
        now: Date,
        decayInterval: TimeInterval
    ) -> Double {
        guard failureScore > 0,
              let lastUpdatedAt else {
            return failureScore
        }
        let elapsed = max(0, now.timeIntervalSince(lastUpdatedAt))
        guard elapsed >= decayInterval else {
            return failureScore
        }
        let decaySteps = Int(elapsed / decayInterval)
        return max(0, failureScore - Double(decaySteps))
    }

    // MARK: - Rolling Metrics

    public static func updatedRollingMetrics(
        current: RouteRollingMetrics?,
        telemetryEvent: RouteTelemetryEvent?,
        rollingWindow: Int
    ) -> RouteRollingMetrics {
        guard let telemetryEvent else {
            return current ?? .empty
        }

        let prior = current ?? .empty
        var recentOutcomes = prior.recentOutcomes
        recentOutcomes.append(rollingOutcomeLabel(for: telemetryEvent))
        if recentOutcomes.count > rollingWindow {
            recentOutcomes.removeFirst(recentOutcomes.count - rollingWindow)
        }

        var recentFirstByteLatencyMilliseconds = prior.recentFirstByteLatencyMilliseconds
        if let firstByteLatencyMilliseconds = telemetryEvent.firstByteLatencyMilliseconds {
            recentFirstByteLatencyMilliseconds.append(firstByteLatencyMilliseconds)
            if recentFirstByteLatencyMilliseconds.count > rollingWindow {
                recentFirstByteLatencyMilliseconds.removeFirst(recentFirstByteLatencyMilliseconds.count - rollingWindow)
            }
        }

        var recentTotalLatencyMilliseconds = prior.recentTotalLatencyMilliseconds
        if let totalLatencyMilliseconds = telemetryEvent.totalLatencyMilliseconds {
            recentTotalLatencyMilliseconds.append(totalLatencyMilliseconds)
            if recentTotalLatencyMilliseconds.count > rollingWindow {
                recentTotalLatencyMilliseconds.removeFirst(recentTotalLatencyMilliseconds.count - rollingWindow)
            }
        }

        return RouteRollingMetrics(
            recentOutcomes: recentOutcomes,
            recentFirstByteLatencyMilliseconds: recentFirstByteLatencyMilliseconds,
            recentTotalLatencyMilliseconds: recentTotalLatencyMilliseconds
        )
    }

    // MARK: - Threshold

    public static func effectiveFailureThreshold(
        policy: RouteCircuitBreakerPolicy,
        healthSensitivity: HealthSensitivity? = nil
    ) -> Double {
        let baseThreshold = policy.failureThreshold
        guard let sensitivity = healthSensitivity, sensitivity != .balanced else {
            return baseThreshold
        }
        return max(1, baseThreshold * sensitivity.failureThresholdScaleFactor)
    }

    // MARK: - Suspect Check

    public static func shouldRemainSuspectAfterSuccess(metrics: RouteRollingMetrics) -> Bool {
        metrics.timeoutRate >= 0.5 || metrics.invalidSuccessRate >= 0.5
    }

    // MARK: - Adaptive Failure Escalation

    public static func adaptiveFailureOpenUntil(
        currentOpenUntil: Date?,
        recentFailureCount: Int,
        now: Date,
        policy: RouteCircuitBreakerPolicy,
        escalationWindow: TimeInterval,
        maxMultiplier: Int
    ) -> Date? {
        guard currentOpenUntil != nil else { return nil }
        guard recentFailureCount >= 3 else { return currentOpenUntil }
        let multiplier = min(maxMultiplier, recentFailureCount)
        return now.addingTimeInterval(policy.cooldown * Double(multiplier))
    }

    // MARK: - Adaptive Concurrency Deferral

    public static func adaptiveConcurrencyDeferralUntil(
        routeHealthKey: String,
        currentState: RouteCircuitState?,
        existingCooldownUntil: Date?,
        telemetryEvent: RouteTelemetryEvent?,
        forcedOpenUntil: Date?,
        concurrency: ConcurrencySnapshot,
        now: Date,
        concurrency429Deferral: TimeInterval,
        repeatedConcurrency429Deferral: TimeInterval,
        singleFlightConcurrency429Deferral: TimeInterval,
        repeatedSingleFlightConcurrency429Deferral: TimeInterval,
        concurrency429RepeatWindow: TimeInterval
    ) -> Date? {
        var candidates: [Date] = []
        if let forcedOpenUntil, forcedOpenUntil > now {
            candidates.append(forcedOpenUntil)
        }
        if let existingCooldownUntil, existingCooldownUntil > now {
            candidates.append(existingCooldownUntil)
        }

        let failureClass = telemetryEvent?.failureClass?.lowercased() ?? ""
        guard failureClass.hasPrefix("classified_429") else {
            return candidates.max()
        }

        let inflightAtRequest = telemetryEvent?.inflightAtRequest ?? concurrency.inflight

        if inflightAtRequest >= concurrency.limit {
            let deferral = now.addingTimeInterval(concurrency429Deferral)
            candidates.append(deferral)
        } else if inflightAtRequest <= 1 {
            let deferral = now.addingTimeInterval(singleFlightConcurrency429Deferral)
            candidates.append(deferral)
        }

        return candidates.max()
    }

    // MARK: - Private Helpers

    private static func rollingOutcomeLabel(for telemetryEvent: RouteTelemetryEvent) -> String {
        if let failureClass = telemetryEvent.failureClass, !failureClass.isEmpty {
            return "\(telemetryEvent.transportOutcome):\(failureClass)"
        }
        return telemetryEvent.transportOutcome
    }

    private static func healthTransitionLabel(from previousStatus: RouteHealthStatus, to nextStatus: RouteHealthStatus) -> String? {
        guard previousStatus != nextStatus else { return nil }
        return "\(previousStatus.rawValue)->\(nextStatus.rawValue)"
    }

    private static func routeSuccessCountsAsLiveTraffic(_ telemetryEvent: RouteTelemetryEvent?) -> Bool {
        guard let telemetryEvent else {
            return true
        }
        switch telemetryEvent.source {
        case "canary", "smart_alias_probe":
            return false
        default:
            return true
        }
    }

    public static func telemetryEventRepresentsHealthySuccess(_ telemetryEvent: RouteTelemetryEvent?) -> Bool {
        guard let telemetryEvent else { return false }
        guard telemetryEvent.transportOutcome == "send_response" else { return false }
        guard telemetryEvent.failureClass == nil else { return false }
        guard let upstreamHTTPStatus = telemetryEvent.upstreamHTTPStatus else { return false }
        return (200..<300).contains(upstreamHTTPStatus)
    }
}
