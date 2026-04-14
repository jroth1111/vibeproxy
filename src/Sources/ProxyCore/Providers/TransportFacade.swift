import Foundation

public final class TransportFacade {
    public struct TransportConfig {
        public let attemptTimeout: TimeInterval?
        public let firstResponseDeadline: TimeInterval?
        public let bufferedResponseDeadline: TimeInterval?

        public init(
            attemptTimeout: TimeInterval? = nil,
            firstResponseDeadline: TimeInterval? = nil,
            bufferedResponseDeadline: TimeInterval? = nil
        ) {
            self.attemptTimeout = attemptTimeout
            self.firstResponseDeadline = firstResponseDeadline
            self.bufferedResponseDeadline = bufferedResponseDeadline
        }
    }

    public init() {}

    public func configForRoute(
        policy: RequestPolicy,
        scaledBy timeoutScale: TimeInterval = 3.0
    ) -> TransportConfig {
        TransportConfig(
            attemptTimeout: policy.attemptTimeout,
            firstResponseDeadline: policy.firstResponseDeadline,
            bufferedResponseDeadline: policy.bufferedResponseDeadline
        )
    }
}
