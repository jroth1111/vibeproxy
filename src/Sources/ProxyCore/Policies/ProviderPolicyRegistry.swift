import Foundation

public final class ProviderPolicyRegistry {
    public struct ProviderCompatibilityRules {
        public let supportsStreaming: Bool
        public let supportsToolCalls: Bool
        public let supportsResponses: Bool
        public let requiresAPIKey: Bool
        public let supportsReasoningEffort: Bool

        public init(
            supportsStreaming: Bool = true,
            supportsToolCalls: Bool = true,
            supportsResponses: Bool = false,
            requiresAPIKey: Bool = true,
            supportsReasoningEffort: Bool = true
        ) {
            self.supportsStreaming = supportsStreaming
            self.supportsToolCalls = supportsToolCalls
            self.supportsResponses = supportsResponses
            self.requiresAPIKey = requiresAPIKey
            self.supportsReasoningEffort = supportsReasoningEffort
        }
    }

    private var compatibilityRulesByProviderID: [String: ProviderCompatibilityRules] = [:]
    private var retryableHTTPStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private var retryableTransportErrorCodes: Set<Int> = []

    public init() {}

    public func load(
        compatibilityRules: [String: ProviderCompatibilityRules] = [:],
        retryableHTTPStatusCodes: Set<Int>? = nil,
        retryableTransportErrorCodes: Set<Int>? = nil
    ) {
        self.compatibilityRulesByProviderID = compatibilityRules
        if let codes = retryableHTTPStatusCodes { self.retryableHTTPStatusCodes = codes }
        if let codes = retryableTransportErrorCodes { self.retryableTransportErrorCodes = codes }
    }

    // MARK: - Compatibility

    public func compatibilityRules(forProviderID providerID: String) -> ProviderCompatibilityRules {
        compatibilityRulesByProviderID[providerID] ?? ProviderCompatibilityRules()
    }

    // MARK: - Retry Status Codes

    public func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        retryableHTTPStatusCodes.contains(statusCode)
    }

    public func isRetryableTransportErrorCode(_ code: Int) -> Bool {
        retryableTransportErrorCodes.contains(code)
    }
}
