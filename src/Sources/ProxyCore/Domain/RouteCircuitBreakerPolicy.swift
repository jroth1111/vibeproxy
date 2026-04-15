import Foundation

public struct RouteCircuitBreakerPolicy {
    public let failureThreshold: Double
    public let cooldown: TimeInterval
    public let recoverySuccessThreshold: Int

    public init(failureThreshold: Double, cooldown: TimeInterval, recoverySuccessThreshold: Int) {
        self.failureThreshold = failureThreshold
        self.cooldown = cooldown
        self.recoverySuccessThreshold = recoverySuccessThreshold
    }
}
