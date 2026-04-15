import Foundation

public final class RouteHealthStore {
    private var circuitStatesByRouteHealthKey: [String: RouteCircuitState] = [:]
    private var cooldownsByRouteHealthKey: [String: Date] = [:]
    private let queue = DispatchQueue(label: "io.automaze.vibeproxy.route-health-store")

    public init() {}

    // MARK: - Circuit State

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

    // MARK: - Cooldowns

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

    // MARK: - Reset

    public func clearAll() {
        queue.sync {
            circuitStatesByRouteHealthKey = [:]
            cooldownsByRouteHealthKey = [:]
        }
    }

    // MARK: - Testing

    public func resetForTesting() {
        clearAll()
    }
}
