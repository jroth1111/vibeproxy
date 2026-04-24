import Foundation

public enum ManagedRouteManifest {
    // MARK: - Route Policy Entries

    public static let nvidiaRoutePolicyEntries: [(String, RequestPolicy)] = [
        ("z-ai/glm-5.1", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos", "max_completion_tokens", "max_output_tokens", "stream_options"],
            attemptTimeout: 900,
            firstResponseDeadline: 720,
            bufferedResponseDeadline: 855,
            transportRetries: 0,
            semanticRetries: 1,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments, .successShapedFailure, .inputEcho, .specialTokenLeak],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .rejectBufferedMitigation,
            toolChoiceMode: .rejectRequiredOrFunctionChoice,
            forcesKimiInstantMode: false
        )),
        ("moonshotai/kimi-k2.5", RequestPolicy(
            minimumMaxTokens: 384,
            maximumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos", "max_completion_tokens", "max_output_tokens", "stream_options"],
            attemptTimeout: 540,
            firstResponseDeadline: 360,
            bufferedResponseDeadline: 450,
            transportRetries: 0,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments, .successShapedFailure, .inputEcho, .specialTokenLeak],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .rejectBufferedMitigation,
            toolChoiceMode: .rejectRequiredOrFunctionChoice,
            forcesKimiInstantMode: true
        )),
        ("minimaxai/minimax-m2.7", RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: 65536,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos", "max_completion_tokens", "max_output_tokens", "stream_options"],
            attemptTimeout: 900,
            firstResponseDeadline: 720,
            bufferedResponseDeadline: 855,
            transportRetries: 0,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments, .successShapedFailure, .repetitionLoop, .inputEcho, .specialTokenLeak, .whitespaceCollapse],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: true,
            salvagesBestEffortRepair: true,
            clientStreamingMode: .rejectBufferedMitigation,
            toolChoiceMode: .rejectRequiredOrFunctionChoice,
            forcesKimiInstantMode: false
        ))
    ]

    public static let workerSmartRouteRequestPolicy = RequestPolicy(
        minimumMaxTokens: 128,
        maximumMaxTokens: nil,
        strippedFields: [],
        attemptTimeout: 900,
        firstResponseDeadline: 180,
        bufferedResponseDeadline: 540,
        transportRetries: 2,
        semanticRetries: 2,
        retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
        retryBackoffMilliseconds: 250,
        stripsReasoningFieldFromSuccess: false,
        allowsThinkLeakRepair: false,
        salvagesBestEffortRepair: false,
        clientStreamingMode: .preserve,
        toolChoiceMode: .preserve,
        forcesKimiInstantMode: false
    )

    public static let nonNVIDIAMitigationPolicyEntries: [(String, RequestPolicy)] = [
        ("glm-4.7", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 600,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        )),
        ("glm-5", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 600,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        )),
        ("glm-5.1", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 600,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        )),
        ("proxy-worker-smart-router", workerSmartRouteRequestPolicy),
        ("gpt-5.5(high)", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 900,
            firstResponseDeadline: 180,
            bufferedResponseDeadline: 540,
            transportRetries: 2,
            semanticRetries: 0,
            retryableFailureClasses: [.emptyBody, .emptyContent],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ))
    ]

    // MARK: - Model Tiers

    public static let modelTierEntries: [(String, ModelTier)] = [
        ("z-ai/glm-5.1", .reasoning),
        ("moonshotai/kimi-k2.5", .reasoning),
        ("minimaxai/minimax-m2.7", .standard),
    ]

    // MARK: - Input Pricing

    public static let inputPricePerMillionTokensEntries: [(String, Double)] = [
        ("z-ai/glm-5.1", 0.0),
        ("moonshotai/kimi-k2.5", 0.0),
        ("minimaxai/minimax-m2.7", 0.0),
        ("ollama-pro/glm-5.1", 0.0),
        ("ollama-pro/minimax-m2.7", 0.0),
    ]

    public static let costSensitivity: Double = 0.3

    // MARK: - Legacy Model Rewrites

    public static let legacyRequestModelRewriteEntries: [(String, String)] = [
        ("glm5", "glm-5.1"),
        ("glm5-nvidia", "glm-5.1-nvidia"),
        ("glm5-nvidia-direct", "glm-5.1-nvidia-direct"),
        ("glm5-nvidia-smart", "glm-5.1-nvidia-smart"),
        ("z-ai/glm5", "glm-5.1-nvidia"),
        ("glm-5", "glm-5.1"),
        ("glm-5-turbo", "glm-5.1"),
        ("z-ai/glm-5.1", "glm-5.1-nvidia"),
        ("moonshotai/kimi-k2.5", "kimi-k2.5-nvidia")
    ]

    // MARK: - NVIDIA Direct Aliases

    public static let publicGLM5NVIDIADirectAlias = "glm-5.1-nvidia"
    public static let publicKimiNVIDIADirectAlias = "kimi-k2.5-nvidia"
    public static let publicGLM5NVIDIASmartAlias = "glm-5.1-nvidia-smart"
    public static let publicKimiNVIDIASmartAlias = "kimi-k2.5-nvidia-smart"
    public static let debugGLM5NVIDIADirectAlias = "glm-5.1-nvidia-direct"
    public static let debugKimiNVIDIADirectAlias = "kimi-k2.5-nvidia-direct"
    public static let directNVIDIAAccessHeader = "X-VibeProxy-Allow-Direct-NVIDIA"

    public static let publicDirectNVIDIAAliasByCanonicalModelID: [String: String] = [
        "z-ai/glm-5.1": publicGLM5NVIDIADirectAlias,
        "moonshotai/kimi-k2.5": publicKimiNVIDIADirectAlias
    ]
    public static let publicDirectNVIDIAAliases: Set<String> = Set(publicDirectNVIDIAAliasByCanonicalModelID.values)
    public static let debugDirectNVIDIAAliasByPublicAlias: [String: String] = [
        publicGLM5NVIDIADirectAlias: debugGLM5NVIDIADirectAlias,
        publicKimiNVIDIADirectAlias: debugKimiNVIDIADirectAlias
    ]
    public static let publicDirectNVIDIAAliasByDebugAlias: [String: String] = [
        debugGLM5NVIDIADirectAlias: publicGLM5NVIDIADirectAlias,
        debugKimiNVIDIADirectAlias: publicKimiNVIDIADirectAlias
    ]
    public static let debugDirectNVIDIAAliases: Set<String> = Set(publicDirectNVIDIAAliasByDebugAlias.keys)

    // MARK: - Smart NVIDIA Aliases

    public static let publicSmartNVIDIACandidateModelsByAlias: [String: [String]] = [
        publicGLM5NVIDIASmartAlias: [
            publicGLM5NVIDIADirectAlias,
            "glm-5.1-zai",
            "glm-5.1-ollama-pro",
            "minimax-m2.7-ollama-pro",
            "muse-spark"
        ],
        publicKimiNVIDIASmartAlias: [
            publicKimiNVIDIADirectAlias,
            "glm-5.1-zai",
            "glm-5.1-ollama-pro",
            "minimax-m2.7-ollama-pro",
            "muse-spark"
        ]
    ]
    public static let publicSmartNVIDIAAliasByDirectAlias: [String: String] = [
        publicGLM5NVIDIADirectAlias: publicGLM5NVIDIASmartAlias,
        publicKimiNVIDIADirectAlias: publicKimiNVIDIASmartAlias
    ]

    // MARK: - Worker Pool

    public static let publicFactoryWorkerSmartRouterAlias = "proxy-worker-smart-router"
    public static let canonicalFactoryWorkerModelID = "custom:Proxy-Worker-Smart-Router-8"
    public static let canonicalWorkerPoolCandidates = ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm-5.1-nvidia", "kimi-k2.5-nvidia", "minimax-m2.7-nvidia"]
    public static let publicWorkerPoolAliases: Set<String> = [
        "worker",
        "glm-5.1",
        publicFactoryWorkerSmartRouterAlias
    ]
    public static let codeOwnedFactoryWorkerRescueModelIDs: Set<String> = [
        "custom:GPT-5.4-High-Proxy-2",
        "custom:Factory-Worker-GPT-5.5-High-8",
        "custom:Factory-Worker-GPT-5.4-High-8",
        "custom:Proxy-WorkerPool-8"
    ]
}
