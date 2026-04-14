public struct RouteEMAMetrics: Equatable {
    public let successRate: Double
    public let averageLatencyMs: Double
    public let observationCount: Int

    public init(successRate: Double, averageLatencyMs: Double, observationCount: Int) {
        self.successRate = successRate
        self.averageLatencyMs = averageLatencyMs
        self.observationCount = observationCount
    }

    public static let empty = RouteEMAMetrics(successRate: 1.0, averageLatencyMs: 0.0, observationCount: 0)

    private static let emaBaseAlpha = 0.2
    private static let emaMinObservationsForStable = 10.0

    private var effectiveAlpha: Double {
        let count = Double(observationCount)
        guard count < Self.emaMinObservationsForStable else { return Self.emaBaseAlpha }
        return min(1.0, Self.emaBaseAlpha + (1.0 - Self.emaBaseAlpha) * (1.0 - count / Self.emaMinObservationsForStable))
    }

    public func updated(isSuccess: Bool, latencyMs: Int?) -> RouteEMAMetrics {
        let alpha = effectiveAlpha
        let newSuccessRate = successRate * (1.0 - alpha) + (isSuccess ? 1.0 : 0.0) * alpha
        let newLatency: Double
        if let latencyMs {
            newLatency = averageLatencyMs * (1.0 - alpha) + Double(latencyMs) * alpha
        } else {
            newLatency = averageLatencyMs
        }
        return RouteEMAMetrics(successRate: newSuccessRate, averageLatencyMs: newLatency, observationCount: observationCount + 1)
    }

    public var compositeScore: Double {
        guard observationCount > 0 else { return 500.0 }
        return successRate * successRate * 1000.0 - averageLatencyMs
    }

    public var isProvenPerfect: Bool {
        observationCount > 0 && successRate >= 0.999
    }
}
