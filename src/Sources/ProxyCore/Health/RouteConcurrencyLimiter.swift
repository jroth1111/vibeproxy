import Foundation

public final class RouteConcurrencyLimiter {
    private var inflightCounts: [String: Int] = [:]
    private var discoveredLimits: [String: Int] = [:]
    private var discoveredLimitUpdatedAt: [String: Date] = [:]
    private let queue = DispatchQueue(label: "io.automaze.vibeproxy.concurrency-limiter")

    public init() {}

    public func inflightCount(forRouteHealthKey key: String) -> Int {
        queue.sync { inflightCounts[key] ?? 0 }
    }

    public func incrementInflight(forRouteHealthKey key: String) -> Int {
        queue.sync {
            let count = (inflightCounts[key] ?? 0) + 1
            inflightCounts[key] = count
            return count
        }
    }

    public func decrementInflight(forRouteHealthKey key: String) {
        queue.sync {
            let current = inflightCounts[key] ?? 0
            inflightCounts[key] = max(0, current - 1)
        }
    }

    public func discoveredLimit(forRouteHealthKey key: String) -> Int? {
        queue.sync { discoveredLimits[key] }
    }

    public func updateDiscoveredLimit(_ limit: Int, forRouteHealthKey key: String, at date: Date = Date()) {
        queue.sync {
            discoveredLimits[key] = limit
            discoveredLimitUpdatedAt[key] = date
        }
    }

    public func hasCapacity(forRouteHealthKey key: String) -> Bool {
        queue.sync {
            guard let limit = discoveredLimits[key] else { return true }
            return (inflightCounts[key] ?? 0) < limit
        }
    }
}
