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

    public func allCircuitStates() -> [String: RouteCircuitState] {
        queue.sync { circuitStatesByRouteHealthKey }
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

    // MARK: - Availability

    public func isRouteAvailable(_ key: String, at now: Date) -> Bool {
        queue.sync {
            if let cooldown = cooldownsByRouteHealthKey[key], now < cooldown { return false }
            if let state = circuitStatesByRouteHealthKey[key] { return !state.isUnavailable(at: now) }
            return true
        }
    }

    // MARK: - Health Status Query

    public func healthStatus(forRouteHealthKey key: String) -> RouteHealthStatus {
        queue.sync {
            circuitStatesByRouteHealthKey[key]?.status ?? .closed
        }
    }
}
