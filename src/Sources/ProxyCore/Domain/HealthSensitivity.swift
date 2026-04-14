public enum HealthSensitivity: String {
    case eager = "eager"
    case balanced = "balanced"
    case conservative = "conservative"

    public var scoreGapThreshold: Double {
        switch self {
        case .eager: return 200.0
        case .balanced: return 500.0
        case .conservative: return 2000.0
        }
    }

    public var failureThresholdScaleFactor: Double {
        switch self {
        case .eager: return 0.5
        case .balanced: return 1.0
        case .conservative: return 2.0
        }
    }
}
