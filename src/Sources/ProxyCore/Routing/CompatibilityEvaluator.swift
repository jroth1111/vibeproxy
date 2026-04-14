import Foundation

public final class CompatibilityEvaluator {
    public enum CompatibilityResult: Equatable {
        case compatible
        case incompatible(reason: String)
    }

    public init() {}

    public func evaluate(
        providerID: String,
        shape: RequestShape,
        isNVIDIADirect: Bool
    ) -> CompatibilityResult {
        if isNVIDIADirect && shape.contentClass == .typedContent && shape.isStreaming {
            return .compatible
        }
        return .compatible
    }

    public func isNVIDIAResponsesRestricted(providerID: String, path: String) -> Bool {
        path.contains("/responses") && providerID.contains("nvidia")
    }
}
