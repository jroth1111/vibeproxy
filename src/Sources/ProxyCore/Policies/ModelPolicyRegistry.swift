import Foundation

public final class ModelPolicyRegistry {
    private var nvidiaPoliciesByCanonicalModelID: [String: RequestPolicy] = [:]
    private var nonNVIDIAMitigationPoliciesByRequestModel: [String: RequestPolicy] = [:]
    private var modelTiersByCanonicalModelID: [String: ModelTier] = [:]
    private var inputPricesByCanonicalModelID: [String: Double] = [:]
    private var legacyRewrites: [String: String] = [:]
    private var workerSmartRoutePolicy: RequestPolicy?

    public init() {}

    public func load(
        nvidiaPolicies: [(String, RequestPolicy)],
        nonNVIDIAMitigationPolicies: [(String, RequestPolicy)],
        modelTiers: [(String, ModelTier)],
        inputPrices: [(String, Double)],
        legacyRewrites: [(String, String)],
        workerSmartRoutePolicy: RequestPolicy?
    ) {
        self.nvidiaPoliciesByCanonicalModelID = Self.deduplicate(nvidiaPolicies, label: "nvidiaPolicies")
        self.nonNVIDIAMitigationPoliciesByRequestModel = Self.deduplicate(nonNVIDIAMitigationPolicies, label: "nonNVIDIAMitigationPolicies")
        self.modelTiersByCanonicalModelID = Self.deduplicate(modelTiers, label: "modelTiers")
        self.inputPricesByCanonicalModelID = Self.deduplicate(inputPrices, label: "inputPrices")
        self.legacyRewrites = Self.deduplicate(legacyRewrites, label: "legacyRewrites")
        self.workerSmartRoutePolicy = workerSmartRoutePolicy
    }

    // MARK: - NVIDIA Policy Lookup

    public func nvidiaPolicy(forCanonicalModelID modelID: String) -> RequestPolicy? {
        nvidiaPoliciesByCanonicalModelID[modelID]
    }

    public func allNVIDIAPolicies() -> [String: RequestPolicy] {
        nvidiaPoliciesByCanonicalModelID
    }

    // MARK: - Non-NVIDIA Mitigation Policy Lookup

    public func nonNVIDIAMitigationPolicy(forRequestModel model: String) -> RequestPolicy? {
        nonNVIDIAMitigationPoliciesByRequestModel[model]
    }

    public func workerSmartRouteRequestPolicy() -> RequestPolicy? {
        workerSmartRoutePolicy
    }

    // MARK: - Model Tier Lookup

    public func modelTier(forCanonicalModelID modelID: String) -> ModelTier? {
        modelTiersByCanonicalModelID[modelID]
    }

    // MARK: - Pricing

    public func inputPricePerMillionTokens(forCanonicalModelID modelID: String) -> Double? {
        inputPricesByCanonicalModelID[modelID]
    }

    public func costFactor(forCanonicalModelID modelID: String) -> Double {
        let price = inputPricesByCanonicalModelID[modelID] ?? 5.0
        return 1.0 / (price + 0.01)
    }

    // MARK: - Legacy Rewrites

    public func rewrittenModel(_ model: String) -> String? {
        legacyRewrites[model]
    }

    // MARK: - Deduplication

    private static func deduplicate<V>(_ entries: [(String, V)], label: String) -> [String: V] {
        var result: [String: V] = [:]
        for (key, value) in entries {
            guard result[key] == nil else { continue }
            result[key] = value
        }
        return result
    }
}
