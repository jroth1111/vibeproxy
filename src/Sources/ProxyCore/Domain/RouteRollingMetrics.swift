import Foundation

public struct RouteRollingMetrics: Equatable {
    public let recentOutcomes: [String]
    public let recentFirstByteLatencyMilliseconds: [Int]
    public let recentTotalLatencyMilliseconds: [Int]

    public init(
        recentOutcomes: [String],
        recentFirstByteLatencyMilliseconds: [Int],
        recentTotalLatencyMilliseconds: [Int] = []
    ) {
        self.recentOutcomes = recentOutcomes
        self.recentFirstByteLatencyMilliseconds = recentFirstByteLatencyMilliseconds
        self.recentTotalLatencyMilliseconds = recentTotalLatencyMilliseconds
    }

    public static let empty = RouteRollingMetrics(
        recentOutcomes: [],
        recentFirstByteLatencyMilliseconds: [],
        recentTotalLatencyMilliseconds: []
    )

    public var timeoutRate: Double {
        guard !recentOutcomes.isEmpty else { return 0 }
        let timeouts = recentOutcomes.filter { $0.contains(":transport_timeout") }.count
        return Double(timeouts) / Double(recentOutcomes.count)
    }

    public var invalidSuccessRate: Double {
        guard !recentOutcomes.isEmpty else { return 0 }
        let invalid = recentOutcomes.filter { $0.hasPrefix("send_response:") }.count
        return Double(invalid) / Double(recentOutcomes.count)
    }

    public var averageFirstByteLatencyMilliseconds: Int? {
        guard !recentFirstByteLatencyMilliseconds.isEmpty else { return nil }
        let total = recentFirstByteLatencyMilliseconds.reduce(0, +)
        return total / recentFirstByteLatencyMilliseconds.count
    }

    public var averageTotalLatencyMilliseconds: Int? {
        guard !recentTotalLatencyMilliseconds.isEmpty else { return nil }
        let total = recentTotalLatencyMilliseconds.reduce(0, +)
        return total / recentTotalLatencyMilliseconds.count
    }

    public var p95FirstByteLatencyMilliseconds: Int? {
        Self.percentileLatencyMilliseconds(recentFirstByteLatencyMilliseconds, percentile: 0.95)
    }

    public var p95TotalLatencyMilliseconds: Int? {
        Self.percentileLatencyMilliseconds(recentTotalLatencyMilliseconds, percentile: 0.95)
    }

    public static func percentileLatencyMilliseconds(_ samples: [Int], percentile: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let clampedPercentile = min(max(percentile, 0), 1)
        let index = Int(ceil(Double(sorted.count - 1) * clampedPercentile))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}
