import Foundation

public final class RouteConcurrencyLimiter {
    private var inflightCounts: [String: Int] = [:]
    private var discoveredLimits: [String: Int] = [:]
    private var discoveredLimitUpdatedAt: [String: Date] = [:]
    private var consecutiveSuccessesAtLimit: [String: Int] = [:]
    private var concurrent429Buckets: [String: (inflightLevel: Int, count: Int)] = [:]
    private var inflightSince: [String: Date] = [:]

    private let slotLeakThreshold: TimeInterval = 10 * 60
    private let defaultConcurrencyLimit = 3
    private let maxConcurrencyLimit = 8
    private let successGrowthThreshold = 20
    private let lowLimitSuccessGrowthThreshold = 3
    private let mediumLimitSuccessGrowthThreshold = 6
    private let learnedLowLimitTTL: TimeInterval = 10 * 60
    private let queue = DispatchQueue(label: "io.automaze.vibeproxy.concurrency-limiter")

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    // MARK: - Slot Management

    public func acquireSlot(routeHealthKey: String) -> Bool {
        queue.sync {
            let limit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
            let current = inflightCounts[routeHealthKey] ?? 0
            guard current < limit else {
                return false
            }
            inflightCounts[routeHealthKey] = current + 1
            if current == 0 {
                inflightSince[routeHealthKey] = Date()
            }
            return true
        }
    }

    public func releaseSlot(routeHealthKey: String) {
        queue.sync {
            let current = inflightCounts[routeHealthKey] ?? 0
            let newCount = max(0, current - 1)
            inflightCounts[routeHealthKey] = newCount
            if newCount == 0 {
                inflightSince.removeValue(forKey: routeHealthKey)
            }
        }
    }

    // MARK: - 429 Recording

    public func record429(routeHealthKey: String, inflightAtRequest: Int) {
        queue.sync {
            let currentLimit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
            consecutiveSuccessesAtLimit[routeHealthKey] = 0

            if inflightAtRequest >= currentLimit,
               let inferredLimit = inferredLimitFromConcurrency429(inflightAtRequest: inflightAtRequest) {
                discoveredLimits[routeHealthKey] = inferredLimit
                discoveredLimitUpdatedAt[routeHealthKey] = Date()
                concurrent429Buckets.removeValue(forKey: routeHealthKey)
                return
            }

            let bucket = concurrent429Buckets[routeHealthKey]
            if let bucket, bucket.inflightLevel == inflightAtRequest {
                let newCount = bucket.count + 1
                if newCount >= 3,
                   let inferredLimit = inferredLimitFromConcurrency429(inflightAtRequest: inflightAtRequest) {
                    discoveredLimits[routeHealthKey] = inferredLimit
                    discoveredLimitUpdatedAt[routeHealthKey] = Date()
                    concurrent429Buckets.removeValue(forKey: routeHealthKey)
                } else {
                    concurrent429Buckets[routeHealthKey] = (inflightLevel: inflightAtRequest, count: newCount)
                }
            } else {
                concurrent429Buckets[routeHealthKey] = (inflightLevel: inflightAtRequest, count: 1)
            }
        }
    }

    // MARK: - Success Recording

    public func recordSuccess(routeHealthKey: String, inflightAtRequest: Int? = nil) {
        queue.sync {
            let currentLimit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
            let currentInflight = inflightAtRequest ?? (inflightCounts[routeHealthKey] ?? 0)

            guard currentInflight >= currentLimit - 1 else { return }

            let successes = (consecutiveSuccessesAtLimit[routeHealthKey] ?? 0) + 1
            consecutiveSuccessesAtLimit[routeHealthKey] = successes
            concurrent429Buckets.removeValue(forKey: routeHealthKey)

            if successes >= successGrowthThreshold(for: currentLimit), currentLimit < maxConcurrencyLimit {
                discoveredLimits[routeHealthKey] = currentLimit + 1
                discoveredLimitUpdatedAt[routeHealthKey] = Date()
                consecutiveSuccessesAtLimit[routeHealthKey] = 0
            }
        }
    }

    // MARK: - Queries

    public func inflightCount(forRouteHealthKey key: String) -> Int {
        queue.sync { inflightCounts[key] ?? 0 }
    }

    public func discoveredLimit(forRouteHealthKey key: String) -> Int? {
        queue.sync { discoveredLimits[key] }
    }

    public func currentLimit(routeHealthKey: String) -> Int {
        queue.sync { effectiveLimitLocked(routeHealthKey: routeHealthKey) }
    }

    public func isAtCapacity(routeHealthKey: String) -> Bool {
        queue.sync {
            let limit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
            return (inflightCounts[routeHealthKey] ?? 0) >= limit
        }
    }

    public func hasCapacity(forRouteHealthKey key: String) -> Bool {
        !isAtCapacity(routeHealthKey: key)
    }

    // MARK: - Slot Leak Recovery

    public func sanitizeStaleSlots() {
        queue.sync {
            let now = Date()
            var leakedRoutes: [String] = []
            for (key, sinceDate) in inflightSince {
                let heldDuration = now.timeIntervalSince(sinceDate)
                if heldDuration > slotLeakThreshold {
                    leakedRoutes.append(key)
                }
            }
            for key in leakedRoutes {
                let previousCount = inflightCounts[key] ?? 0
                inflightCounts[key] = 0
                inflightSince.removeValue(forKey: key)
                NSLog("[RouteConcurrencyLimiter] Concurrency: recovered %d leaked slot(s) for route %@ (held for >%.0fs)", previousCount, key, slotLeakThreshold)
            }
        }
    }

    // MARK: - Testing

    public func resetForTesting() {
        queue.sync {
            inflightCounts.removeAll()
            inflightSince.removeAll()
            discoveredLimits.removeAll()
            discoveredLimitUpdatedAt.removeAll()
            consecutiveSuccessesAtLimit.removeAll()
            concurrent429Buckets.removeAll()
        }
    }

    public func forceDiscoveredLimitForTesting(routeHealthKey: String, limit: Int) {
        queue.sync {
            discoveredLimits[routeHealthKey] = limit
            discoveredLimitUpdatedAt[routeHealthKey] = Date()
        }
    }

    // MARK: - Persistence

    public func persistLocked(into payload: inout [String: Any]) {
        let (limits, metadata): ([String: Int], [String: [String: String]]) = queue.sync {
            let effectiveRoutes = discoveredLimits.keys.compactMap { routeHealthKey -> (String, Int, Date?)? in
                let limit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
                guard limit != defaultConcurrencyLimit else {
                    return nil
                }
                return (routeHealthKey, limit, discoveredLimitUpdatedAt[routeHealthKey])
            }

            let limits = effectiveRoutes.reduce(into: [String: Int]()) { partial, route in
                partial[route.0] = route.1
            }
            let metadata = effectiveRoutes.reduce(into: [String: [String: String]]()) { partial, route in
                guard let updatedAt = route.2 else { return }
                partial[route.0] = [
                    "updated_at": Self.isoFormatter.string(from: updatedAt)
                ]
            }
            return (limits, metadata)
        }
        guard !limits.isEmpty else { return }
        payload["discovered_concurrency_limits"] = limits
        if !metadata.isEmpty {
            payload["discovered_concurrency_limit_metadata"] = metadata
        }
    }

    public func loadLocked(from json: [String: Any], persistedVersion: Int) {
        guard let limits = json["discovered_concurrency_limits"] as? [String: Int] else { return }
        queue.sync {
            if let metadata = json["discovered_concurrency_limit_metadata"] as? [String: [String: String]] {
                discoveredLimits = limits.filter { _, limit in
                    !(persistedVersion < 5 && limit <= 1)
                }
                discoveredLimitUpdatedAt = metadata.reduce(into: [String: Date]()) { partial, entry in
                    guard discoveredLimits[entry.key] != nil else { return }
                    guard let rawTimestamp = entry.value["updated_at"],
                          let updatedAt = Self.isoFormatter.date(from: rawTimestamp) else {
                        return
                    }
                    partial[entry.key] = updatedAt
                }
            } else {
                discoveredLimits = limits.filter { $0.value >= defaultConcurrencyLimit }
                discoveredLimitUpdatedAt = [:]
            }
        }
    }

    // MARK: - Private

    private func successGrowthThreshold(for learnedLimit: Int) -> Int {
        if learnedLimit <= 1 {
            return lowLimitSuccessGrowthThreshold
        }
        if learnedLimit == 2 {
            return mediumLimitSuccessGrowthThreshold
        }
        return successGrowthThreshold
    }

    private func resetLearnedLimitLocked(routeHealthKey: String) {
        discoveredLimits.removeValue(forKey: routeHealthKey)
        discoveredLimitUpdatedAt.removeValue(forKey: routeHealthKey)
        consecutiveSuccessesAtLimit.removeValue(forKey: routeHealthKey)
        concurrent429Buckets.removeValue(forKey: routeHealthKey)
    }

    private func inferredLimitFromConcurrency429(inflightAtRequest: Int) -> Int? {
        guard inflightAtRequest > 1 else {
            return nil
        }
        return max(1, inflightAtRequest - 1)
    }

    private func effectiveLimitLocked(routeHealthKey: String, now: Date = Date()) -> Int {
        guard let learnedLimit = discoveredLimits[routeHealthKey] else {
            return defaultConcurrencyLimit
        }

        if learnedLimit < defaultConcurrencyLimit,
           let updatedAt = discoveredLimitUpdatedAt[routeHealthKey],
           now.timeIntervalSince(updatedAt) >= learnedLowLimitTTL {
            resetLearnedLimitLocked(routeHealthKey: routeHealthKey)
            return defaultConcurrencyLimit
        }

        return learnedLimit
    }
}
