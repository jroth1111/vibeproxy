import Foundation

public enum Provider429Disposition: Equatable {
    case overload(retryDelaySeconds: TimeInterval)
    case concurrency(retryAfterSeconds: TimeInterval?)
    case quotaWindow(cooldownUntil: Date)
}
