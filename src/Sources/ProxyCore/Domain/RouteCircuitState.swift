import Foundation

public struct RouteCircuitState: Equatable {
    public let status: RouteHealthStatus
    public let failureScore: Double
    public let recoverySuccesses: Int
    public let openUntil: Date?
    public let lastScoreUpdatedAt: Date?
    public let lastTelemetryEvent: RouteTelemetryEvent?
    public let rollingMetrics: RouteRollingMetrics
    public let emaMetrics: RouteEMAMetrics
    public let recoveredAt: Date?
    public let lastSuccessAt: Date?
    public let lastLiveSuccessAt: Date?
    public let lastSuccessRequestID: String?
    public let lastFailureAt: Date?
    public let lastFailureClass: String?
    public let nvidiaInferenceProbe: NVIDIAInferenceProbeState?

    public init(
        status: RouteHealthStatus,
        failureScore: Double,
        recoverySuccesses: Int,
        openUntil: Date?,
        lastScoreUpdatedAt: Date?,
        lastTelemetryEvent: RouteTelemetryEvent?,
        rollingMetrics: RouteRollingMetrics,
        emaMetrics: RouteEMAMetrics,
        recoveredAt: Date?,
        lastSuccessAt: Date? = nil,
        lastLiveSuccessAt: Date? = nil,
        lastSuccessRequestID: String? = nil,
        lastFailureAt: Date? = nil,
        lastFailureClass: String? = nil,
        nvidiaInferenceProbe: NVIDIAInferenceProbeState? = nil
    ) {
        self.status = status
        self.failureScore = failureScore
        self.recoverySuccesses = recoverySuccesses
        self.openUntil = openUntil
        self.lastScoreUpdatedAt = lastScoreUpdatedAt
        self.lastTelemetryEvent = lastTelemetryEvent
        self.rollingMetrics = rollingMetrics
        self.emaMetrics = emaMetrics
        self.recoveredAt = recoveredAt
        self.lastSuccessAt = lastSuccessAt
        self.lastLiveSuccessAt = lastLiveSuccessAt
        self.lastSuccessRequestID = lastSuccessRequestID
        self.lastFailureAt = lastFailureAt
        self.lastFailureClass = lastFailureClass
        self.nvidiaInferenceProbe = nvidiaInferenceProbe
    }

    private static let momentumBaseBonus: Double = 50.0
    private static let momentumDecayPerSecond: Double = 0.95

    public func momentumBonus(at now: Date) -> Double {
        guard status == .closed, let recoveredAt else { return 0.0 }
        let elapsed = now.timeIntervalSince(recoveredAt)
        guard elapsed > 0 else { return Self.momentumBaseBonus }
        return Self.momentumBaseBonus * pow(Self.momentumDecayPerSecond, elapsed)
    }

    public func isUnavailable(at now: Date) -> Bool {
        switch status {
        case .closed, .suspect, .halfOpen:
            return false
        case .open:
            if let openUntil {
                return now < openUntil
            }
            return true
        }
    }

    public func isOpen(at now: Date) -> Bool {
        isUnavailable(at: now)
    }
}
