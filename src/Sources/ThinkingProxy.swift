import Foundation
import Network

enum OpenAICompatTemporaryShim {
    struct ClientFacingNVIDIAFailure {
        let statusCode: Int
        let message: String
        let reasonCode: String?

        init(statusCode: Int, message: String, reasonCode: String? = nil) {
            self.statusCode = statusCode
            self.message = message
            self.reasonCode = reasonCode
        }
    }

    struct NvidiaReasoningEvaluation {
        let failureClass: FailureClass?
        let repairedBodyData: Data?
        let normalizedBodyData: Data?

        var retryReason: String? {
            failureClass?.rawValue
        }

        var shouldRetry: Bool {
            failureClass != nil
        }
    }

    struct ResponseDeadlineTracker {
        private(set) var hasReceivedPayload = false
        private(set) var deadlineExceeded = false
        private(set) var isFinished = false
        private(set) var deadlineStage: DeadlineStage = .none

        mutating func firstResponseDeadlineDidFire() -> Bool {
            guard !hasReceivedPayload, !isFinished else {
                return false
            }
            deadlineExceeded = true
            deadlineStage = .firstResponse
            return true
        }

        mutating func bufferedResponseDeadlineDidFire() -> Bool {
            guard !isFinished else {
                return false
            }
            deadlineExceeded = true
            deadlineStage = .bufferedResponse
            return true
        }

        mutating func interChunkReadDeadlineDidFire() -> Bool {
            guard hasReceivedPayload, !isFinished else {
                return false
            }
            deadlineExceeded = true
            deadlineStage = .interChunkRead
            return true
        }

        mutating func payloadReceived() {
            hasReceivedPayload = true
        }

        mutating func finish() {
            isFinished = true
            hasReceivedPayload = true
        }
    }

    enum SemanticFailureDisposition {
        case retry(nextSemanticRetriesRemaining: Int, preservedBestEffortRepair: Data?)
        case returnRepaired(Data)
        case returnGatewayError
    }

    enum TransportFailureDisposition {
        case retry(nextTransportRetriesRemaining: Int)
        case returnRepaired(Data)
        case returnGatewayError(statusCode: Int, message: String)
    }

    enum DeadlineStage: String {
        case none = "none"
        case firstResponse = "first_response"
        case bufferedResponse = "buffered_response"
        case interChunkRead = "inter_chunk_read"
    }

    struct RouteTelemetryEvent: Equatable {
        let timestamp: Date
        let requestModel: String
        let requestedAlias: String?
        let canonicalModelID: String
        let transportOutcome: String
        let healthTransition: String?
        let attemptLane: Int
        let winnerAttemptLane: Int?
        let failoverDepth: Int?
        let finalWinnerRequestModel: String?
        let failureClass: String?
        let timeoutStage: DeadlineStage
        let upstreamHTTPStatus: Int?
        let retryCount: Int
        let source: String
        let firstByteLatencyMilliseconds: Int?
        let totalLatencyMilliseconds: Int?
        let inflightAtRequest: Int?
        let proxyRequestID: String?
        let callerRequestID: String?
        let callerSessionID: String?
        let requestShape: String?
        let negotiatedApplicationProtocol: String?
        let errorBodySnippet: String?

        init(
            timestamp: Date,
            requestModel: String,
            requestedAlias: String? = nil,
            canonicalModelID: String,
            transportOutcome: String,
            healthTransition: String? = nil,
            attemptLane: Int = 1,
            winnerAttemptLane: Int? = nil,
            failoverDepth: Int? = nil,
            finalWinnerRequestModel: String? = nil,
            failureClass: String?,
            timeoutStage: DeadlineStage,
            upstreamHTTPStatus: Int?,
            retryCount: Int,
            source: String,
            firstByteLatencyMilliseconds: Int? = nil,
            totalLatencyMilliseconds: Int? = nil,
            inflightAtRequest: Int? = nil,
            proxyRequestID: String? = nil,
            callerRequestID: String? = nil,
            callerSessionID: String? = nil,
            requestShape: String? = nil,
            negotiatedApplicationProtocol: String? = nil,
            errorBodySnippet: String? = nil
        ) {
            self.timestamp = timestamp
            self.requestModel = requestModel
            self.requestedAlias = requestedAlias
            self.canonicalModelID = canonicalModelID
            self.transportOutcome = transportOutcome
            self.healthTransition = healthTransition
            self.attemptLane = attemptLane
            self.winnerAttemptLane = winnerAttemptLane
            self.failoverDepth = failoverDepth
            self.finalWinnerRequestModel = finalWinnerRequestModel
            self.failureClass = failureClass
            self.timeoutStage = timeoutStage
            self.upstreamHTTPStatus = upstreamHTTPStatus
            self.retryCount = retryCount
            self.source = source
            self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
            self.totalLatencyMilliseconds = totalLatencyMilliseconds
            self.inflightAtRequest = inflightAtRequest
            self.proxyRequestID = proxyRequestID
            self.callerRequestID = callerRequestID
            self.callerSessionID = callerSessionID
            self.requestShape = requestShape
            self.negotiatedApplicationProtocol = negotiatedApplicationProtocol
            self.errorBodySnippet = errorBodySnippet
        }
    }

    struct NVIDIARetryState: Equatable {
        let model: String
        let requiredToolParameters: [String: [String]]?
        let initialTransportRetries: Int
        let initialSemanticRetries: Int
        var transportRetriesRemaining: Int
        var semanticRetriesRemaining: Int
        let retryBackoffMilliseconds: Int
        let salvagesBestEffortRepair: Bool
        var bestEffortRepairedBodyData: Data?
        let coalescingKey: String?

        init(
            model: String,
            requiredToolParameters: [String: [String]]? = nil,
            initialTransportRetries: Int,
            initialSemanticRetries: Int,
            transportRetriesRemaining: Int,
            semanticRetriesRemaining: Int,
            retryBackoffMilliseconds: Int,
            salvagesBestEffortRepair: Bool,
            bestEffortRepairedBodyData: Data?,
            coalescingKey: String? = nil
        ) {
            self.model = model
            self.requiredToolParameters = requiredToolParameters
            self.initialTransportRetries = initialTransportRetries
            self.initialSemanticRetries = initialSemanticRetries
            self.transportRetriesRemaining = transportRetriesRemaining
            self.semanticRetriesRemaining = semanticRetriesRemaining
            self.retryBackoffMilliseconds = retryBackoffMilliseconds
            self.salvagesBestEffortRepair = salvagesBestEffortRepair
            self.bestEffortRepairedBodyData = bestEffortRepairedBodyData
            self.coalescingKey = coalescingKey
        }
    }

    struct NVIDIAAttemptResult {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
        let deadlineStage: DeadlineStage
        let firstByteLatencyMilliseconds: Int?
        let totalLatencyMilliseconds: Int?
        let negotiatedApplicationProtocol: String?

        init(
            data: Data?,
            response: HTTPURLResponse?,
            error: Error?,
            deadlineStage: DeadlineStage,
            firstByteLatencyMilliseconds: Int? = nil,
            totalLatencyMilliseconds: Int? = nil,
            negotiatedApplicationProtocol: String? = nil
        ) {
            self.data = data
            self.response = response
            self.error = error
            self.deadlineStage = deadlineStage
            self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
            self.totalLatencyMilliseconds = totalLatencyMilliseconds
            self.negotiatedApplicationProtocol = negotiatedApplicationProtocol
        }
    }

    enum NVIDIARuntimeOutcome {
        case retry(NVIDIARetryState)
        case sendResponse(statusCode: Int, headers: [AnyHashable: Any], body: Data)
        case sendError(statusCode: Int, message: String)
    }

    struct RouteIdentity: Equatable {
        let providerID: String
        let canonicalModelID: String

        var routeHealthKey: String {
            "\(providerID)::\(canonicalModelID)"
        }
    }

    struct ProviderEndpoint: Equatable {
        let providerID: String
        let baseURL: String
        let proxyURL: String
        let apiKey: String?
    }

    struct SmartAliasDefinition: Equatable {
        let alias: String
        let requestClass: String
        let failover: String
        let candidates: [String]
        let healthSensitivity: HealthSensitivity
    }

    enum HealthSensitivity: String {
        case eager = "eager"
        case balanced = "balanced"
        case conservative = "conservative"

        var scoreGapThreshold: Double {
            switch self {
            case .eager: return 200.0
            case .balanced: return 500.0
            case .conservative: return 2000.0
            }
        }

        var failureThresholdScaleFactor: Double {
            switch self {
            case .eager: return 0.5
            case .balanced: return 1.0
            case .conservative: return 2.0
            }
        }
    }

    enum RouteHealthStatus: String {
        case closed = "closed"
        case suspect = "suspect"
        case open = "open"
        case halfOpen = "half_open"
    }

    struct RouteRollingMetrics: Equatable {
        let recentOutcomes: [String]
        let recentFirstByteLatencyMilliseconds: [Int]
        let recentTotalLatencyMilliseconds: [Int]

        init(
            recentOutcomes: [String],
            recentFirstByteLatencyMilliseconds: [Int],
            recentTotalLatencyMilliseconds: [Int] = []
        ) {
            self.recentOutcomes = recentOutcomes
            self.recentFirstByteLatencyMilliseconds = recentFirstByteLatencyMilliseconds
            self.recentTotalLatencyMilliseconds = recentTotalLatencyMilliseconds
        }

        static let empty = RouteRollingMetrics(
            recentOutcomes: [],
            recentFirstByteLatencyMilliseconds: [],
            recentTotalLatencyMilliseconds: []
        )

        var timeoutRate: Double {
            guard !recentOutcomes.isEmpty else { return 0 }
            let timeouts = recentOutcomes.filter { $0.contains(":transport_timeout") }.count
            return Double(timeouts) / Double(recentOutcomes.count)
        }

        var invalidSuccessRate: Double {
            guard !recentOutcomes.isEmpty else { return 0 }
            let invalid = recentOutcomes.filter { $0.hasPrefix("send_response:") }.count
            return Double(invalid) / Double(recentOutcomes.count)
        }

        var averageFirstByteLatencyMilliseconds: Int? {
            guard !recentFirstByteLatencyMilliseconds.isEmpty else { return nil }
            let total = recentFirstByteLatencyMilliseconds.reduce(0, +)
            return total / recentFirstByteLatencyMilliseconds.count
        }

        var averageTotalLatencyMilliseconds: Int? {
            guard !recentTotalLatencyMilliseconds.isEmpty else { return nil }
            let total = recentTotalLatencyMilliseconds.reduce(0, +)
            return total / recentTotalLatencyMilliseconds.count
        }

        var p95FirstByteLatencyMilliseconds: Int? {
            percentileLatencyMilliseconds(recentFirstByteLatencyMilliseconds, percentile: 0.95)
        }

        var p95TotalLatencyMilliseconds: Int? {
            percentileLatencyMilliseconds(recentTotalLatencyMilliseconds, percentile: 0.95)
        }
    }

    struct RouteEMAMetrics: Equatable {
        let successRate: Double
        let averageLatencyMs: Double
        let observationCount: Int

        static let empty = RouteEMAMetrics(successRate: 1.0, averageLatencyMs: 0.0, observationCount: 0)

        private static let emaBaseAlpha = 0.2
        private static let emaMinObservationsForStable = 10.0

        private var effectiveAlpha: Double {
            let count = Double(observationCount)
            guard count < Self.emaMinObservationsForStable else { return Self.emaBaseAlpha }
            return min(1.0, Self.emaBaseAlpha + (1.0 - Self.emaBaseAlpha) * (1.0 - count / Self.emaMinObservationsForStable))
        }

        func updated(isSuccess: Bool, latencyMs: Int?) -> RouteEMAMetrics {
            let alpha = effectiveAlpha
            let newSuccessRate = successRate * (1.0 - alpha) + (isSuccess ? 1.0 : 0.0) * alpha
            let newLatency: Double
            if let latencyMs {
                newLatency = averageLatencyMs * (1.0 - alpha) + Double(latencyMs) * alpha
            } else {
                newLatency = averageLatencyMs
            }
            return RouteEMAMetrics(successRate: newSuccessRate, averageLatencyMs: newLatency, observationCount: observationCount + 1)
        }

        var compositeScore: Double {
            guard observationCount > 0 else { return 500.0 }
            return successRate * successRate * 1000.0 - averageLatencyMs
        }

        var isProvenPerfect: Bool {
            observationCount > 0 && successRate >= 0.999
        }
    }

    struct RouteLatencyDiagnostics: Equatable {
        let averageFirstByteLatencyMilliseconds: Int?
        let p95FirstByteLatencyMilliseconds: Int?
        let averageTotalLatencyMilliseconds: Int?
        let p95TotalLatencyMilliseconds: Int?
        let slowFirstByteThresholdMilliseconds: Int?
        let slowTotalThresholdMilliseconds: Int?
        let pressureStatus: String
    }

    enum NVIDIAInferenceProbeStatus: String {
        case success = "success"
        case failure = "failure"
    }

    struct NVIDIAInferenceProbeState: Equatable {
        let lastProbeAt: Date
        let lastStatus: NVIDIAInferenceProbeStatus
        let lastSuccessAt: Date?
        let lastFailureAt: Date?
        let lastFailureClass: String?
        let lastTimeoutStage: DeadlineStage
        let lastUpstreamHTTPStatus: Int?
        let lastTransportOutcome: String
        let lastFirstByteLatencyMilliseconds: Int?
        let lastTotalLatencyMilliseconds: Int?
    }

    private static func percentileLatencyMilliseconds(_ samples: [Int], percentile: Double) -> Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let clampedPercentile = min(max(percentile, 0), 1)
        let index = Int(ceil(Double(sorted.count - 1) * clampedPercentile))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }

    struct RouteCircuitState: Equatable {
        let status: RouteHealthStatus
        let failureScore: Double
        let recoverySuccesses: Int
        let openUntil: Date?
        let lastScoreUpdatedAt: Date?
        let lastTelemetryEvent: RouteTelemetryEvent?
        let rollingMetrics: RouteRollingMetrics
        let emaMetrics: RouteEMAMetrics
        let recoveredAt: Date?
        let lastSuccessAt: Date?
        let lastLiveSuccessAt: Date?
        let lastSuccessRequestID: String?
        let lastFailureAt: Date?
        let lastFailureClass: String?
        let nvidiaInferenceProbe: NVIDIAInferenceProbeState?

        init(
            status: RouteHealthStatus,
            failureScore: Double,
            recoverySuccesses: Int,
            openUntil: Date?,
            lastScoreUpdatedAt: Date?,
            lastTelemetryEvent: RouteTelemetryEvent?,
            rollingMetrics: RouteRollingMetrics,
            emaMetrics: RouteEMAMetrics,
            recoveredAt: Date?,
            lastSuccessAt: Date? = nil,
            lastLiveSuccessAt: Date? = nil,
            lastSuccessRequestID: String? = nil,
            lastFailureAt: Date? = nil,
            lastFailureClass: String? = nil,
            nvidiaInferenceProbe: NVIDIAInferenceProbeState? = nil
        ) {
            self.status = status
            self.failureScore = failureScore
            self.recoverySuccesses = recoverySuccesses
            self.openUntil = openUntil
            self.lastScoreUpdatedAt = lastScoreUpdatedAt
            self.lastTelemetryEvent = lastTelemetryEvent
            self.rollingMetrics = rollingMetrics
            self.emaMetrics = emaMetrics
            self.recoveredAt = recoveredAt
            self.lastSuccessAt = lastSuccessAt
            self.lastLiveSuccessAt = lastLiveSuccessAt
            self.lastSuccessRequestID = lastSuccessRequestID
            self.lastFailureAt = lastFailureAt
            self.lastFailureClass = lastFailureClass
            self.nvidiaInferenceProbe = nvidiaInferenceProbe
        }

        private static let momentumBaseBonus: Double = 50.0
        private static let momentumDecayPerSecond: Double = 0.95

        func momentumBonus(at now: Date) -> Double {
            guard status == .closed, let recoveredAt else { return 0.0 }
            let elapsed = now.timeIntervalSince(recoveredAt)
            guard elapsed > 0 else { return Self.momentumBaseBonus }
            return Self.momentumBaseBonus * pow(Self.momentumDecayPerSecond, elapsed)
        }

        func isUnavailable(at now: Date) -> Bool {
            switch status {
            case .closed, .suspect, .halfOpen:
                return false
            case .open:
                if let openUntil {
                    return now < openUntil
                }
                return true
            }
        }

        func isOpen(at now: Date) -> Bool {
            isUnavailable(at: now)
        }
    }

    private struct CachedRouteConfiguration {
        let configPath: String?
        let modificationDate: Date?
        let routesByRequestModel: [String: RouteIdentity]
        let nvidiaRoutesByRequestModel: [String: RouteIdentity]
        let anthropicRequestModels: Set<String>
        let smartAliasesByAlias: [String: SmartAliasDefinition]
        let providerEndpointsByProviderID: [String: ProviderEndpoint]
    }

    private struct RouteCircuitBreakerPolicy {
        let failureThreshold: Double
        let cooldown: TimeInterval
        let recoverySuccessThreshold: Int
    }

    private struct PersistentRouteHealthEntry {
        let status: RouteHealthStatus
        let failureScore: Double
        let recoverySuccesses: Int
        let openUntil: Date?
        let lastScoreUpdatedAt: Date?
        let lastTelemetryEvent: RouteTelemetryEvent?
        let rollingMetrics: RouteRollingMetrics
    }

    private enum ClientStreamingMode {
        case preserve
        case rejectBufferedMitigation
    }

    private enum ToolChoiceMode {
        case preserve
        case rejectRequiredOrFunctionChoice
    }

    private static func deduplicatedStaticLookup<Value>(
        _ entries: [(String, Value)],
        label: String
    ) -> [String: Value] {
        var result: [String: Value] = [:]
        var duplicateKeys: [String] = []
        for (key, value) in entries {
            guard result[key] == nil else {
                duplicateKeys.append(key)
                continue
            }
            result[key] = value
        }
        if !duplicateKeys.isEmpty {
            NSLog(
                "[ThinkingProxy] Deduplicated %d duplicate static lookup key(s) for %@: %@",
                duplicateKeys.count,
                label,
                duplicateKeys.joined(separator: ",")
            )
        }
        return result
    }

    static func deduplicatedStaticLookupForTesting(
        _ entries: [(String, String)],
        label: String = "test"
    ) -> [String: String] {
        deduplicatedStaticLookup(entries, label: label)
    }

    enum ModelTier: Double {
        case reasoning = 1.0
        case standard = 0.85
        case economy = 0.6
        case free = 0.4
    }

    enum FailureClass: String, Hashable {
        case emptyBody = "empty_body"
        case emptyContent = "empty_content"
        case reasoningOnlyContentMissing = "reasoning_only_content_missing"
        case reasoningLeakLength = "reasoning_leak_length"
        case reasoningLeakContent = "reasoning_leak_content"
        case malformedToolArguments = "malformed_tool_arguments"
        case invalidJson = "invalid_json"
        case missingChoices = "missing_choices"
    }

    enum Provider429Disposition: Equatable {
        case overload(retryDelaySeconds: TimeInterval)
        case concurrency(retryAfterSeconds: TimeInterval?)
        case quotaWindow(cooldownUntil: Date)
    }

    static let requestTimeoutScale: TimeInterval = 3

    static func scaledRequestTimeout(_ seconds: TimeInterval) -> TimeInterval {
        seconds * requestTimeoutScale
    }

    private static let knownNVIDIARoutePolicyEntries: [(String, RequestPolicy)] = [
        ("z-ai/glm5", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos", "max_completion_tokens", "max_output_tokens", "stream_options"],
            attemptTimeout: scaledRequestTimeout(300),
            firstResponseDeadline: scaledRequestTimeout(240),
            bufferedResponseDeadline: scaledRequestTimeout(285),
            transportRetries: 0,
            semanticRetries: 1,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
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
            attemptTimeout: scaledRequestTimeout(180),
            firstResponseDeadline: scaledRequestTimeout(120),
            bufferedResponseDeadline: scaledRequestTimeout(150),
            transportRetries: 0,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .rejectBufferedMitigation,
            toolChoiceMode: .rejectRequiredOrFunctionChoice,
            forcesKimiInstantMode: true
        )),
        ("minimaxai/minimax-m2.5", RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: 65536,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos", "max_completion_tokens", "max_output_tokens", "stream_options"],
            attemptTimeout: scaledRequestTimeout(300),
            firstResponseDeadline: scaledRequestTimeout(240),
            bufferedResponseDeadline: scaledRequestTimeout(285),
            transportRetries: 0,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: true,
            salvagesBestEffortRepair: true,
            clientStreamingMode: .rejectBufferedMitigation,
            toolChoiceMode: .rejectRequiredOrFunctionChoice,
            forcesKimiInstantMode: false
        ))
    ]
    private static let knownNVIDIARoutePoliciesByCanonicalModelID: [String: RequestPolicy] = deduplicatedStaticLookup(
        knownNVIDIARoutePolicyEntries,
        label: "knownNVIDIARoutePoliciesByCanonicalModelID"
    )
    private static let modelTierEntries: [(String, ModelTier)] = [
        ("z-ai/glm5", .reasoning),
        ("moonshotai/kimi-k2.5", .reasoning),
        ("minimaxai/minimax-m2.5", .standard),
    ]
    private static let modelTierByCanonicalModelID: [String: ModelTier] = deduplicatedStaticLookup(
        modelTierEntries,
        label: "modelTierByCanonicalModelID"
    )
    // Input price per million tokens (0.0 = free tier).  costFactor = 1/(price+0.01)
    // gives free models ~100x routing advantage over paid ($5/M) ones.
    private static let inputPricePerMillionTokensEntries: [(String, Double)] = [
        ("z-ai/glm5", 0.0),
        ("moonshotai/kimi-k2.5", 0.0),
        ("minimaxai/minimax-m2.5", 0.0),
        ("ollama-pro/glm-5.1", 0.0),
        ("ollama-pro/minimax-m2.7", 0.0),
    ]
    private static let inputPriceByCanonicalModelID: [String: Double] = deduplicatedStaticLookup(
        inputPricePerMillionTokensEntries,
        label: "inputPriceByCanonicalModelID"
    )
    private static let costSensitivity: Double = 0.3  // moderate: costFactor^0.3
    static let canaryDisabledCanonicalModelIDs: Set<String> = [MetaAIWebAdapter.modelAlias]
    private static let workerSmartRouteRequestPolicy = RequestPolicy(
        minimumMaxTokens: 128,
        maximumMaxTokens: nil,
        strippedFields: [],
        attemptTimeout: scaledRequestTimeout(300),
        firstResponseDeadline: scaledRequestTimeout(60),
        bufferedResponseDeadline: scaledRequestTimeout(180),
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

    private static let nonNVIDIAMitigationPolicyEntries: [(String, RequestPolicy)] = [
        ("glm-4.7", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: scaledRequestTimeout(200),
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
            attemptTimeout: scaledRequestTimeout(200),
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
            attemptTimeout: scaledRequestTimeout(200),
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
        ("gpt-5.4(high)", RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: scaledRequestTimeout(300),
            firstResponseDeadline: scaledRequestTimeout(60),
            bufferedResponseDeadline: scaledRequestTimeout(180),
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
    private static let nonNVIDIAMitigationPoliciesByRequestModel: [String: RequestPolicy] = deduplicatedStaticLookup(
        nonNVIDIAMitigationPolicyEntries,
        label: "nonNVIDIAMitigationPoliciesByRequestModel"
    )

    private struct RequestPolicy {
        let minimumMaxTokens: Int?
        let maximumMaxTokens: Int?
        let strippedFields: Set<String>
        let attemptTimeout: TimeInterval?
        let firstResponseDeadline: TimeInterval?
        let bufferedResponseDeadline: TimeInterval?
        let transportRetries: Int
        let semanticRetries: Int
        let retryableFailureClasses: Set<FailureClass>
        let retryBackoffMilliseconds: Int
        let stripsReasoningFieldFromSuccess: Bool
        let allowsThinkLeakRepair: Bool
        let salvagesBestEffortRepair: Bool
        let clientStreamingMode: ClientStreamingMode
        let toolChoiceMode: ToolChoiceMode
        let forcesKimiInstantMode: Bool
    }
    private static let retryableHTTPStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    private static let retryableTransportErrorCodes: Set<Int> = [
        URLError.Code.timedOut.rawValue,
        URLError.Code.cannotFindHost.rawValue,
        URLError.Code.cannotConnectToHost.rawValue,
        URLError.Code.networkConnectionLost.rawValue,
        URLError.Code.dnsLookupFailed.rawValue,
        URLError.Code.notConnectedToInternet.rawValue,
        URLError.Code.resourceUnavailable.rawValue
    ]
    private static let routeConfigCacheQueue = DispatchQueue(label: "io.automaze.vibeproxy.route-config-cache")
    private static var cachedRouteConfiguration: CachedRouteConfiguration?
    private static let routeHealthQueue = DispatchQueue(label: "io.automaze.vibeproxy.route-health")
    private static var routeCircuitStatesByRouteHealthKey: [String: RouteCircuitState] = [:]
    private static var routeCooldownsByRouteHealthKey: [String: Date] = [:]

    // Alias-scoped recent dispatches and live winners are tracked separately
    // from per-route telemetry so later canaries, direct requests, or failures
    // on the same route cannot erase worker-pool diagnostics.
    private static var recentSmartAliasDispatchByRequestedAlias: [String: RecentSmartAliasDispatch] = [:]
    private static var recentSmartAliasWinnerByRequestedAlias: [String: RecentSmartAliasWinner] = [:]
    struct RecentSmartAliasDispatch {
        let requestModel: String
        let timestamp: Date
        let requestShape: String?
        let callerRequestID: String?
        let callerSessionID: String?
    }
    struct RecentSmartAliasWinner {
        let requestModel: String
        let timestamp: Date
        let requestShape: String?
        let callerRequestID: String?
        let callerSessionID: String?
    }

    static func recordRecentSmartAliasDispatch(
        requestedAlias: String,
        requestModel: String,
        requestShape: String? = nil,
        callerRequestID: String? = nil,
        callerSessionID: String? = nil,
        at now: Date = Date()
    ) {
        routeHealthQueue.sync {
            recentSmartAliasDispatchByRequestedAlias[requestedAlias] = RecentSmartAliasDispatch(
                requestModel: requestModel,
                timestamp: now,
                requestShape: requestShape,
                callerRequestID: callerRequestID,
                callerSessionID: callerSessionID
            )
        }
    }

    static func recentSmartAliasDispatch(
        forRequestedAlias alias: String,
        maxAge: TimeInterval = 30,
        at now: Date = Date()
    ) -> RecentSmartAliasDispatch? {
        routeHealthQueue.sync {
            guard let dispatch = recentSmartAliasDispatchByRequestedAlias[alias],
                  now.timeIntervalSince(dispatch.timestamp) <= maxAge else {
                return nil
            }
            return dispatch
        }
    }

    static func recordRecentSmartAliasWinner(
        requestedAlias: String,
        requestModel: String,
        requestShape: String? = nil,
        callerRequestID: String? = nil,
        callerSessionID: String? = nil,
        at now: Date = Date()
    ) {
        routeHealthQueue.sync {
            recentSmartAliasWinnerByRequestedAlias[requestedAlias] = RecentSmartAliasWinner(
                requestModel: requestModel,
                timestamp: now,
                requestShape: requestShape,
                callerRequestID: callerRequestID,
                callerSessionID: callerSessionID
            )
        }
    }

    static func recentSmartAliasWinner(
        forRequestedAlias alias: String,
        maxAge: TimeInterval = 30,
        at now: Date = Date()
    ) -> RecentSmartAliasWinner? {
        routeHealthQueue.sync {
            guard let winner = recentSmartAliasWinnerByRequestedAlias[alias],
                  now.timeIntervalSince(winner.timestamp) <= maxAge else {
                return nil
            }
            return winner
        }
    }

    private static var hasLoadedPersistedRouteHealth = false
    static var routeTelemetryHookForTesting: ((RouteTelemetryEvent) -> Void)?
    static var retryBackoffJitterProviderForTesting: ((ClosedRange<Int>) -> Int)?
    private static let routeCircuitBreakerPolicy = RouteCircuitBreakerPolicy(
        failureThreshold: 4,
        cooldown: 10,
        recoverySuccessThreshold: 1
    )
    private static let retryBackoffPositiveJitterDivisor = 4
    private static let adaptiveFailureEscalationWindow: TimeInterval = 30 * 60
    private static let adaptiveFailureCooldownMaxMultiplier = 8
    private static let routeRollingWindow = 8
    private static let fastCanaryInterval: TimeInterval = 30
    private static let defaultCanaryInterval: TimeInterval = 60
    private static let defaultSuspectHedgeDelay: TimeInterval = 5
    fileprivate static let nvidiaInferenceProbeFreshnessWindow: TimeInterval = 300
    private static let routeFailureScoreDecayInterval: TimeInterval = 180
    private static let concurrency429RepeatWindow: TimeInterval = 10 * 60
    private static let concurrency429Deferral: TimeInterval = 15
    private static let repeatedConcurrency429Deferral: TimeInterval = 60
    private static let singleFlightConcurrency429Deferral: TimeInterval = 5
    private static let repeatedSingleFlightConcurrency429Deferral: TimeInterval = 15
    private static let retryableMetaAdapterDeferral: TimeInterval = 60
    private static let legacyRequestModelRewriteEntries: [(String, String)] = [
        ("glm-5", "glm-5.1"),
        ("glm-5-turbo", "glm-5.1"),
        // Canonical GLM requests should land on the resilient pooled alias, not the debug-only
        // direct lane.
        ("z-ai/glm5", "glm5-nvidia")
    ]
    private static let legacyRequestModelRewrites: [String: String] = deduplicatedStaticLookup(
        legacyRequestModelRewriteEntries,
        label: "legacyRequestModelRewrites"
    )

    // MARK: - Provider Concurrency Tracker

    final class ProviderConcurrencyRegistry {
        private let queue = DispatchQueue(label: "io.automaze.vibeproxy.concurrency-registry")
        private var inflightCounts: [String: Int] = [:]
        private var discoveredLimits: [String: Int] = [:]
        private var discoveredLimitUpdatedAt: [String: Date] = [:]
        private var consecutiveSuccessesAtLimit: [String: Int] = [:]
        private var concurrent429Buckets: [String: (inflightLevel: Int, count: Int)] = [:]
        /// Tracks when inflightCounts[key] first went from 0 to >0, used to detect leaked slots.
        private var inflightSince: [String: Date] = [:]
        /// Maximum time a slot can be held before it's considered leaked.
        private let slotLeakThreshold: TimeInterval = 10 * 60  // 10 minutes

        private let defaultConcurrencyLimit = 3
        private let maxConcurrencyLimit = 8
        private let successGrowthThreshold = 20
        private let lowLimitSuccessGrowthThreshold = 3
        private let mediumLimitSuccessGrowthThreshold = 6
        private let learnedLowLimitTTL: TimeInterval = 10 * 60

        private func successGrowthThreshold(for learnedLimit: Int) -> Int {
            if learnedLimit <= 1 {
                return lowLimitSuccessGrowthThreshold
            }
            if learnedLimit == 2 {
                return mediumLimitSuccessGrowthThreshold
            }
            return successGrowthThreshold
        }

        private func resetLearnedLimitLocked(routeHealthKey: String) {
            discoveredLimits.removeValue(forKey: routeHealthKey)
            discoveredLimitUpdatedAt.removeValue(forKey: routeHealthKey)
            consecutiveSuccessesAtLimit.removeValue(forKey: routeHealthKey)
            concurrent429Buckets.removeValue(forKey: routeHealthKey)
        }

        private func inferredLimitFromConcurrency429(inflightAtRequest: Int) -> Int? {
            // A single-flight 429 is ambiguous: it may reflect upstream/global saturation rather
            // than a true local concurrency ceiling of 1. Only ratchet the learned limit down when
            // we have direct evidence that parallel local requests are colliding.
            guard inflightAtRequest > 1 else {
                return nil
            }
            return max(1, inflightAtRequest - 1)
        }

        private func effectiveLimitLocked(routeHealthKey: String, now: Date = Date()) -> Int {
            guard let learnedLimit = discoveredLimits[routeHealthKey] else {
                return defaultConcurrencyLimit
            }

            if learnedLimit < defaultConcurrencyLimit,
               let updatedAt = discoveredLimitUpdatedAt[routeHealthKey],
               now.timeIntervalSince(updatedAt) >= learnedLowLimitTTL {
                resetLearnedLimitLocked(routeHealthKey: routeHealthKey)
                return defaultConcurrencyLimit
            }

            return learnedLimit
        }

        func resetForTesting() {
            queue.sync {
                inflightCounts.removeAll()
                inflightSince.removeAll()
                discoveredLimits.removeAll()
                discoveredLimitUpdatedAt.removeAll()
                consecutiveSuccessesAtLimit.removeAll()
                concurrent429Buckets.removeAll()
            }
        }

        /// Reset inflight counts for routes whose slots have been held beyond the leak threshold.
        /// Called from the maintenance timer to recover from crashed requests that never released.
        func sanitizeStaleSlots() {
            queue.sync {
                let now = Date()
                var leakedRoutes: [String] = []
                for (key, sinceDate) in inflightSince {
                    let heldDuration = now.timeIntervalSince(sinceDate)
                    if heldDuration > slotLeakThreshold {
                        leakedRoutes.append(key)
                    }
                }
                for key in leakedRoutes {
                    let previousCount = inflightCounts[key] ?? 0
                    inflightCounts[key] = 0
                    inflightSince.removeValue(forKey: key)
                    NSLog("[ThinkingProxy] Concurrency: recovered %d leaked slot(s) for route %@ (held for >%.0fs)", previousCount, key, slotLeakThreshold)
                }
            }
        }

        func acquireSlot(routeHealthKey: String) -> Bool {
            queue.sync {
                let limit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
                let current = inflightCounts[routeHealthKey] ?? 0
                guard current < limit else {
                    return false
                }
                inflightCounts[routeHealthKey] = current + 1
                if current == 0 {
                    inflightSince[routeHealthKey] = Date()
                }
                return true
            }
        }

        func releaseSlot(routeHealthKey: String) {
            queue.sync {
                let current = inflightCounts[routeHealthKey] ?? 0
                let newCount = max(0, current - 1)
                inflightCounts[routeHealthKey] = newCount
                if newCount == 0 {
                    inflightSince.removeValue(forKey: routeHealthKey)
                }
            }
        }

        func record429(routeHealthKey: String, inflightAtRequest: Int) {
            queue.sync {
                let currentLimit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
                consecutiveSuccessesAtLimit[routeHealthKey] = 0

                // If we were at or above the limit when the 429 arrived, the limit is too high
                if inflightAtRequest >= currentLimit,
                   let inferredLimit = inferredLimitFromConcurrency429(inflightAtRequest: inflightAtRequest) {
                    discoveredLimits[routeHealthKey] = inferredLimit
                    discoveredLimitUpdatedAt[routeHealthKey] = Date()
                    concurrent429Buckets.removeValue(forKey: routeHealthKey)
                    return
                }

                // Track 429s at the same inflight level — repeated hits suggest a lower limit
                let bucket = concurrent429Buckets[routeHealthKey]
                if let bucket, bucket.inflightLevel == inflightAtRequest {
                    let newCount = bucket.count + 1
                    if newCount >= 3,
                       let inferredLimit = inferredLimitFromConcurrency429(inflightAtRequest: inflightAtRequest) {
                        discoveredLimits[routeHealthKey] = inferredLimit
                        discoveredLimitUpdatedAt[routeHealthKey] = Date()
                        concurrent429Buckets.removeValue(forKey: routeHealthKey)
                    } else {
                        concurrent429Buckets[routeHealthKey] = (inflightLevel: inflightAtRequest, count: newCount)
                    }
                } else {
                    concurrent429Buckets[routeHealthKey] = (inflightLevel: inflightAtRequest, count: 1)
                }
            }
        }

        func recordSuccess(routeHealthKey: String, inflightAtRequest: Int? = nil) {
            queue.sync {
                let currentLimit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
                let currentInflight = inflightAtRequest ?? (inflightCounts[routeHealthKey] ?? 0)

                // Only count as "at-limit" success if we were near the limit
                guard currentInflight >= currentLimit - 1 else { return }

                let successes = (consecutiveSuccessesAtLimit[routeHealthKey] ?? 0) + 1
                consecutiveSuccessesAtLimit[routeHealthKey] = successes
                concurrent429Buckets.removeValue(forKey: routeHealthKey)

                // After sustained success at current limit, try growing
                if successes >= successGrowthThreshold(for: currentLimit), currentLimit < maxConcurrencyLimit {
                    discoveredLimits[routeHealthKey] = currentLimit + 1
                    discoveredLimitUpdatedAt[routeHealthKey] = Date()
                    consecutiveSuccessesAtLimit[routeHealthKey] = 0
                }
            }
        }

        func currentInflight(routeHealthKey: String) -> Int {
            queue.sync { inflightCounts[routeHealthKey] ?? 0 }
        }

        func isAtCapacity(routeHealthKey: String) -> Bool {
            queue.sync {
                let limit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
                return (inflightCounts[routeHealthKey] ?? 0) >= limit
            }
        }

        func currentLimit(routeHealthKey: String) -> Int {
            queue.sync { effectiveLimitLocked(routeHealthKey: routeHealthKey) }
        }


        // MARK: - Persistence

        func persistLocked(into payload: inout [String: Any]) {
            // Already on caller's queue — safe to read synchronously
            let (limits, metadata): ([String: Int], [String: [String: String]]) = queue.sync {
                let effectiveRoutes = discoveredLimits.keys.compactMap { routeHealthKey -> (String, Int, Date?)? in
                    let limit = effectiveLimitLocked(routeHealthKey: routeHealthKey)
                    guard limit != defaultConcurrencyLimit else {
                        return nil
                    }
                    return (routeHealthKey, limit, discoveredLimitUpdatedAt[routeHealthKey])
                }

                let limits = effectiveRoutes.reduce(into: [String: Int]()) { partial, route in
                    partial[route.0] = route.1
                }
                let metadata = effectiveRoutes.reduce(into: [String: [String: String]]()) { partial, route in
                    guard let updatedAt = route.2 else { return }
                    partial[route.0] = [
                        "updated_at": OpenAICompatTemporaryShim.iso8601String(from: updatedAt)
                    ]
                }
                return (limits, metadata)
            }
            guard !limits.isEmpty else { return }
            payload["discovered_concurrency_limits"] = limits
            if !metadata.isEmpty {
                payload["discovered_concurrency_limit_metadata"] = metadata
            }
        }

        func loadLocked(from json: [String: Any], persistedVersion: Int) {
            guard let limits = json["discovered_concurrency_limits"] as? [String: Int] else { return }
            queue.sync {
                if let metadata = json["discovered_concurrency_limit_metadata"] as? [String: [String: String]] {
                    // Versions before 5 could learn a cap of 1 from repeated single-flight 429s.
                    // That evidence is structurally ambiguous, so migrate those persisted values
                    // away on reload and let the new learner re-establish them from true
                    // multi-flight contention if needed.
                    discoveredLimits = limits.filter { _, limit in
                        !(persistedVersion < 5 && limit <= 1)
                    }
                    discoveredLimitUpdatedAt = metadata.reduce(into: [String: Date]()) { partial, entry in
                        guard discoveredLimits[entry.key] != nil else {
                            return
                        }
                        guard let rawTimestamp = entry.value["updated_at"],
                              let updatedAt = OpenAICompatTemporaryShim.parseISO8601Date(rawTimestamp) else {
                            return
                        }
                        partial[entry.key] = updatedAt
                    }
                } else {
                    // Legacy persisted limits lacked freshness metadata. Keep only non-restrictive
                    // legacy values so stale single-flight caps do not pin the worker lane.
                    discoveredLimits = limits.filter { $0.value >= defaultConcurrencyLimit }
                    discoveredLimitUpdatedAt = [:]
                }
            }
        }

        func forceDiscoveredLimitForTesting(routeHealthKey: String, limit: Int) {
            queue.sync {
                discoveredLimits[routeHealthKey] = limit
                discoveredLimitUpdatedAt[routeHealthKey] = Date()
            }
        }
    }

    fileprivate static let concurrencyRegistry = ProviderConcurrencyRegistry()

    // Public accessors for concurrency registry (used by ThinkingProxy main class)
    static func acquireConcurrencySlot(routeHealthKey: String) -> Bool {
        concurrencyRegistry.acquireSlot(routeHealthKey: routeHealthKey)
    }

    static func releaseConcurrencySlot(routeHealthKey: String) {
        concurrencyRegistry.releaseSlot(routeHealthKey: routeHealthKey)
    }

    static func recordConcurrency429(routeHealthKey: String, inflightAtRequest: Int? = nil) {
        let inflight = inflightAtRequest ?? concurrencyRegistry.currentInflight(routeHealthKey: routeHealthKey)
        concurrencyRegistry.record429(routeHealthKey: routeHealthKey, inflightAtRequest: inflight)
    }

    static func shouldTreatProvider429AsConcurrency(
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let disposition = classifyProvider429Disposition(
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            now: now
        ) else {
            return false
        }

        if case .concurrency = disposition {
            return true
        }
        return false
    }

    static func recordConcurrency429IfNeeded(
        routeHealthKey: String,
        inflightAtRequest: Int? = nil,
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) {
        guard shouldTreatProvider429AsConcurrency(
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            now: now
        ) else {
            return
        }
        recordConcurrency429(
            routeHealthKey: routeHealthKey,
            inflightAtRequest: inflightAtRequest
        )
    }

    static func recordConcurrencySuccess(routeHealthKey: String, inflightAtRequest: Int? = nil) {
        concurrencyRegistry.recordSuccess(routeHealthKey: routeHealthKey, inflightAtRequest: inflightAtRequest)
    }

    static func currentInflightConcurrency(routeHealthKey: String) -> Int {
        concurrencyRegistry.currentInflight(routeHealthKey: routeHealthKey)
    }

    static func currentConcurrencyLimit(routeHealthKey: String) -> Int {
        concurrencyRegistry.currentLimit(routeHealthKey: routeHealthKey)
    }

    static func resetConcurrencyRegistryForTesting() {
        concurrencyRegistry.resetForTesting()
        retryBackoffJitterProviderForTesting = nil
    }

    static func resetRetryBackoffJitterForTesting() {
        retryBackoffJitterProviderForTesting = nil
    }

    static func jitteredRetryBackoffMilliseconds(_ baseMilliseconds: Int) -> Int {
        guard baseMilliseconds > 0 else { return 0 }
        let jitterUpperBound = max(1, baseMilliseconds / retryBackoffPositiveJitterDivisor)
        let rawOffset = retryBackoffJitterProviderForTesting?(0 ... jitterUpperBound)
            ?? Int.random(in: 0 ... jitterUpperBound)
        let jitterOffset = min(max(0, rawOffset), jitterUpperBound)
        return baseMilliseconds + jitterOffset
    }

    // MARK: - Route Health Write Debouncing

    private static var routeHealthDirty = false
    private static var routeHealthPersistWorkItem: DispatchWorkItem?
    private static let routeHealthPersistDebounce: DispatchTimeInterval = .seconds(2)

    fileprivate enum ToolCallValidation {
        case none
        case valid
        case invalid
    }

    private enum ContentNormalizationResult {
        case unchanged
        case flattened(String)
        case unsupported
    }

    static func transformRequest(method: String, path: String, jsonString: String) -> String? {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let rawModel = json["model"] as? String else {
            return nil
        }
        let model = normalizedRequestModel(rawModel)
        guard let policy = policy(forModel: model) else {
            return nil
        }
        var modified = false

        if model != rawModel {
            json["model"] = model
            modified = true
        }

        if let messages = json["messages"] as? [[String: Any]] {
            var normalizedMessages = messages
            var normalizedAnyMessage = false
            for index in normalizedMessages.indices {
                switch normalizedContentResult(from: normalizedMessages[index]["content"]) {
                case .unchanged:
                    break
                case .flattened(let flattened):
                    normalizedMessages[index]["content"] = flattened
                    normalizedAnyMessage = true
                case .unsupported:
                    break
                }
            }
            if normalizedAnyMessage {
                json["messages"] = normalizedMessages
                modified = true
            }
        }

        if json["max_tokens"] == nil {
            if let aliasedMaxTokens = integerValue(json["max_completion_tokens"]) {
                json["max_tokens"] = aliasedMaxTokens
                modified = true
            } else if let aliasedMaxTokens = integerValue(json["max_output_tokens"]) {
                json["max_tokens"] = aliasedMaxTokens
                modified = true
            }
        }

        if let minimumMaxTokens = policy.minimumMaxTokens {
            if let currentMaxTokens = integerValue(json["max_tokens"]) {
                if currentMaxTokens < minimumMaxTokens {
                    json["max_tokens"] = minimumMaxTokens
                    modified = true
                }
            } else {
                json["max_tokens"] = minimumMaxTokens
                modified = true
            }
        }

        if let maximumMaxTokens = policy.maximumMaxTokens {
            for tokenField in ["max_tokens", "max_completion_tokens", "max_output_tokens"] {
                if let currentMaxTokens = integerValue(json[tokenField]),
                   currentMaxTokens > maximumMaxTokens {
                    json[tokenField] = maximumMaxTokens
                    modified = true
                }
            }
        }

        for field in policy.strippedFields where json[field] != nil {
            json.removeValue(forKey: field)
            modified = true
        }

        if let tools = json["tools"] as? [Any], !tools.isEmpty {
            if json["response_format"] != nil {
                json.removeValue(forKey: "response_format")
                modified = true
            }
        }

        if policy.forcesKimiInstantMode {
            var chatTemplate = json["chat_template_kwargs"] as? [String: Any] ?? [:]
            var chatTemplateModified = false
            if (chatTemplate["thinking"] as? Bool) != false {
                chatTemplate["thinking"] = false
                chatTemplateModified = true
            }
            if (chatTemplate["enable_thinking"] as? Bool) != false {
                chatTemplate["enable_thinking"] = false
                chatTemplateModified = true
            }
            if chatTemplateModified {
                json["chat_template_kwargs"] = chatTemplate
                modified = true
            }
            if (json["include_reasoning"] as? Bool) != false {
                json["include_reasoning"] = false
                modified = true
            }
        }

        guard modified,
              let modifiedData = try? JSONSerialization.data(withJSONObject: json),
              let modifiedString = String(data: modifiedData, encoding: .utf8) else {
            return nil
        }

        NSLog("[ThinkingProxy] Applied temporary provider mitigation request shim for %@", model)
        return modifiedString
    }

    static func requestedStream(forRequestJSON jsonString: String) -> Bool {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return false
        }
        return (json["stream"] as? Bool) == true
    }

    static func allowsDirectNVIDIAStreaming(
        method: String,
        path: String,
        jsonString: String
    ) -> Bool {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              resolveNVIDIAHostedRoute(forRequestModel: normalizedRequestModel(model)) != nil else {
            return false
        }

        if let tools = json["tools"] as? [Any], !tools.isEmpty {
            return false
        }

        return true
    }

    static func allowsHedgedNVIDIARequest(
        method: String,
        path: String,
        jsonString: String,
        routeHealthStatus: RouteHealthStatus?
    ) -> Bool {
        guard routeHealthStatus == .suspect,
              method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              policy(forModel: model) != nil else {
            return false
        }

        if requestedStream(forRequestJSON: jsonString) {
            return false
        }

        if let tools = json["tools"] as? [Any], !tools.isEmpty {
            return false
        }

        if json["response_format"] != nil {
            return false
        }

        return true
    }

    static func allowsPlainSafeNVIDIARequest(
        method: String,
        path: String,
        jsonString: String
    ) -> Bool {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              policy(forModel: model) != nil else {
            return false
        }

        if requestedStream(forRequestJSON: jsonString) {
            return false
        }

        if let tools = json["tools"] as? [Any], !tools.isEmpty {
            return false
        }

        if json["response_format"] != nil {
            return false
        }

        return true
    }

    static func rewrittenRequestJSON(
        method: String,
        path: String,
        replacingRequestModelIn jsonString: String,
        with requestModel: String
    ) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        json["model"] = requestModel
        guard let rewrittenJSONData = try? JSONSerialization.data(withJSONObject: json),
              let rewrittenJSONString = String(data: rewrittenJSONData, encoding: .utf8) else {
            return nil
        }
        return transformRequest(method: method, path: path, jsonString: rewrittenJSONString) ?? rewrittenJSONString
    }

    private static let publicFactoryWorkerSmartRouterAlias = "proxy-worker-smart-router"
    private static let publicNVIDIASmartAlias = "glm5-nvidia"
    fileprivate static let publicNVIDIADirectAlias = "glm5-nvidia-direct"
    private static let directNVIDIAAccessHeader = "X-VibeProxy-Allow-Direct-NVIDIA"
    private static let publicNVIDIASmartAliasCandidateModels = [
        "glm5-nvidia",
        "glm-5.1-zai",
        "glm-5.1-ollama-pro",
        "minimax-m2.7-ollama-pro",
        "muse-spark"
    ]
    fileprivate static let canonicalFactoryWorkerModelID = "custom:Proxy-Worker-Smart-Router-8"
    private static let publicWorkerPoolAliases: Set<String> = [
        "worker",
        "glm-5.1",
        publicFactoryWorkerSmartRouterAlias
    ]
    fileprivate static let codeOwnedFactoryWorkerRescueModelIDs: Set<String> = [
        "custom:Factory-Worker-GPT-5.4-High-8",
        "custom:Proxy-WorkerPool-8"
    ]
    static func publicWorkerSmartRouterAlias() -> String {
        publicFactoryWorkerSmartRouterAlias
    }
    static func canonicalFactoryWorkerModelIDForTesting() -> String {
        canonicalFactoryWorkerModelID
    }
    static func workerPrimaryCandidateModel() -> String {
        smartAliasDefinition(forRequestModel: "worker")?.candidates.first ?? "glm-5.1-zai"
    }

    fileprivate static func isWorkerPoolPublicAlias(_ requestModel: String) -> Bool {
        publicWorkerPoolAliases.contains(requestModel)
    }

    fileprivate static func isCodeOwnedFactoryWorkerIncomingModelID(_ requestModel: String) -> Bool {
        requestModel == canonicalFactoryWorkerModelID || codeOwnedFactoryWorkerRescueModelIDs.contains(requestModel)
    }

    static func smartAliasDefinition(forRequestModel requestModel: String) -> SmartAliasDefinition? {
        let requestModel = normalizedRequestModel(requestModel)
        if requestModel == publicNVIDIASmartAlias {
            return SmartAliasDefinition(
                alias: publicNVIDIASmartAlias,
                requestClass: "plain-chat",
                failover: "silent",
                candidates: publicNVIDIASmartAliasCandidateModels,
                healthSensitivity: .balanced
            )
        }
        let smartAliases = configuredRouteConfiguration().smartAliasesByAlias
        if let exact = smartAliases[requestModel] {
            return exact
        }

        // `worker` is a proxy-internal pool alias. It is useful inside VibeProxy for policy, failover,
        // and audit semantics, but clients like Factory should not need to couple themselves to that
        // internal alias name.
        //
        // Factory currently re-resolves the raw API model string in some runtime paths and does not
        // reliably preserve the original custom-model identity. That means the inner API model can
        // leak back into Droid's built-in model lookup even though the user selected a custom model.
        //
        // The pooled route therefore keeps a neutral public alias for Droid/Factory safety and one
        // legacy concrete alias for direct proxy users:
        // - `proxy-worker-smart-router` is the Droid-safe public entrypoint for Factory workers
        // - `glm-5.1` remains a legacy direct public pooled entrypoint for existing proxy callers
        //
        // Important: callers hitting this branch still see their original public alias on the way out.
        // The internal `worker` alias remains a proxy concern, not an external runtime contract.
        if requestModel == "glm-5.1" || requestModel == publicFactoryWorkerSmartRouterAlias {
            return smartAliases["worker"]
        }

        return nil
    }

    static func effectiveSmartAliasCandidateModels(
        forPublicAlias publicAlias: String,
        method: String,
        path: String,
        jsonString: String,
        smartAlias: SmartAliasDefinition
    ) -> [String] {
        // Worker entrypoints intentionally share one execution policy. Plain chat, tool-bearing
        // chat, structured-output chat, and large Factory worker payloads all traverse the same
        // smart-alias candidate list so routing semantics stay coherent across request shapes.
        //
        // The worker contract must keep its configured business ordering while all candidates are
        // healthy: ZAI GLM first, then Ollama GLM, then the MiniMax fallback. When a lane degrades,
        // only health bucket ordering may move it back; latency/EMA scoring must not leapfrog a
        // lower-priority backend ahead of a healthy preferred sibling.
        let trustRankedCandidates = candidateModelsAdjustedForNVIDIATrust(
            smartAlias.candidates,
            publicAlias: publicAlias
        )
        let availabilityRankedCandidates = availabilityRankedSmartAliasCandidateModels(trustRankedCandidates)
        return requestShapeAdjustedSmartAliasCandidateModels(
            availabilityRankedCandidates,
            method: method,
            path: path,
            jsonString: jsonString
        )
    }

    private static func candidateModelsAdjustedForNVIDIATrust(
        _ candidateModels: [String],
        publicAlias: String
    ) -> [String] {
        guard publicAlias == publicNVIDIASmartAlias,
              !hasRecentStableNVIDIAInferenceSuccess(forRequestModel: publicNVIDIASmartAlias) else {
            return candidateModels
        }
        guard let nvidiaCandidate = publicNVIDIASmartAliasCandidateModels.first,
              candidateModels.contains(nvidiaCandidate) else {
            return candidateModels
        }
        return candidateModels.filter { $0 != nvidiaCandidate } + [nvidiaCandidate]
    }

    private static func requestShapeAdjustedSmartAliasCandidateModels(
        _ candidateModels: [String],
        method: String,
        path: String,
        jsonString: String
    ) -> [String] {
        switch metaBridgeDispositionForWorkerRequest(
        method: method,
        path: path,
        jsonString: jsonString
        ) {
        case .keep:
            return candidateModels
        case .deferToNative:
            return moveCandidate(
                MetaAIWebAdapter.modelAlias,
                after: "glm5-nvidia",
                in: candidateModels
            )
        case .exclude:
            return candidateModels.filter { $0 != MetaAIWebAdapter.modelAlias }
        }
    }

    private enum WorkerMetaBridgeDisposition {
        case keep
        case deferToNative
        case exclude
    }

    private static func metaBridgeDispositionForWorkerRequest(
        method: String,
        path: String,
        jsonString: String
    ) -> WorkerMetaBridgeDisposition {
        if MetaAIWebAdapter.preflightFailure(
            path: path,
            body: jsonString,
            publicModel: MetaAIWebAdapter.modelAlias
        ) != nil {
            return .exclude
        }

        if metaBridgeShouldYieldToNativeToolLanes(
            method: method,
            path: path,
            jsonString: jsonString
        ) {
            return .deferToNative
        }

        return .keep
    }

    private static func metaBridgeShouldYieldToNativeToolLanes(
        method: String,
        path: String,
        jsonString: String
    ) -> Bool {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let tools = json["tools"] as? [Any],
              !tools.isEmpty else {
            return false
        }

        // muse-spark relies on a prompt-mediated synthetic tool bridge. It works well enough for
        // auto/plain tool planning, but exact function/required tool_choice still has materially
        // worse reliability than the native tool lanes. Keep Meta in the pool, but only after the
        // native fallbacks for turns that require strict tool semantics.
        return hasStrictToolChoice(in: json)
    }

    private static func moveCandidate(
        _ candidateModel: String,
        after anchorModel: String,
        in candidateModels: [String]
    ) -> [String] {
        guard let candidateIndex = candidateModels.firstIndex(of: candidateModel),
              let anchorIndex = candidateModels.firstIndex(of: anchorModel),
              candidateIndex < anchorIndex else {
            return candidateModels
        }

        var reordered = candidateModels
        let candidate = reordered.remove(at: candidateIndex)
        guard let refreshedAnchorIndex = reordered.firstIndex(of: anchorModel) else {
            return candidateModels
        }
        reordered.insert(candidate, at: refreshedAnchorIndex + 1)
        return reordered
    }

    private static func availabilityRankedSmartAliasCandidateModels(_ candidateModels: [String]) -> [String] {
        let indexedModels = Array(candidateModels.enumerated())
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return indexedModels.sorted { lhs, rhs in
                let lhsPriority = candidateAvailabilityPriority(forRequestModel: lhs.element)
                let rhsPriority = candidateAvailabilityPriority(forRequestModel: rhs.element)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.offset < rhs.offset
            }.map(\.element)
        }
    }

    private static func candidateAvailabilityPriority(forRequestModel requestModel: String) -> Int {
        let now = Date()
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return 0
        }

        if let cooldownUntil = routeCooldownsByRouteHealthKey[route.routeHealthKey],
           now < cooldownUntil {
            return 4
        }

        switch routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.status ?? .closed {
        case .closed:
            return 0
        case .suspect:
            return 1
        case .halfOpen:
            return 2
        case .open:
            return 3
        }
    }

    static func forcedSmartAliasProbeCandidateModels(
        forPublicAlias publicAlias: String,
        method: String,
        path: String,
        jsonString: String,
        smartAlias: SmartAliasDefinition
    ) -> Set<String> {
        if publicAlias == publicNVIDIASmartAlias,
           let nvidiaCandidate = publicNVIDIASmartAliasCandidateModels.first,
           !hasRecentLiveInferenceSuccess(forRequestModel: publicNVIDIASmartAlias) {
            return [nvidiaCandidate]
        }
        // No request class gets a hidden worker-specific probe lane. Candidate selection and
        // recovery policy are shared across plain and tool-heavy worker traffic.
        return []
    }

    static func smartAliasContractError(forRequestModel requestModel: String) -> ClientFacingNVIDIAFailure? {
        // Validate the internal alias and the one explicit public pooled entrypoint against the same
        // underlying pool contract. `worker` stays proxy-internal; `glm-5.1` is the only remaining
        // external pooled alias.
        guard isWorkerPoolPublicAlias(requestModel),
              let smartAlias = smartAliasDefinition(forRequestModel: requestModel) else {
            return nil
        }

        let canonicalCandidates = ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"]
        guard smartAlias.candidates == canonicalCandidates,
              let primaryRoute = resolveConfiguredRoute(forRequestModel: canonicalCandidates[0]),
              primaryRoute.providerID == "zai",
              primaryRoute.canonicalModelID == "glm-5.1",
              let secondaryRoute = resolveConfiguredRoute(forRequestModel: canonicalCandidates[1]),
              secondaryRoute.providerID == "ollama-pro",
              secondaryRoute.canonicalModelID == "glm-5.1",
              let fallbackRoute = resolveConfiguredRoute(forRequestModel: canonicalCandidates[2]),
              fallbackRoute.providerID == "ollama-pro",
              fallbackRoute.canonicalModelID == "minimax-m2.7",
              let metaRoute = resolveConfiguredRoute(forRequestModel: canonicalCandidates[3]),
              metaRoute.providerID == MetaAIWebAdapter.providerID,
              metaRoute.canonicalModelID == MetaAIWebAdapter.modelAlias,
              let terminalFallbackRoute = resolveConfiguredRoute(forRequestModel: canonicalCandidates[4]),
              terminalFallbackRoute.providerID == "nvidia",
              terminalFallbackRoute.canonicalModelID == "z-ai/glm5" else {
            return ClientFacingNVIDIAFailure(
                statusCode: 500,
                message: "The \(requestModel) pooled alias is misconfigured: candidates must be glm-5.1-zai, then glm-5.1-ollama-pro, then minimax-m2.7-ollama-pro, then muse-spark, then glm5-nvidia."
            )
        }

        return nil
    }

    static func isAnthropicConfiguredRoute(forRequestModel requestModel: String) -> Bool {
        configuredRouteConfiguration().anthropicRequestModels.contains(requestModel)
    }

    static func isSafePlainChatRequest(
        method: String,
        path: String,
        jsonString: String
    ) -> Bool {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return false
        }

        if requestedStream(forRequestJSON: jsonString) {
            return false
        }

        if let tools = json["tools"] as? [Any], !tools.isEmpty {
            return false
        }

        if json["response_format"] != nil {
            return false
        }

        return true
    }

    fileprivate struct SmartAliasCandidateTransition {
        let body: String
        let model: String
        let remainingCandidateModels: [String]
    }

    fileprivate struct SmartAliasCandidateSelectionResult {
        let transition: SmartAliasCandidateTransition?
        let terminalPreflightError: ClientFacingNVIDIAFailure?
        let exhaustionSummary: SmartAliasExhaustionSummary?
    }

    fileprivate enum SmartAliasExhaustionClassification: String {
        case capacityExhausted = "capacity_exhausted"
        case cooldownExhausted = "cooldown_exhausted"
        case routeUnavailable = "route_unavailable"
        case policyExhausted = "policy_exhausted"
        case mixedExhaustion = "mixed_exhaustion"
    }

    fileprivate struct SmartAliasExhaustionSummary {
        let classification: SmartAliasExhaustionClassification
        let countsByReason: [String: Int]
        let skippedReasons: [(model: String, reason: String)]

        var statusCode: Int {
            switch classification {
            case .capacityExhausted, .cooldownExhausted:
                return 429
            case .routeUnavailable, .policyExhausted, .mixedExhaustion:
                return 503
            }
        }

        func clientFacingMessage(publicAlias: String) -> String {
            switch classification {
            case .capacityExhausted:
                return "All configured worker backends for \(publicAlias) are currently at concurrency capacity; retry shortly."
            case .cooldownExhausted:
                return "All configured worker backends for \(publicAlias) are temporarily cooling down after upstream pressure; retry shortly."
            case .policyExhausted:
                return "All remaining worker backends for \(publicAlias) were rejected by proxy policy for this request shape."
            case .routeUnavailable:
                return "All configured worker backends for \(publicAlias) are currently quarantined or unavailable."
            case .mixedExhaustion:
                return "All configured worker backends for \(publicAlias) are currently unavailable due to mixed capacity, cooldown, and policy constraints."
            }
        }

        var logSummary: [String: Any] {
            [
                "classification": classification.rawValue,
                "counts_by_reason": countsByReason,
                "skipped": skippedReasons.map { ["model": $0.model, "reason": $0.reason] }
            ]
        }
    }

    fileprivate enum FactoryEffectiveRouteModelSource: String {
        case observedRecentWinner = "observed_recent_winner"
        case dispatchablePrediction = "dispatchable_prediction"
        case authoritativeFallback = "authoritative_fallback"
        case configuredRoute = "configured_route"
        case requestShapeDivergent = "request_shape_divergent"
    }

    private enum SmartAliasCandidateEvaluation {
        case available(body: String)
        case skipped(reason: String)
        case providerPreflightBlocked(reason: String, error: ClientFacingNVIDIAFailure)
    }

    private static func smartAliasExhaustionSummary(
        for skippedReasons: [(model: String, reason: String)]
    ) -> SmartAliasExhaustionSummary? {
        guard !skippedReasons.isEmpty else { return nil }
        let countsByReason = skippedReasons.reduce(into: [String: Int]()) { counts, skipped in
            counts[skipped.reason, default: 0] += 1
        }
        let reasonSet = Set(skippedReasons.map(\.reason))

        let classification: SmartAliasExhaustionClassification
        if reasonSet.allSatisfy({ $0 == "concurrency_capacity" }) {
            classification = .capacityExhausted
        } else if reasonSet.allSatisfy({ $0 == "provider_cooldown" }) {
            classification = .cooldownExhausted
        } else if reasonSet.allSatisfy({ $0 == "route_closed" }) {
            classification = .routeUnavailable
        } else if reasonSet.allSatisfy({ $0.hasPrefix("provider_preflight_") }) {
            classification = .policyExhausted
        } else {
            classification = .mixedExhaustion
        }

        return SmartAliasExhaustionSummary(
            classification: classification,
            countsByReason: countsByReason,
            skippedReasons: skippedReasons
        )
    }

    static func smartAliasExhaustionLogSummaryForTesting(
        skippedReasons: [(model: String, reason: String)]
    ) -> [String: Any] {
        if let exhaustionSummary = smartAliasExhaustionSummary(for: skippedReasons) {
            return exhaustionSummary.logSummary
        }
        return [
            "classification": "empty_candidate_set",
            "counts_by_reason": [:],
            "skipped": []
        ]
    }

    private static func evaluateSmartAliasCandidate(
        method: String,
        path: String,
        currentBody: String,
        candidateModel: String,
        forceAllowClosedModels: Set<String> = [],
        applyProviderAwarePreflight: Bool = true
    ) -> SmartAliasCandidateEvaluation {
        guard resolveConfiguredRoute(forRequestModel: candidateModel) != nil else {
            return .skipped(reason: "no_route")
        }
        guard let candidateBody = rewrittenRequestJSON(
            method: method,
            path: path,
            replacingRequestModelIn: currentBody,
            with: candidateModel
        ) else {
            return .skipped(reason: "rewrite_failed")
        }
        if isConfiguredRouteOpen(forRequestModel: candidateModel) &&
            !forceAllowClosedModels.contains(candidateModel) {
            return .skipped(reason: "route_closed")
        }
        if !forceAllowClosedModels.contains(candidateModel),
           let candidateRoute = resolveRouteIdentityForAnyProvider(forRequestModel: candidateModel),
           let cooldownUntil = routeCooldownsByRouteHealthKey[candidateRoute.routeHealthKey],
           Date() < cooldownUntil {
            return .skipped(reason: "provider_cooldown")
        }
        if !forceAllowClosedModels.contains(candidateModel),
           let candidateRoute = resolveRouteIdentityForAnyProvider(forRequestModel: candidateModel),
           Self.concurrencyRegistry.isAtCapacity(routeHealthKey: candidateRoute.routeHealthKey) {
            return .skipped(reason: "concurrency_capacity")
        }
        let transformedCandidateBody = transformRequest(
            method: method,
            path: path,
            jsonString: candidateBody
        ) ?? candidateBody
        let preflightCandidateBody: String
        if requestedStream(forRequestJSON: transformedCandidateBody),
           let data = transformedCandidateBody.data(using: .utf8),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json["stream"] = false
            if let bufferedData = try? JSONSerialization.data(withJSONObject: json),
               let bufferedBody = String(data: bufferedData, encoding: .utf8) {
                preflightCandidateBody = bufferedBody
            } else {
                preflightCandidateBody = transformedCandidateBody
            }
        } else {
            preflightCandidateBody = transformedCandidateBody
        }
        if applyProviderAwarePreflight,
           let preflightError = configuredRoutePreflightError(
            method: method,
            path: path,
            jsonString: preflightCandidateBody,
            headers: []
           ) {
            let reason = [
                "provider_preflight_\(preflightError.statusCode)",
                preflightError.reasonCode
            ].compactMap { $0 }.joined(separator: "_")
            return .providerPreflightBlocked(
                reason: reason,
                error: preflightError
            )
        }
        return .available(body: transformedCandidateBody)
    }

    fileprivate static func nextSmartAliasCandidateSelection(
        method: String,
        path: String,
        currentBody: String,
        candidateModelsRemaining: [String],
        forceAllowClosedModels: Set<String> = [],
        proxyRequestID: String? = nil
    ) -> SmartAliasCandidateSelectionResult {
        var remainingCandidateModels = candidateModelsRemaining
        var skippedReasons: [(model: String, reason: String)] = []
        var terminalPreflightError: ClientFacingNVIDIAFailure?
        var sawNonPreflightSkip = false

        while !remainingCandidateModels.isEmpty {
            let nextCandidateModel = remainingCandidateModels.removeFirst()
            switch evaluateSmartAliasCandidate(
                method: method,
                path: path,
                currentBody: currentBody,
                candidateModel: nextCandidateModel,
                forceAllowClosedModels: forceAllowClosedModels
            ) {
            case .available(let candidateBody):
                return SmartAliasCandidateSelectionResult(
                    transition: SmartAliasCandidateTransition(
                        body: candidateBody,
                        model: nextCandidateModel,
                        remainingCandidateModels: remainingCandidateModels
                    ),
                    terminalPreflightError: nil,
                    exhaustionSummary: nil
                )
            case .skipped(let reason):
                sawNonPreflightSkip = true
                skippedReasons.append((nextCandidateModel, reason))
            case .providerPreflightBlocked(let reason, let error):
                skippedReasons.append((nextCandidateModel, reason))
                terminalPreflightError = terminalPreflightError ?? error
                // Preflight rejections are content-compatibility checks, not upstream failures.
                // Recording them as route failures would quarantine routes that are healthy but
                // cannot handle specific request shapes (e.g., typed content arrays on NVIDIA).
                break
            }
        }

        let exhaustionSummary = smartAliasExhaustionSummary(for: skippedReasons)
        let correlationPrefix = proxyRequestID.map { "proxy_request_id:\($0) " } ?? ""
        let logSummary = smartAliasExhaustionLogSummaryForTesting(skippedReasons: skippedReasons)
        if let jsonData = try? JSONSerialization.data(withJSONObject: logSummary, options: [.sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            NSLog("[ThinkingProxy] nextSmartAliasCandidateTransition: no valid candidates. %@%@", correlationPrefix, jsonString)
        } else {
            NSLog("[ThinkingProxy] nextSmartAliasCandidateTransition: no valid candidates. %@Skipped: %@", correlationPrefix, skippedReasons)
        }

        return SmartAliasCandidateSelectionResult(
            transition: nil,
            terminalPreflightError: sawNonPreflightSkip ? nil : terminalPreflightError,
            exhaustionSummary: exhaustionSummary
        )
    }

    static func nextSmartAliasCandidateTransition(
        method: String,
        path: String,
        currentBody: String,
        candidateModelsRemaining: [String],
        forceAllowClosedModels: Set<String> = []
    ) -> (body: String, model: String, remainingCandidateModels: [String])? {
        let selection = nextSmartAliasCandidateSelection(
            method: method,
            path: path,
            currentBody: currentBody,
            candidateModelsRemaining: candidateModelsRemaining,
            forceAllowClosedModels: forceAllowClosedModels
        )
        guard let transition = selection.transition else {
            return nil
        }
        return (transition.body, transition.model, transition.remainingCandidateModels)
    }

    static func nextSmartAliasRetryDelay(
        forCandidateModels candidateModels: [String],
        forceAllowClosedModels: Set<String> = [],
        now: Date = Date()
    ) -> TimeInterval? {
        var retryDelays: [TimeInterval] = []

        for candidateModel in candidateModels {
            guard let candidateRoute = resolveConfiguredRoute(forRequestModel: candidateModel) else {
                continue
            }
            if !forceAllowClosedModels.contains(candidateModel),
               let cooldownUntil = routeCooldownsByRouteHealthKey[candidateRoute.routeHealthKey],
               now < cooldownUntil {
                retryDelays.append(max(0.05, cooldownUntil.timeIntervalSince(now)))
                continue
            }
            if !forceAllowClosedModels.contains(candidateModel),
               Self.concurrencyRegistry.isAtCapacity(routeHealthKey: candidateRoute.routeHealthKey) {
                retryDelays.append(1)
            }
        }

        return retryDelays.min()
    }

    static func availableSmartAliasCandidateTransitions(
        method: String,
        path: String,
        currentBody: String,
        candidateModelsRemaining: [String],
        forceAllowClosedModels: Set<String> = []
    ) -> [(body: String, model: String)] {
        candidateModelsRemaining.compactMap { candidateModel in
            switch evaluateSmartAliasCandidate(
                method: method,
                path: path,
                currentBody: currentBody,
                candidateModel: candidateModel,
                forceAllowClosedModels: forceAllowClosedModels
            ) {
            case .available(let candidateBody):
                return (candidateBody, candidateModel)
            case .skipped, .providerPreflightBlocked:
                return nil
            }
        }
    }

    static func rankedSmartAliasFallbackCandidateModels(
        _ candidateModels: [String],
        healthSensitivity: HealthSensitivity = .balanced
    ) -> [String] {
        let indexedModels = Array(candidateModels.enumerated())
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return indexedModels.sorted { lhs, rhs in
                let lhsScore = smartAliasFallbackRankingScore(forRequestModel: lhs.element, originalIndex: lhs.offset)
                let rhsScore = smartAliasFallbackRankingScore(forRequestModel: rhs.element, originalIndex: rhs.offset)
                if lhsScore.healthPriority != rhsScore.healthPriority {
                    return lhsScore.healthPriority < rhsScore.healthPriority
                }
                if lhsScore.isProvenPerfect != rhsScore.isProvenPerfect {
                    return lhsScore.isProvenPerfect
                }
                let scoreGap = lhsScore.compositeScore - rhsScore.compositeScore
                if abs(scoreGap) >= healthSensitivity.scoreGapThreshold {
                    return scoreGap > 0
                }
                return lhsScore.originalIndex < rhsScore.originalIndex
            }.map(\.element)
        }
    }

    private static func requestHeaderValue(
        _ name: String,
        in headers: [(String, String)]
    ) -> String? {
        for (headerName, headerValue) in headers.reversed() {
            if headerName.caseInsensitiveCompare(name) == .orderedSame {
                return headerValue
            }
        }
        return nil
    }

    private static func allowsExplicitNVIDIADirectAccess(headers: [(String, String)]) -> Bool {
        if let probeHeader = requestHeaderValue("X-VibeProxy-Probe", in: headers)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !probeHeader.isEmpty {
            return true
        }

        guard let allowHeader = requestHeaderValue(directNVIDIAAccessHeader, in: headers)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return allowHeader == "1" || allowHeader == "true" || allowHeader == "yes"
    }

    static func preflightError(
        method: String,
        path: String,
        jsonString: String,
        headers: [(String, String)] = []
    ) -> ClientFacingNVIDIAFailure? {
        guard method == "POST",
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              let route = resolveNVIDIAHostedRoute(forRequestModel: model) else {
            return nil
        }

        if normalizedRequestModel(model) == publicNVIDIADirectAlias,
           !allowsExplicitNVIDIADirectAccess(headers: headers) {
            return ClientFacingNVIDIAFailure(
                statusCode: 403,
                message: "\(publicNVIDIADirectAlias) is reserved for probe/debug traffic; use \(publicNVIDIASmartAlias) for resilient routed NVIDIA access.",
                reasonCode: "direct_alias_debug_only"
            )
        }

        if isResponsesPath(path) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "NVIDIA hosted inference does not reliably support /v1/responses via this proxy; use /v1/chat/completions.",
                reasonCode: "responses_path_unsupported"
            )
        }

        if isNVIDIAHostedRouteOpen(forRequestModel: model) {
            return ClientFacingNVIDIAFailure(
                statusCode: 503,
                message: "This NVIDIA route is temporarily quarantined by the proxy due to repeated upstream failures. Retry later or use another model.",
                reasonCode: "route_quarantined"
            )
        }

        if isChatCompletionsPath(path),
           containsUnsupportedTypedMessageContent(in: json) {
            return ClientFacingNVIDIAFailure(
                statusCode: 400,
                message: "NVIDIA hosted chat completions currently require string message content; typed content arrays are not supported on this route.",
                reasonCode: "typed_content_array"
            )
        }

        guard isChatCompletionsPath(path),
              let policy = policy(forModel: model) else {
            return nil
        }

        if policy.clientStreamingMode == .rejectBufferedMitigation,
           requestedStream(forRequestJSON: jsonString),
           !allowsDirectNVIDIAStreaming(method: method, path: path, jsonString: jsonString) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "Streaming is temporarily disabled for this NVIDIA route in the proxy because full-response normalization is required; use non-streaming chat completions.",
                reasonCode: "buffered_streaming_disabled"
            )
        }

        if let tools = json["tools"] as? [Any],
           !tools.isEmpty,
           requestedStream(forRequestJSON: jsonString) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "Streaming NVIDIA tool calls are not reliably supported through this proxy; use non-streaming chat completions.",
                reasonCode: "streaming_tool_calls"
            )
        }

        if policy.toolChoiceMode == .rejectRequiredOrFunctionChoice,
           hasStrictToolChoice(in: json) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "This NVIDIA route does not reliably preserve required/function tool-choice semantics through the proxy; use tool_choice=auto or another provider.",
                reasonCode: "strict_tool_choice"
            )
        }

        _ = route
        return nil
    }

    static func configuredRoutePreflightError(
        method: String,
        path: String,
        jsonString: String,
        headers: [(String, String)] = []
    ) -> ClientFacingNVIDIAFailure? {
        guard method == "POST",
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              let route = resolveConfiguredRoute(forRequestModel: model) else {
            return nil
        }

        if route.providerID == MetaAIWebAdapter.providerID,
           let failure = MetaAIWebAdapter.preflightFailure(path: path, body: jsonString, publicModel: model) {
            return ClientFacingNVIDIAFailure(
                statusCode: failure.statusCode,
                message: failure.message,
                reasonCode: "meta_preflight_rejection"
            )
        }

        if route.providerID == "zai",
           route.canonicalModelID == "glm-5.1",
           isResponsesPath(path) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "Z.AI glm-5.1 does not provide a reliable /v1/responses surface via this proxy; use Anthropic /v1/messages or /v1/chat/completions.",
                reasonCode: "responses_path_unsupported"
            )
        }

        return preflightError(method: method, path: path, jsonString: jsonString, headers: headers)
    }

    static func isNvidiaReasoningChatRequest(method: String, path: String, jsonString: String) -> Bool {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return false
        }

        // Only NVIDIA-hosted routes enter the NVIDIA reasoning path.
        // Non-NVIDIA models (e.g. gpt-5.4(high)) may have retryableFailureClasses
        // in their policy but must NOT enter this path.
        guard resolveNVIDIAHostedRoute(forRequestModel: normalizedRequestModel(model)) != nil else {
            return false
        }

        guard let policy = policy(forModel: model) else {
            return false
        }
        return policy.clientStreamingMode == .rejectBufferedMitigation || !policy.retryableFailureClasses.isEmpty
    }

private static func sanitizeErrorBody(_ bodyData: Data) -> String {
        // Limit error body size and redact potential sensitive information
        let maxLength = 200
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        
        // Truncate to reasonable length for telemetry
        let truncated = bodyString.prefix(maxLength)
        
        // Basic redaction of common sensitive patterns
        let sanitized = truncated
            .replacingOccurrences(of: "\"api_key\"\\s*:\\s*\"[^\"]*\"", with: "\"api_key\":\"[REDACTED]\"", options: .regularExpression)
            .replacingOccurrences(of: "\"authorization\"\\s*:\\s*\"[^\"]*\"", with: "\"authorization\":\"[REDACTED]\"", options: .regularExpression)
            .replacingOccurrences(of: "\"password\"\\s*:\\s*\"[^\"]*\"", with: "\"password\":\"[REDACTED]\"", options: .regularExpression)
            .replacingOccurrences(of: "\"token\"\\s*:\\s*\"[^\"]*\"", with: "\"token\":\"[REDACTED]\"", options: .regularExpression)
            .replacingOccurrences(of: "\"key\"\\s*:\\s*\"[^\"]*\"", with: "\"key\":\"[REDACTED]\"", options: .regularExpression)
            .replacingOccurrences(of: "\"secret\"\\s*:\\s*\"[^\"]*\"", with: "\"secret\":\"[REDACTED]\"", options: .regularExpression)
        
        return String(sanitized)
    }

    static func classifyUpstreamFailure(
        model: String,
        path: String,
        statusCode: Int,
        bodyData: Data
    ) -> ClientFacingNVIDIAFailure? {
        guard isNVIDIAHostedModel(model) else {
            return nil
        }
        
        let body = String(data: bodyData, encoding: .utf8)?.lowercased() ?? ""
        
        if isResponsesPath(path),
           statusCode == 404,
           body.contains("404 page not found") {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "NVIDIA hosted inference does not provide a reliable /v1/responses surface for this route."
            )
        }
        
        if statusCode == 429 {
            return ClientFacingNVIDIAFailure(
                statusCode: 429,
                message: "Upstream NVIDIA route is rate-limited or overloaded. Retry later."
            )
        }
        
        if statusCode == 400,
           body.contains("input should be a valid string"),
           body.contains("messages") &&
           body.contains("content") {
            return ClientFacingNVIDIAFailure(
                statusCode: 400,
                message: "NVIDIA hosted chat completions rejected non-string message content."
            )
        }
        
        if (statusCode == 403 || statusCode == 404) &&
           (body.contains("not found for account") ||
            body.contains("function") && body.contains("not found")) {
            return ClientFacingNVIDIAFailure(
                statusCode: 503,
                message: "Upstream NVIDIA model route is unavailable for chat completions on this account."
            )
        }
        
        if statusCode == 500,
           body.contains("enginecore encountered an issue") {
            return ClientFacingNVIDIAFailure(
                statusCode: 502,
                message: "Upstream NVIDIA engine error"
            )
        }
        
        if statusCode == 500 || statusCode == 502,
           body.contains("context canceled") || body.contains("context deadline exceeded") {
            return ClientFacingNVIDIAFailure(
                statusCode: 504,
                message: "Upstream proxy context canceled or timed out"
            )
        }
        
        return nil
    }

    private static let minimumAttemptTimeout: TimeInterval = scaledRequestTimeout(300)
    private static let untrustedNVIDIAProbeFirstResponseDeadline: TimeInterval = 15
    private static let untrustedNVIDIAProbeBufferedResponseDeadline: TimeInterval = 20
    private static var untrustedNVIDIAProbeDeadlineOverrideForTesting: (firstResponse: TimeInterval, bufferedResponse: TimeInterval)?

    private static func enforcedAttemptTimeout(_ timeout: TimeInterval?) -> TimeInterval? {
        guard let timeout else {
            return nil
        }
        return max(timeout, minimumAttemptTimeout)
    }

    static func attemptTimeout(forRequestJSON jsonString: String) -> TimeInterval? {
        enforcedAttemptTimeout(policy(forRequestJSON: jsonString)?.attemptTimeout)
    }

    static func attemptTimeout(forRequestModel requestModel: String) -> TimeInterval? {
        enforcedAttemptTimeout(policy(forModel: requestModel)?.attemptTimeout)
    }

    static func firstResponseDeadline(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.firstResponseDeadline
    }

    private static func nvidiaUntrustedDeadlineCap(forRequestJSON jsonString: String) -> (firstResponse: TimeInterval, bufferedResponse: TimeInterval)? {
        guard let requestModel = modelName(forRequestJSON: jsonString).map(normalizedRequestModel),
              let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel),
              route.providerID == "nvidia" else {
            return nil
        }
        guard !hasRecentStableNVIDIAInferenceSuccess(forRequestModel: requestModel) else {
            return nil
        }
        let deadlineOverride = untrustedNVIDIAProbeDeadlineOverrideForTesting
        return (
            firstResponse: deadlineOverride?.firstResponse ?? untrustedNVIDIAProbeFirstResponseDeadline,
            bufferedResponse: deadlineOverride?.bufferedResponse ?? untrustedNVIDIAProbeBufferedResponseDeadline
        )
    }

    static func untrustedNVIDIADirectRequestDeadline(
        forRequestJSON jsonString: String
    ) -> (seconds: TimeInterval, stage: DeadlineStage)? {
        guard let cap = nvidiaUntrustedDeadlineCap(forRequestJSON: jsonString) else {
            return nil
        }
        if requestedStream(forRequestJSON: jsonString) {
            return (seconds: cap.firstResponse, stage: .firstResponse)
        }
        return (seconds: cap.bufferedResponse, stage: .bufferedResponse)
    }

    static func effectiveFirstResponseDeadline(
        forRequestJSON jsonString: String,
        routeHealthStatus: RouteHealthStatus?
    ) -> TimeInterval? {
        let baseDeadline = firstResponseDeadline(forRequestJSON: jsonString)

        // If p95 first-byte latency history exists, use it for an adaptive deadline
        // regardless of trust status. This lets slow-but-functional routes get proportional
        // timeouts instead of being stuck at the 15s untrusted cap.
        if let requestModel = modelName(forRequestJSON: jsonString),
           let p95ms = rollingMetrics(forRequestModel: requestModel)?.p95FirstByteLatencyMilliseconds,
           p95ms > 0 {
            let p95Seconds = Double(p95ms) / 1000.0
            let adaptiveCap = min(max(p95Seconds * 3.0, 60.0), 360.0)
            if let baseDeadline {
                return min(baseDeadline, adaptiveCap)
            }
            return adaptiveCap
        }

        guard let cap = nvidiaUntrustedDeadlineCap(forRequestJSON: jsonString) else {
            // Trusted route with no latency history — use the full policy deadline.
            return baseDeadline
        }
        return min(baseDeadline ?? cap.firstResponse, cap.firstResponse)
    }

    static func effectiveBufferedResponseDeadline(forRequestJSON jsonString: String) -> TimeInterval? {
        let baseDeadline = bufferedResponseDeadline(forRequestJSON: jsonString)
        guard let cap = nvidiaUntrustedDeadlineCap(forRequestJSON: jsonString) else {
            return baseDeadline
        }
        return min(baseDeadline ?? cap.bufferedResponse, cap.bufferedResponse)
    }

    static func setUntrustedNVIDIAProbeDeadlineOverrideForTesting(
        firstResponse: TimeInterval?,
        bufferedResponse: TimeInterval?
    ) {
        if let firstResponse, let bufferedResponse {
            untrustedNVIDIAProbeDeadlineOverrideForTesting = (
                firstResponse: firstResponse,
                bufferedResponse: bufferedResponse
            )
        } else {
            untrustedNVIDIAProbeDeadlineOverrideForTesting = nil
        }
    }

    static func bufferedResponseDeadline(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.bufferedResponseDeadline
    }

    static func retryBudget(forRequestJSON jsonString: String) -> (transport: Int, semantic: Int, backoffMilliseconds: Int, salvagesBestEffortRepair: Bool)? {
        guard let policy = policy(forRequestJSON: jsonString) else {
            return nil
        }
        return (
            transport: policy.transportRetries,
            semantic: policy.semanticRetries,
            backoffMilliseconds: policy.retryBackoffMilliseconds,
            salvagesBestEffortRepair: policy.salvagesBestEffortRepair
        )
    }

    static func semanticFailureDisposition(
        evaluation: NvidiaReasoningEvaluation,
        semanticRetriesRemaining: Int,
        preservedBestEffortRepair: Data?,
        salvagesBestEffortRepair: Bool
    ) -> SemanticFailureDisposition {
        let bestEffortRepairedBodyData = evaluation.repairedBodyData ?? preservedBestEffortRepair

        if !evaluation.shouldRetry {
            return .returnRepaired(evaluation.normalizedBodyData ?? bestEffortRepairedBodyData ?? Data())
        }

        if semanticRetriesRemaining > 0 {
            return .retry(
                nextSemanticRetriesRemaining: semanticRetriesRemaining - 1,
                preservedBestEffortRepair: bestEffortRepairedBodyData
            )
        }

        if salvagesBestEffortRepair,
           let repairedBodyData = bestEffortRepairedBodyData {
            return .returnRepaired(repairedBodyData)
        }

        return .returnGatewayError
    }

    static func transportFailureDisposition(
        error: Error,
        transportRetriesRemaining: Int,
        salvagesBestEffortRepair: Bool,
        preservedBestEffortRepair: Data?
    ) -> TransportFailureDisposition {
        if transportRetriesRemaining > 0,
           shouldRetryNvidiaReasoningTransport(error: error) {
            return .retry(nextTransportRetriesRemaining: transportRetriesRemaining - 1)
        }

        if salvagesBestEffortRepair,
           let repairedBodyData = preservedBestEffortRepair {
            return .returnRepaired(repairedBodyData)
        }

        let nsError = error as NSError
        let statusCode = nsError.domain == NSURLErrorDomain &&
            nsError.code == URLError.Code.timedOut.rawValue ? 504 : 502
        return .returnGatewayError(
            statusCode: statusCode,
            message: statusCode == 504 ? "Gateway Timeout" : "Bad Gateway"
        )
    }

    static func resolveNVIDIARuntimeOutcome(
        path: String,
        state: NVIDIARetryState,
        attempt: NVIDIAAttemptResult
    ) -> NVIDIARuntimeOutcome {
        if let error = attempt.error {
            let effectiveError: Error
            if attempt.deadlineStage != .none {
                effectiveError = URLError(.timedOut)
            } else {
                effectiveError = error
            }
            switch transportFailureDisposition(
                error: effectiveError,
                transportRetriesRemaining: state.transportRetriesRemaining,
                salvagesBestEffortRepair: state.salvagesBestEffortRepair,
                preservedBestEffortRepair: state.bestEffortRepairedBodyData
            ) {
            case .retry(let nextTransportRetriesRemaining):
                var nextState = state
                nextState.transportRetriesRemaining = nextTransportRetriesRemaining
                return .retry(nextState)
            case .returnRepaired(let repairedBodyData):
                return .sendResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json; charset=utf-8"],
                    body: repairedBodyData
                )
            case .returnGatewayError(let statusCode, let message):
                return .sendError(statusCode: statusCode, message: message)
            }
        }

        guard let httpResponse = attempt.response,
              let bodyData = attempt.data else {
            return .sendError(statusCode: 502, message: "Bad Gateway")
        }

        if let classifiedFailure = classifyUpstreamFailure(
            model: state.model,
            path: path,
            statusCode: httpResponse.statusCode,
            bodyData: bodyData
        ) {
            return .sendError(statusCode: classifiedFailure.statusCode, message: classifiedFailure.message)
        }

        if state.transportRetriesRemaining > 0,
           shouldRetryNvidiaReasoningTransport(statusCode: httpResponse.statusCode) {
            var nextState = state
            nextState.transportRetriesRemaining -= 1
            return .retry(nextState)
        }

        let evaluation = evaluateNvidiaReasoningResponse(
            model: state.model,
            statusCode: httpResponse.statusCode,
            bodyData: bodyData,
            requiredToolParameters: state.requiredToolParameters
        )

        if evaluation.shouldRetry {
            switch semanticFailureDisposition(
                evaluation: evaluation,
                semanticRetriesRemaining: state.semanticRetriesRemaining,
                preservedBestEffortRepair: state.bestEffortRepairedBodyData,
                salvagesBestEffortRepair: state.salvagesBestEffortRepair
            ) {
            case .retry(let nextSemanticRetriesRemaining, let preservedBestEffortRepair):
                var nextState = state
                nextState.semanticRetriesRemaining = nextSemanticRetriesRemaining
                nextState.bestEffortRepairedBodyData = preservedBestEffortRepair
                return .retry(nextState)
            case .returnRepaired(let repairedBodyData):
                return .sendResponse(
                    statusCode: 200,
                    headers: httpResponse.allHeaderFields,
                    body: repairedBodyData
                )
            case .returnGatewayError:
                return .sendError(
                    statusCode: 502,
                    message: "Bad Gateway - Upstream provider returned an unusable response"
                )
            }
        }

        return .sendResponse(
            statusCode: httpResponse.statusCode,
            headers: httpResponse.allHeaderFields,
            body: evaluation.normalizedBodyData ?? bodyData
        )
    }

    static func telemetryEvent(
        path: String,
        state: NVIDIARetryState,
        attempt: NVIDIAAttemptResult,
        outcome: NVIDIARuntimeOutcome,
        source: String,
        attemptLane: Int = 1,
        proxyRequestID: String? = nil,
        callerRequestID: String? = nil,
        callerSessionID: String? = nil,
        requestShape: String? = nil,
        errorBodyData: Data? = nil
    ) -> RouteTelemetryEvent {
        let canonicalModelID = resolveConfiguredRoute(forRequestModel: state.model)?.canonicalModelID ?? state.model
        let retryCount = max(0, state.initialTransportRetries - state.transportRetriesRemaining) +
            max(0, state.initialSemanticRetries - state.semanticRetriesRemaining)
        let upstreamHTTPStatus = attempt.response?.statusCode
        let snippet = sanitizeErrorBodySnippet(errorBodyData ?? attempt.data)

        if let error = attempt.error {
            let failureClass: String
            if attempt.deadlineStage != .none {
                failureClass = attempt.deadlineStage == .firstResponse
                    ? "transport_timeout_first_byte"
                    : "transport_timeout"
            } else if shouldRetryNvidiaReasoningTransport(error: error) {
                failureClass = "transport_error_retryable"
            } else {
                failureClass = "transport_error"
            }
            return RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: state.model,
                canonicalModelID: canonicalModelID,
                transportOutcome: outcomeTelemetryLabel(outcome),
                attemptLane: attemptLane,
                failureClass: failureClass,
                timeoutStage: attempt.deadlineStage,
                upstreamHTTPStatus: upstreamHTTPStatus,
                retryCount: retryCount,
                source: source,
                firstByteLatencyMilliseconds: attempt.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: attempt.totalLatencyMilliseconds,
                proxyRequestID: proxyRequestID,
                callerRequestID: callerRequestID,
                callerSessionID: callerSessionID,
                requestShape: requestShape,
                negotiatedApplicationProtocol: attempt.negotiatedApplicationProtocol,
                errorBodySnippet: snippet
            )
        }

        if let response = attempt.response,
           let bodyData = attempt.data,
           let classifiedFailure = classifyUpstreamFailure(
                model: state.model,
                path: path,
                statusCode: response.statusCode,
                bodyData: bodyData
           ) {
            let failureClass: String
            if response.statusCode == 429 {
                failureClass = failureClassFor429(
                    headers: response.allHeaderFields,
                    bodyData: bodyData
                )
            } else {
                failureClass = "classified_\(classifiedFailure.statusCode)"
            }
            return RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: state.model,
                canonicalModelID: canonicalModelID,
                transportOutcome: outcomeTelemetryLabel(outcome),
                attemptLane: attemptLane,
                failureClass: failureClass,
                timeoutStage: attempt.deadlineStage,
                upstreamHTTPStatus: response.statusCode,
                retryCount: retryCount,
                source: source,
                firstByteLatencyMilliseconds: attempt.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: attempt.totalLatencyMilliseconds,
                proxyRequestID: proxyRequestID,
                callerRequestID: callerRequestID,
                callerSessionID: callerSessionID,
                requestShape: requestShape
            )
        }

        if let response = attempt.response,
           let bodyData = attempt.data {
            if !(200...299).contains(response.statusCode) {
                let failureClass: String
                if response.statusCode == 429 {
                    failureClass = failureClassFor429(
                        headers: response.allHeaderFields,
                        bodyData: bodyData
                    )
                } else {
                    failureClass = "classified_\(response.statusCode)"
                }
                return RouteTelemetryEvent(
                    timestamp: Date(),
                    requestModel: state.model,
                    canonicalModelID: canonicalModelID,
                    transportOutcome: outcomeTelemetryLabel(outcome),
                    attemptLane: attemptLane,
                    failureClass: failureClass,
                    timeoutStage: attempt.deadlineStage,
                    upstreamHTTPStatus: response.statusCode,
                    retryCount: retryCount,
                    source: source,
                    firstByteLatencyMilliseconds: attempt.firstByteLatencyMilliseconds,
                    totalLatencyMilliseconds: attempt.totalLatencyMilliseconds,
                    proxyRequestID: proxyRequestID,
                    callerRequestID: callerRequestID,
                    callerSessionID: callerSessionID,
                    requestShape: requestShape,
                    errorBodySnippet: snippet
                )
            }

            let evaluation = evaluateNvidiaReasoningResponse(
                model: state.model,
                statusCode: response.statusCode,
                bodyData: bodyData
            )
            return RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: state.model,
                canonicalModelID: canonicalModelID,
                transportOutcome: outcomeTelemetryLabel(outcome),
                attemptLane: attemptLane,
                failureClass: evaluation.retryReason,
                timeoutStage: attempt.deadlineStage,
                upstreamHTTPStatus: response.statusCode,
                retryCount: retryCount,
                source: source,
                firstByteLatencyMilliseconds: attempt.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: attempt.totalLatencyMilliseconds,
                proxyRequestID: proxyRequestID,
                callerRequestID: callerRequestID,
                callerSessionID: callerSessionID,
                requestShape: requestShape,
                negotiatedApplicationProtocol: attempt.negotiatedApplicationProtocol,
                errorBodySnippet: snippet
            )
        }

        return RouteTelemetryEvent(
            timestamp: Date(),
            requestModel: state.model,
            canonicalModelID: canonicalModelID,
            transportOutcome: outcomeTelemetryLabel(outcome),
            attemptLane: attemptLane,
            failureClass: "missing_response_material",
            timeoutStage: attempt.deadlineStage,
            upstreamHTTPStatus: upstreamHTTPStatus,
            retryCount: retryCount,
            source: source,
            firstByteLatencyMilliseconds: attempt.firstByteLatencyMilliseconds,
            totalLatencyMilliseconds: attempt.totalLatencyMilliseconds,
            proxyRequestID: proxyRequestID,
            callerRequestID: callerRequestID,
            callerSessionID: callerSessionID,
            requestShape: requestShape,
            negotiatedApplicationProtocol: attempt.negotiatedApplicationProtocol,
            errorBodySnippet: snippet
        )
    }

    private static func outcomeTelemetryLabel(_ outcome: NVIDIARuntimeOutcome) -> String {
        switch outcome {
        case .retry:
            return "retry"
        case .sendResponse:
            return "send_response"
        case .sendError:
            return "send_error"
        }
    }

    static func rawModelName(forRequestJSON jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return nil
        }
        return model
    }

    static func modelName(forRequestJSON jsonString: String) -> String? {
        guard let model = rawModelName(forRequestJSON: jsonString) else {
            return nil
        }
        return normalizedRequestModel(model)
    }

    static func normalizedRequestModelRewrite(
        method: String,
        path: String,
        jsonString: String
    ) -> (rewrittenJSONString: String, originalModel: String, normalizedModel: String)? {
        guard let originalModel = rawModelName(forRequestJSON: jsonString) else {
            return nil
        }
        let normalizedModel = normalizedRequestModel(originalModel)
        guard normalizedModel != originalModel,
              let rewrittenJSONString = rewrittenRequestJSON(
                method: method,
                path: path,
                replacingRequestModelIn: jsonString,
                with: normalizedModel
              ) else {
            return nil
        }
        return (rewrittenJSONString, originalModel, normalizedModel)
    }

    static func filteredModelListBodyRemovingOpenNVIDIARoutes(_ bodyData: Data, now: Date = Date()) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            return nil
        }

        let unavailableModelIDs = unavailableRequestModelIDs(at: now)
        var changed = false
        var seenNormalizedIDs: Set<String> = []
        let filteredData = data.compactMap { entry -> [String: Any]? in
            guard let id = entry["id"] as? String else {
                return entry
            }
            let normalizedID = normalizedRequestModel(id)
            let keep = !unavailableModelIDs.contains(id) && !unavailableModelIDs.contains(normalizedID)
            if !keep {
                changed = true
                return nil
            }

            var filteredEntry = entry
            if normalizedID != id {
                filteredEntry["id"] = normalizedID
                changed = true
            }

            guard seenNormalizedIDs.insert(normalizedID).inserted else {
                changed = true
                return nil
            }

            return filteredEntry
        }

        guard changed else {
            return nil
        }

        var filteredJSON = json
        filteredJSON["data"] = filteredData
        guard let filteredBody = try? JSONSerialization.data(withJSONObject: filteredJSON) else {
            return nil
        }
        return filteredBody
    }

    static func quarantinedNVIDIAHostedRequestModels(at now: Date = Date()) -> [String] {
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let routesByHealthKey = resolvedRoutesByRequestModel().values.reduce(into: [String: OpenAICompatTemporaryShim.RouteIdentity]()) { routesByHealthKey, route in
                routesByHealthKey[route.routeHealthKey] = route
            }
            return routeCircuitStatesByRouteHealthKey.compactMap { routeHealthKey, state in
                guard state.isUnavailable(at: now),
                      let route = routesByHealthKey[routeHealthKey] else {
                    return nil
                }
                return route.canonicalModelID
            }.sorted()
        }
    }

    static func quarantinedRequestModels(at now: Date = Date()) -> [String] {
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let routes = resolvedRoutesByRequestModel()
            let requestModelsByRouteHealthKey = Dictionary(grouping: routes.keys) { requestModel in
                routes[requestModel]?.routeHealthKey ?? requestModel
            }
            return routeCircuitStatesByRouteHealthKey.compactMap { routeHealthKey, state in
                guard state.isUnavailable(at: now) else { return nil }
                if let candidates = requestModelsByRouteHealthKey[routeHealthKey] {
                    return preferredRouteHealthDisplayRequestModel(
                        from: candidates,
                        routes: routes
                    )
                }
                return routeHealthKey.components(separatedBy: "::").last
            }.sorted()
        }
    }

    static func canaryProbeRequestModels(at now: Date = Date()) -> [String] {
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let routes = resolvedRoutesByRequestModel()
            let requestModelsByRouteHealthKey = Dictionary(grouping: routes.keys) { requestModel in
                routes[requestModel]?.routeHealthKey ?? requestModel
            }

            return routeCircuitStatesByRouteHealthKey.compactMap { routeHealthKey, state in
                guard shouldProbeRouteWithCanary(
                    routeHealthKey: routeHealthKey,
                    state: state,
                    at: now
                ) else {
                    return nil
                }
                if let candidates = requestModelsByRouteHealthKey[routeHealthKey] {
                    return preferredCanaryProbeRequestModel(
                        from: candidates,
                        routes: routes
                    )
                }
                return routeHealthKey.components(separatedBy: "::").last
            }.sorted()
        }
    }

    private static func preferredRouteHealthDisplayRequestModel(
        from candidates: [String],
        routes: [String: RouteIdentity]
    ) -> String? {
        if candidates.contains(publicNVIDIADirectAlias) {
            return publicNVIDIADirectAlias
        }
        if candidates.contains(where: { candidate in
            guard let route = routes[candidate] else { return false }
            return route.providerID.hasPrefix("nvidia") && route.canonicalModelID == "z-ai/glm5"
        }) {
            return publicNVIDIADirectAlias
        }
        return preferredConcreteRequestModel(from: candidates, routes: routes)
    }

    private static func preferredConcreteRequestModel(
        from candidates: [String],
        routes: [String: RouteIdentity]
    ) -> String? {
        return candidates.sorted { lhs, rhs in
            let lhsIsSmartAlias = smartAliasDefinition(forRequestModel: lhs) != nil
            let rhsIsSmartAlias = smartAliasDefinition(forRequestModel: rhs) != nil
            if lhsIsSmartAlias != rhsIsSmartAlias {
                return !lhsIsSmartAlias
            }

            let lhsIsCanonical = routes[lhs]?.canonicalModelID == lhs
            let rhsIsCanonical = routes[rhs]?.canonicalModelID == rhs
            if lhsIsCanonical != rhsIsCanonical {
                return !lhsIsCanonical
            }

            let lhsIsCustom = lhs.hasPrefix("custom:")
            let rhsIsCustom = rhs.hasPrefix("custom:")
            if lhsIsCustom != rhsIsCustom {
                return !lhsIsCustom
            }

            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs < rhs
        }.first
    }

    private static func preferredCanaryProbeRequestModel(
        from candidates: [String],
        routes: [String: RouteIdentity]
    ) -> String? {
        if candidates.contains(where: { candidate in
            guard let route = routes[candidate] else { return false }
            return route.providerID.hasPrefix("nvidia") && route.canonicalModelID == "z-ai/glm5"
        }) {
            return publicNVIDIASmartAlias
        }

        let nonDirectCandidates = candidates.filter { $0 != publicNVIDIADirectAlias }
        let hasNVIDIADirectAlias = candidates.contains(publicNVIDIADirectAlias)
        let hasNonDirectNVIDIA = nonDirectCandidates.contains { candidate in
            guard let route = routes[candidate] else { return false }
            return route.providerID.hasPrefix("nvidia") && route.canonicalModelID == "z-ai/glm5"
        }
        if hasNVIDIADirectAlias, hasNonDirectNVIDIA,
           let preferredNonDirect = preferredConcreteRequestModel(
            from: nonDirectCandidates,
            routes: routes
        ) {
            return preferredNonDirect
        }
        return preferredRouteHealthDisplayRequestModel(
            from: candidates,
            routes: routes
        )
    }

    fileprivate static func routeIdentityForHealthTracking(forRequestModel requestModel: String) -> RouteIdentity? {
        if let route = resolveConfiguredRoute(forRequestModel: requestModel) {
            return route
        }
        if let smartAlias = smartAliasDefinition(forRequestModel: requestModel),
           let primaryCandidate = smartAlias.candidates.first {
            return resolveConfiguredRoute(forRequestModel: primaryCandidate)
        }
        if let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) {
            return route
        }
        return nil
    }

    static func resolveRouteIdentityForAnyProvider(
        forRequestModel requestModel: String
    ) -> RouteIdentity? {
        if let route = resolveConfiguredRoute(forRequestModel: requestModel) {
            return route
        }
        let normalized = normalizedRequestModel(requestModel)
        if let factoryBinding = ThinkingProxy.factoryModelBinding(forIncomingModelID: requestModel)
            ?? ThinkingProxy.factoryModelBinding(forIncomingModelID: normalized) {
            if let resolvedBoundRoute = resolveConfiguredRoute(forRequestModel: factoryBinding.routeModel) {
                return resolvedBoundRoute
            }
            return RouteIdentity(
                providerID: factoryBinding.routeProvider,
                canonicalModelID: factoryBinding.routeModel
            )
        }
        for (prefix, providerID) in ProviderCatalog.oauthPassthroughPrefixes {
            if normalized.hasPrefix(prefix) {
                return RouteIdentity(providerID: providerID, canonicalModelID: normalized)
            }
        }
        return nil
    }

    static func routeHealthStatus(forRequestModel requestModel: String, at now: Date = Date()) -> RouteHealthStatus? {
        _ = now
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return nil
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            guard let state = routeCircuitStatesByRouteHealthKey[route.routeHealthKey] else { return nil }
            return state.status == .closed ? nil : state.status
        }
    }

    static func rollingMetrics(forRequestModel requestModel: String) -> RouteRollingMetrics? {
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return nil
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.rollingMetrics
        }
    }

    static func routeHealthState(forRequestModel requestModel: String) -> RouteCircuitState? {
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return nil
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]
        }
    }

    static func routeCooldownUntil(forRequestModel requestModel: String, at now: Date = Date()) -> Date? {
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return nil
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            guard let cooldownUntil = routeCooldownsByRouteHealthKey[route.routeHealthKey],
                  cooldownUntil > now else {
                return nil
            }
            return cooldownUntil
        }
    }

    static func nextRetryHint(
        forRequestModel requestModel: String,
        at now: Date = Date()
    ) -> (seconds: Int, reason: String)? {
        if let cooldownUntil = routeCooldownUntil(forRequestModel: requestModel, at: now),
           cooldownUntil > now {
            return (max(1, Int(ceil(cooldownUntil.timeIntervalSince(now)))), "cooldown")
        }
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel),
              concurrencyRegistry.isAtCapacity(routeHealthKey: route.routeHealthKey) else {
            return nil
        }
        return (1, "concurrency")
    }

    static func latencyDiagnostics(forRequestModel requestModel: String) -> RouteLatencyDiagnostics? {
        guard let metrics = rollingMetrics(forRequestModel: requestModel) else {
            return nil
        }

        let slowFirstByteThresholdMilliseconds = policy(forModel: requestModel)?
            .firstResponseDeadline
            .map { Int($0 * 1000) }
        let slowTotalThresholdMilliseconds = policy(forModel: requestModel)?
            .attemptTimeout
            .map { Int($0 * 1000) }

        let p95FirstByte = metrics.p95FirstByteLatencyMilliseconds
        let p95Total = metrics.p95TotalLatencyMilliseconds

        let pressureStatus: String
        if let p95Total, let threshold = slowTotalThresholdMilliseconds, p95Total >= Int(Double(threshold) * 0.9) {
            pressureStatus = "severe"
        } else if let p95FirstByte, let threshold = slowFirstByteThresholdMilliseconds, p95FirstByte >= Int(Double(threshold) * 0.9) {
            pressureStatus = "severe"
        } else if let p95Total, let threshold = slowTotalThresholdMilliseconds, p95Total >= Int(Double(threshold) * 0.75) {
            pressureStatus = "elevated"
        } else if let p95FirstByte, let threshold = slowFirstByteThresholdMilliseconds, p95FirstByte >= Int(Double(threshold) * 0.75) {
            pressureStatus = "elevated"
        } else {
            pressureStatus = "normal"
        }

        return RouteLatencyDiagnostics(
            averageFirstByteLatencyMilliseconds: metrics.averageFirstByteLatencyMilliseconds,
            p95FirstByteLatencyMilliseconds: p95FirstByte,
            averageTotalLatencyMilliseconds: metrics.averageTotalLatencyMilliseconds,
            p95TotalLatencyMilliseconds: p95Total,
            slowFirstByteThresholdMilliseconds: slowFirstByteThresholdMilliseconds,
            slowTotalThresholdMilliseconds: slowTotalThresholdMilliseconds,
            pressureStatus: pressureStatus
        )
    }

    static func recommendedNVIDIAHedgeDelay(forRequestModel requestModel: String) -> TimeInterval {
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return defaultSuspectHedgeDelay
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return recommendedNVIDIAHedgeDelay(
                metrics: routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.rollingMetrics
            )
        }
    }

    static func recommendedCanaryInterval() -> TimeInterval {
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let metrics = routeCircuitStatesByRouteHealthKey.values
                .filter { $0.isUnavailable(at: Date()) }
                .map(\.rollingMetrics)
            return recommendedCanaryInterval(metrics: metrics)
        }
    }

    static func isConfiguredRouteOpen(forRequestModel requestModel: String, at now: Date = Date()) -> Bool {
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return false
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            guard let state = routeCircuitStatesByRouteHealthKey[route.routeHealthKey] else { return false }
            // halfOpen routes are probeable — allow them through for candidate selection
            // so the circuit breaker recovery mechanism can test the route.
            if state.status == .halfOpen { return false }
            return state.isUnavailable(at: now)
        }
    }

    static func isNVIDIAHostedRouteOpen(forRequestModel requestModel: String, at now: Date = Date()) -> Bool {
        guard let route = resolveNVIDIAHostedRoute(forRequestModel: requestModel) else {
            return false
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.isUnavailable(at: now) ?? false
        }
    }

    // Concurrency-aware failure tracking: deduplicate failures within window per route
    private static let routeFailureDedupQueue = DispatchQueue(label: "io.automaze.vibeproxy.route-failure-dedup")
    private static var recentFailureTimestampsByRoute: [String: [Date]] = [:]
    private struct RouteFailureBurstInfo {
        let recentFailureCount: Int
        let burstDeduplicated: Bool
    }
    private static let failureDedupWindow: TimeInterval = 0.2  // 200ms burst window
    private static var disableFailureDedupForTesting = false

    private static func adaptiveConcurrencyDeferralUntil(
        routeHealthKey: String,
        currentState: RouteCircuitState?,
        existingCooldownUntil: Date?,
        telemetryEvent: RouteTelemetryEvent?,
        forcedOpenUntil: Date?,
        now: Date
    ) -> Date? {
        var deferredUntil = [existingCooldownUntil, forcedOpenUntil].compactMap { $0 }.max()

        guard let telemetryEvent,
              telemetryEvent.failureClass?.lowercased() == "classified_429_concurrency" else {
            return deferredUntil
        }

        // When upstream already supplied an explicit short retry window for this request,
        // honor it exactly instead of inflating it into the proxy's learned fallback deferral.
        if deferredUntil != nil {
            return deferredUntil
        }

        let inflightAtRequest = telemetryEvent.inflightAtRequest ??
            concurrencyRegistry.currentInflight(routeHealthKey: routeHealthKey)
        let repeatedConcurrencyFailure =
            currentState?.lastTelemetryEvent.map { lastTelemetryEvent in
                guard lastTelemetryEvent.failureClass?.lowercased() == "classified_429_concurrency" else {
                    return false
                }
                return now.timeIntervalSince(lastTelemetryEvent.timestamp) <= concurrency429RepeatWindow
            } ?? false

        let minimumDeferral: TimeInterval
        if inflightAtRequest <= 1 {
            // Single-flight "concurrency" 429s are ambiguous. If upstream already told us the
            // retry window, honor that explicit hint instead of inflating it into a long
            // route-level cooldown that pushes traffic onto lower-priority fallbacks for minutes.
            if deferredUntil != nil {
                return deferredUntil
            }
            minimumDeferral = repeatedConcurrencyFailure
                ? repeatedSingleFlightConcurrency429Deferral
                : singleFlightConcurrency429Deferral
        } else {
            minimumDeferral = repeatedConcurrencyFailure
                ? repeatedConcurrency429Deferral
                : concurrency429Deferral
        }

        let adaptiveUntil = now.addingTimeInterval(minimumDeferral)
        if deferredUntil == nil || adaptiveUntil > deferredUntil! {
            deferredUntil = adaptiveUntil
        }
        return deferredUntil
    }

    private static func noteFailureBurst(
        routeHealthKey: String,
        at now: Date
    ) -> RouteFailureBurstInfo {
        routeFailureDedupQueue.sync {
            var timestamps = recentFailureTimestampsByRoute[routeHealthKey] ?? []
            timestamps.removeAll { now.timeIntervalSince($0) > adaptiveFailureEscalationWindow }

            if !disableFailureDedupForTesting,
               let last = timestamps.last,
               now.timeIntervalSince(last) <= failureDedupWindow {
                recentFailureTimestampsByRoute[routeHealthKey] = timestamps
                return RouteFailureBurstInfo(
                    recentFailureCount: timestamps.count,
                    burstDeduplicated: true
                )
            }

            timestamps.append(now)
            recentFailureTimestampsByRoute[routeHealthKey] = timestamps
            return RouteFailureBurstInfo(
                recentFailureCount: timestamps.count,
                burstDeduplicated: false
            )
        }
    }

    private static func adaptiveFailureOpenUntil(
        currentOpenUntil: Date?,
        recentFailureCount: Int,
        now: Date
    ) -> Date? {
        guard Double(recentFailureCount) >= routeCircuitBreakerPolicy.failureThreshold else {
            return currentOpenUntil
        }

        let escalationExponent = max(0, recentFailureCount - Int(routeCircuitBreakerPolicy.failureThreshold))
        let multiplier = min(
            adaptiveFailureCooldownMaxMultiplier,
            Int(pow(2.0, Double(escalationExponent)))
        )
        let escalatedUntil = now.addingTimeInterval(routeCircuitBreakerPolicy.cooldown * TimeInterval(multiplier))

        guard let currentOpenUntil else {
            return escalatedUntil
        }
        return max(currentOpenUntil, escalatedUntil)
    }

    static func recordRouteFailure(
        forRequestModel requestModel: String,
        telemetryEvent: RouteTelemetryEvent? = nil,
        at now: Date = Date(),
        forcedOpenUntil: Date? = nil,
        healthSensitivity: HealthSensitivity? = nil
    ) {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return
        }

        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let current = routeCircuitStatesByRouteHealthKey[route.routeHealthKey]
            let failureBurst = noteFailureBurst(
                routeHealthKey: route.routeHealthKey,
                at: now
            )

            let normalizedFailureClass = telemetryEvent?.failureClass?.lowercased()

            if normalizedFailureClass == "classified_429_overload" {
                // Overload 429s are transient provider pressure, not evidence that
                // the route itself is unhealthy. Preserve telemetry, but do not
                // change circuit state, cooldowns, or ranking inputs.
                if let telemetryEvent {
                    let currentStatus = current?.status ?? .closed
                    let enrichedTelemetryEvent = enrichTelemetryEvent(
                        telemetryEvent,
                        from: currentStatus,
                        to: currentStatus
                    )
                    logNVIDIARouteTelemetry(enrichedTelemetryEvent)
                }
                return
            }

            if normalizedFailureClass == "classified_429_concurrency" {
                // Concurrency 429s should influence short retry routing and the
                // learned concurrency registry, but they are not evidence that
                // the route itself is unhealthy. Preserve the current route
                // state, emit telemetry, and only update the availability
                // deferral window.
                let currentStatus = current?.status ?? .closed
                let enrichedTelemetryEvent = telemetryEvent.map {
                    enrichTelemetryEvent($0, from: currentStatus, to: currentStatus)
                }
                let probeState = updatedNVIDIAInferenceProbeState(
                    current: current?.nvidiaInferenceProbe,
                    route: route,
                    telemetryEvent: enrichedTelemetryEvent
                )
                let preservedState = routeCircuitState(
                    current ?? RouteCircuitState(
                        status: .closed,
                        failureScore: 0,
                        recoverySuccesses: 0,
                        openUntil: nil,
                        lastScoreUpdatedAt: now,
                        lastTelemetryEvent: nil,
                        rollingMetrics: .empty,
                        emaMetrics: .empty,
                        recoveredAt: nil
                    ),
                    replacingLastTelemetryEvent: enrichedTelemetryEvent,
                    replacingNVIDIAInferenceProbe: probeState
                )
                routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = preservedState
                if let cooldownUntil = adaptiveConcurrencyDeferralUntil(
                    routeHealthKey: route.routeHealthKey,
                    currentState: current,
                    existingCooldownUntil: routeCooldownsByRouteHealthKey[route.routeHealthKey],
                    telemetryEvent: enrichedTelemetryEvent,
                    forcedOpenUntil: forcedOpenUntil,
                    now: now
                ), now < cooldownUntil {
                    routeCooldownsByRouteHealthKey[route.routeHealthKey] = cooldownUntil
                }
                scheduleRouteHealthPersistLocked()
                if let enrichedTelemetryEvent {
                    logNVIDIARouteTelemetry(enrichedTelemetryEvent)
                }
                return
            }

            // Always count failures — the circuit breaker threshold dampens rapid failures naturally

            var nextState = nextRouteCircuitState(
                current: current,
                afterFailureAt: now,
                routeHealthKey: route.routeHealthKey,
                telemetryEvent: telemetryEvent,
                burstDeduplicated: failureBurst.burstDeduplicated,
                policy: routeCircuitBreakerPolicy,
                forcedOpenUntil: forcedOpenUntil,
                healthSensitivity: healthSensitivity
            )
            if nextState.status == .open,
               let adaptiveOpenUntil = adaptiveFailureOpenUntil(
                    currentOpenUntil: nextState.openUntil,
                    recentFailureCount: failureBurst.recentFailureCount,
                    now: now
               ) {
                nextState = RouteCircuitState(
                    status: nextState.status,
                    failureScore: nextState.failureScore,
                    recoverySuccesses: nextState.recoverySuccesses,
                    openUntil: adaptiveOpenUntil,
                    lastScoreUpdatedAt: nextState.lastScoreUpdatedAt,
                    lastTelemetryEvent: nextState.lastTelemetryEvent,
                    rollingMetrics: nextState.rollingMetrics,
                    emaMetrics: nextState.emaMetrics,
                    recoveredAt: nextState.recoveredAt,
                    lastSuccessAt: nextState.lastSuccessAt,
                    lastLiveSuccessAt: nextState.lastLiveSuccessAt,
                    lastSuccessRequestID: nextState.lastSuccessRequestID,
                    lastFailureAt: nextState.lastFailureAt,
                    lastFailureClass: nextState.lastFailureClass,
                    nvidiaInferenceProbe: nextState.nvidiaInferenceProbe
                )
            }
            let enrichedTelemetryEvent = telemetryEvent.map {
                enrichTelemetryEvent($0, from: current?.status ?? .closed, to: nextState.status)
            }
            let probeState = updatedNVIDIAInferenceProbeState(
                current: current?.nvidiaInferenceProbe,
                route: route,
                telemetryEvent: enrichedTelemetryEvent
            )
            nextState = routeCircuitState(
                nextState,
                replacingLastTelemetryEvent: enrichedTelemetryEvent,
                replacingNVIDIAInferenceProbe: probeState
            )
            if current?.status != nextState.status {
                NSLog(
                    "[ThinkingProxy] Route health transition %@: %@ -> %@",
                    route.routeHealthKey,
                    (current?.status ?? .closed).rawValue,
                    nextState.status.rawValue
                )
            }
            routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = nextState
            if let cooldownUntil = adaptiveConcurrencyDeferralUntil(
                routeHealthKey: route.routeHealthKey,
                currentState: current,
                existingCooldownUntil: routeCooldownsByRouteHealthKey[route.routeHealthKey],
                telemetryEvent: enrichedTelemetryEvent,
                forcedOpenUntil: forcedOpenUntil,
                now: now
            ), now < cooldownUntil {
                routeCooldownsByRouteHealthKey[route.routeHealthKey] = cooldownUntil
            }
            scheduleRouteHealthPersistLocked()
            if let enrichedTelemetryEvent {
                logNVIDIARouteTelemetry(enrichedTelemetryEvent)
            }
        }
    }

    static func recordRouteAvailabilityDeferral(
        forRequestModel requestModel: String,
        until deferredUntil: Date,
        at now: Date = Date()
    ) {
        guard deferredUntil > now,
              let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return
        }
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let current = routeCooldownsByRouteHealthKey[route.routeHealthKey]
            if current == nil || deferredUntil > current! {
                routeCooldownsByRouteHealthKey[route.routeHealthKey] = deferredUntil
                scheduleRouteHealthPersistLocked()
            }
        }
    }

    static func recordRouteSuccess(
        forRequestModel requestModel: String,
        telemetryEvent: RouteTelemetryEvent? = nil,
        at now: Date = Date()
    ) {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return
        }
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let current = routeCircuitStatesByRouteHealthKey[route.routeHealthKey]
            var nextState = nextRouteCircuitStateAfterSuccess(
                current: current,
                telemetryEvent: telemetryEvent,
                at: now,
                policy: routeCircuitBreakerPolicy
            )
            let enrichedTelemetryEvent = telemetryEvent.map {
                enrichTelemetryEvent($0, from: current?.status ?? .closed, to: nextState.status)
            }
            let probeState = updatedNVIDIAInferenceProbeState(
                current: current?.nvidiaInferenceProbe,
                route: route,
                telemetryEvent: enrichedTelemetryEvent
            )
            nextState = routeCircuitState(
                nextState,
                replacingLastTelemetryEvent: enrichedTelemetryEvent,
                replacingNVIDIAInferenceProbe: probeState
            )
            if current?.status != nextState.status {
                NSLog(
                    "[ThinkingProxy] Route health transition %@: %@ -> %@",
                    route.routeHealthKey,
                    (current?.status ?? .closed).rawValue,
                    nextState.status.rawValue
                )
            }
            routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = nextState
            concurrencyRegistry.recordSuccess(routeHealthKey: route.routeHealthKey)
            if let telemetryEvent,
               telemetryEvent.source == "smart_alias",
               let requestedAlias = telemetryEvent.requestedAlias {
                let winningRequestModel = telemetryEvent.finalWinnerRequestModel ?? requestModel
                recentSmartAliasWinnerByRequestedAlias[requestedAlias] = RecentSmartAliasWinner(
                    requestModel: winningRequestModel,
                    timestamp: telemetryEvent.timestamp,
                    requestShape: telemetryEvent.requestShape,
                    callerRequestID: telemetryEvent.callerRequestID,
                    callerSessionID: telemetryEvent.callerSessionID
                )
            }
            scheduleRouteHealthPersistLocked()
            if let enrichedTelemetryEvent {
                logNVIDIARouteTelemetry(enrichedTelemetryEvent)
            }
        }
    }

    static func clearRouteHealthForTesting() {
        disableFailureDedupForTesting = false
        routeHealthQueue.sync {
            routeHealthPersistWorkItem?.cancel()
            routeHealthPersistWorkItem = nil
            routeHealthDirty = false
            routeCircuitStatesByRouteHealthKey = [:]
            routeCooldownsByRouteHealthKey = [:]
            recentSmartAliasDispatchByRequestedAlias = [:]
            recentSmartAliasWinnerByRequestedAlias = [:]
            hasLoadedPersistedRouteHealth = true
            persistRouteHealthLocked()
        }
        routeFailureDedupQueue.sync {
            recentFailureTimestampsByRoute = [:]
        }
        concurrencyRegistry.resetForTesting()
    }

    static func routeAvailabilityDeferralUntilForTesting(requestModel: String) -> Date? {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return nil
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCooldownsByRouteHealthKey[route.routeHealthKey]
        }
    }

    static func forceOpenRouteForTesting(requestModel: String, until: Date) {
        guard let route = routeIdentityForHealthTracking(forRequestModel: requestModel) else {
            return
        }
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = RouteCircuitState(
                status: .open,
                failureScore: routeCircuitBreakerPolicy.failureThreshold,
                recoverySuccesses: 0,
                openUntil: until,
                lastScoreUpdatedAt: until,
                lastTelemetryEvent: nil,
                rollingMetrics: .empty,
                emaMetrics: .empty,
                recoveredAt: nil,
                lastLiveSuccessAt: routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.lastLiveSuccessAt,
                nvidiaInferenceProbe: routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.nvidiaInferenceProbe
            )
            persistRouteHealthLocked()
        }
    }

    static func routeHealthSnapshotByRequestModel() -> [String: RouteCircuitState] {
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            var routes = resolvedRoutesByRequestModel()
            if let bindings = ThinkingProxy.factoryModelBindings()?.bindingsByIncomingModelID {
                for (requestModel, _) in bindings {
                    if let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) {
                        routes[requestModel] = route
                    }
                }
            }
            let requestModelsByRouteHealthKey = Dictionary(grouping: routes.keys) { requestModel in
                routes[requestModel]?.routeHealthKey ?? requestModel
            }
            return routeCircuitStatesByRouteHealthKey.reduce(into: [String: RouteCircuitState]()) { snapshot, entry in
                let routeHealthKey = entry.key
                let state = entry.value
                if let candidates = requestModelsByRouteHealthKey[routeHealthKey],
                   let requestModel = preferredRouteHealthDisplayRequestModel(
                        from: candidates,
                        routes: routes
                   ) {
                    snapshot[requestModel] = state
                    return
                }
                let fallbackRequestModel = routeHealthKey.components(separatedBy: "::").last ?? routeHealthKey
                snapshot[fallbackRequestModel] = state
            }
        }
    }

    fileprivate static func latestObservedSmartAliasResolvedWinner(
        forRequestedAlias requestedAlias: String,
        maxAge: TimeInterval = 30,
        at now: Date = Date()
    ) -> ThinkingProxy.RecentObservedSmartAliasWinner? {
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let freshestObservedWinner = routeCircuitStatesByRouteHealthKey.values
                .compactMap(\.lastTelemetryEvent)
                .compactMap { event -> ThinkingProxy.RecentObservedSmartAliasWinner? in
                    guard event.requestedAlias == requestedAlias,
                          event.source == "smart_alias",
                          now.timeIntervalSince(event.timestamp) <= maxAge else {
                        return nil
                    }

                    if let finalWinnerRequestModel = event.finalWinnerRequestModel {
                        return ThinkingProxy.RecentObservedSmartAliasWinner(
                            timestamp: event.timestamp,
                            requestModel: finalWinnerRequestModel,
                            requestShape: event.requestShape,
                            callerRequestID: event.callerRequestID,
                            callerSessionID: event.callerSessionID
                        )
                    }

                    guard event.transportOutcome == "send_response",
                          event.failureClass == nil,
                          let upstreamHTTPStatus = event.upstreamHTTPStatus,
                          (200..<300).contains(upstreamHTTPStatus) else {
                        return nil
                    }

                    return ThinkingProxy.RecentObservedSmartAliasWinner(
                        timestamp: event.timestamp,
                        requestModel: event.requestModel,
                        requestShape: event.requestShape,
                        callerRequestID: event.callerRequestID,
                        callerSessionID: event.callerSessionID
                    )
                }
                .max { lhs, rhs in
                    lhs.timestamp < rhs.timestamp
                }

            return freshestObservedWinner
        }
    }

    static func latestObservedSmartAliasResolvedModel(
        forRequestedAlias requestedAlias: String,
        maxAge: TimeInterval = 30,
        at now: Date = Date()
    ) -> String? {
        latestObservedSmartAliasResolvedWinner(
            forRequestedAlias: requestedAlias,
            maxAge: maxAge,
            at: now
        )?.requestModel
    }

    static func hasRecentInferenceSuccess(
        forRequestModel requestModel: String,
        maxAge: TimeInterval = 300,
        at now: Date = Date()
    ) -> Bool {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return false
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            guard let state = routeCircuitStatesByRouteHealthKey[route.routeHealthKey],
                  let lastSuccessAt = state.lastSuccessAt else {
                return false
            }
            return now.timeIntervalSince(lastSuccessAt) <= maxAge
        }
    }

    static func hasRecentLiveInferenceSuccess(
        forRequestModel requestModel: String,
        maxAge: TimeInterval = 300,
        at now: Date = Date()
    ) -> Bool {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return false
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            guard let state = routeCircuitStatesByRouteHealthKey[route.routeHealthKey],
                  let lastLiveSuccessAt = state.lastLiveSuccessAt else {
                return false
            }
            return now.timeIntervalSince(lastLiveSuccessAt) <= maxAge
        }
    }

    static func hasRecentStableNVIDIAInferenceSuccess(
        forRequestModel requestModel: String,
        maxAge: TimeInterval = 300,
        at now: Date = Date()
    ) -> Bool {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel),
              route.providerID == "nvidia" else {
            return hasRecentLiveInferenceSuccess(forRequestModel: requestModel, maxAge: maxAge, at: now)
        }

        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            guard let state = routeCircuitStatesByRouteHealthKey[route.routeHealthKey],
                  let lastLiveSuccessAt = state.lastLiveSuccessAt,
                  now.timeIntervalSince(lastLiveSuccessAt) <= maxAge,
                  state.status == .closed else {
                return false
            }

            let metrics = state.rollingMetrics
            let successCount = metrics.recentOutcomes.filter { $0 == "send_response" }.count
            guard successCount >= 3,
                  metrics.recentFirstByteLatencyMilliseconds.count >= 3 else {
                return false
            }
            guard metrics.timeoutRate < 0.25,
                  metrics.invalidSuccessRate == 0 else {
                return false
            }
            if let p95FirstByte = metrics.p95FirstByteLatencyMilliseconds,
               p95FirstByte > 8_000 {
                return false
            }
            return true
        }
    }

    static func nvidiaInferenceProbeState(
        forRequestModel requestModel: String
    ) -> NVIDIAInferenceProbeState? {
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel),
              route.providerID == "nvidia" else {
            return nil
        }
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.nvidiaInferenceProbe
        }
    }

    static func hasRecentNVIDIAInferenceProbeSuccess(
        forRequestModel requestModel: String,
        maxAge: TimeInterval = nvidiaInferenceProbeFreshnessWindow,
        at now: Date = Date()
    ) -> Bool {
        guard let probe = nvidiaInferenceProbeState(forRequestModel: requestModel),
              probe.lastStatus == .success else {
            return false
        }
        return now.timeIntervalSince(probe.lastProbeAt) <= maxAge
    }

    static func hasRecentNVIDIAInferenceEvidence(
        forRequestModel requestModel: String,
        maxAge: TimeInterval = nvidiaInferenceProbeFreshnessWindow,
        at now: Date = Date()
    ) -> Bool {
        hasRecentInferenceSuccess(
            forRequestModel: requestModel,
            maxAge: maxAge,
            at: now
        ) || hasRecentNVIDIAInferenceProbeSuccess(
            forRequestModel: requestModel,
            maxAge: maxAge,
            at: now
        )
    }

    static func routeHealthSnapshot() -> [String: RouteCircuitState] {
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let routesByHealthKey = resolvedRoutesByRequestModel().values.reduce(into: [String: OpenAICompatTemporaryShim.RouteIdentity]()) { routesByHealthKey, route in
                routesByHealthKey[route.routeHealthKey] = route
            }
            return routeCircuitStatesByRouteHealthKey.reduce(into: [String: RouteCircuitState]()) { snapshot, entry in
                let canonicalModelID = routesByHealthKey[entry.key]?.canonicalModelID ?? entry.key
                snapshot[canonicalModelID] = entry.value
            }
        }
    }

    static func routeHealthSnapshotForTesting() -> [String: RouteCircuitState] {
        routeHealthSnapshot()
    }

    static func syntheticFactoryWorkerHealthRequestForTesting(routeModel: String) -> String {
        ThinkingProxy.syntheticFactoryWorkerHealthRequestForTesting(routeModel: routeModel)
    }

    static func reloadPersistedRouteHealthForTesting() {
        routeHealthQueue.sync {
            routeHealthPersistWorkItem?.cancel()
            routeHealthPersistWorkItem = nil
            routeHealthDirty = false
            hasLoadedPersistedRouteHealth = false
            routeCircuitStatesByRouteHealthKey = [:]
            routeCooldownsByRouteHealthKey = [:]
            recentSmartAliasDispatchByRequestedAlias = [:]
            recentSmartAliasWinnerByRequestedAlias = [:]
            loadPersistedRouteHealthIfNeededLocked()
        }
    }

    static func forcePersistRouteHealthForTesting() {
        routeHealthQueue.sync {
            forcePersistRouteHealthLocked()
        }
    }

    static func evaluateNvidiaReasoningResponse(model: String, statusCode: Int, bodyData: Data, requiredToolParameters: [String: [String]]? = nil) -> NvidiaReasoningEvaluation {
        guard let policy = policy(forModel: model) else {
            return NvidiaReasoningEvaluation(failureClass: nil, repairedBodyData: nil, normalizedBodyData: nil)
        }

        if statusCode == 200, bodyData.isEmpty {
            return retryEvaluation(
                for: .emptyBody,
                policy: policy,
                repairedBodyData: nil,
                normalizedBodyData: nil
            )
        }

        guard statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              !choices.isEmpty else {
            return NvidiaReasoningEvaluation(failureClass: nil, repairedBodyData: nil, normalizedBodyData: nil)
        }

        let choice = choices[0]
        let message = choice["message"] as? [String: Any] ?? [:]
        let content = (message["content"] as? String) ?? ""
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = reasoningString(from: message)
        let finishReason = (choice["finish_reason"] as? String)?.lowercased()
        let normalizedBodyData = normalizedResponseBody(
            json: json,
            contentOverride: nil,
            stripsReasoningField: policy.stripsReasoningFieldFromSuccess
        )
        switch validateToolCalls(in: message, requiredToolParameters: requiredToolParameters) {
        case .invalid:
            return retryEvaluation(
                for: .malformedToolArguments,
                policy: policy,
                repairedBodyData: nil,
                normalizedBodyData: nil
            )
        case .valid:
            let argumentRepairedBody = repairNativeToolCallArguments(in: json)
            return NvidiaReasoningEvaluation(
                failureClass: nil,
                repairedBodyData: argumentRepairedBody,
                normalizedBodyData: argumentRepairedBody ?? normalizedBodyData
            )
        case .none:
            break
        }

        if trimmedContent.isEmpty,
           !reasoning.isEmpty,
           finishReason == "length" {
            return retryEvaluation(
                for: .reasoningOnlyContentMissing,
                policy: policy,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        }

        if trimmedContent.isEmpty {
            return retryEvaluation(
                for: .emptyContent,
                policy: policy,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        }

        guard startsWithThinkTag(trimmedContent) else {
            return NvidiaReasoningEvaluation(
                failureClass: nil,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        }

        let repairedBodyData = policy.allowsThinkLeakRepair
            ? normalizedResponseBody(
                json: json,
                contentOverride: stripLeadingThinkBlock(from: content),
                stripsReasoningField: policy.stripsReasoningFieldFromSuccess
            )
            : nil

        return retryEvaluation(
            for: .reasoningLeakLength,
            policy: policy,
            repairedBodyData: repairedBodyData,
            normalizedBodyData: repairedBodyData ?? normalizedBodyData
        )
    }

    static func shouldRetryNvidiaReasoningTransport(statusCode: Int? = nil, error: Error? = nil) -> Bool {
        if let statusCode {
            return retryableHTTPStatusCodes.contains(statusCode)
        }

        guard let nsError = error as NSError? else {
            return false
        }
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        return retryableTransportErrorCodes.contains(nsError.code)
    }

    fileprivate static func isChatCompletionsPath(_ path: String) -> Bool {
        path == "/v1/chat/completions" || path == "/api/v1/chat/completions"
    }

    fileprivate static func isResponsesPath(_ path: String) -> Bool {
        path == "/v1/responses" || path == "/api/v1/responses"
    }

    fileprivate static func chatCompletionsPath(matching path: String) -> String {
        path.hasPrefix("/api/") ? "/api/v1/chat/completions" : "/v1/chat/completions"
    }

    static func chatCompletionsRequestJSON(fromResponsesRequestJSON jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return nil
        }

        var chatJSON: [String: Any] = [
            "model": normalizedRequestModel(model)
        ]

        var messages: [[String: Any]] = []
        if let instructions = (json["instructions"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !instructions.isEmpty {
            messages.append([
                "role": "system",
                "content": instructions
            ])
        }

        guard let inputMessages = chatMessages(fromResponsesInput: json["input"]) else {
            return nil
        }
        messages.append(contentsOf: inputMessages)
        guard !messages.isEmpty else {
            return nil
        }

        chatJSON["messages"] = messages

        if let stream = json["stream"] as? Bool {
            chatJSON["stream"] = stream
        }
        if json["tools"] != nil {
            guard let convertedTools = chatCompletionTools(fromResponsesTools: json["tools"]) else {
                return nil
            }
            chatJSON["tools"] = convertedTools
        }
        if let toolChoice = json["tool_choice"] {
            chatJSON["tool_choice"] = toolChoice
        }
        if let parallelToolCalls = json["parallel_tool_calls"] {
            chatJSON["parallel_tool_calls"] = parallelToolCalls
        }

        if let maxTokens = integerValue(json["max_output_tokens"])
            ?? integerValue(json["max_tokens"])
            ?? integerValue(json["max_completion_tokens"]) {
            chatJSON["max_tokens"] = maxTokens
        }

        for passthroughField in [
            "temperature",
            "top_p",
            "stop",
            "presence_penalty",
            "frequency_penalty",
            "logit_bias",
            "seed",
            "n",
            "user",
            "response_format",
            "metadata"
        ] where json[passthroughField] != nil {
            chatJSON[passthroughField] = json[passthroughField]
        }

        guard let rewrittenJSONData = try? JSONSerialization.data(withJSONObject: chatJSON),
              let rewrittenJSONString = String(data: rewrittenJSONData, encoding: .utf8) else {
            return nil
        }
        return transformRequest(
            method: "POST",
            path: chatCompletionsPath(matching: "/v1/chat/completions"),
            jsonString: rewrittenJSONString
        ) ?? rewrittenJSONString
    }

    private static func chatMessages(fromResponsesInput input: Any?) -> [[String: Any]]? {
        guard let input else {
            return []
        }

        if let inputString = input as? String {
            return [[
                "role": "user",
                "content": inputString
            ]]
        }

        guard let inputItems = input as? [Any] else {
            return nil
        }

        var messages: [[String: Any]] = []
        for inputItem in inputItems {
            if let inputString = inputItem as? String {
                messages.append([
                    "role": "user",
                    "content": inputString
                ])
                continue
            }

            guard let inputDictionary = inputItem as? [String: Any],
                  let convertedMessages = chatMessages(fromResponsesInputItem: inputDictionary) else {
                // Skip unrecognized input items instead of failing the entire conversion.
                continue
            }
            messages.append(contentsOf: convertedMessages)
        }

        return messages
    }

    private static func chatMessages(fromResponsesInputItem item: [String: Any]) -> [[String: Any]]? {
        let normalizedRole = (item["role"] as? String)?.lowercased()
        let normalizedType = (item["type"] as? String)?.lowercased()

        if normalizedType == "reasoning" {
            let summary = (flattenedResponseInputText(from: item["summary"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else {
                return []
            }
            return [[
                "role": "assistant",
                "content": "<thinking>\n\(summary)\n</thinking>"
            ]]
        }

        if normalizedType == "function_call" || normalizedType == "custom_tool_call" {
            let callID = (item["call_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let callID, !callID.isEmpty, let name, !name.isEmpty else {
                return nil
            }

            let arguments: String
            if normalizedType == "custom_tool_call" {
                let customInput: [String: Any] = [
                    "input": (item["input"] as? String) ?? ""
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: customInput),
                      let encoded = String(data: data, encoding: .utf8) else {
                    return nil
                }
                arguments = encoded
            } else if let rawArguments = item["arguments"] as? String {
                arguments = rawArguments
            } else {
                return nil
            }

            return [[
                "role": "assistant",
                "content": "",
                "tool_calls": [[
                    "id": callID,
                    "type": "function",
                    "function": [
                        "name": name,
                        "arguments": arguments
                    ]
                ]]
            ]]
        }

        if normalizedType == "function_call_output" || normalizedType == "custom_tool_call_output" {
            let callID = (item["call_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let callID, !callID.isEmpty else {
                return nil
            }
            return [[
                "role": "tool",
                "tool_call_id": callID,
                "content": stringValue(fromJSONValue: item["output"]) ?? ""
            ]]
        }

        if let normalizedRole {
            let chatRole = normalizedRole == "developer" ? "system" : normalizedRole
            guard ["system", "user", "assistant", "tool"].contains(chatRole) else {
                return nil
            }

            if chatRole == "tool" {
                let toolCallID = (item["call_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let toolCallID, !toolCallID.isEmpty else {
                    return nil
                }
                return [[
                    "role": "tool",
                    "tool_call_id": toolCallID,
                    "content": stringValue(fromJSONValue: item["content"]) ?? stringValue(fromJSONValue: item["output"]) ?? ""
                ]]
            }

            guard let content = flattenedResponseInputText(from: item["content"])
                ?? stringValue(fromJSONValue: item["content"]) else {
                // Skip items with unextractable content (e.g., image-only messages)
                // instead of failing the entire conversion.
                return []
            }
            return [[
                "role": chatRole,
                "content": content
            ]]
        }

        // Skip unrecognized Responses API item types (web_search_call, file_search_call, etc.)
        // instead of failing the entire conversion.
        return []
    }

    private static func flattenedResponseInputText(from content: Any?) -> String? {
        guard let content else {
            return nil
        }

        if let stringContent = content as? String {
            return stringContent
        }

        guard let segments = content as? [Any] else {
            return nil
        }

        var collectedSegments: [String] = []
        for segment in segments {
            if let stringSegment = segment as? String {
                collectedSegments.append(stringSegment)
                continue
            }

            guard let dictionary = segment as? [String: Any] else {
                return nil
            }

            let type = (dictionary["type"] as? String)?.lowercased()
            let textValue = dictionary["text"] as? String
            if let textValue,
               type == nil || type == "text" || type == "input_text" || type == "output_text" || type == "summary_text" {
                collectedSegments.append(textValue)
                continue
            }

            // Skip non-text segments (input_image, etc.) instead of failing
            continue
        }

        guard !collectedSegments.isEmpty else {
            return nil
        }
        return collectedSegments.joined()
    }

    private static func stringValue(fromJSONValue value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return encoded
    }

    private static func chatCompletionTools(fromResponsesTools value: Any?) -> [[String: Any]]? {
        guard let value else {
            return nil
        }
        guard let tools = value as? [Any] else {
            return nil
        }

        var convertedTools: [[String: Any]] = []
        for tool in tools {
            guard let toolDictionary = tool as? [String: Any],
                  let type = (toolDictionary["type"] as? String)?.lowercased() else {
                return nil
            }

            switch type {
            case "function":
                if let nestedFunction = toolDictionary["function"] as? [String: Any] {
                    convertedTools.append([
                        "type": "function",
                        "function": nestedFunction
                    ])
                    continue
                }

                guard let name = toolDictionary["name"] as? String else {
                    return nil
                }
                var function: [String: Any] = [
                    "name": name
                ]
                if let description = toolDictionary["description"] {
                    function["description"] = description
                }
                if let parameters = toolDictionary["parameters"] {
                    function["parameters"] = parameters
                }
                convertedTools.append([
                    "type": "function",
                    "function": function
                ])
            default:
                // Skip Responses API-specific tool types (web_search, code_interpreter, etc.)
                // that don't have a Chat Completions equivalent.
                continue
            }
        }

        return convertedTools
    }

    fileprivate static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    static func classifyProvider429Disposition(
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Provider429Disposition? {
        guard statusCode == 429 else { return nil }

        let concurrencyThreshold: TimeInterval = 300
        let quotaExhaustionFallbackCooldown: TimeInterval = 15 * 60

        // --- Retry-After header ---
        if let retryAfter = headerValue("Retry-After", in: headers)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !retryAfter.isEmpty {
            if let seconds = TimeInterval(retryAfter), seconds > 0 {
                if seconds < concurrencyThreshold {
                    return .concurrency(retryAfterSeconds: seconds)
                }
                return .quotaWindow(cooldownUntil: now.addingTimeInterval(seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: retryAfter) {
                let seconds = date.timeIntervalSince(now)
                if seconds <= 0 { return .concurrency(retryAfterSeconds: nil) }
                if seconds < concurrencyThreshold {
                    return .concurrency(retryAfterSeconds: seconds)
                }
                return .quotaWindow(cooldownUntil: date)
            }
        }

        guard let bodyData,
              let bodyString = String(data: bodyData, encoding: .utf8) else {
            return .concurrency(retryAfterSeconds: nil)
        }

        let normalizedBody = bodyString.lowercased()
        if normalizedBody.contains("temporarily overloaded") ||
            normalizedBody.contains("service may be temporarily overloaded") ||
            normalizedBody.contains("\"code\":\"1305\"") ||
            normalizedBody.contains("\"code\":1305") {
            return .overload(retryDelaySeconds: 1)
        }

        if normalizedBody.contains("too many concurrent") ||
            normalizedBody.contains("too many connections") ||
            normalizedBody.contains("too many concurrent connections") {
            return .concurrency(retryAfterSeconds: nil)
        }

        // --- Body-embedded reset time (e.g. GLM: "will reset at YYYY-MM-DD HH:mm:ss") ---
        if let range = bodyString.range(of: #"will reset at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"#,
                                        options: .regularExpression) {
            let full = String(bodyString[range])
            let timestamp = String(full.dropFirst("will reset at ".count))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            // GLM timestamps are in CST (UTC+8)
            formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
            if let resetDate = formatter.date(from: timestamp),
               resetDate > now {
                NSLog("[ThinkingProxy] GLM rate-limit 429: honoring cooldown until %@", timestamp)
                return .quotaWindow(cooldownUntil: resetDate)
            }
        }

        if normalizedBody.contains("usage limit") ||
            normalizedBody.contains("upgrade for higher limits") ||
            normalizedBody.contains("quota exceeded") {
            return .quotaWindow(cooldownUntil: now.addingTimeInterval(quotaExhaustionFallbackCooldown))
        }

        return .concurrency(retryAfterSeconds: nil)
    }

    static func providerCooldownUntil(
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Date? {
        guard let disposition = classifyProvider429Disposition(
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            now: now
        ) else {
            return nil
        }
        if case .quotaWindow(let cooldownUntil) = disposition {
            return cooldownUntil
        }
        return nil
    }

    static func providerDeferralUntil(
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Date? {
        guard let disposition = classifyProvider429Disposition(
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            now: now
        ) else {
            return nil
        }
        switch disposition {
        case .overload(let retryDelaySeconds):
            // Provider overload should stay on the same lane without poisoning
            // route-level availability. The caller can still retry the request
            // immediately on the same provider using the provider hint.
            _ = retryDelaySeconds
            return nil
        case .concurrency(let retryAfterSeconds):
            guard let retryAfterSeconds else { return now.addingTimeInterval(1) }
            return now.addingTimeInterval(retryAfterSeconds)
        case .quotaWindow(let cooldownUntil):
            return cooldownUntil
        }
    }

    static func smartAliasForcedOpenUntil(
        failureClass: String?,
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Date? {
        let providerCooldown = providerCooldownUntil(
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            now: now
        )

        guard failureClass?.lowercased() == "classified_retryable_400_meta_adapter" else {
            return providerCooldown
        }

        let metaAdapterCooldown = now.addingTimeInterval(retryableMetaAdapterDeferral)
        guard let providerCooldown else {
            return metaAdapterCooldown
        }
        return max(providerCooldown, metaAdapterCooldown)
    }

    static func smartAliasAvailabilityDeferralUntil(
        failureClass: String?,
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Date? {
        let providerDeferral = providerDeferralUntil(
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            now: now
        )

        guard failureClass?.lowercased() == "classified_retryable_400_meta_adapter" else {
            return providerDeferral
        }

        let metaAdapterDeferral = now.addingTimeInterval(retryableMetaAdapterDeferral)
        guard let providerDeferral else {
            return metaAdapterDeferral
        }
        return max(providerDeferral, metaAdapterDeferral)
    }

    static func failureClassFor429(
        headers: [AnyHashable: Any],
        bodyData: Data?,
        now: Date = Date()
    ) -> String {
        switch classifyProvider429Disposition(
            statusCode: 429,
            headers: headers,
            bodyData: bodyData,
            now: now
        ) {
        case .overload:
            return "classified_429_overload"
        case .concurrency:
            return "classified_429_concurrency"
        case .quotaWindow:
            return "classified_429_window"
        case nil:
            return "classified_429"
        }
    }

    private static func headerValue(_ name: String, in headers: [AnyHashable: Any]) -> String? {
        for (key, value) in headers {
            if String(describing: key).lowercased() == name.lowercased() {
                return String(describing: value)
            }
        }
        return nil
    }

    private static func nextRouteCircuitState(
        current: RouteCircuitState?,
        afterFailureAt now: Date,
        routeHealthKey: String,
        telemetryEvent: RouteTelemetryEvent?,
        burstDeduplicated: Bool,
        policy: RouteCircuitBreakerPolicy? = nil,
        forcedOpenUntil: Date? = nil,
        healthSensitivity: HealthSensitivity? = nil
    ) -> RouteCircuitState {
        let effectivePolicy = policy ?? routeCircuitBreakerPolicy
        let failurePenalty = failurePenalty(
            for: telemetryEvent,
            routeHealthKey: routeHealthKey,
            burstDeduplicated: burstDeduplicated
        )
        let lastTelemetryEvent = telemetryEvent ?? current?.lastTelemetryEvent
        let nextRollingMetrics = updatedRollingMetrics(
            current: current?.rollingMetrics,
            telemetryEvent: telemetryEvent
        )
        let nextEMA = (current?.emaMetrics ?? .empty).updated(
            isSuccess: false,
            latencyMs: nil
        )
        let decayedFailureScore = decayedFailureScore(
            current?.failureScore ?? 0,
            lastUpdatedAt: current?.lastScoreUpdatedAt,
            now: now
        )
        let failureThreshold = effectiveFailureThreshold(
            policy: effectivePolicy,
            healthSensitivity: healthSensitivity
        )
        let effectiveForcedOpenUntil = [current?.openUntil, forcedOpenUntil]
            .compactMap { $0 }
            .filter { $0 > now }
            .max()
        let nextLastSuccessAt = current?.lastSuccessAt
        let nextLastLiveSuccessAt = current?.lastLiveSuccessAt
        let nextLastSuccessRequestID = current?.lastSuccessRequestID
        let nextLastFailureAt = telemetryEvent != nil ? now : current?.lastFailureAt
        let nextLastFailureClass = telemetryEvent?.failureClass ?? current?.lastFailureClass

        if let effectiveForcedOpenUntil {
            return RouteCircuitState(
                status: .open,
                failureScore: failureThreshold,
                recoverySuccesses: 0,
                openUntil: effectiveForcedOpenUntil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        }

        switch current?.status ?? .closed {
        case .closed, .suspect:
            if failurePenalty == 0 {
                return RouteCircuitState(
                    status: current?.status ?? .closed,
                    failureScore: decayedFailureScore,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: current?.recoveredAt,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            let nextFailureScore = min(
                failureThreshold,
                decayedFailureScore + failurePenalty
            )
            if nextFailureScore >= failureThreshold {
                return RouteCircuitState(
                    status: .open,
                    failureScore: failureThreshold,
                    recoverySuccesses: 0,
                    openUntil: now.addingTimeInterval(effectivePolicy.cooldown),
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: nil,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .suspect,
                failureScore: nextFailureScore,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .open, .halfOpen:
            if failurePenalty == 0 {
                return RouteCircuitState(
                    status: current?.status ?? .closed,
                    failureScore: current?.failureScore ?? 0,
                    recoverySuccesses: current?.recoverySuccesses ?? 0,
                    openUntil: current?.openUntil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: current?.recoveredAt,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .open,
                failureScore: failureThreshold,
                recoverySuccesses: 0,
                openUntil: now.addingTimeInterval(effectivePolicy.cooldown),
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        }
    }

    private static func routeSuccessCountsAsLiveTraffic(_ telemetryEvent: RouteTelemetryEvent?) -> Bool {
        guard let telemetryEvent else {
            return true
        }
        switch telemetryEvent.source {
        case "canary", "smart_alias_probe":
            return false
        default:
            return true
        }
    }

    private static func nextRouteCircuitStateAfterSuccess(
        current: RouteCircuitState?,
        telemetryEvent: RouteTelemetryEvent?,
        at now: Date,
        policy: RouteCircuitBreakerPolicy? = nil
    ) -> RouteCircuitState {
        let effectivePolicy = policy ?? routeCircuitBreakerPolicy
        let lastTelemetryEvent = telemetryEvent ?? current?.lastTelemetryEvent
        let nextRollingMetrics = updatedRollingMetrics(
            current: current?.rollingMetrics,
            telemetryEvent: telemetryEvent
        )
        let nextEMA = (current?.emaMetrics ?? .empty).updated(
            isSuccess: true,
            latencyMs: telemetryEvent?.firstByteLatencyMilliseconds
        )
        let decayedScore = decayedFailureScore(
            current?.failureScore ?? 0,
            lastUpdatedAt: current?.lastScoreUpdatedAt,
            now: now
        )
        let reducedScore = max(0, decayedScore - 1)
        let countsAsLiveTraffic = routeSuccessCountsAsLiveTraffic(telemetryEvent)
        let nextLastSuccessAt = now
        let nextLastLiveSuccessAt = countsAsLiveTraffic ? now : current?.lastLiveSuccessAt
        let nextLastSuccessRequestID = telemetryEvent?.proxyRequestID ?? current?.lastSuccessRequestID
        let nextLastFailureAt = current?.lastFailureAt
        let nextLastFailureClass = current?.lastFailureClass

        switch current?.status ?? .closed {
        case .closed:
            return RouteCircuitState(
                status: .closed,
                failureScore: 0,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .suspect:
            if reducedScore > 0 || shouldRemainSuspectAfterSuccess(metrics: nextRollingMetrics) {
                return RouteCircuitState(
                    status: .suspect,
                    failureScore: reducedScore,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: nil,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .closed,
                failureScore: 0,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .open:
            if effectivePolicy.recoverySuccessThreshold <= 1 {
                return RouteCircuitState(
                    status: .closed,
                    failureScore: 0,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: now,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .halfOpen,
                failureScore: 0,
                recoverySuccesses: 1,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        case .halfOpen:
            let nextRecoverySuccesses = (current?.recoverySuccesses ?? 0) + 1
            if nextRecoverySuccesses >= effectivePolicy.recoverySuccessThreshold {
                return RouteCircuitState(
                    status: .closed,
                    failureScore: 0,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: lastTelemetryEvent,
                    rollingMetrics: nextRollingMetrics,
                    emaMetrics: nextEMA,
                    recoveredAt: now,
                    lastSuccessAt: nextLastSuccessAt,
                    lastLiveSuccessAt: nextLastLiveSuccessAt,
                    lastSuccessRequestID: nextLastSuccessRequestID,
                    lastFailureAt: nextLastFailureAt,
                    lastFailureClass: nextLastFailureClass
                )
            }
            return RouteCircuitState(
                status: .halfOpen,
                failureScore: 0,
                recoverySuccesses: nextRecoverySuccesses,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil,
                lastSuccessAt: nextLastSuccessAt,
                lastLiveSuccessAt: nextLastLiveSuccessAt,
                lastSuccessRequestID: nextLastSuccessRequestID,
                lastFailureAt: nextLastFailureAt,
                lastFailureClass: nextLastFailureClass
            )
        }
    }

    private static func updatedNVIDIAInferenceProbeState(
        current: NVIDIAInferenceProbeState?,
        route: RouteIdentity,
        telemetryEvent: RouteTelemetryEvent?
    ) -> NVIDIAInferenceProbeState? {
        guard route.providerID == "nvidia" else { return nil }
        guard let telemetryEvent, telemetryEvent.source == "canary" else {
            return current
        }

        let isSuccess = telemetryEvent.transportOutcome == "send_response" &&
            telemetryEvent.failureClass == nil &&
            telemetryEvent.upstreamHTTPStatus.map { (200..<300).contains($0) } == true

        return NVIDIAInferenceProbeState(
            lastProbeAt: telemetryEvent.timestamp,
            lastStatus: isSuccess ? .success : .failure,
            lastSuccessAt: isSuccess ? telemetryEvent.timestamp : current?.lastSuccessAt,
            lastFailureAt: isSuccess ? current?.lastFailureAt : telemetryEvent.timestamp,
            lastFailureClass: isSuccess ? current?.lastFailureClass : telemetryEvent.failureClass,
            lastTimeoutStage: telemetryEvent.timeoutStage,
            lastUpstreamHTTPStatus: telemetryEvent.upstreamHTTPStatus,
            lastTransportOutcome: telemetryEvent.transportOutcome,
            lastFirstByteLatencyMilliseconds: telemetryEvent.firstByteLatencyMilliseconds,
            lastTotalLatencyMilliseconds: telemetryEvent.totalLatencyMilliseconds
        )
    }

    private static func routeCircuitState(
        _ state: RouteCircuitState,
        replacingLastTelemetryEvent telemetryEvent: RouteTelemetryEvent?,
        replacingNVIDIAInferenceProbe nvidiaInferenceProbe: NVIDIAInferenceProbeState? = nil
    ) -> RouteCircuitState {
        RouteCircuitState(
            status: state.status,
            failureScore: state.failureScore,
            recoverySuccesses: state.recoverySuccesses,
            openUntil: state.openUntil,
            lastScoreUpdatedAt: state.lastScoreUpdatedAt,
            lastTelemetryEvent: telemetryEvent,
            rollingMetrics: state.rollingMetrics,
            emaMetrics: state.emaMetrics,
            recoveredAt: state.recoveredAt,
            lastSuccessAt: state.lastSuccessAt,
            lastLiveSuccessAt: state.lastLiveSuccessAt,
            lastSuccessRequestID: state.lastSuccessRequestID,
            lastFailureAt: state.lastFailureAt,
            lastFailureClass: state.lastFailureClass,
            nvidiaInferenceProbe: nvidiaInferenceProbe ?? state.nvidiaInferenceProbe
        )
    }

    private static func enrichTelemetryEvent(
        _ event: RouteTelemetryEvent,
        from previousStatus: RouteHealthStatus,
        to nextStatus: RouteHealthStatus,
        winnerAttemptLane: Int? = nil
    ) -> RouteTelemetryEvent {
        RouteTelemetryEvent(
            timestamp: event.timestamp,
            requestModel: event.requestModel,
            requestedAlias: event.requestedAlias,
            canonicalModelID: event.canonicalModelID,
            transportOutcome: event.transportOutcome,
            healthTransition: healthTransitionLabel(from: previousStatus, to: nextStatus),
            attemptLane: event.attemptLane,
            winnerAttemptLane: winnerAttemptLane ?? event.winnerAttemptLane,
            failoverDepth: event.failoverDepth,
            finalWinnerRequestModel: event.finalWinnerRequestModel,
            failureClass: event.failureClass,
            timeoutStage: event.timeoutStage,
            upstreamHTTPStatus: event.upstreamHTTPStatus,
            retryCount: event.retryCount,
            source: event.source,
            firstByteLatencyMilliseconds: event.firstByteLatencyMilliseconds,
            totalLatencyMilliseconds: event.totalLatencyMilliseconds,
            inflightAtRequest: event.inflightAtRequest,
            proxyRequestID: event.proxyRequestID,
            callerRequestID: event.callerRequestID,
            callerSessionID: event.callerSessionID,
            requestShape: event.requestShape,
            negotiatedApplicationProtocol: event.negotiatedApplicationProtocol,
            errorBodySnippet: event.errorBodySnippet
        )
    }

    private static let errorBodySnippetMaxLength = 256

    static func sanitizeErrorBodySnippet(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        guard let raw = String(data: data.prefix(errorBodySnippetMaxLength), encoding: .utf8) else {
            return "<\(data.count)-byte non-utf8 body>"
        }
        let truncated = raw.prefix(errorBodySnippetMaxLength)
        let wasTruncated = data.count > errorBodySnippetMaxLength
        return wasTruncated ? "\(truncated)…" : String(truncated)
    }

    private static func healthTransitionLabel(from previousStatus: RouteHealthStatus, to nextStatus: RouteHealthStatus) -> String? {
        guard previousStatus != nextStatus else { return nil }
        return "\(previousStatus.rawValue)->\(nextStatus.rawValue)"
    }

    private static func failurePenalty(
        for telemetryEvent: RouteTelemetryEvent?,
        routeHealthKey: String,
        burstDeduplicated: Bool
    ) -> Double {
        guard let failureClass = telemetryEvent?.failureClass?.lowercased() else {
            return burstDeduplicated ? 0 : 1
        }

        // 429 rate-limit responses indicate concurrency oversubscription, not route health issues.
        // The concurrency registry handles backing off; the circuit breaker should not penalize.
        if failureClass.hasPrefix("classified_429") {
            return 0
        }

        let basePenalty: Double
        if failureClass.hasPrefix("transport_timeout"),
           telemetryEvent?.timeoutStage == .firstResponse {
            basePenalty = 3
        } else if failureClass == "transport_error" ||
            failureClass == "missing_response_material" ||
            failureClass.hasPrefix("classified_5") {
            basePenalty = 2
        } else {
            basePenalty = 1
        }

        if burstDeduplicated {
            return 0
        }

        let currentLimit = concurrencyRegistry.currentLimit(routeHealthKey: routeHealthKey)
        let inflightAtRequest = telemetryEvent?.inflightAtRequest ?? concurrencyRegistry.currentInflight(routeHealthKey: routeHealthKey)
        if inflightAtRequest >= currentLimit {
            return basePenalty * 0.25
        }

        return basePenalty
    }

    private static func decayedFailureScore(
        _ failureScore: Double,
        lastUpdatedAt: Date?,
        now: Date
    ) -> Double {
        guard failureScore > 0,
              let lastUpdatedAt else {
            return failureScore
        }
        let elapsed = max(0, now.timeIntervalSince(lastUpdatedAt))
        guard elapsed >= routeFailureScoreDecayInterval else {
            return failureScore
        }
        let decaySteps = Int(elapsed / routeFailureScoreDecayInterval)
        return max(0, failureScore - Double(decaySteps))
    }

    private static func effectiveFailureThreshold(
        policy: RouteCircuitBreakerPolicy,
        healthSensitivity: HealthSensitivity? = nil
    ) -> Double {
        let baseThreshold = policy.failureThreshold
        guard let sensitivity = healthSensitivity, sensitivity != .balanced else {
            return baseThreshold
        }
        return max(1, baseThreshold * sensitivity.failureThresholdScaleFactor)
    }

    private static func updatedRollingMetrics(
        current: RouteRollingMetrics?,
        telemetryEvent: RouteTelemetryEvent?
    ) -> RouteRollingMetrics {
        guard let telemetryEvent else {
            return current ?? .empty
        }

        let prior = current ?? .empty
        var recentOutcomes = prior.recentOutcomes
        recentOutcomes.append(rollingOutcomeLabel(for: telemetryEvent))
        if recentOutcomes.count > routeRollingWindow {
            recentOutcomes.removeFirst(recentOutcomes.count - routeRollingWindow)
        }

        var recentFirstByteLatencyMilliseconds = prior.recentFirstByteLatencyMilliseconds
        if let firstByteLatencyMilliseconds = telemetryEvent.firstByteLatencyMilliseconds {
            recentFirstByteLatencyMilliseconds.append(firstByteLatencyMilliseconds)
            if recentFirstByteLatencyMilliseconds.count > routeRollingWindow {
                recentFirstByteLatencyMilliseconds.removeFirst(recentFirstByteLatencyMilliseconds.count - routeRollingWindow)
            }
        }

        var recentTotalLatencyMilliseconds = prior.recentTotalLatencyMilliseconds
        if let totalLatencyMilliseconds = telemetryEvent.totalLatencyMilliseconds {
            recentTotalLatencyMilliseconds.append(totalLatencyMilliseconds)
            if recentTotalLatencyMilliseconds.count > routeRollingWindow {
                recentTotalLatencyMilliseconds.removeFirst(recentTotalLatencyMilliseconds.count - routeRollingWindow)
            }
        }

        return RouteRollingMetrics(
            recentOutcomes: recentOutcomes,
            recentFirstByteLatencyMilliseconds: recentFirstByteLatencyMilliseconds,
            recentTotalLatencyMilliseconds: recentTotalLatencyMilliseconds
        )
    }

    private static func rollingOutcomeLabel(for telemetryEvent: RouteTelemetryEvent) -> String {
        if let failureClass = telemetryEvent.failureClass, !failureClass.isEmpty {
            return "\(telemetryEvent.transportOutcome):\(failureClass)"
        }
        return telemetryEvent.transportOutcome
    }

    private static func isInvalidSuccessFailureClass(_ failureClass: String?) -> Bool {
        guard let failureClass else { return false }
        return FailureClass(rawValue: failureClass) != nil
    }

    private static func shouldRemainSuspectAfterSuccess(metrics: RouteRollingMetrics) -> Bool {
        metrics.timeoutRate >= 0.5 || metrics.invalidSuccessRate >= 0.5
    }

    private static func recommendedNVIDIAHedgeDelay(metrics: RouteRollingMetrics?) -> TimeInterval {
        guard let metrics else { return defaultSuspectHedgeDelay }
        if let averageFirstByteLatencyMilliseconds = metrics.averageFirstByteLatencyMilliseconds,
           averageFirstByteLatencyMilliseconds >= 120_000 {
            return 10
        }
        if metrics.invalidSuccessRate >= 0.5 {
            return 3
        }
        if let averageFirstByteLatencyMilliseconds = metrics.averageFirstByteLatencyMilliseconds,
           averageFirstByteLatencyMilliseconds >= 60_000 {
            return 8
        }
        if metrics.timeoutRate >= 0.5 {
            return 5
        }
        if let averageFirstByteLatencyMilliseconds = metrics.averageFirstByteLatencyMilliseconds,
           averageFirstByteLatencyMilliseconds >= 20_000 {
            return 5
        }
        return defaultSuspectHedgeDelay
    }

    private static func recommendedCanaryInterval(metrics: [RouteRollingMetrics]) -> TimeInterval {
        guard !metrics.isEmpty else { return defaultCanaryInterval }
        if metrics.contains(where: { $0.timeoutRate >= 0.5 }) {
            return fastCanaryInterval
        }
        if metrics.contains(where: { $0.invalidSuccessRate >= 0.5 }) {
            return 45
        }
        if metrics.contains(where: { ($0.averageFirstByteLatencyMilliseconds ?? 0) >= 4_000 }) {
            return fastCanaryInterval
        }
        return defaultCanaryInterval
    }

    private static func smartAliasFallbackRankingScore(
        forRequestModel requestModel: String,
        originalIndex: Int
    ) -> (healthPriority: Int, compositeScore: Double, isProvenPerfect: Bool, tierWeight: Double, originalIndex: Int) {
        let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel)
        let state = route.flatMap { routeCircuitStatesByRouteHealthKey[$0.routeHealthKey] }
        let ema = state?.emaMetrics ?? .empty
        let now = Date()
        var healthPriority: Int
        switch state?.status ?? .closed {
        case .closed:
            healthPriority = 0
        case .suspect:
            healthPriority = 1
        case .halfOpen:
            healthPriority = 2
        case .open:
            healthPriority = state?.isUnavailable(at: now) == true ? 3 : 2
        }
        if healthPriority < 3,
           let routeKey = route?.routeHealthKey,
           let cooldownUntil = routeCooldownsByRouteHealthKey[routeKey],
           now < cooldownUntil {
            healthPriority = 3
        }
        let tier = modelTier(forRequestModel: requestModel)
        let momentum = state?.momentumBonus(at: now) ?? 0.0
        let price = inputPriceByCanonicalModelID[route?.canonicalModelID ?? ""] ?? 0.0
        let costFactor = 1.0 / (price + 0.01)
        let adjustedScore = (ema.compositeScore + momentum) * tier.rawValue * pow(costFactor, costSensitivity)
        return (
            healthPriority: healthPriority,
            compositeScore: adjustedScore,
            isProvenPerfect: ema.isProvenPerfect,
            tierWeight: tier.rawValue,
            originalIndex: originalIndex
        )
    }

    private static func loadPersistedRouteHealthIfNeededLocked() {
        dispatchPrecondition(condition: .onQueue(routeHealthQueue))
        guard !hasLoadedPersistedRouteHealth else { return }
        hasLoadedPersistedRouteHealth = true
        guard let path = routeHealthStatePath(),
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? Int, version >= 1, version <= 9,
              let routes = json["routes"] as? [String: [String: Any]] else {
            routeCircuitStatesByRouteHealthKey = [:]
            return
        }

        var loaded: [String: RouteCircuitState] = [:]
        let configuredRouteHealthKeys = Set(resolvedRoutesByRequestModel().values.map(\.routeHealthKey))
        let oauthProviderIDs = Set(ProviderCatalog.oauthPassthroughPrefixes.map(\.providerID))
        var prunedUnknownEntries = false
        var normalizedPersistedAvailability = false
        for (routeHealthKey, entry) in routes {
            let components = routeHealthKey.components(separatedBy: "::")
            let providerID = components.first
            let isKnownRoute = configuredRouteHealthKeys.contains(routeHealthKey)
            let isOAuthRoute = (components.count == 2 && providerID.map { oauthProviderIDs.contains($0) } == true)
            guard isKnownRoute || isOAuthRoute else {
                prunedUnknownEntries = true
                continue
            }
            let persistedStatus = (entry["status"] as? String)
                .flatMap(RouteHealthStatus.init(rawValue:))
                ?? ((parseISO8601Date(entry["open_until"]) != nil) ? .open : .closed)
            var status = persistedStatus
            let failureScore = max(
                0,
                (entry["failure_score"] as? Double)
                    ?? Double(entry["failure_score"] as? Int ?? entry["consecutive_failures"] as? Int ?? 0)
            )
            let recoverySuccesses = entry["recovery_successes"] as? Int ?? 0
            var openUntil = parseISO8601Date(entry["open_until"])
            let lastScoreUpdatedAt = parseISO8601Date(entry["last_score_updated_at"])
            let lastTelemetryEvent = parseTelemetryEvent(entry["last_event"])
            let rollingMetrics = parseRollingMetrics(entry["rolling_metrics"])
            let lastSuccessAt = parseISO8601Date(entry["last_success_at"])
            let lastLiveSuccessAt = parseISO8601Date(entry["last_live_success_at"])
            let lastSuccessRequestID = entry["last_success_request_id"] as? String
            let lastFailureAt =
                parseISO8601Date(entry["last_failure_at"])
                ?? ((lastTelemetryEvent?.failureClass != nil) ? lastTelemetryEvent?.timestamp : nil)
            let lastFailureClass = entry["last_failure_class"] as? String

            if status == .open {
                // Persisted open circuits are useful evidence, but they should not hard-quarantine
                // the proxy after restart before live traffic or canaries get a chance to re-probe.
                status = .suspect
                openUntil = nil
                normalizedPersistedAvailability = true
            }

            loaded[routeHealthKey] = RouteCircuitState(
                status: status,
                failureScore: failureScore,
                recoverySuccesses: recoverySuccesses,
                openUntil: openUntil,
                lastScoreUpdatedAt: lastScoreUpdatedAt,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: rollingMetrics,
                emaMetrics: parseEMAMetrics(entry["ema_metrics"]),
                recoveredAt: parseISO8601Date(entry["recovered_at"] as? String),
                lastSuccessAt: lastSuccessAt,
                lastLiveSuccessAt: lastLiveSuccessAt,
                lastSuccessRequestID: lastSuccessRequestID,
                lastFailureAt: lastFailureAt,
                lastFailureClass: lastFailureClass,
                nvidiaInferenceProbe: parseNVIDIAInferenceProbeState(entry["nvidia_inference_probe"])
            )
        }
        routeCircuitStatesByRouteHealthKey = loaded
        // Route cooldowns are runtime-only backpressure hints. Replaying them across restart can
        // blackhole the worker pool before the new process has observed any live failures.
        routeCooldownsByRouteHealthKey = [:]
        concurrencyRegistry.loadLocked(from: json, persistedVersion: version)
        if prunedUnknownEntries || normalizedPersistedAvailability || version < 9 {
            persistRouteHealthLocked()
        }

        let now = Date()
        for (routeKey, state) in routeCircuitStatesByRouteHealthKey {
            let lastActivity: Date? = state.lastTelemetryEvent?.timestamp ?? state.lastScoreUpdatedAt
            let staleness = lastActivity.map { now.timeIntervalSince($0) } ?? nil
            let statusDesc = "status=\(state.status.rawValue) failure_score=\(state.failureScore)"
            if let staleness = staleness {
                NSLog("[ThinkingProxy] Startup: loaded route %@: %@ (staleness: %.0fs)", routeKey, statusDesc, staleness)
            } else {
                NSLog("[ThinkingProxy] Startup: loaded route %@: %@ (no activity)", routeKey, statusDesc)
            }
        }

        // Startup keeps historical failure evidence but does not let persisted unavailability alone
        // define live routing authority for the new process.
        healStaleSuspectRoutesLocked()
    }

    /// Heal suspect routes whose last telemetry event is older than the stale threshold.
    /// Must be called on routeHealthQueue. Used by both startup load and background maintenance.
    /// Routes with strong EMA success rates (>80%) get a shorter threshold (60s) since a single
    /// transient failure is unlikely to indicate a sustained outage. Routes without meaningful
    /// success evidence remain suspect until live traffic or canaries prove recovery.
    private static func healStaleSuspectRoutesLocked() {
        let defaultStaleThreshold: TimeInterval = 5 * 60  // 5 minutes
        let healthyEmaStaleThreshold: TimeInterval = 60    // 1 minute for historically healthy routes
        let healthyEmaThreshold: Double = 0.8
        let minimumHealObservations = 3
        let minimumHealSuccessRate = 0.2
        let maxSuspectStaleness: TimeInterval = 10 * 60   // 10 minutes — pure staleness auto-close
        let now = Date()
        var healedAny = false
        for key in routeCircuitStatesByRouteHealthKey.keys {
            guard let state = routeCircuitStatesByRouteHealthKey[key],
                  state.status == .suspect else { continue }

            let stalenessAnchor: Date
            if let lastFailureAt = state.lastFailureAt {
                stalenessAnchor = lastFailureAt
            } else if let lastEvent = state.lastTelemetryEvent,
                      lastEvent.failureClass != nil {
                stalenessAnchor = lastEvent.timestamp
            } else if let lastUpdate = state.lastScoreUpdatedAt {
                stalenessAnchor = lastUpdate
            } else {
                continue
            }

            let age = now.timeIntervalSince(stalenessAnchor)

            // Auto-close suspect routes that have been stale beyond the maximum threshold,
            // regardless of recovery evidence. Without this, routes with zero observations
            // (e.g., direct requests that bypassed telemetry) stay suspect forever.
            if age > maxSuspectStaleness {
                NSLog("[ThinkingProxy] Self-heal: promoting route %@ from suspect to closed (stale for %ds, no observations needed)", key, Int(age))
                routeCircuitStatesByRouteHealthKey[key] = RouteCircuitState(
                    status: .closed,
                    failureScore: 0,
                    recoverySuccesses: 0,
                    openUntil: nil,
                    lastScoreUpdatedAt: now,
                    lastTelemetryEvent: state.lastTelemetryEvent,
                    rollingMetrics: state.rollingMetrics,
                    emaMetrics: state.emaMetrics,
                    recoveredAt: now,
                    lastSuccessAt: state.lastSuccessAt,
                    lastLiveSuccessAt: state.lastLiveSuccessAt,
                    lastSuccessRequestID: state.lastSuccessRequestID,
                    lastFailureAt: state.lastFailureAt,
                    lastFailureClass: state.lastFailureClass,
                    nvidiaInferenceProbe: state.nvidiaInferenceProbe
                )
                healedAny = true
                continue
            }

            let emaSuccessRate = state.emaMetrics.successRate
            let staleThreshold = emaSuccessRate >= healthyEmaThreshold ? healthyEmaStaleThreshold : defaultStaleThreshold

            let hasRecoveryEvidence =
                state.emaMetrics.observationCount >= minimumHealObservations &&
                emaSuccessRate >= minimumHealSuccessRate
            guard age > staleThreshold else {
                continue
            }
            guard hasRecoveryEvidence else {
                continue
            }
            NSLog("[ThinkingProxy] Self-heal: promoting route %@ from suspect to closed (stale for %ds, EMA success rate: %.2f)", key, Int(age), emaSuccessRate)
            routeCircuitStatesByRouteHealthKey[key] = RouteCircuitState(
                status: .closed,
                failureScore: 0,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: state.lastTelemetryEvent,
                rollingMetrics: state.rollingMetrics,
                emaMetrics: state.emaMetrics,
                recoveredAt: now,
                lastSuccessAt: state.lastSuccessAt,
                lastLiveSuccessAt: state.lastLiveSuccessAt,
                lastSuccessRequestID: state.lastSuccessRequestID,
                lastFailureAt: state.lastFailureAt,
                lastFailureClass: state.lastFailureClass,
                nvidiaInferenceProbe: state.nvidiaInferenceProbe
            )
            healedAny = true
        }
        if healedAny {
            persistRouteHealthLocked()
        }
    }

    /// Public entry point for maintenance timer to heal stale suspect routes.
    static func maintenanceRouteHealthPass() {
        routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            healStaleSuspectRoutesLocked()
            purgeExpiredCooldownsLocked()
        }
        concurrencyRegistry.sanitizeStaleSlots()
    }

    /// Remove expired cooldown entries to prevent unbounded dict growth.
    /// Must be called on routeHealthQueue.
    private static func purgeExpiredCooldownsLocked() {
        let now = Date()
        let before = routeCooldownsByRouteHealthKey.count
        routeCooldownsByRouteHealthKey = routeCooldownsByRouteHealthKey.filter { $0.value > now }
        let removed = before - routeCooldownsByRouteHealthKey.count
        if removed > 0 {
            NSLog("[ThinkingProxy] Maintenance: purged %d expired cooldown entries (%d remaining)", removed, routeCooldownsByRouteHealthKey.count)
        }
    }

    private static func shouldProbeRouteWithCanary(
        routeHealthKey: String,
        state: RouteCircuitState,
        at now: Date
    ) -> Bool {
        let activeQuotaWindowUntil = [
            state.openUntil,
            routeCooldownsByRouteHealthKey[routeHealthKey]
        ]
        .compactMap { $0 }
        .filter { $0 > now }
        .max()

        if let activeQuotaWindowUntil,
           now < activeQuotaWindowUntil,
           state.lastTelemetryEvent?.failureClass?.lowercased() == "classified_429_window" {
            return false
        }

        if state.status == .open {
            return true
        }

        if routeHealthKey.hasPrefix("nvidia::"),
           state.status == .suspect || state.status == .halfOpen {
            return true
        }

        return false
    }

    /// Schedule a debounced persist of route health state.
    /// Called from recordRouteFailure/recordRouteSuccess paths where rapid sequential writes are common.
    /// Must already be on routeHealthQueue.
    private static func scheduleRouteHealthPersistLocked() {
        routeHealthDirty = true
        routeHealthPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard routeHealthDirty else { return }
            routeHealthDirty = false
            persistRouteHealthLocked()
        }
        routeHealthPersistWorkItem = workItem
        routeHealthQueue.asyncAfter(deadline: .now() + routeHealthPersistDebounce, execute: workItem)
    }

    /// Force-persist route health state immediately (for shutdown, testing, startup self-heal).
    private static func forcePersistRouteHealthLocked() {
        routeHealthPersistWorkItem?.cancel()
        routeHealthPersistWorkItem = nil
        routeHealthDirty = false
        persistRouteHealthLocked()
    }

    static func jsonNumberPreservingIntegers(_ value: Double) -> Any {
        if value.rounded(.towardZero) == value {
            return Int(value)
        }
        return value
    }

    private static func persistRouteHealthLocked() {
        dispatchPrecondition(condition: .onQueue(routeHealthQueue))
        guard let path = routeHealthStatePath() else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var routes: [String: [String: Any]] = [:]
        for (routeHealthKey, state) in routeCircuitStatesByRouteHealthKey {
            var entry: [String: Any] = [
                "status": state.status.rawValue,
                "failure_score": jsonNumberPreservingIntegers(state.failureScore),
                "recovery_successes": state.recoverySuccesses
            ]
            if let openUntil = state.openUntil {
                entry["open_until"] = iso8601String(from: openUntil)
            }
            if let lastScoreUpdatedAt = state.lastScoreUpdatedAt {
                entry["last_score_updated_at"] = iso8601String(from: lastScoreUpdatedAt)
            }
            if let lastTelemetryEvent = state.lastTelemetryEvent {
                entry["last_event"] = telemetryEventDictionary(lastTelemetryEvent)
            }
            entry["rolling_metrics"] = rollingMetricsDictionary(state.rollingMetrics)
            entry["ema_metrics"] = emaMetricsDictionary(state.emaMetrics)
            if let recoveredAt = state.recoveredAt {
                entry["recovered_at"] = iso8601String(from: recoveredAt)
            }
            if let lastSuccessAt = state.lastSuccessAt {
                entry["last_success_at"] = iso8601String(from: lastSuccessAt)
            }
            if let lastLiveSuccessAt = state.lastLiveSuccessAt {
                entry["last_live_success_at"] = iso8601String(from: lastLiveSuccessAt)
            }
            if let lastSuccessRequestID = state.lastSuccessRequestID {
                entry["last_success_request_id"] = lastSuccessRequestID
            }
            if let lastFailureAt = state.lastFailureAt {
                entry["last_failure_at"] = iso8601String(from: lastFailureAt)
            }
            if let lastFailureClass = state.lastFailureClass {
                entry["last_failure_class"] = lastFailureClass
            }
            if let nvidiaInferenceProbe = state.nvidiaInferenceProbe {
                entry["nvidia_inference_probe"] = nvidiaInferenceProbeStateDictionary(nvidiaInferenceProbe)
            }
            routes[routeHealthKey] = entry
        }

        let activeCooldowns = routeCooldownsByRouteHealthKey.filter { $0.value > Date() }.mapValues { iso8601String(from: $0) }
        var payload: [String: Any] = [
            "version": 9,
            "routes": routes,
            "provider_cooldowns": activeCooldowns,
            "route_cooldowns": activeCooldowns
        ]
        concurrencyRegistry.persistLocked(into: &payload)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func routeHealthStatePath() -> String? {
        if let overridePath = ProcessInfo.processInfo.environment["VIBEPROXY_ROUTE_HEALTH_PATH"],
           !overridePath.isEmpty {
            return overridePath
        }
        if let legacyOverridePath = ProcessInfo.processInfo.environment["VIBEPROXY_NVIDIA_ROUTE_HEALTH_PATH"],
           !legacyOverridePath.isEmpty {
            return legacyOverridePath
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".cli-proxy-api/route-health.json")
    }

    private static func telemetryEventDictionary(_ event: RouteTelemetryEvent) -> [String: Any] {
        var dict: [String: Any] = [
            "timestamp": iso8601String(from: event.timestamp),
            "request_model": event.requestModel,
            "canonical_model_id": event.canonicalModelID,
            "transport_outcome": event.transportOutcome,
            "attempt_lane": event.attemptLane,
            "timeout_stage": event.timeoutStage.rawValue,
            "retry_count": event.retryCount,
            "source": event.source
        ]
        if let requestedAlias = event.requestedAlias {
            dict["requested_alias"] = requestedAlias
        }
        if let healthTransition = event.healthTransition {
            dict["health_transition"] = healthTransition
        }
        if let winnerAttemptLane = event.winnerAttemptLane {
            dict["winner_attempt_lane"] = winnerAttemptLane
        }
        if let failoverDepth = event.failoverDepth {
            dict["failover_depth"] = failoverDepth
        }
        if let finalWinnerRequestModel = event.finalWinnerRequestModel {
            dict["final_winner_request_model"] = finalWinnerRequestModel
        }
        if let failureClass = event.failureClass {
            dict["failure_class"] = failureClass
        }
        if let upstreamHTTPStatus = event.upstreamHTTPStatus {
            dict["upstream_http_status"] = upstreamHTTPStatus
        }
        if let firstByteLatencyMilliseconds = event.firstByteLatencyMilliseconds {
            dict["first_byte_latency_ms"] = firstByteLatencyMilliseconds
        }
        if let totalLatencyMilliseconds = event.totalLatencyMilliseconds {
            dict["total_latency_ms"] = totalLatencyMilliseconds
        }
        if let inflightAtRequest = event.inflightAtRequest {
            dict["inflight_at_request"] = inflightAtRequest
        }
        if let proxyRequestID = event.proxyRequestID {
            dict["proxy_request_id"] = proxyRequestID
        }
        if let callerRequestID = event.callerRequestID {
            dict["caller_request_id"] = callerRequestID
        }
        if let callerSessionID = event.callerSessionID {
            dict["caller_session_id"] = callerSessionID
        }
        if let requestShape = event.requestShape {
            dict["request_shape"] = requestShape
        }
        if let negotiatedApplicationProtocol = event.negotiatedApplicationProtocol {
            dict["negotiated_application_protocol"] = negotiatedApplicationProtocol
        }
        if let errorBodySnippet = event.errorBodySnippet {
            dict["error_body_snippet"] = errorBodySnippet
        }
        return dict
    }

    private static func parseTelemetryEvent(_ rawValue: Any?) -> RouteTelemetryEvent? {
        guard let dict = rawValue as? [String: Any],
              let timestamp = parseISO8601Date(dict["timestamp"]),
              let requestModel = dict["request_model"] as? String,
              let canonicalModelID = dict["canonical_model_id"] as? String,
              let transportOutcome = (dict["transport_outcome"] as? String) ?? (dict["outcome"] as? String),
              let timeoutStageRaw = dict["timeout_stage"] as? String,
              let timeoutStage = DeadlineStage(rawValue: timeoutStageRaw),
              let retryCount = dict["retry_count"] as? Int,
              let source = dict["source"] as? String else {
            return nil
        }
        let attemptLane = integerValue(dict["attempt_lane"]) ?? 1
        return RouteTelemetryEvent(
            timestamp: timestamp,
            requestModel: requestModel,
            requestedAlias: dict["requested_alias"] as? String,
            canonicalModelID: canonicalModelID,
            transportOutcome: transportOutcome,
            healthTransition: dict["health_transition"] as? String,
            attemptLane: attemptLane,
            winnerAttemptLane: integerValue(dict["winner_attempt_lane"]),
            failoverDepth: integerValue(dict["failover_depth"]),
            finalWinnerRequestModel: dict["final_winner_request_model"] as? String,
            failureClass: dict["failure_class"] as? String,
            timeoutStage: timeoutStage,
            upstreamHTTPStatus: dict["upstream_http_status"] as? Int,
            retryCount: retryCount,
            source: source,
            firstByteLatencyMilliseconds: integerValue(dict["first_byte_latency_ms"]),
            totalLatencyMilliseconds: integerValue(dict["total_latency_ms"]),
            inflightAtRequest: integerValue(dict["inflight_at_request"]),
            proxyRequestID: dict["proxy_request_id"] as? String,
            callerRequestID: dict["caller_request_id"] as? String,
            callerSessionID: dict["caller_session_id"] as? String,
            requestShape: dict["request_shape"] as? String,
            negotiatedApplicationProtocol: dict["negotiated_application_protocol"] as? String,
            errorBodySnippet: dict["error_body_snippet"] as? String
        )
    }

    private static func rollingMetricsDictionary(_ metrics: RouteRollingMetrics) -> [String: Any] {
        [
            "recent_outcomes": metrics.recentOutcomes,
            "recent_first_byte_latency_ms": metrics.recentFirstByteLatencyMilliseconds,
            "recent_total_latency_ms": metrics.recentTotalLatencyMilliseconds
        ]
    }

    private static func emaMetricsDictionary(_ metrics: RouteEMAMetrics) -> [String: Any] {
        [
            "success_rate": metrics.successRate,
            "average_latency_ms": metrics.averageLatencyMs,
            "observation_count": metrics.observationCount
        ]
    }

    private static func nvidiaInferenceProbeStateDictionary(_ probe: NVIDIAInferenceProbeState) -> [String: Any] {
        var dict: [String: Any] = [
            "last_probe_at": iso8601String(from: probe.lastProbeAt),
            "last_status": probe.lastStatus.rawValue,
            "last_timeout_stage": probe.lastTimeoutStage.rawValue,
            "last_transport_outcome": probe.lastTransportOutcome
        ]
        if let lastSuccessAt = probe.lastSuccessAt {
            dict["last_success_at"] = iso8601String(from: lastSuccessAt)
        }
        if let lastFailureAt = probe.lastFailureAt {
            dict["last_failure_at"] = iso8601String(from: lastFailureAt)
        }
        if let lastFailureClass = probe.lastFailureClass {
            dict["last_failure_class"] = lastFailureClass
        }
        if let lastUpstreamHTTPStatus = probe.lastUpstreamHTTPStatus {
            dict["last_upstream_http_status"] = lastUpstreamHTTPStatus
        }
        if let lastFirstByteLatencyMilliseconds = probe.lastFirstByteLatencyMilliseconds {
            dict["last_first_byte_latency_ms"] = lastFirstByteLatencyMilliseconds
        }
        if let lastTotalLatencyMilliseconds = probe.lastTotalLatencyMilliseconds {
            dict["last_total_latency_ms"] = lastTotalLatencyMilliseconds
        }
        return dict
    }

    private static func parseRollingMetrics(_ rawValue: Any?) -> RouteRollingMetrics {
        guard let dict = rawValue as? [String: Any] else {
            return .empty
        }
        return RouteRollingMetrics(
            recentOutcomes: dict["recent_outcomes"] as? [String] ?? [],
            recentFirstByteLatencyMilliseconds: dict["recent_first_byte_latency_ms"] as? [Int] ?? [],
            recentTotalLatencyMilliseconds: dict["recent_total_latency_ms"] as? [Int] ?? []
        )
    }

    private static func parseEMAMetrics(_ rawValue: Any?) -> RouteEMAMetrics {
        guard let dict = rawValue as? [String: Any],
              let successRate = dict["success_rate"] as? Double,
              let averageLatencyMs = dict["average_latency_ms"] as? Double,
              let observationCount = dict["observation_count"] as? Int else {
            return .empty
        }
        return RouteEMAMetrics(
            successRate: successRate,
            averageLatencyMs: averageLatencyMs,
            observationCount: observationCount
        )
    }

    private static func parseNVIDIAInferenceProbeState(_ rawValue: Any?) -> NVIDIAInferenceProbeState? {
        guard let dict = rawValue as? [String: Any],
              let lastProbeAt = parseISO8601Date(dict["last_probe_at"]),
              let lastStatusRaw = dict["last_status"] as? String,
              let lastStatus = NVIDIAInferenceProbeStatus(rawValue: lastStatusRaw),
              let timeoutStageRaw = dict["last_timeout_stage"] as? String,
              let lastTimeoutStage = DeadlineStage(rawValue: timeoutStageRaw),
              let lastTransportOutcome = dict["last_transport_outcome"] as? String else {
            return nil
        }

        return NVIDIAInferenceProbeState(
            lastProbeAt: lastProbeAt,
            lastStatus: lastStatus,
            lastSuccessAt: parseISO8601Date(dict["last_success_at"]),
            lastFailureAt: parseISO8601Date(dict["last_failure_at"]),
            lastFailureClass: dict["last_failure_class"] as? String,
            lastTimeoutStage: lastTimeoutStage,
            lastUpstreamHTTPStatus: integerValue(dict["last_upstream_http_status"]),
            lastTransportOutcome: lastTransportOutcome,
            lastFirstByteLatencyMilliseconds: integerValue(dict["last_first_byte_latency_ms"]),
            lastTotalLatencyMilliseconds: integerValue(dict["last_total_latency_ms"])
        )
    }

    private static func parseISO8601Date(_ rawValue: Any?) -> Date? {
        guard let string = rawValue as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    private static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func logNVIDIARouteTelemetry(_ event: RouteTelemetryEvent) {
        routeTelemetryHookForTesting?(event)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: telemetryEventDictionary(event), options: [.sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            NSLog("[ThinkingProxy] Route telemetry encode failed for %@", event.requestModel)
            return
        }
        NSLog("[ThinkingProxy] Route telemetry %@", jsonString)
    }

    static func telemetryEventWithWinnerAttemptLane(
        _ event: RouteTelemetryEvent,
        winnerAttemptLane: Int
    ) -> RouteTelemetryEvent {
        RouteTelemetryEvent(
            timestamp: event.timestamp,
            requestModel: event.requestModel,
            requestedAlias: event.requestedAlias,
            canonicalModelID: event.canonicalModelID,
            transportOutcome: event.transportOutcome,
            healthTransition: event.healthTransition,
            attemptLane: event.attemptLane,
            winnerAttemptLane: winnerAttemptLane,
            failoverDepth: event.failoverDepth,
            finalWinnerRequestModel: event.finalWinnerRequestModel,
            failureClass: event.failureClass,
            timeoutStage: event.timeoutStage,
            upstreamHTTPStatus: event.upstreamHTTPStatus,
            retryCount: event.retryCount,
            source: event.source,
            firstByteLatencyMilliseconds: event.firstByteLatencyMilliseconds,
            totalLatencyMilliseconds: event.totalLatencyMilliseconds,
            inflightAtRequest: event.inflightAtRequest,
            proxyRequestID: event.proxyRequestID,
            callerRequestID: event.callerRequestID,
            callerSessionID: event.callerSessionID,
            requestShape: event.requestShape,
            errorBodySnippet: event.errorBodySnippet
        )
    }

    private static func normalizedResponseBody(
        json: [String: Any],
        contentOverride: String?,
        stripsReasoningField: Bool
    ) -> Data? {
        var repairedJSON = json
        guard var choices = repairedJSON["choices"] as? [[String: Any]],
              !choices.isEmpty else {
            return nil
        }

        var firstChoice = choices[0]
        var message = firstChoice["message"] as? [String: Any] ?? [:]
        var modified = false

        if let contentOverride {
            message["content"] = contentOverride
            modified = true
        }
        if stripsReasoningField {
            if message["reasoning"] != nil {
                message.removeValue(forKey: "reasoning")
                modified = true
            }
            if message["reasoning_content"] != nil {
                message.removeValue(forKey: "reasoning_content")
                modified = true
            }
        }
        guard modified else {
            return nil
        }

        firstChoice["message"] = message
        choices[0] = firstChoice
        repairedJSON["choices"] = choices

        return try? JSONSerialization.data(withJSONObject: repairedJSON)
    }

    private static func startsWithThinkTag(_ value: String) -> Bool {
        value.lowercased().hasPrefix("<think>")
    }

    fileprivate static func containsUnsupportedTypedMessageContent(in json: [String: Any]) -> Bool {
        guard let messages = json["messages"] as? [[String: Any]] else {
            return false
        }

        for message in messages {
            if case .unsupported = normalizedContentResult(from: message["content"]) {
                return true
            }
        }
        return false
    }

    private static func normalizedContentResult(from content: Any?) -> ContentNormalizationResult {
        guard let content else {
            return .unchanged
        }
        if content is String {
            return .unchanged
        }
        if !(content is [String: Any]) && !(content is [Any]),
           let scalarText = normalizedStructuredPayloadString(content) {
            return .flattened(scalarText)
        }
        if let dictionary = content as? [String: Any] {
            if let flattened = flattenedTextMessageContent(from: dictionary) {
                return .flattened(flattened)
            }
            if isIgnorableNonMediaTypedContent(dictionary) {
                return .flattened("")
            }
            return .unsupported
        }
        guard let segments = content as? [Any] else {
            return .unsupported
        }

        var collectedSegments: [String] = []
        var sawIgnorableNonMediaSegment = false
        for segment in segments {
            if let textSegment = segment as? String {
                collectedSegments.append(textSegment)
                continue
            }
            if !(segment is [String: Any]),
               let scalarText = normalizedStructuredPayloadString(segment) {
                collectedSegments.append(scalarText)
                continue
            }

            guard let dictionary = segment as? [String: Any] else {
                return .unsupported
            }
            if containsUnsupportedMediaPayload(dictionary) {
                return .unsupported
            }
            guard let textValue = flattenedTextMessageContent(from: dictionary) else {
                if isIgnorableNonMediaTypedContent(dictionary) {
                    sawIgnorableNonMediaSegment = true
                    continue
                }
                continue
            }
            collectedSegments.append(textValue)
        }

        if !collectedSegments.isEmpty {
            return .flattened(collectedSegments.joined())
        }

        if sawIgnorableNonMediaSegment {
            return .flattened("")
        }

        guard !collectedSegments.isEmpty else {
            return .unsupported
        }
        return .flattened(collectedSegments.joined())
    }

    private static func flattenedTextMessageContent(from dictionary: [String: Any]) -> String? {
        let type = (dictionary["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let allowsDirectText = type == nil || type == "text" || type == "input_text" || type == "output_text" || type == "summary_text" || type == "reasoning" || type == "tool_result"
        let allowsStructuredPayload = type == nil || type == "tool_result" || type == "output_json" || type == "input_json" || type == "json" || type == "reasoning" || type == "metadata_marker"

        if let textValue = normalizedTextMessageScalar(dictionary["text"]),
           allowsDirectText {
            return textValue
        }

        if let outputText = normalizedTextMessageScalar(dictionary["output_text"]),
           allowsDirectText || type == "output_json" {
            return outputText
        }

        if let valueText = normalizedTextMessageScalar(dictionary["value"]),
           allowsStructuredPayload {
            return valueText
        }

        if let structuredJSON = normalizedStructuredPayloadString(dictionary["json"]),
           allowsStructuredPayload {
            return structuredJSON
        }

        if let structuredResult = normalizedStructuredPayloadString(dictionary["result"]),
           allowsStructuredPayload {
            return structuredResult
        }

        if let structuredArguments = normalizedStructuredPayloadString(dictionary["arguments"]),
           allowsStructuredPayload {
            return structuredArguments
        }

        if let structuredValue = normalizedStructuredPayloadString(dictionary["value"]),
           allowsStructuredPayload {
            return structuredValue
        }

        if let nestedContent = dictionary["content"] {
            switch normalizedContentResult(from: nestedContent) {
            case .flattened(let flattened):
                return flattened
            case .unchanged, .unsupported:
                break
            }
            if let structuredContent = normalizedStructuredPayloadString(nestedContent) {
                return structuredContent
            }
        }

        return nil
    }

    private static func hasVisibleStructuredPayloadField(_ dictionary: [String: Any]) -> Bool {
        let visiblePayloadKeys: Set<String> = [
            "text",
            "output_text",
            "value",
            "json",
            "result",
            "arguments",
            "content"
        ]
        return visiblePayloadKeys.contains { dictionary[$0] != nil }
    }

    private static func isIgnorableNonMediaTypedContent(_ dictionary: [String: Any]) -> Bool {
        guard !containsUnsupportedMediaPayload(dictionary) else {
            return false
        }

        let nonIgnorableTypes: Set<String> = [
            "text",
            "input_text",
            "output_text",
            "summary_text",
            "tool_result",
            "output_json",
            "input_json",
            "json"
        ]
        guard let type = (dictionary["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !type.isEmpty else {
            // Opaque non-media dictionaries without a type marker still show up in live worker
            // transcripts. For text-only fallback lanes, degrade them to empty-string context
            // rather than excluding the route outright.
            return true
        }

        if !hasVisibleStructuredPayloadField(dictionary) {
            // Some providers and SDKs emit metadata-only wrappers such as `tool_result` with
            // identifiers but no visible payload. These should not exclude text-only fallback
            // routes when the surrounding transcript still has usable visible context.
            return true
        }

        return !nonIgnorableTypes.contains(type)
    }

    private static func normalizedTextMessageScalar(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func normalizedStructuredPayloadString(_ value: Any?) -> String? {
        if let text = normalizedTextMessageScalar(value) {
            return text
        }
        if let boolean = value as? Bool {
            return boolean ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let dictionary = value as? [String: Any] {
            guard !containsUnsupportedMediaPayload(dictionary),
                  JSONSerialization.isValidJSONObject(dictionary),
                  let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return text
        }
        if let array = value as? [Any] {
            guard !containsUnsupportedMediaPayload(array),
                  JSONSerialization.isValidJSONObject(array),
                  let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return text
        }
        return nil
    }

    private static func containsUnsupportedMediaPayload(_ value: Any) -> Bool {
        let unsupportedTypes: Set<String> = [
            "input_image",
            "image",
            "image_url",
            "input_audio",
            "audio",
            "audio_url",
            "file",
            "input_file",
            "video",
            "input_video"
        ]
        let unsupportedKeys: Set<String> = [
            "image",
            "image_url",
            "audio",
            "audio_url",
            "file",
            "file_data",
            "file_url",
            "video",
            "video_url"
        ]

        if let dictionary = value as? [String: Any] {
            if let type = (dictionary["type"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               unsupportedTypes.contains(type) {
                return true
            }
            if dictionary.keys.contains(where: { unsupportedKeys.contains($0) }) {
                return true
            }
            for nestedValue in dictionary.values where containsUnsupportedMediaPayload(nestedValue) {
                return true
            }
            return false
        }

        if let array = value as? [Any] {
            for element in array where containsUnsupportedMediaPayload(element) {
                return true
            }
        }

        return false
    }

    static func requiredToolParametersIndex(forRequestJSON jsonString: String) -> [String: [String]]? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let tools = json["tools"] as? [[String: Any]],
              !tools.isEmpty else {
            return nil
        }

        var index: [String: [String]] = [:]
        for tool in tools {
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let parameters = function["parameters"] as? [String: Any],
                  let required = parameters["required"] as? [String],
                  !required.isEmpty else {
                continue
            }
            index[name] = required
        }
        return index.isEmpty ? nil : index
    }

    fileprivate static func validateToolCalls(in message: [String: Any], requiredToolParameters: [String: [String]]? = nil) -> ToolCallValidation {
        guard let toolCalls = message["tool_calls"] as? [[String: Any]],
              !toolCalls.isEmpty else {
            return .none
        }

        for toolCall in toolCalls {
            guard let function = toolCall["function"] as? [String: Any] else {
                return .invalid
            }

            let argsDict = resolveArgsDict(from: function)
            guard let argsDict else {
                return .invalid
            }

            if let requiredParams = requiredToolParameters,
               let toolName = function["name"] as? String,
               let required = requiredParams[toolName] {
                for param in required {
                    if argsDict[param] == nil {
                        return .invalid
                    }
                }
            }
        }

        return .valid
    }

    private static func resolveArgsDict(from function: [String: Any]) -> [String: Any]? {
        if let arguments = function["arguments"] as? String {
            let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let dict = obj as? [String: Any] else {
                return nil
            }
            return dict
        }
        if let dict = function["arguments"] as? [String: Any] {
            return dict
        }
        return nil
    }

    private static func repairNativeToolCallArguments(in json: [String: Any]) -> Data? {
        guard var choices = json["choices"] as? [[String: Any]],
              !choices.isEmpty else {
            return nil
        }

        var modified = false
        var firstChoice = choices[0]
        var message = firstChoice["message"] as? [String: Any] ?? [:]

        guard var toolCalls = message["tool_calls"] as? [[String: Any]],
              !toolCalls.isEmpty else {
            return nil
        }

        for i in toolCalls.indices {
            var toolCall = toolCalls[i]
            guard var function = toolCall["function"] as? [String: Any] else { continue }
            if function["arguments"] is String { continue }
            guard let dict = function["arguments"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dict),
                  let str = String(data: data, encoding: .utf8) else { continue }
            function["arguments"] = str.replacingOccurrences(of: "\\/", with: "/")
            toolCall["function"] = function
            toolCalls[i] = toolCall
            modified = true
        }

        guard modified else { return nil }

        message["tool_calls"] = toolCalls
        firstChoice["message"] = message
        choices[0] = firstChoice

        var repaired = json
        repaired["choices"] = choices
        return try? JSONSerialization.data(withJSONObject: repaired)
    }

    private static func stripLeadingThinkBlock(from content: String) -> String? {
        let pattern = #"(?is)^\s*<think>.*?</think>\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.range.location != NSNotFound,
              match.range.location == 0 else {
            return nil
        }

        let stripped = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func policy(forRequestJSON jsonString: String) -> RequestPolicy? {
        guard let model = modelName(forRequestJSON: jsonString) else {
            return nil
        }
        return policy(forModel: model)
    }

    private static func policy(forModel model: String) -> RequestPolicy? {
        let model = normalizedRequestModel(model)
        if isWorkerPoolPublicAlias(model) {
            return workerSmartRouteRequestPolicy
        }
        if let policy = nonNVIDIAMitigationPoliciesByRequestModel[model] {
            return policy
        }
        if let route = resolveNVIDIAHostedRoute(forRequestModel: model) {
            return knownNVIDIARoutePoliciesByCanonicalModelID[route.canonicalModelID]
        }
        return nil
    }

    private static func isNVIDIAHostedModel(_ model: String) -> Bool {
        resolveNVIDIAHostedRoute(forRequestModel: model) != nil
    }

    static func modelTier(forRequestModel model: String) -> ModelTier {
        let normalized = normalizedRequestModel(model)
        if let route = resolveConfiguredRoute(forRequestModel: normalized),
           let tier = modelTierByCanonicalModelID[route.canonicalModelID] {
            return tier
        }
        if let tier = modelTierByCanonicalModelID[normalized] {
            return tier
        }
        return .standard
    }

    private static func reasoningString(from message: [String: Any]) -> String {
        if let reasoning = (message["reasoning"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoning.isEmpty {
            return reasoning
        }
        if let reasoningContent = (message["reasoning_content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoningContent.isEmpty {
            return reasoningContent
        }
        return ""
    }

    private static func resolvedRoutesByRequestModel() -> [String: RouteIdentity] {
        configuredRouteConfiguration().routesByRequestModel
    }

    static func resolveConfiguredRoute(forRequestModel model: String) -> RouteIdentity? {
        let normalized = normalizedRequestModel(model)
        if normalized == publicNVIDIADirectAlias {
            return resolvedRoutesByRequestModel()[publicNVIDIASmartAlias]
        }
        return resolvedRoutesByRequestModel()[normalized]
    }

    static func providerEndpoint(forProviderID providerID: String) -> ProviderEndpoint? {
        configuredRouteConfiguration().providerEndpointsByProviderID[providerID]
    }

    private static func normalizedRequestModel(_ model: String) -> String {
        let legacyNormalized = legacyRequestModelRewrites[model] ?? model
        if let resolved = ThinkingProxy.factoryResolvedRouteModel(forIncomingModelID: legacyNormalized) {
            return resolved
        }
        // Reverse-map bare route model names (e.g. "proxy-worker-smart-router") that
        // the Factory Droid sometimes sends instead of the custom model ID
        // (e.g. "custom:Proxy-Worker-Smart-Router-8").  When the bare name matches a
        // known factory binding's route model, use that binding's route model so the
        // request gets the correct provider, timeout policy, and health tracking.
        if let binding = ThinkingProxy.factoryModelBindingByRouteModel(forRouteModel: legacyNormalized) {
            return binding.routeModel
        }
        return legacyNormalized
    }

    private static func resolveNVIDIAHostedRoute(forRequestModel model: String) -> RouteIdentity? {
        guard let route = resolveConfiguredRoute(forRequestModel: model),
              route.providerID.hasPrefix("nvidia") else {
            return nil
        }
        return route
    }

    static func rewrittenNVIDIADirectUpstreamRequestJSON(
        method: String,
        path: String,
        jsonString: String
    ) -> String? {
        guard rawModelName(forRequestJSON: jsonString) == publicNVIDIADirectAlias else {
            return nil
        }
        return rewrittenRequestJSON(
            method: method,
            path: path,
            replacingRequestModelIn: jsonString,
            with: publicNVIDIASmartAlias
        )
    }

    private static func unavailableRequestModelIDs(at now: Date) -> Set<String> {
        let routes = resolvedRoutesByRequestModel()
        let openRouteHealthKeys: Set<String> = routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return Set(routeCircuitStatesByRouteHealthKey.compactMap { key, value in
                value.isUnavailable(at: now) ? key : nil
            })
        }
        guard !openRouteHealthKeys.isEmpty else {
            return []
        }
        return Set(routes.compactMap { requestModel, route in
            openRouteHealthKeys.contains(route.routeHealthKey) ? requestModel : nil
        })
    }

    private static func configuredRouteConfiguration() -> CachedRouteConfiguration {
        let path = mergedConfigPath()
        let modificationDate = path.flatMap { configPath in
            (try? FileManager.default.attributesOfItem(atPath: configPath)[.modificationDate]) as? Date
        }

        return routeConfigCacheQueue.sync {
            if let cachedRouteConfiguration,
               cachedRouteConfiguration.configPath == path,
               cachedRouteConfiguration.modificationDate == modificationDate {
                return cachedRouteConfiguration
            }

            let loadedConfiguration = loadConfiguredRouteConfiguration(from: path)
            let cachedMap = CachedRouteConfiguration(
                configPath: path,
                modificationDate: modificationDate,
                routesByRequestModel: loadedConfiguration.routesByRequestModel,
                nvidiaRoutesByRequestModel: loadedConfiguration.nvidiaRoutesByRequestModel,
                anthropicRequestModels: loadedConfiguration.anthropicRequestModels,
                smartAliasesByAlias: loadedConfiguration.smartAliasesByAlias,
                providerEndpointsByProviderID: loadedConfiguration.providerEndpointsByProviderID
            )
            cachedRouteConfiguration = cachedMap
            return cachedMap
        }
    }

    private static func loadConfiguredRouteConfiguration(from path: String?) -> (
        routesByRequestModel: [String: RouteIdentity],
        nvidiaRoutesByRequestModel: [String: RouteIdentity],
        anthropicRequestModels: Set<String>,
        smartAliasesByAlias: [String: SmartAliasDefinition],
        providerEndpointsByProviderID: [String: ProviderEndpoint]
    ) {
        guard let path,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ([:], [:], [], [:], [:])
        }

        struct ParsedModel {
            var alias: String?
            var name: String?
            var registerCanonicalName: Bool = true
        }

        struct ParsedProvider {
            var name = ""
            var baseURL = ""
            var proxyURL: String?
            var apiKey: String?
            var models: [ParsedModel] = []
        }

        enum ParsedSection {
            case none
            case openAICompatibility
            case claudeAPIKey
            case smartAliases
        }

        var routesByRequestModel: [String: RouteIdentity] = [:]
        var nvidiaRoutesByRequestModel: [String: RouteIdentity] = [:]
        var anthropicRequestModels: Set<String> = []
        var smartAliasesByAlias: [String: SmartAliasDefinition] = [:]
        var providerEndpointsByProviderID: [String: ProviderEndpoint] = [:]
        var currentSection: ParsedSection = .none
        var currentProvider: ParsedProvider?
        var insideModels = false
        var currentModel = ParsedModel()
        var currentSmartAliasName: String?
        var currentSmartAliasRequestClass: String?
        var currentSmartAliasFailover: String?
        var currentSmartAliasHealthSensitivity: HealthSensitivity?
        var currentSmartAliasCandidates: [String] = []

        func indentation(of line: String) -> Int {
            line.prefix { $0 == " " }.count
        }

        func scalarValue(from line: String) -> String? {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                return nil
            }
            let rawValue = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespaces)
            guard !rawValue.isEmpty else {
                return nil
            }
            return rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }

        func booleanValue(from line: String) -> Bool? {
            guard let scalar = scalarValue(from: line)?.lowercased() else {
                return nil
            }
            switch scalar {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }

        func normalizedProviderAPIKey(_ rawValue: String?) -> String? {
            guard var normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalized.isEmpty else {
                return nil
            }
            if normalized.count >= 7, normalized.prefix(7).caseInsensitiveCompare("Bearer ") == .orderedSame {
                normalized = String(normalized.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return normalized.isEmpty ? nil : normalized
        }

        func finalizeCurrentModel() {
            guard currentProvider != nil else {
                currentModel = ParsedModel()
                return
            }
            let trimmedAlias = currentModel.alias?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = currentModel.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let canonicalModelID = [trimmedName, trimmedAlias].compactMap({ $0 }).first,
                  !canonicalModelID.isEmpty else {
                currentModel = ParsedModel()
                return
            }

            let shouldRegisterCanonicalName = currentModel.registerCanonicalName || trimmedAlias == nil

            var provider = currentProvider ?? ParsedProvider()
            provider.models.append(
                ParsedModel(
                    alias: trimmedAlias,
                    name: canonicalModelID,
                    registerCanonicalName: shouldRegisterCanonicalName
                )
            )
            currentProvider = provider
            currentModel = ParsedModel()
        }

        func providerIdentifier(
            explicitName: String,
            baseURL: String,
            section: ParsedSection
        ) -> String {
            if !explicitName.isEmpty {
                return explicitName
            }

            if baseURL.contains("integrate.api.nvidia.com") {
                return "nvidia"
            }
            if baseURL.contains("api.z.ai") {
                return "zai"
            }
            if baseURL.contains("api.anthropic.com") {
                return "claude"
            }

            switch section {
            case .claudeAPIKey:
                return "claude"
            default:
                return "unknown"
            }
        }

        func finalizeCurrentProvider(section: ParsedSection) {
            finalizeCurrentModel()
            guard let provider = currentProvider else {
                return
            }
            let trimmedName = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isNVIDIAProvider = trimmedName.hasPrefix("nvidia") || trimmedBaseURL.contains("integrate.api.nvidia.com")
            let providerID = providerIdentifier(
                explicitName: trimmedName,
                baseURL: trimmedBaseURL,
                section: section
            )
            for model in provider.models {
                guard let canonicalModelID = model.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !canonicalModelID.isEmpty else {
                    continue
                }
                let routeIdentity = RouteIdentity(
                    providerID: providerID,
                    canonicalModelID: canonicalModelID
                )
                if let alias = model.alias?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !alias.isEmpty {
                    routesByRequestModel[alias] = routeIdentity
                    if isNVIDIAProvider {
                        nvidiaRoutesByRequestModel[alias] = routeIdentity
                    }
                    if section == .claudeAPIKey {
                        anthropicRequestModels.insert(alias)
                    }
                }
                if model.registerCanonicalName {
                    routesByRequestModel[canonicalModelID] = routeIdentity
                    if isNVIDIAProvider {
                        nvidiaRoutesByRequestModel[canonicalModelID] = routeIdentity
                    }
                    if section == .claudeAPIKey {
                        anthropicRequestModels.insert(canonicalModelID)
                    }
                }
            }
            if let proxyURL = provider.proxyURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !proxyURL.isEmpty {
                let endpointBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !endpointBaseURL.isEmpty {
                    providerEndpointsByProviderID[providerID] = ProviderEndpoint(
                        providerID: providerID,
                        baseURL: endpointBaseURL,
                        proxyURL: proxyURL,
                        apiKey: normalizedProviderAPIKey(provider.apiKey)
                    )
                }
            }
            currentProvider = nil
            insideModels = false
        }

        func finalizeCurrentSmartAlias() {
            guard let smartAliasName = currentSmartAliasName else {
                currentSmartAliasRequestClass = nil
                currentSmartAliasFailover = nil
                currentSmartAliasHealthSensitivity = nil
                currentSmartAliasCandidates = []
                return
            }
            let requestClass = currentSmartAliasRequestClass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let failover = currentSmartAliasFailover?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let healthSensitivity = currentSmartAliasHealthSensitivity ?? .balanced
            let candidates = currentSmartAliasCandidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !requestClass.isEmpty, !failover.isEmpty, !candidates.isEmpty {
                smartAliasesByAlias[smartAliasName] = SmartAliasDefinition(
                    alias: smartAliasName,
                    requestClass: requestClass,
                    failover: failover,
                    candidates: candidates,
                    healthSensitivity: healthSensitivity
                )
            }
            currentSmartAliasName = nil
            currentSmartAliasRequestClass = nil
            currentSmartAliasFailover = nil
            currentSmartAliasHealthSensitivity = nil
            currentSmartAliasCandidates = []
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let indent = indentation(of: line)

            if indent == 0 && trimmed == "smart-aliases:" {
                finalizeCurrentProvider(section: currentSection)
                finalizeCurrentSmartAlias()
                currentSection = .smartAliases
                continue
            }

            if indent == 0 && trimmed == "openai-compatibility:" {
                finalizeCurrentSmartAlias()
                finalizeCurrentProvider(section: currentSection)
                currentSection = .openAICompatibility
                continue
            }

            if indent == 0 && trimmed == "claude-api-key:" {
                finalizeCurrentSmartAlias()
                finalizeCurrentProvider(section: currentSection)
                currentSection = .claudeAPIKey
                continue
            }

            if currentSection == .none {
                continue
            }

            if currentSection == .smartAliases {
                if trimmed == "smart-aliases:" {
                    continue
                }
                if indent == 2, trimmed.hasSuffix(":") {
                    finalizeCurrentSmartAlias()
                    currentSmartAliasName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                    continue
                }
                if indent == 4, trimmed.hasPrefix("request-class: "), let value = scalarValue(from: trimmed) {
                    currentSmartAliasRequestClass = value
                    continue
                }
                if indent == 4, trimmed.hasPrefix("failover: "), let value = scalarValue(from: trimmed) {
                    currentSmartAliasFailover = value
                    continue
                }
                if indent == 4, trimmed.hasPrefix("health-sensitivity: "), let value = scalarValue(from: trimmed) {
                    currentSmartAliasHealthSensitivity = HealthSensitivity(rawValue: value)
                    continue
                }
                if indent == 4, trimmed == "candidates:" {
                    continue
                }
                if indent >= 4, trimmed.hasPrefix("- ") {
                    let candidate = String(trimmed.dropFirst(2)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                    if !candidate.isEmpty {
                        currentSmartAliasCandidates.append(candidate)
                    }
                }
                continue
            }

            if indent == 0 && trimmed.hasPrefix("- ") {
                finalizeCurrentProvider(section: currentSection)
                currentProvider = ParsedProvider()
                if trimmed.hasPrefix("- name: "),
                   let value = scalarValue(from: trimmed) {
                    currentProvider?.name = value
                }
                continue
            }

            if indent == 0,
               trimmed.hasSuffix(":"),
               trimmed != "smart-aliases:",
               trimmed != "openai-compatibility:",
               trimmed != "claude-api-key:" {
                finalizeCurrentSmartAlias()
                finalizeCurrentProvider(section: currentSection)
                currentSection = .none
                continue
            }

            guard currentProvider != nil else {
                continue
            }

            if indent == 2 && trimmed == "models:" {
                finalizeCurrentModel()
                insideModels = true
                continue
            }

            if indent == 2 && trimmed.hasSuffix(":") && trimmed != "models:" {
                if insideModels {
                    finalizeCurrentModel()
                }
                insideModels = false
            }

            if indent == 2, trimmed.hasPrefix("name: "), let value = scalarValue(from: trimmed) {
                currentProvider?.name = value
                continue
            }

            if indent == 2, trimmed.hasPrefix("base-url: "), let value = scalarValue(from: trimmed) {
                currentProvider?.baseURL = value
                continue
            }

            if indent == 2, trimmed.hasPrefix("proxy-url: "), let value = scalarValue(from: trimmed) {
                currentProvider?.proxyURL = value
                continue
            }

            if indent == 2, trimmed.hasPrefix("api-key: "), let value = scalarValue(from: trimmed),
               currentProvider?.apiKey == nil {
                currentProvider?.apiKey = value
                continue
            }

            // Capture first API key from api-key-entries (for direct proxied requests).
            // Accept both standard YAML list-item indentation (`- api-key:`) and any
            // already-flattened scalar form that may appear in merged configs.
            if (indent == 2 && trimmed.hasPrefix("- api-key: "))
                || (indent == 4 && trimmed.hasPrefix("api-key: ")),
               let value = scalarValue(from: trimmed),
               currentProvider?.apiKey == nil {
                currentProvider?.apiKey = value
                continue
            }

            guard insideModels else {
                continue
            }

            if indent == 2 && trimmed.hasPrefix("- ") {
                finalizeCurrentModel()
                if trimmed.hasPrefix("- alias: ") {
                    currentModel.alias = scalarValue(from: trimmed)
                } else if trimmed.hasPrefix("- name: ") {
                    currentModel.name = scalarValue(from: trimmed)
                }
                continue
            }

            if indent >= 4, trimmed.hasPrefix("alias: "), let value = scalarValue(from: trimmed) {
                currentModel.alias = value
                continue
            }

            if indent >= 4,
               trimmed.hasPrefix("name: "),
               let value = scalarValue(from: trimmed) {
                currentModel.name = value
                continue
            }

            if indent >= 4,
               trimmed.hasPrefix("register-canonical-name: "),
               let value = booleanValue(from: trimmed) {
                currentModel.registerCanonicalName = value
            }
        }

        finalizeCurrentProvider(section: currentSection)
        finalizeCurrentSmartAlias()
        return (
            routesByRequestModel,
            nvidiaRoutesByRequestModel,
            anthropicRequestModels,
            smartAliasesByAlias.filter { !$0.key.isEmpty },
            providerEndpointsByProviderID
        )
    }

    private static func retryEvaluation(
        for failureClass: FailureClass,
        policy: RequestPolicy,
        repairedBodyData: Data?,
        normalizedBodyData: Data?
    ) -> NvidiaReasoningEvaluation {
        if policy.retryableFailureClasses.contains(failureClass) {
            return NvidiaReasoningEvaluation(
                failureClass: failureClass,
                repairedBodyData: repairedBodyData,
                normalizedBodyData: nil
            )
        }

        return NvidiaReasoningEvaluation(
            failureClass: nil,
            repairedBodyData: nil,
            normalizedBodyData: normalizedBodyData
        )
    }

    fileprivate static func hasStrictToolChoice(in json: [String: Any]) -> Bool {
        guard let toolChoice = json["tool_choice"] else {
            return false
        }

        if let toolChoiceString = toolChoice as? String {
            let normalized = toolChoiceString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "required"
        }

        guard let toolChoiceDict = toolChoice as? [String: Any],
              let type = (toolChoiceDict["type"] as? String)?.lowercased() else {
            return false
        }
        return type == "function" || type == "required"
    }

    static func mergedConfigPath() -> String? {
        if let overridePath = ProcessInfo.processInfo.environment["VIBEPROXY_MERGED_CONFIG_PATH"],
           !overridePath.isEmpty,
           FileManager.default.fileExists(atPath: overridePath) {
            return overridePath
        }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".cli-proxy-api/merged-config.yaml")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

}

enum MetaAIWebAdapter {
    static let providerID = "meta-web"
    static let modelAlias = "muse-spark"
    static let conversationMode = "think_hard"
    private static let maxEventStreamDataLineBytes = 256 * 1024

    enum ResponseSurface: Equatable {
        case chatCompletions
        case responses
    }

    struct Failure: Error, Equatable {
        let statusCode: Int
        let message: String
    }

    struct ExecutionResult {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    struct ParsedRequest: Equatable {
        let surface: ResponseSurface
        let prompt: String
        let executionPrompt: String
        let stream: Bool
        let publicModel: String
        let toolDefinitions: [ToolDefinition]
        let toolChoice: ToolChoice
        /// True when the request contains only a single user message (new thread).
        /// False when it contains multi-turn context (system/assistant messages = follow-up).
        let isNewThread: Bool
    }

    enum ToolChoice: Equatable {
        case none
        case auto
        case required
        case specific(String)
    }

    struct ToolDefinition: Equatable {
        let name: String
        let description: String?
        let parametersJSONString: String
    }

    struct SyntheticToolDirective: Equatable {
        let name: String
        let argumentsJSONString: String
    }

    struct ParsedEventStream: Equatable {
        let assistantText: String?
        let errorMessage: String?
        let sources: [Source]
    }

    struct HARAuthSnapshot: Equatable {
        let cookieHeader: String
        let userAgent: String
        let acceptLanguage: String
        let clientTimezone: String
        let userLocale: String
        let devicePixelRatio: Double?
    }

    struct Source: Equatable {
        let url: String
        let title: String
        let subtitle: String?
    }

    struct PlannedGraphQLRequest {
        enum Kind: Equatable, CustomStringConvertible {
            case updateLastSelectedMode
            case warmupConversation
            case updateConversationMode
            case sendMessage

            var description: String {
                switch self {
                case .updateLastSelectedMode:
                    return "updateLastSelectedMode"
                case .warmupConversation:
                    return "warmupConversation"
                case .updateConversationMode:
                    return "updateConversationMode"
                case .sendMessage:
                    return "sendMessage"
                }
            }
        }

        let kind: Kind
        let isBestEffort: Bool
        let request: URLRequest
    }

    private static let graphQLEndpointURL = URL(string: "https://www.meta.ai/api/graphql")!
    private static let browserOrigin = "https://www.meta.ai"
    private static let browserRootReferer = "https://www.meta.ai/"
    static let setupGraphQLAcceptHeader = "multipart/mixed, application/json"
    private static let updateLastSelectedModeDocID = "98081c3f48eddb05c71cb79d46fc337b"
    private static let warmupConversationDocID = "e7f802582dbfed8e181b012e010993eb"
    private static let updateConversationModeDocID = "c32bbe999c48e64e855dc63177d5153f"
    private static let sendMessageSubscriptionDocID = "af4c07d1fb42eb351dba31b5a299a819"

    static func preflightFailure(path: String, body: String, publicModel: String) -> Failure? {
        do {
            _ = try parseRequest(path: path, body: body, publicModel: publicModel)
            return nil
        } catch let failure as Failure {
            return failure
        } catch {
            return Failure(statusCode: 400, message: "Meta web adapter could not parse the request body.")
        }
    }

    static func execute(
        path: String,
        body: String,
        publicModel: String,
        fileManager: FileManager = .default
    ) -> Result<ExecutionResult, Failure> {
        let parsedRequest: ParsedRequest
        do {
            parsedRequest = try parseRequest(path: path, body: body, publicModel: publicModel)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure(statusCode: 400, message: "Meta web adapter could not parse the request body."))
        }

        let authSnapshot: HARAuthSnapshot
        do {
            authSnapshot = try loadHARAuthSnapshot(fileManager: fileManager)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure(statusCode: 500, message: "Meta web adapter failed to load auth material."))
        }

        let conversationID = UUID().uuidString
        let plannedRequests: [PlannedGraphQLRequest]
        do {
            plannedRequests = try buildExecutionRequests(
                authSnapshot: authSnapshot,
                conversationID: conversationID,
                prompt: parsedRequest.executionPrompt
            )
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure(statusCode: 500, message: "Meta web adapter failed to build the GraphQL request sequence."))
        }

        let session = makeSession(authSnapshot: authSnapshot)
        defer { session.finishTasksAndInvalidate() }

        do {
            let parsedEventStream = try executePromptSequence(
                plannedRequests: plannedRequests,
                session: session
            )
            if let assistantText = parsedEventStream.assistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !assistantText.isEmpty {
                let renderedAssistantOutput: RenderedAssistantOutput
                do {
                    renderedAssistantOutput = try renderAssistantOutputWithRepair(
                        assistantText: assistantText,
                        parsedRequest: parsedRequest,
                        authSnapshot: authSnapshot,
                        session: session
                    )
                } catch let failure as Failure {
                    return .failure(failure)
                } catch {
                    return .failure(Failure(statusCode: 502, message: "Meta web adapter failed while rendering synthetic tool output."))
                }
                let bodyData: Data
                let headers: [String: String]
                switch (parsedRequest.surface, parsedRequest.stream, renderedAssistantOutput) {
                case (.chatCompletions, false, .text(let text)):
                    bodyData = buildChatCompletionsResponseBody(text: text, publicModel: parsedRequest.publicModel)
                    headers = ["Content-Type": "application/json; charset=utf-8"]
                case (.chatCompletions, true, .text(let text)):
                    bodyData = buildChatCompletionsStreamBody(text: text, publicModel: parsedRequest.publicModel)
                    headers = ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                case (.responses, false, .text(let text)):
                    bodyData = buildResponsesResponseBody(
                        text: text,
                        publicModel: parsedRequest.publicModel,
                        sources: parsedEventStream.sources
                    )
                    headers = ["Content-Type": "application/json; charset=utf-8"]
                case (.responses, true, .text(let text)):
                    bodyData = buildResponsesStreamBody(
                        text: text,
                        publicModel: parsedRequest.publicModel,
                        sources: parsedEventStream.sources
                    )
                    headers = ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                case (.chatCompletions, false, .toolCall(let directive)):
                    bodyData = buildChatCompletionsResponseBody(toolCall: directive, publicModel: parsedRequest.publicModel)
                    headers = ["Content-Type": "application/json; charset=utf-8"]
                case (.chatCompletions, true, .toolCall(let directive)):
                    bodyData = buildChatCompletionsStreamBody(toolCall: directive, publicModel: parsedRequest.publicModel)
                    headers = ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                case (.responses, false, .toolCall(let directive)):
                    bodyData = buildResponsesResponseBody(toolCall: directive, publicModel: parsedRequest.publicModel)
                    headers = ["Content-Type": "application/json; charset=utf-8"]
                case (.responses, true, .toolCall(let directive)):
                    bodyData = buildResponsesStreamBody(toolCall: directive, publicModel: parsedRequest.publicModel)
                    headers = ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                }
                return .success(
                    ExecutionResult(
                        statusCode: 200,
                        headers: headers,
                        body: bodyData
                    )
                )
            }

            let errorMessage = parsedEventStream.errorMessage?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(
                Failure(
                    statusCode: 502,
                    message: errorMessage?.isEmpty == false
                        ? errorMessage!
                        : "Meta web adapter received no assistant output from the GraphQL stream."
                )
            )
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure(statusCode: 502, message: "Meta web adapter failed while executing the GraphQL request sequence."))
        }
    }

    private static func executePromptSequence(
        plannedRequests: [PlannedGraphQLRequest],
        session: URLSession
    ) throws -> ParsedEventStream {
        var eventStreamData: Data?
        for plannedRequest in plannedRequests {
            do {
                let responseData = try postGraphQL(session: session, request: plannedRequest.request)
                if plannedRequest.kind == .sendMessage {
                    eventStreamData = responseData
                }
            } catch let failure as Failure {
                if plannedRequest.isBestEffort {
                    NSLog("[ThinkingProxy] Meta AI web adapter ignored best-effort \(plannedRequest.kind) failure (\(failure.statusCode)): \(failure.message)")
                    continue
                }
                throw failure
            }
        }

        guard let eventStreamData else {
            throw Failure(statusCode: 500, message: "Meta web adapter did not produce a send-message GraphQL request.")
        }

        return parseEventStream(eventStreamData)
    }

    static func parseRequest(path: String, body: String, publicModel: String) throws -> ParsedRequest {
        let surface: ResponseSurface
        let normalizedBody: String
        if isResponsesPath(path) {
            guard let chatBody = OpenAICompatTemporaryShim.chatCompletionsRequestJSON(fromResponsesRequestJSON: body) else {
                throw Failure(statusCode: 400, message: "Meta web adapter only supports /v1/responses payloads that can be flattened onto text-only chat messages.")
            }
            surface = .responses
            normalizedBody = chatBody
        } else if isChatCompletionsPath(path) {
            surface = .chatCompletions
            normalizedBody = body
        } else {
            throw Failure(statusCode: 501, message: "Meta web adapter only supports /v1/chat/completions and /v1/responses.")
        }

        guard let data = normalizedBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(statusCode: 400, message: "Meta web adapter requires a valid JSON request body.")
        }

        let toolDefinitions = try parseToolDefinitions(from: json)
        let toolChoice = try parseToolChoice(from: json, toolDefinitions: toolDefinitions)

        var cleanedJSON = json
        cleanedJSON.removeValue(forKey: "tools")
        cleanedJSON.removeValue(forKey: "tool_choice")
        cleanedJSON.removeValue(forKey: "parallel_tool_calls")

        let stream = (json["stream"] as? Bool) ?? false
        let (prompt, isNewThread) = try extractPrompt(fromChatRequestJSONObject: cleanedJSON)
        return ParsedRequest(
            surface: surface,
            prompt: prompt,
            executionPrompt: buildExecutionPrompt(basePrompt: prompt, toolDefinitions: toolDefinitions, toolChoice: toolChoice),
            stream: stream,
            publicModel: publicModel,
            toolDefinitions: toolDefinitions,
            toolChoice: toolChoice,
            isNewThread: isNewThread
        )
    }

    private enum RenderedAssistantOutput: Equatable {
        case text(String)
        case toolCall(SyntheticToolDirective)
    }

    static func parseEventStream(_ data: Data) -> ParsedEventStream {
        guard let text = String(data: data, encoding: .utf8) else {
            return ParsedEventStream(
                assistantText: nil,
                errorMessage: "Meta web adapter received a non-UTF8 event stream.",
                sources: []
            )
        }

        var latestAssistantText: String?
        var latestErrorMessages: [String] = []
        var latestSources: [Source] = []

        for rawLine in text.components(separatedBy: .newlines) {
            guard rawLine.hasPrefix("data:") else {
                continue
            }
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.utf8.count > maxEventStreamDataLineBytes {
                return ParsedEventStream(
                    assistantText: nil,
                    errorMessage: "Meta web adapter received an oversized event-stream frame.",
                    sources: []
                )
            }
            guard !payload.isEmpty, payload != "[DONE]",
                  let payloadData = payload.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }

            latestErrorMessages.append(contentsOf: graphQLErrorMessages(fromJSONObject: root))

            guard let dataObject = root["data"] as? [String: Any],
                  let streamObject = dataObject["sendMessageStream"] as? [String: Any] else {
                continue
            }

            if let assistantText = (streamObject["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !assistantText.isEmpty {
                latestAssistantText = assistantText
            }

            if let errorObject = streamObject["error"] as? [String: Any],
               let errorMessage = (errorObject["message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !errorMessage.isEmpty {
                latestErrorMessages.append(errorMessage)
            }

            let extractedSources = extractSources(fromSendMessageStream: streamObject)
            if !extractedSources.isEmpty {
                latestSources = extractedSources
            }
        }

        let errorMessages = deduplicatedMessages(latestErrorMessages)
        return ParsedEventStream(
            assistantText: latestAssistantText,
            errorMessage: errorMessages.isEmpty ? nil : errorMessages.joined(separator: " | "),
            sources: latestSources
        )
    }

    private static func metaAIHARURL(fileManager: FileManager) -> URL {
        if let override = ProcessInfo.processInfo.environment["VIBEPROXY_META_AI_HAR_PATH"],
           let normalizedOverride = normalizedString(override) {
            return URL(fileURLWithPath: normalizedOverride)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".cli-proxy-api", isDirectory: true)
            .appendingPathComponent("meta.ai.har")
    }

    private static func isChatCompletionsPath(_ path: String) -> Bool {
        path == "/v1/chat/completions" || path == "/api/v1/chat/completions"
    }

    private static func isResponsesPath(_ path: String) -> Bool {
        path == "/v1/responses" || path == "/api/v1/responses"
    }

    static func loadHARAuthSnapshot(fileManager: FileManager) throws -> HARAuthSnapshot {
        let harURL = metaAIHARURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: harURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let log = root["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]] else {
            throw Failure(
                statusCode: 500,
                message: "Meta web adapter requires a HAR at \(harURL.path) with captured meta.ai GraphQL traffic."
            )
        }

        var selectedCookieHeader: String?
        var selectedUserAgent: String?
        var selectedAcceptLanguage: String?
        var selectedClientTimezone: String?
        var selectedUserLocale: String?
        var selectedDevicePixelRatio: Double?

        for entry in entries {
            guard let request = entry["request"] as? [String: Any],
                  let url = request["url"] as? String,
                  url.contains("/api/graphql"),
                  let headers = request["headers"] as? [[String: Any]] else {
                continue
            }

            let headerMap = headers.reduce(into: [String: String]()) { partialResult, header in
                guard let name = (header["name"] as? String)?.lowercased(),
                      let value = header["value"] as? String else {
                    return
                }
                partialResult[name] = value
            }

            guard let cookieHeader = normalizedString(headerMap["cookie"]),
                  let userAgent = normalizedString(headerMap["user-agent"]) else {
                continue
            }

            let cookieValues = parseCookieHeader(cookieHeader)
            guard requiredMetaCookieFailure(for: cookieValues) == nil else {
                continue
            }

            let acceptLanguage = normalizedString(headerMap["accept-language"]) ?? "en-US,en;q=0.9"
            let requestHints = extractGraphQLRequestHints(from: request)

            if selectedCookieHeader == nil {
                selectedCookieHeader = cookieHeader
                selectedUserAgent = userAgent
                selectedAcceptLanguage = acceptLanguage
            }

            guard cookieHeader == selectedCookieHeader,
                  userAgent == selectedUserAgent else {
                continue
            }

            if selectedClientTimezone == nil {
                selectedClientTimezone = requestHints.clientTimezone
            }
            if selectedUserLocale == nil {
                selectedUserLocale = requestHints.userLocale
            }
            if selectedDevicePixelRatio == nil {
                selectedDevicePixelRatio = requestHints.devicePixelRatio
            }

            if selectedClientTimezone != nil,
               selectedUserLocale != nil,
               selectedDevicePixelRatio != nil {
                break
            }
        }

        if let cookieHeader = selectedCookieHeader,
           let userAgent = selectedUserAgent,
           let acceptLanguage = selectedAcceptLanguage {
            return HARAuthSnapshot(
                cookieHeader: cookieHeader,
                userAgent: userAgent,
                acceptLanguage: acceptLanguage,
                clientTimezone: selectedClientTimezone ?? "UTC",
                userLocale: selectedUserLocale ?? preferredMetaUserLocale(fromAcceptLanguage: acceptLanguage),
                devicePixelRatio: selectedDevicePixelRatio
                    ?? parseNumericCookie(named: "dpr", in: parseCookieHeader(cookieHeader))
            )
        }

        let missingCookieMessage = "Meta web adapter requires a HAR with a cookie-bearing GraphQL request that includes fresh datr and ecto_1_sess cookies."
        if harContainsCookieBearingGraphQLRequest(entries: entries) {
            throw Failure(statusCode: 500, message: missingCookieMessage)
        }

        throw Failure(
            statusCode: 500,
            message: "Meta web adapter could not find a cookie-bearing GraphQL request in the configured HAR."
        )
    }

    static func buildExecutionRequests(
        authSnapshot: HARAuthSnapshot,
        conversationID: String,
        prompt: String
    ) throws -> [PlannedGraphQLRequest] {
        let promptReferer = conversationPromptReferer(for: conversationID)
        return [
            PlannedGraphQLRequest(
                kind: .updateLastSelectedMode,
                isBestEffort: true,
                request: try makeGraphQLRequest(
                    authSnapshot: authSnapshot,
                    accept: setupGraphQLAcceptHeader,
                    docID: updateLastSelectedModeDocID,
                    variables: ["input": ["mode": conversationMode]],
                    referer: browserRootReferer
                )
            ),
            PlannedGraphQLRequest(
                kind: .warmupConversation,
                isBestEffort: false,
                request: try makeGraphQLRequest(
                    authSnapshot: authSnapshot,
                    accept: setupGraphQLAcceptHeader,
                    docID: warmupConversationDocID,
                    variables: ["conversationId": conversationID],
                    referer: browserRootReferer
                )
            ),
            PlannedGraphQLRequest(
                kind: .updateConversationMode,
                isBestEffort: false,
                request: try makeGraphQLRequest(
                    authSnapshot: authSnapshot,
                    accept: setupGraphQLAcceptHeader,
                    docID: updateConversationModeDocID,
                    variables: ["input": ["conversationId": conversationID, "mode": conversationMode]],
                    referer: browserRootReferer
                )
            ),
            PlannedGraphQLRequest(
                kind: .sendMessage,
                isBestEffort: false,
                request: try makeGraphQLRequest(
                    authSnapshot: authSnapshot,
                    accept: "text/event-stream",
                    docID: sendMessageSubscriptionDocID,
                    variables: buildSendMessageVariables(
                        authSnapshot: authSnapshot,
                        conversationID: conversationID,
                        prompt: prompt
                    ),
                    referer: promptReferer
                )
            )
        ]
    }

    private static func makeSession(authSnapshot: HARAuthSnapshot) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // Meta's web GraphQL lane can take materially longer on heavier prompts than the
        // direct provider lanes. Use the same scaled timeout posture as the proxy's
        // long-lived coding routes so the adapter has headroom instead of failing close
        // to completion.
        configuration.timeoutIntervalForRequest = OpenAICompatTemporaryShim.scaledRequestTimeout(180)
        configuration.timeoutIntervalForResource = OpenAICompatTemporaryShim.scaledRequestTimeout(300)
        configuration.httpAdditionalHeaders = [
            "User-Agent": authSnapshot.userAgent,
            "Origin": browserOrigin,
            "Referer": browserRootReferer,
            "Accept-Language": authSnapshot.acceptLanguage,
            "Cookie": authSnapshot.cookieHeader
        ]
        let delegate = RedirectFollowingDelegate()
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    /// URLSessionDelegate that follows HTTP redirects while preserving per-request headers
    /// (Content-Type, Accept, Origin, Referer) that URLSession strips on cross-host redirects.
    private final class RedirectFollowingDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            var redirected = request
            // Re-apply headers that the system drops when building the redirect request.
            if let original = task.originalRequest {
                for header in ["Content-Type", "Accept", "Origin", "Referer"] {
                    if let value = original.value(forHTTPHeaderField: header) {
                        redirected.setValue(value, forHTTPHeaderField: header)
                    }
                }
            }
            completionHandler(redirected)
        }
    }

    private static func postGraphQL(
        session: URLSession,
        request: URLRequest
    ) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var capturedData: Data?
        var capturedResponse: URLResponse?
        var capturedError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            capturedData = data
            capturedResponse = response
            capturedError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let capturedError {
            throw Failure(statusCode: 502, message: "Meta web adapter network error: \(capturedError.localizedDescription)")
        }

        guard let httpResponse = capturedResponse as? HTTPURLResponse else {
            throw Failure(statusCode: 502, message: "Meta web adapter received no HTTP response from meta.ai.")
        }

        let responseData = capturedData ?? Data()
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw Failure(
                statusCode: httpResponse.statusCode,
                message: formattedUpstreamErrorMessage(statusCode: httpResponse.statusCode, responseData: responseData)
            )
        }

        return responseData
    }

    static func makeGraphQLRequest(
        authSnapshot: HARAuthSnapshot,
        accept: String,
        docID: String,
        variables: [String: Any],
        referer: String
    ) throws -> URLRequest {
        var request = URLRequest(url: graphQLEndpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(browserOrigin, forHTTPHeaderField: "Origin")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(authSnapshot.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(authSnapshot.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(authSnapshot.cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "doc_id": docID,
            "variables": variables
        ])
        return request
    }

    private static func conversationPromptReferer(for conversationID: String) -> String {
        let trimmed = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return browserRootReferer }
        let safeConversationID = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return "\(browserOrigin)/prompt/\(safeConversationID)"
    }

    private static func buildSendMessageVariables(
        authSnapshot: HARAuthSnapshot,
        conversationID: String,
        prompt: String
    ) -> [String: Any] {
        [
            "assistantMessageId": UUID().uuidString,
            "attachments": NSNull(),
            "clientLatitude": NSNull(),
            "clientLongitude": NSNull(),
            "clientTimezone": authSnapshot.clientTimezone,
            "clippyIp": NSNull(),
            "content": prompt,
            "conversationId": conversationID,
            "conversationStarterId": NSNull(),
            "currentBranchPath": "1",
            "developerOverridesForMessage": NSNull(),
            "devicePixelRatio": authSnapshot.devicePixelRatio ?? NSNull(),
            "entryPoint": "KADABRA__UNKNOWN",
            "imagineOperationRequest": NSNull(),
            // This adapter is stateless: every request starts a fresh Meta conversation
            // and carries prior turns only via the flattened transcript prompt.
            "isNewConversation": true,
            "mentions": NSNull(),
            "mode": conversationMode,
            "promptEditType": "new_message",
            "promptSessionId": UUID().uuidString,
            "promptType": NSNull(),
            "qplJoinId": NSNull(),
            "requestedToolCall": NSNull(),
            "rewriteOptions": NSNull(),
            "turnId": UUID().uuidString,
            "userAgent": authSnapshot.userAgent,
            "userEventId": NSNull(),
            "userLocale": authSnapshot.userLocale,
            "userMessageId": UUID().uuidString,
            "userUniqueMessageId": String(Int.random(in: 7_000_000_000_000_000_000 ... 8_999_999_999_999_999_999))
        ]
    }

    private static func extractPrompt(fromChatRequestJSONObject json: [String: Any]) throws -> (prompt: String, isNewThread: Bool) {
        guard let messages = json["messages"] as? [[String: Any]], !messages.isEmpty else {
            throw Failure(statusCode: 400, message: "Meta web adapter requires at least one chat message.")
        }

        var transcript: [String] = []
        var hasNonUserRole = false
        for message in messages {
            let role = ((message["role"] as? String) ?? "user").lowercased()

            // Convert tool-related messages to readable transcript entries.
            // Tool results and function calls are inlined as text context.
            if role == "tool" {
                if let text = try flattenedText(from: message["content"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    hasNonUserRole = true
                    transcript.append("Tool result: \(text)")
                }
                continue
            }

            // For assistant messages with tool_calls, include both the text content
            // and a summary of the tool invocations.
            if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                hasNonUserRole = true
                var parts: [String] = []
                if let text = try flattenedText(from: message["content"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    parts.append(text)
                }
                for call in toolCalls {
                    if let fn = call["function"] as? [String: Any],
                       let name = fn["name"] as? String {
                        let args = fn["arguments"] as? String ?? ""
                        parts.append("[Called \(name)(\(args.prefix(200)))]")
                    }
                }
                if !parts.isEmpty {
                    transcript.append("Assistant: \(parts.joined(separator: " "))")
                }
                continue
            }

            guard let flattenedText = try flattenedText(from: message["content"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !flattenedText.isEmpty else {
                continue
            }

            if role != "user" {
                hasNonUserRole = true
            }

            switch role {
            case "system":
                transcript.append("System: \(flattenedText)")
            case "assistant":
                transcript.append("Assistant: \(flattenedText)")
            default:
                transcript.append("User: \(flattenedText)")
            }
        }

        guard !transcript.isEmpty else {
            throw Failure(statusCode: 400, message: "Meta web adapter only supports text messages.")
        }

        // New thread: single user message with no system/assistant context.
        // Follow-up: multi-turn (system/assistant messages present) or multiple user messages.
        let isNewThread = !hasNonUserRole && transcript.count == 1

        if isNewThread,
           let onlyLine = transcript.first,
           onlyLine.hasPrefix("User: ") {
            return (String(onlyLine.dropFirst("User: ".count)), true)
        }

        return (transcript.joined(separator: "\n\n"), isNewThread)
    }

    private static func flattenedText(from value: Any?) throws -> String? {
        guard let value else {
            return nil
        }
        if let stringValue = value as? String {
            return stringValue
        }
        if !(value is [String: Any]) && !(value is [Any]),
           let scalarText = normalizedStructuredPayloadString(value) {
            return scalarText
        }
        if let dictionaryValue = value as? [String: Any] {
            return try flattenedText(fromContentDictionary: dictionaryValue)
        }
        guard let segments = value as? [Any] else {
            throw Failure(statusCode: 400, message: "Meta web adapter only supports text message content.")
        }

        var parts: [String] = []
        var sawIgnorableNonMediaSegment = false
        for segment in segments {
            if let stringSegment = segment as? String {
                parts.append(stringSegment)
                continue
            }
            if !(segment is [String: Any]),
               let scalarText = normalizedStructuredPayloadString(segment) {
                parts.append(scalarText)
                continue
            }
            guard let dictionary = segment as? [String: Any] else {
                throw Failure(statusCode: 400, message: "Meta web adapter only supports text message content.")
            }
            if containsUnsupportedMediaContent(dictionary) {
                throw Failure(statusCode: 400, message: "Meta web adapter only supports text message content.")
            }
            guard let text = try flattenedText(fromContentDictionary: dictionary) else {
                if isIgnorableNonMediaContent(dictionary) {
                    sawIgnorableNonMediaSegment = true
                    continue
                }
                continue
            }
            parts.append(text)
        }
        if !parts.isEmpty {
            return parts.joined()
        }
        if sawIgnorableNonMediaSegment {
            return ""
        }
        guard !parts.isEmpty else {
            throw Failure(statusCode: 400, message: "Meta web adapter only supports text message content.")
        }
        return parts.joined()
    }

    private static func flattenedText(fromContentDictionary dictionary: [String: Any]) throws -> String? {
        if containsUnsupportedMediaContent(dictionary) {
            throw Failure(statusCode: 400, message: "Meta web adapter only supports text message content.")
        }

        let type = normalizedString(dictionary["type"] as? String)?.lowercased()
        let allowsDirectText = type == nil || type == "text" || type == "input_text" || type == "output_text" || type == "summary_text" || type == "reasoning" || type == "tool_result"
        let allowsStructuredPayload = type == nil || type == "tool_result" || type == "output_json" || type == "input_json" || type == "json" || type == "reasoning" || type == "metadata_marker"
        if let text = normalizedContentText(dictionary["text"]),
           allowsDirectText {
            return text
        }
        if let outputText = normalizedContentText(dictionary["output_text"]),
           allowsDirectText || type == "output_json" {
            return outputText
        }
        if let valueText = normalizedContentText(dictionary["value"]),
           allowsStructuredPayload {
            return valueText
        }

        if let structuredJSON = normalizedStructuredPayloadString(dictionary["json"]),
           allowsStructuredPayload {
            return structuredJSON
        }

        if let structuredResult = normalizedStructuredPayloadString(dictionary["result"]),
           allowsStructuredPayload {
            return structuredResult
        }

        if let structuredArguments = normalizedStructuredPayloadString(dictionary["arguments"]),
           allowsStructuredPayload {
            return structuredArguments
        }

        if let structuredValue = normalizedStructuredPayloadString(dictionary["value"]),
           allowsStructuredPayload {
            return structuredValue
        }

        if let content = dictionary["content"],
           let flattenedContent = try flattenedText(from: content)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !flattenedContent.isEmpty {
            return flattenedContent
        }

        if let structuredContent = normalizedStructuredPayloadString(dictionary["content"]) {
            return structuredContent
        }

        if isIgnorableNonMediaContent(dictionary) {
            return ""
        }

        return nil
    }

    private static func isIgnorableNonMediaContent(_ dictionary: [String: Any]) -> Bool {
        guard !containsUnsupportedMediaContent(dictionary) else {
            return false
        }

        let nonIgnorableTypes: Set<String> = [
            "text",
            "input_text",
            "output_text",
            "summary_text",
            "tool_result",
            "output_json",
            "input_json",
            "json"
        ]
        guard let type = normalizedString(dictionary["type"] as? String)?.lowercased() else {
            return true
        }
        if !hasVisibleStructuredPayloadField(dictionary) {
            return true
        }
        return !nonIgnorableTypes.contains(type)
    }

    private static func hasVisibleStructuredPayloadField(_ dictionary: [String: Any]) -> Bool {
        let visiblePayloadKeys: Set<String> = [
            "text",
            "output_text",
            "value",
            "json",
            "result",
            "arguments",
            "content"
        ]
        return visiblePayloadKeys.contains { dictionary[$0] != nil }
    }

    private static func containsUnsupportedMediaContent(_ dictionary: [String: Any]) -> Bool {
        let unsupportedTypes: Set<String> = [
            "input_image",
            "image",
            "image_url",
            "input_audio",
            "audio",
            "audio_url",
            "file",
            "input_file",
            "video",
            "input_video"
        ]
        let unsupportedKeys: Set<String> = [
            "image",
            "image_url",
            "audio",
            "audio_url",
            "file",
            "file_data",
            "file_url",
            "video",
            "video_url"
        ]

        if let type = normalizedString(dictionary["type"] as? String)?.lowercased(),
           unsupportedTypes.contains(type) {
            return true
        }

        for key in unsupportedKeys where dictionary[key] != nil {
            return true
        }

        return false
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedContentText(_ value: Any?) -> String? {
        guard let stringValue = value as? String,
              !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return stringValue
    }

    private static func normalizedStructuredPayloadString(_ value: Any?) -> String? {
        if let stringValue = value as? String,
           let normalized = normalizedString(stringValue) {
            return normalized
        }
        if let boolean = value as? Bool {
            return boolean ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let dictionary = value as? [String: Any] {
            guard !containsUnsupportedMediaPayload(dictionary),
                  JSONSerialization.isValidJSONObject(dictionary),
                  let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return text
        }
        if let array = value as? [Any] {
            guard !containsUnsupportedMediaPayload(array),
                  JSONSerialization.isValidJSONObject(array),
                  let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return text
        }
        return nil
    }

    private static func containsUnsupportedMediaPayload(_ value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            if containsUnsupportedMediaContent(dictionary) {
                return true
            }
            for nestedValue in dictionary.values where containsUnsupportedMediaPayload(nestedValue) {
                return true
            }
            return false
        }

        if let array = value as? [Any] {
            for element in array where containsUnsupportedMediaPayload(element) {
                return true
            }
        }

        return false
    }

    private static func parseCookieHeader(_ rawCookieHeader: String) -> [String: String] {
        rawCookieHeader
            .split(separator: ";")
            .reduce(into: [String: String]()) { partialResult, rawPart in
                let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !part.isEmpty,
                      let equalsIndex = part.firstIndex(of: "=") else {
                    return
                }
                let name = String(part[..<equalsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(part[part.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !value.isEmpty else {
                    return
                }
                partialResult[name] = value
            }
    }

    private static func parseNumericCookie(named name: String, in cookies: [String: String]) -> Double? {
        guard let value = normalizedString(cookies[name]) else {
            return nil
        }
        return Double(value)
    }

    private static func preferredMetaUserLocale(fromAcceptLanguage acceptLanguage: String) -> String {
        let primaryLanguageRange = acceptLanguage
            .split(separator: ",")
            .first?
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedString(primaryLanguageRange.map { String($0) }) ?? "en-US"
    }

    private struct GraphQLRequestHints {
        let clientTimezone: String?
        let userLocale: String?
        let devicePixelRatio: Double?
    }

    private static func extractGraphQLRequestHints(from request: [String: Any]) -> GraphQLRequestHints {
        guard let postData = request["postData"] as? [String: Any],
              let text = postData["text"] as? String,
              let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let variables = root["variables"] as? [String: Any] else {
            return GraphQLRequestHints(clientTimezone: nil, userLocale: nil, devicePixelRatio: nil)
        }

        return GraphQLRequestHints(
            clientTimezone: normalizedString(variables["clientTimezone"] as? String),
            userLocale: normalizedString(variables["userLocale"] as? String),
            devicePixelRatio: numericJSONValue(variables["devicePixelRatio"])
        )
    }

    private static func numericJSONValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func requiredMetaCookieFailure(for cookies: [String: String]) -> Failure? {
        let requiredCookieNames = ["datr", "ecto_1_sess"]
        let missing = requiredCookieNames.filter { normalizedString(cookies[$0]) == nil }
        guard !missing.isEmpty else {
            return nil
        }
        return Failure(
            statusCode: 500,
            message: "Meta web adapter requires fresh \(missing.joined(separator: " and ")) cookies in the captured HAR GraphQL request."
        )
    }

    private static func harContainsCookieBearingGraphQLRequest(entries: [[String: Any]]) -> Bool {
        for entry in entries {
            guard let request = entry["request"] as? [String: Any],
                  let url = request["url"] as? String,
                  url.contains("/api/graphql"),
                  let headers = request["headers"] as? [[String: Any]] else {
                continue
            }

            let headerMap = headers.reduce(into: [String: String]()) { partialResult, header in
                guard let name = (header["name"] as? String)?.lowercased(),
                      let value = header["value"] as? String else {
                    return
                }
                partialResult[name] = value
            }

            if normalizedString(headerMap["cookie"]) != nil,
               normalizedString(headerMap["user-agent"]) != nil {
                return true
            }
        }
        return false
    }

    private static func requestsUnsupportedToolExecution(in json: [String: Any]) -> Bool {
        if let tools = json["tools"] as? [Any], !tools.isEmpty {
            return true
        }

        guard let toolChoice = json["tool_choice"] else {
            return false
        }

        if let toolChoiceString = toolChoice as? String {
            let normalized = toolChoiceString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized != "auto" && normalized != "none"
        }

        guard let toolChoiceDictionary = toolChoice as? [String: Any],
              let type = (toolChoiceDictionary["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return true
        }

        return type != "auto" && type != "none"
    }

    private static func parseToolDefinitions(from json: [String: Any]) throws -> [ToolDefinition] {
        guard let toolsValue = json["tools"] else {
            return []
        }
        guard let tools = toolsValue as? [Any] else {
            throw Failure(statusCode: 400, message: "Meta web adapter requires tools to be an array.")
        }

        var definitions: [ToolDefinition] = []
        var seenToolNames: Set<String> = []
        for tool in tools {
            guard let toolDictionary = tool as? [String: Any] else {
                continue
            }

            let type = normalizedString(toolDictionary["type"] as? String)?.lowercased()
            let inferredFunction = toolDictionary["function"] as? [String: Any]
            let isFunctionTool = (type == nil && inferredFunction != nil) || type == "function"
            guard isFunctionTool else {
                continue
            }

            guard let function = inferredFunction,
                  let rawName = function["name"] as? String,
                  let name = normalizedString(rawName) else {
                continue
            }

            guard !seenToolNames.contains(name) else {
                continue
            }

            let parametersObject = function["parameters"] ?? ["type": "object", "properties": [String: Any]()]
            guard JSONSerialization.isValidJSONObject(parametersObject),
                  let parametersData = try? JSONSerialization.data(withJSONObject: parametersObject, options: [.sortedKeys]),
                  let parametersJSONString = String(data: parametersData, encoding: .utf8) else {
                let fallbackParametersJSONString = #"{"properties":{},"type":"object"}"#
                definitions.append(
                    ToolDefinition(
                        name: name,
                        description: normalizedString(function["description"] as? String),
                        parametersJSONString: fallbackParametersJSONString
                    )
                )
                seenToolNames.insert(name)
                continue
            }

            definitions.append(
                ToolDefinition(
                    name: name,
                    description: normalizedString(function["description"] as? String),
                    parametersJSONString: parametersJSONString
                )
            )
            seenToolNames.insert(name)
        }
        return definitions
    }

    private static func parseToolChoice(from json: [String: Any], toolDefinitions: [ToolDefinition]) throws -> ToolChoice {
        guard !toolDefinitions.isEmpty else {
            return .none
        }

        guard let toolChoice = json["tool_choice"] else {
            return .auto
        }

        if let toolChoiceString = toolChoice as? String {
            switch toolChoiceString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "", "auto":
                return .auto
            case "none":
                return .none
            case "required":
                return .required
            default:
                return .auto
            }
        }

        guard let toolChoiceDictionary = toolChoice as? [String: Any],
              let type = (toolChoiceDictionary["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return .auto
        }

        switch type {
        case "auto":
            return .auto
        case "none":
            return .none
        case "required":
            return .required
        case "function":
            let functionContainer = toolChoiceDictionary["function"] as? [String: Any]
            let rawName = (functionContainer?["name"] as? String) ?? (toolChoiceDictionary["name"] as? String)
            guard let functionName = normalizedString(rawName) else {
                return toolDefinitions.count == 1 ? .specific(toolDefinitions[0].name) : .required
            }
            let allowedToolNames = Set(toolDefinitions.map(\.name))
            guard let resolvedFunctionName = resolveSyntheticToolName(
                rawName: functionName,
                allowedToolNames: allowedToolNames,
                requiredToolName: toolDefinitions.count == 1 ? toolDefinitions[0].name : nil
            ) else {
                return toolDefinitions.count == 1 ? .specific(toolDefinitions[0].name) : .required
            }
            return .specific(resolvedFunctionName)
        default:
            return .auto
        }
    }

    private static func buildExecutionPrompt(
        basePrompt: String,
        toolDefinitions: [ToolDefinition],
        toolChoice: ToolChoice
    ) -> String {
        guard !toolDefinitions.isEmpty, toolChoice != .none else {
            return basePrompt
        }

        let toolLines = toolDefinitions.map { tool in
            var line = "- \(tool.name)"
            if let description = tool.description {
                line += ": \(description)"
            }
            line += "\n  parameters: \(tool.parametersJSONString)"
            return line
        }.joined(separator: "\n")

        let directiveInstruction: String
        switch toolChoice {
        case .required:
            directiveInstruction = "You must respond with exactly one tool directive JSON object and no prose."
        case .specific(let name):
            directiveInstruction = "You must respond with exactly one tool directive JSON object using the tool name \"\(name)\" and no prose."
        case .auto:
            directiveInstruction = "If a tool is needed, respond with exactly one tool directive JSON object and no prose. If no tool is needed, answer normally in plain text."
        case .none:
            directiveInstruction = "Answer normally in plain text."
        }

        return """
        Tool-use mode:
        \(directiveInstruction)
        Use at most one tool call in this turn.
        Any prose outside the tool directive will be discarded as a failure.
        The only valid tool directive format is a single raw JSON object with this exact shape:
        {"name":"tool_name","arguments":{"key":"value"}}
        Valid example:
        {"name":"\(toolDefinitions[0].name)","arguments":{}}
        Invalid examples:
        [{"name":"\(toolDefinitions[0].name)","arguments":{}}]
        {"tool_calls":[{"name":"\(toolDefinitions[0].name)","arguments":{}}]}
        Here is the JSON:
        {"name":"\(toolDefinitions[0].name)","arguments":{}}
        Do not wrap the JSON in markdown unless absolutely necessary.
        Do not return a JSON array.
        Do not return an OpenAI tool_calls wrapper.
        Do not stringify the arguments object.
        Do not invent tool names.
        Arguments must be a JSON object.

        Available tools:
        \(toolLines)

        Conversation transcript:
        \(basePrompt)
        """
    }

    static func buildSyntheticToolRepairPrompt(
        basePrompt: String,
        assistantText: String,
        toolDefinitions: [ToolDefinition],
        toolChoice: ToolChoice
    ) -> String {
        let originalPrompt = buildExecutionPrompt(
            basePrompt: basePrompt,
            toolDefinitions: toolDefinitions,
            toolChoice: toolChoice
        )
        let trimmedAssistantText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        \(originalPrompt)

        Your previous reply was malformed for tool-use mode:
        \(trimmedAssistantText)

        Repair instructions:
        Preserve the same intent and arguments, but rewrite the reply into exactly one valid raw JSON tool directive object.
        Do not add any explanation, apology, markdown fence, label, or surrounding prose.
        If the intent was to call a tool, emit only the corrected JSON object now.
        """
    }

    private static func renderAssistantOutput(
        assistantText: String,
        parsedRequest: ParsedRequest
    ) throws -> RenderedAssistantOutput {
        guard !parsedRequest.toolDefinitions.isEmpty, parsedRequest.toolChoice != .none else {
            return .text(assistantText)
        }

        let directiveAttempted = looksLikeSyntheticToolDirective(assistantText)
        if let directive = try syntheticToolDirective(from: assistantText, parsedRequest: parsedRequest) {
            return .toolCall(directive)
        }

        switch parsedRequest.toolChoice {
        case .required:
            throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode required a tool call, but Meta returned plain text instead.")
        case .specific(let name):
            throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode required tool \(name), but Meta did not return a valid tool directive.")
        case .auto:
            if directiveAttempted {
                throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode returned an invalid tool directive; refusing to guess at tool execution.")
            }
            return .text(assistantText)
        case .none:
            return .text(assistantText)
        }
    }

    private static func renderAssistantOutputWithRepair(
        assistantText: String,
        parsedRequest: ParsedRequest,
        authSnapshot: HARAuthSnapshot,
        session: URLSession
    ) throws -> RenderedAssistantOutput {
        do {
            return try renderAssistantOutput(assistantText: assistantText, parsedRequest: parsedRequest)
        } catch let failure as Failure {
            guard shouldAttemptSyntheticToolRepair(
                failure: failure,
                assistantText: assistantText,
                parsedRequest: parsedRequest
            ) else {
                throw failure
            }

            let repairPrompt = buildSyntheticToolRepairPrompt(
                basePrompt: parsedRequest.prompt,
                assistantText: assistantText,
                toolDefinitions: parsedRequest.toolDefinitions,
                toolChoice: parsedRequest.toolChoice
            )
            NSLog("[ThinkingProxy] Meta AI web adapter retrying malformed synthetic tool output with repair prompt. Original assistant text: %@", assistantText)

            let repairRequests = try buildExecutionRequests(
                authSnapshot: authSnapshot,
                conversationID: UUID().uuidString,
                prompt: repairPrompt
            )
            let repairedEventStream = try executePromptSequence(
                plannedRequests: repairRequests,
                session: session
            )

            guard let repairedAssistantText = repairedEventStream.assistantText?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !repairedAssistantText.isEmpty else {
                let errorMessage = repairedEventStream.errorMessage?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw Failure(
                    statusCode: 502,
                    message: errorMessage?.isEmpty == false
                        ? errorMessage!
                        : "Meta web adapter repair turn received no assistant output from the GraphQL stream."
                )
            }

            do {
                return try renderAssistantOutput(
                    assistantText: repairedAssistantText,
                    parsedRequest: parsedRequest
                )
            } catch let repairFailure as Failure {
                NSLog("[ThinkingProxy] Meta AI web adapter repair turn still produced invalid synthetic tool output. Repaired assistant text: %@", repairedAssistantText)
                throw repairFailure
            }
        }
    }

    private static func shouldAttemptSyntheticToolRepair(
        failure: Failure,
        assistantText: String,
        parsedRequest: ParsedRequest
    ) -> Bool {
        guard !parsedRequest.toolDefinitions.isEmpty, parsedRequest.toolChoice != .none else {
            return false
        }
        let trimmedAssistantText = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAssistantText.isEmpty else {
            return false
        }

        switch parsedRequest.toolChoice {
        case .required, .specific:
            return true
        case .auto:
            return looksLikeSyntheticToolDirective(trimmedAssistantText)
                || failure.message.contains("tool directive")
                || failure.message.contains("tool call")
        case .none:
            return false
        }
    }

    private static func looksLikeSyntheticToolDirective(_ assistantText: String) -> Bool {
        let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```") {
            return true
        }
        let lower = trimmed.lowercased()
        return lower.contains("\"arguments\"") || lower.contains("\"tool\"") || lower.contains("\"name\"")
    }

    static func syntheticToolDirective(
        from assistantText: String,
        parsedRequest: ParsedRequest
    ) throws -> SyntheticToolDirective? {
        let candidateJSONStrings = syntheticToolDirectiveCandidateStrings(from: assistantText)
        guard !candidateJSONStrings.isEmpty else {
            return nil
        }

        let allowedToolNames = Set(parsedRequest.toolDefinitions.map(\.name))
        for candidateJSONString in candidateJSONStrings {
            guard let candidateData = candidateJSONString.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: candidateData) as? [String: Any] else {
                continue
            }

            if let directive = try syntheticToolDirective(fromJSONObject: root, parsedRequest: parsedRequest) {
                return directive
            }
        }

        if let heuristicDirective = try heuristicSyntheticToolDirective(
            from: assistantText,
            allowedToolNames: allowedToolNames,
            parsedRequest: parsedRequest
        ) {
            return heuristicDirective
        }

        return nil
    }

    private static func syntheticToolDirective(
        fromJSONObject root: [String: Any],
        parsedRequest: ParsedRequest
    ) throws -> SyntheticToolDirective? {
        let allowedToolNames = Set(parsedRequest.toolDefinitions.map(\.name))
        let requiredToolName = requiredSyntheticToolName(for: parsedRequest.toolChoice)
        let matchedTopLevelToolNames = root.keys.compactMap { key -> String? in
            guard let normalized = normalizedString(key),
                  let resolved = resolveSyntheticToolName(
                    rawName: normalized,
                    allowedToolNames: allowedToolNames,
                    requiredToolName: requiredToolName
                  ) else {
                return nil
            }
            return resolved
        }

        let explicitToolName = normalizedString((root["name"] ?? root["tool"] ?? root["tool_name"]) as? String).flatMap {
            resolveSyntheticToolName(rawName: $0, allowedToolNames: allowedToolNames, requiredToolName: requiredToolName)
        }
        if let explicitToolName {
            try validateSyntheticToolChoice(toolName: explicitToolName, parsedRequest: parsedRequest, allowRepair: true)

            if let argumentsJSONString = try normalizeSyntheticArguments(
                from: root["arguments"] ?? root["args"] ?? root["parameters"]
            ) {
                return SyntheticToolDirective(name: explicitToolName, argumentsJSONString: argumentsJSONString)
            }

            let residualArguments = root.filter { key, _ in
                !["name", "tool", "tool_name", "arguments", "args", "parameters", "type"].contains(key)
            }
            if let argumentsJSONString = try normalizeSyntheticArguments(from: residualArguments) {
                return SyntheticToolDirective(name: explicitToolName, argumentsJSONString: argumentsJSONString)
            }

            throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode required arguments for tool \(explicitToolName), but Meta returned no usable arguments object.")
        }

        if matchedTopLevelToolNames.count == 1,
           let nestedToolName = matchedTopLevelToolNames.first {
            try validateSyntheticToolChoice(toolName: nestedToolName, parsedRequest: parsedRequest, allowRepair: true)
            if let argumentsJSONString = try normalizeSyntheticArguments(from: root[nestedToolName]) {
                return SyntheticToolDirective(name: nestedToolName, argumentsJSONString: argumentsJSONString)
            }
        }

        if let requiredToolName {
            let conflictingToolNames = matchedTopLevelToolNames.filter { $0 != requiredToolName }
            if !conflictingToolNames.isEmpty {
                if let argumentsJSONString = try normalizeSyntheticArguments(from: root) {
                    return SyntheticToolDirective(name: requiredToolName, argumentsJSONString: argumentsJSONString)
                }
            }

            if let requiredWrapper = root[requiredToolName],
               let argumentsJSONString = try normalizeSyntheticArguments(from: requiredWrapper) {
                return SyntheticToolDirective(name: requiredToolName, argumentsJSONString: argumentsJSONString)
            }

            if let argumentsJSONString = try normalizeSyntheticArguments(from: root) {
                return SyntheticToolDirective(name: requiredToolName, argumentsJSONString: argumentsJSONString)
            }
        }

        return nil
    }

    private static func syntheticToolDirectiveCandidateStrings(from assistantText: String) -> [String] {
        let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var candidates: [String] = [trimmed]

        if trimmed.hasPrefix("```"), let range = trimmed.range(of: "```", options: .backwards), range.lowerBound > trimmed.startIndex {
            let withoutPrefix = trimmed.dropFirst(3)
            let bodyStart = withoutPrefix.firstIndex(of: "\n").map { withoutPrefix.index(after: $0) } ?? withoutPrefix.startIndex
            let body = String(withoutPrefix[bodyStart..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                candidates.append(body)
            }
        }

        if let start = trimmed.range(of: "{"), let end = trimmed.range(of: "}", options: .backwards), start.lowerBound < end.upperBound {
            let body = String(trimmed[start.lowerBound..<end.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                candidates.append(body)
            }
        }

        candidates.append(contentsOf: balancedJSONObjectStrings(in: trimmed))

        var deduped: [String] = []
        var seen: Set<String> = []
        for candidate in candidates {
            if seen.insert(candidate).inserted {
                deduped.append(candidate)
            }
        }
        return deduped
    }

    private static func balancedJSONObjectStrings(in text: String) -> [String] {
        var results: [String] = []
        var stackDepth = 0
        var objectStart: String.Index?
        var isInsideString = false
        var isEscaped = false

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    if stackDepth == 0 {
                        objectStart = index
                    }
                    stackDepth += 1
                } else if character == "}", stackDepth > 0 {
                    stackDepth -= 1
                    if stackDepth == 0, let objectStart {
                        let nextIndex = text.index(after: index)
                        let candidate = String(text[objectStart..<nextIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !candidate.isEmpty {
                            results.append(candidate)
                        }
                    }
                }
            }

            index = text.index(after: index)
        }

        return results
    }

    private static func heuristicSyntheticToolDirective(
        from assistantText: String,
        allowedToolNames: Set<String>,
        parsedRequest: ParsedRequest
    ) throws -> SyntheticToolDirective? {
        let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        for toolName in allowedToolNames.sorted() {
            if let argumentsJSONString = extractArgumentsObject(
                pattern: #"(?is)\b\#(toolName)\s*\(\s*(\{.*\})\s*\)"#,
                from: trimmed
            ) {
                return SyntheticToolDirective(name: toolName, argumentsJSONString: argumentsJSONString)
            }

            if let argumentsJSONString = extractArgumentsObject(
                pattern: #"(?is)\b(?:tool|function)\s*:\s*\#(toolName)\b.*?\barguments?\s*:\s*(\{.*\})"#,
                from: trimmed
            ) {
                return SyntheticToolDirective(name: toolName, argumentsJSONString: argumentsJSONString)
            }

            if let argumentsJSONString = extractArgumentsObject(
                pattern: #"(?is)\b(?:call|use)\s+\#(toolName)\b.*?\barguments?\b.*?(\{.*\})"#,
                from: trimmed
            ) {
                return SyntheticToolDirective(name: toolName, argumentsJSONString: argumentsJSONString)
            }
        }

        if allowedToolNames.count == 1,
           let soleToolName = allowedToolNames.first,
           let argumentsJSONString = extractArgumentsObject(
            pattern: #"(?is)(\{.*\})"#,
            from: trimmed
           ),
           case .required = parsedRequest.toolChoice {
            return SyntheticToolDirective(name: soleToolName, argumentsJSONString: argumentsJSONString)
        }

        return nil
    }

    private static func requiredSyntheticToolName(for toolChoice: ToolChoice) -> String? {
        switch toolChoice {
        case .specific(let name):
            return name
        default:
            return nil
        }
    }

    private static func validateSyntheticToolChoice(
        toolName: String,
        parsedRequest: ParsedRequest,
        allowRepair: Bool
    ) throws {
        if case .specific(let requiredName) = parsedRequest.toolChoice,
           requiredName != toolName,
           !allowRepair {
            throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode returned tool \(toolName), but tool_choice required \(requiredName).")
        }
    }

    private static func resolveSyntheticToolName(
        rawName: String,
        allowedToolNames: Set<String>,
        requiredToolName: String?
    ) -> String? {
        if allowedToolNames.contains(rawName) {
            return rawName
        }

        if let requiredToolName,
           canonicalSyntheticToolName(rawName) == canonicalSyntheticToolName(requiredToolName) {
            return requiredToolName
        }

        let canonicalRawName = canonicalSyntheticToolName(rawName)
        guard !canonicalRawName.isEmpty else {
            return nil
        }

        let canonicalMatches = allowedToolNames.filter { canonicalSyntheticToolName($0) == canonicalRawName }
        if canonicalMatches.count == 1 {
            return canonicalMatches.first
        }

        let containsMatches = allowedToolNames.filter {
            let candidate = canonicalSyntheticToolName($0)
            return candidate.contains(canonicalRawName) || canonicalRawName.contains(candidate)
        }
        if containsMatches.count == 1 {
            return containsMatches.first
        }

        if let requiredToolName {
            return requiredToolName
        }

        return nil
    }

    private static func canonicalSyntheticToolName(_ rawName: String) -> String {
        rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizeSyntheticArguments(from rawValue: Any?) throws -> String? {
        guard let rawValue else {
            return nil
        }

        let argumentsObject: [String: Any]
        switch rawValue {
        case let dictionary as [String: Any]:
            argumentsObject = dictionary
        case let string as String:
            guard let stringData = string.data(using: .utf8),
                  let parsedArguments = try? JSONSerialization.jsonObject(with: stringData) as? [String: Any] else {
                throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode returned non-object function arguments.")
            }
            argumentsObject = parsedArguments
        default:
            throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode requires arguments to be a JSON object.")
        }

        guard JSONSerialization.isValidJSONObject(argumentsObject),
              let argumentsData = try? JSONSerialization.data(withJSONObject: argumentsObject, options: [.sortedKeys]),
              let argumentsJSONString = String(data: argumentsData, encoding: .utf8) else {
            throw Failure(statusCode: 502, message: "Meta web adapter synthetic tool mode could not serialize function arguments.")
        }
        return argumentsJSONString
    }

    private static func extractArgumentsObject(pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let objectRange = Range(match.range(at: match.numberOfRanges - 1), in: text) else {
            return nil
        }
        let candidate = String(text[objectRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidateData = candidate.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: candidateData) as? [String: Any],
              JSONSerialization.isValidJSONObject(jsonObject),
              let normalizedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
              let normalizedJSONString = String(data: normalizedData, encoding: .utf8) else {
            return nil
        }
        return normalizedJSONString
    }

    static func formattedUpstreamErrorMessage(statusCode: Int, responseData: Data) -> String {
        let bodyText = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let classifiedMessage = classifiedNonGraphQLFailureMessage(statusCode: statusCode, responseText: bodyText) {
            return classifiedMessage
        }

        let errorMessages = extractGraphQLErrorMessages(from: responseData)
        if !errorMessages.isEmpty {
            return "Meta web adapter upstream error (\(statusCode)): \(errorMessages.joined(separator: " | "))"
        }

        if let bodyText, !bodyText.isEmpty {
            return "Meta web adapter upstream error (\(statusCode)): \(bodyText)"
        }

        return "Meta web adapter upstream error (\(statusCode))."
    }

    private static func extractGraphQLErrorMessages(from responseData: Data) -> [String] {
        guard let text = String(data: responseData, encoding: .utf8) else {
            return []
        }

        var messages: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            guard rawLine.hasPrefix("data:") else {
                continue
            }
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]",
                  let payloadData = payload.data(using: .utf8) else {
                continue
            }
            messages.append(contentsOf: graphQLErrorMessages(fromJSONObjectData: payloadData))
        }

        if !messages.isEmpty {
            return deduplicatedMessages(messages)
        }

        return deduplicatedMessages(graphQLErrorMessages(fromJSONObjectData: responseData))
    }

    private static func graphQLErrorMessages(fromJSONObjectData data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return graphQLErrorMessages(fromJSONObject: root)
    }

    private static func graphQLErrorMessages(fromJSONObject root: [String: Any]) -> [String] {
        if let errors = root["errors"] as? [[String: Any]] {
            let messages = errors.compactMap { errorObject -> String? in
                normalizedString(errorObject["message"] as? String)
            }
            if !messages.isEmpty {
                return messages
            }
        }

        if let errorObject = root["error"] as? [String: Any],
           let message = normalizedString(errorObject["message"] as? String) {
            return [message]
        }

        if let message = normalizedString(root["message"] as? String) {
            return [message]
        }

        return []
    }

    private static func classifiedNonGraphQLFailureMessage(statusCode: Int, responseText: String?) -> String? {
        guard let responseText = normalizedString(responseText) else {
            return nil
        }

        let normalizedBody = responseText.lowercased()
        if looksLikeMetaChallengePage(normalizedBody) {
            return "Meta web adapter was blocked by a Meta/Cloudflare challenge page; refresh the HAR in a normal browser session and retry."
        }

        if looksLikeMetaServiceFailurePage(normalizedBody, statusCode: statusCode) {
            return "Meta web adapter received a temporary Meta error page; retry later. If this persists, verify meta.ai is reachable in a normal browser session."
        }

        if looksLikeMetaSessionFailure(normalizedBody, statusCode: statusCode) {
            return "Meta web adapter session is no longer authorized; capture a fresh HAR with current datr and ecto_1_sess cookies and retry."
        }

        return nil
    }

    private static func looksLikeMetaChallengePage(_ normalizedBody: String) -> Bool {
        let htmlIndicators = ["<!doctype html", "<html", "<head", "<body"]
        let challengeIndicators = [
            "just a moment",
            "cloudflare",
            "cf-chl",
            "captcha",
            "attention required",
            "challenge-platform",
            "bot detection",
            "verify you are human"
        ]
        return htmlIndicators.contains(where: normalizedBody.contains)
            && challengeIndicators.contains(where: normalizedBody.contains)
    }

    private static func looksLikeMetaServiceFailurePage(_ normalizedBody: String, statusCode: Int) -> Bool {
        let serviceIndicators = [
            "facebook | error",
            "no server is available for the request",
            "temporarily unavailable",
            "an unexpected error occurred"
        ]
        if serviceIndicators.contains(where: normalizedBody.contains) {
            return true
        }
        return statusCode >= 500 && normalizedBody.contains("<title>facebook | error</title>")
    }

    private static func looksLikeMetaSessionFailure(_ normalizedBody: String, statusCode: Int) -> Bool {
        let authIndicators = [
            "access token required",
            "authentication required",
            "authentication failed",
            "authentication error",
            "unauthorized",
            "invalid session",
            "session expired",
            "log in to continue",
            "login required",
            "please log in"
        ]
        if authIndicators.contains(where: normalizedBody.contains) {
            return true
        }
        return statusCode == 403 && normalizedBody.contains("forbidden")
    }

    private static func deduplicatedMessages(_ messages: [String]) -> [String] {
        var seen: Set<String> = []
        var deduplicated: [String] = []
        for message in messages {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            deduplicated.append(trimmed)
        }
        return deduplicated
    }

    private static func extractSources(fromSendMessageStream streamObject: [String: Any]) -> [Source] {
        let candidateSourceArrays: [Any?] = [
            streamObject["sources"],
            ((streamObject["contentRenderer"] as? [String: Any])?["message"] as? [String: Any])?["sources"],
            ((streamObject["message"] as? [String: Any])?["sources"])
        ]

        for candidate in candidateSourceArrays {
            guard let sourceObjects = candidate as? [[String: Any]], !sourceObjects.isEmpty else {
                continue
            }

            let sources = sourceObjects.compactMap { sourceObject -> Source? in
                guard let url = normalizedString(
                    (sourceObject["source_url"] as? String) ??
                        (sourceObject["url"] as? String) ??
                        ((sourceObject["source"] as? [String: Any])?["url"] as? String)
                ) else {
                    return nil
                }

                let title = normalizedString(
                    (sourceObject["source_display_name"] as? String) ??
                        (sourceObject["title"] as? String) ??
                        (sourceObject["name"] as? String)
                ) ?? url

                let subtitle = normalizedString(
                    (sourceObject["source_subtitle"] as? String) ??
                        (sourceObject["subtitle"] as? String)
                )

                return Source(url: url, title: title, subtitle: subtitle)
            }

            if !sources.isEmpty {
                return deduplicatedSources(sources)
            }
        }

        return []
    }

    private static func deduplicatedSources(_ sources: [Source]) -> [Source] {
        var seenURLs: Set<String> = []
        var deduplicated: [Source] = []
        for source in sources {
            guard !seenURLs.contains(source.url) else {
                continue
            }
            seenURLs.insert(source.url)
            deduplicated.append(source)
        }
        return deduplicated
    }

    static func responseAnnotations(from sources: [Source]) -> [[String: Any]] {
        sources.map { source in
            var annotation: [String: Any] = [
                "type": "url_citation",
                "url": source.url,
                "title": source.title,
                "start_index": 0,
                "end_index": 0
            ]
            if let subtitle = source.subtitle {
                annotation["subtitle"] = subtitle
            }
            return annotation
        }
    }

    private static func buildChatCompletionsResponseBody(text: String, publicModel: String) -> Data {
        let created = Int(Date().timeIntervalSince1970)
        let id = "chatcmpl_meta_\(UUID().uuidString)"
        let payload: [String: Any] = [
            "id": id,
            "object": "chat.completion",
            "created": created,
            "model": publicModel,
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": text
                ],
                "finish_reason": "stop"
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }

    private static func buildChatCompletionsResponseBody(toolCall: SyntheticToolDirective, publicModel: String) -> Data {
        let created = Int(Date().timeIntervalSince1970)
        let id = "chatcmpl_meta_\(UUID().uuidString)"
        let callID = "call_meta_\(UUID().uuidString)"
        let payload: [String: Any] = [
            "id": id,
            "object": "chat.completion",
            "created": created,
            "model": publicModel,
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [[
                        "id": callID,
                        "type": "function",
                        "function": [
                            "name": toolCall.name,
                            "arguments": toolCall.argumentsJSONString
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }

    private static func buildChatCompletionsStreamBody(text: String, publicModel: String) -> Data {
        let id = "chatcmpl_meta_\(UUID().uuidString)"
        let created = Int(Date().timeIntervalSince1970)
        let lines = [
            sseLine([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicModel,
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant"],
                    "finish_reason": NSNull()
                ]]
            ]),
            sseLine([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicModel,
                "choices": [[
                    "index": 0,
                    "delta": ["content": text],
                    "finish_reason": NSNull()
                ]]
            ]),
            sseLine([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicModel,
                "choices": [[
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop"
                ]]
            ]),
            "data: [DONE]\n\n"
        ]
        return Data(lines.joined().utf8)
    }

    private static func buildChatCompletionsStreamBody(toolCall: SyntheticToolDirective, publicModel: String) -> Data {
        let id = "chatcmpl_meta_\(UUID().uuidString)"
        let callID = "call_meta_\(UUID().uuidString)"
        let created = Int(Date().timeIntervalSince1970)
        let lines = [
            sseLine([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicModel,
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant"],
                    "finish_reason": NSNull()
                ]]
            ]),
            sseLine([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicModel,
                "choices": [[
                    "index": 0,
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": callID,
                            "type": "function",
                            "function": [
                                "name": toolCall.name,
                                "arguments": toolCall.argumentsJSONString
                            ]
                        ]]
                    ],
                    "finish_reason": NSNull()
                ]]
            ]),
            sseLine([
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicModel,
                "choices": [[
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "tool_calls"
                ]]
            ]),
            "data: [DONE]\n\n"
        ]
        return Data(lines.joined().utf8)
    }

    static func buildResponsesResponseBody(text: String, publicModel: String, sources: [Source] = []) -> Data {
        let created = Int(Date().timeIntervalSince1970)
        let responseID = "resp_meta_\(UUID().uuidString)"
        let messageID = "msg_meta_\(UUID().uuidString)"
        let payload: [String: Any] = [
            "id": responseID,
            "object": "response",
            "created": created,
            "status": "completed",
            "model": publicModel,
            "output": [[
                "id": messageID,
                "type": "message",
                "role": "assistant",
                "status": "completed",
                "content": [[
                    "type": "output_text",
                    "text": text,
                    "annotations": responseAnnotations(from: sources)
                ]]
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }

    static func buildResponsesResponseBody(toolCall: SyntheticToolDirective, publicModel: String) -> Data {
        let created = Int(Date().timeIntervalSince1970)
        let responseID = "resp_meta_\(UUID().uuidString)"
        let callID = "call_meta_\(UUID().uuidString)"
        let payload: [String: Any] = [
            "id": responseID,
            "object": "response",
            "created": created,
            "status": "completed",
            "model": publicModel,
            "output": [[
                "id": "fc_\(callID)",
                "type": "function_call",
                "call_id": callID,
                "name": toolCall.name,
                "arguments": toolCall.argumentsJSONString,
                "status": "completed"
            ]]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }

    static func buildResponsesStreamBody(text: String, publicModel: String, sources: [Source] = []) -> Data {
        let created = Int(Date().timeIntervalSince1970)
        let responseID = "resp_meta_\(UUID().uuidString)"
        let messageID = "msg_meta_\(UUID().uuidString)"
        let annotations = responseAnnotations(from: sources)
        let lines = [
            sseLine([
                "type": "response.created",
                "response": [
                    "id": responseID,
                    "object": "response",
                    "created": created,
                    "status": "in_progress",
                    "model": publicModel,
                    "output": []
                ]
            ]),
            sseLine([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": [
                    "id": messageID,
                    "type": "message",
                    "role": "assistant",
                    "status": "in_progress",
                    "content": []
                ]
            ]),
            sseLine([
                "type": "response.output_text.delta",
                "output_index": 0,
                "item_id": messageID,
                "content_index": 0,
                "delta": text
            ]),
            sseLine([
                "type": "response.output_text.done",
                "output_index": 0,
                "item_id": messageID,
                "content_index": 0,
                "text": text
            ]),
            sseLine([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": [
                    "id": messageID,
                    "type": "message",
                    "role": "assistant",
                    "status": "completed",
                    "content": [[
                        "type": "output_text",
                        "text": text,
                        "annotations": annotations
                    ]]
                ]
            ]),
            sseLine([
                "type": "response.completed",
                "response": [
                    "id": responseID,
                    "object": "response",
                    "created": created,
                    "status": "completed",
                    "model": publicModel,
                    "output": [[
                        "id": messageID,
                        "type": "message",
                        "role": "assistant",
                        "status": "completed",
                        "content": [[
                            "type": "output_text",
                            "text": text,
                            "annotations": annotations
                        ]]
                    ]]
                ]
            ]),
            "data: [DONE]\n\n"
        ]
        return Data(lines.joined().utf8)
    }

    static func buildResponsesStreamBody(toolCall: SyntheticToolDirective, publicModel: String) -> Data {
        let created = Int(Date().timeIntervalSince1970)
        let responseID = "resp_meta_\(UUID().uuidString)"
        let callID = "call_meta_\(UUID().uuidString)"
        let outputItem: [String: Any] = [
            "id": "fc_\(callID)",
            "type": "function_call",
            "call_id": callID,
            "name": toolCall.name,
            "arguments": toolCall.argumentsJSONString,
            "status": "completed"
        ]
        var addedItem = outputItem
        addedItem["arguments"] = ""
        let responseObject: [String: Any] = [
            "id": responseID,
            "object": "response",
            "created": created,
            "status": "completed",
            "model": publicModel,
            "output": [outputItem]
        ]
        let lines = [
            sseLine([
                "type": "response.created",
                "response": [
                    "id": responseID,
                    "object": "response",
                    "created": created,
                    "status": "in_progress",
                    "model": publicModel,
                    "output": []
                ]
            ]),
            sseLine([
                "type": "response.output_item.added",
                "output_index": 0,
                "item": addedItem
            ]),
            sseLine([
                "type": "response.function_call_arguments.delta",
                "output_index": 0,
                "delta": toolCall.argumentsJSONString
            ]),
            sseLine([
                "type": "response.function_call_arguments.done",
                "output_index": 0,
                "arguments": toolCall.argumentsJSONString
            ]),
            sseLine([
                "type": "response.output_item.done",
                "output_index": 0,
                "item": outputItem
            ]),
            sseLine([
                "type": "response.completed",
                "response": responseObject
            ]),
            "data: [DONE]\n\n"
        ]
        return Data(lines.joined().utf8)
    }

    private static func sseLine(_ json: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "data: \(string)\n\n"
    }
}

/**
 A lightweight HTTP proxy that intercepts requests to add extended thinking parameters
 for Claude models based on model name suffixes.
 
 Model name pattern:
 - `*-thinking-NUMBER` → Custom token budget (e.g., claude-sonnet-4-5-20250929-thinking-5000)
 
 The proxy strips the suffix and adds the `thinking` parameter to the request body
 before forwarding to CLIProxyAPI.
 
 Examples:
 - claude-sonnet-4-5-20250929-thinking-2000 → 2,000 token budget
 - claude-sonnet-4-5-20250929-thinking-8000 → 8,000 token budget
 */
struct VercelGatewayConfig {
    var enabled: Bool
    var apiKey: String

    var isActive: Bool { enabled && !apiKey.isEmpty }
}

class ThinkingProxy {
    private struct RuntimeProvenance {
        let appVersion: String
        let appBuild: String
        let backendBinaryPath: String?
        let backendBinaryFingerprint: String?
        let mergedConfigPath: String?
        let mergedConfigFingerprint: String?
    }

    private struct RequestTraceContext {
        let proxyRequestID: String
        let callerRequestID: String?
        let callerSessionID: String?
        let requestShape: String

        var responseHeaders: [String: String] {
            var headers = ["X-VibeProxy-Request-ID": proxyRequestID]
            if let callerRequestID {
                headers["X-VibeProxy-Caller-Request-ID"] = callerRequestID
            }
            if let callerSessionID {
                headers["X-VibeProxy-Caller-Session-ID"] = callerSessionID
            }
            headers["X-VibeProxy-Request-Shape"] = requestShape
            return headers
        }
    }

    private struct FactoryWorkerContract {
        let workerModelID: String
        let validationWorkerModelID: String?
        let workerReasoningEffort: String?
        let validationWorkerReasoningEffort: String?
        let configuredRouteModel: String
        let routeModel: String
        let authoritativeRouteModel: String
        let routeProvider: String
        let requestSurface: String
        let requestShapeContracts: [FactoryWorkerRequestShapeContract]
        let dispatchableRouteModel: String?
        let effectiveRouteModel: String?
        let effectiveRouteModelSource: OpenAICompatTemporaryShim.FactoryEffectiveRouteModelSource?
        let effectiveRouteProvider: String?
        let recentDispatchedRouteModel: String?
        let recentDispatchedRouteProvider: String?
        let recentDispatchedRequestShape: String?
        let recentDispatchedRouteAt: Date?
        let recentDispatchedCallerRequestID: String?
        let recentDispatchedCallerSessionID: String?
        let recentLiveRouteModel: String?
        let recentLiveRouteProvider: String?
        let recentLiveRequestShape: String?
        let recentLiveRouteAt: Date?
        let recentLiveCallerRequestID: String?
        let recentLiveCallerSessionID: String?
        let displayName: String?
        let baseURL: String?
        let routeHealthStatus: String?
        let authoritativeSettingsPath: String
        let snapshotDriftPaths: [String]
        let acceptedRequestModelIDs: [String]
        let rescuedRequestModelIDs: [String]
        let settingsAvailable: Bool

        var blockingSnapshotDriftPaths: [String] {
            ThinkingProxy.blockingFactoryWorkerSnapshotDriftPaths(snapshotDriftPaths)
        }

        var ready: Bool {
            blockingSnapshotDriftPaths.isEmpty && requestShapeContracts.allSatisfy(\.ready)
        }
    }

    private struct FactoryWorkerRequestShapeContract {
        let id: String
        let candidateModels: [String]
        let dispatchableCandidateModels: [String]
        let dispatchableRouteModel: String?
        let effectiveRouteModel: String
        let effectiveRouteModelSource: OpenAICompatTemporaryShim.FactoryEffectiveRouteModelSource
        let effectiveRouteProvider: String?
        let routeHealthStatus: String?
        let recentDispatchedRouteModel: String?
        let recentDispatchedRouteProvider: String?
        let recentDispatchedRouteAt: Date?

        var ready: Bool {
            dispatchableRouteModel != nil
        }
    }

    private enum FactoryWorkerHealthRequestShape: String, CaseIterable {
        case plainChat = "plain_chat"
        case toolChat = "tool_string_content"
        case typedToolChat = "typed_tool_content"
    }

    private struct FactoryRoleContract {
        let modelID: String
        let reasoningEffort: String?
        let routeModel: String
        let routeProvider: String
        let requestSurface: String
        let effectiveRouteModel: String
        let effectiveRouteModelSource: OpenAICompatTemporaryShim.FactoryEffectiveRouteModelSource
        let effectiveRouteProvider: String?
        let displayName: String?
        let baseURL: String?
        let routeHealthStatus: String?

        var ready: Bool {
            routeHealthStatus == nil
        }
    }

    fileprivate struct RecentObservedSmartAliasWinner {
        let timestamp: Date
        let requestModel: String
        let requestShape: String?
        let callerRequestID: String?
        let callerSessionID: String?
    }

    fileprivate struct FactoryModelBinding {
        let incomingModelID: String
        let authoritativeModelID: String
        let routeModel: String
        let routeProvider: String
        let requestSurface: String
        let displayName: String?
        let baseURL: String?
        let authoritativeSettingsPath: String
        let source: String
    }

    fileprivate struct CachedFactoryModelBindings {
        let settingsPath: String
        let settingsFingerprint: String?
        let bindingsByIncomingModelID: [String: FactoryModelBinding]
        let authoritativeWorkerModelID: String?
    }

    private static let factoryBindingsCacheQueue = DispatchQueue(label: "io.automaze.vibeproxy.factory-bindings-cache")
    private static var cachedFactoryModelBindings: CachedFactoryModelBindings?

    struct BufferedProxyResponse {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
        let firstByteLatencyMilliseconds: Int?
        let totalLatencyMilliseconds: Int?
        let deadlineStage: OpenAICompatTemporaryShim.DeadlineStage

        init(
            data: Data?,
            response: HTTPURLResponse?,
            error: Error?,
            firstByteLatencyMilliseconds: Int? = nil,
            totalLatencyMilliseconds: Int? = nil,
            deadlineStage: OpenAICompatTemporaryShim.DeadlineStage = .none
        ) {
            self.data = data
            self.response = response
            self.error = error
            self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
            self.totalLatencyMilliseconds = totalLatencyMilliseconds
            self.deadlineStage = deadlineStage
        }
    }

    struct NVIDIADirectTransportResponse {
        let chunks: [Data]
        let response: HTTPURLResponse?
        let error: Error?
        let firstByteLatencyMilliseconds: Int?
        let totalLatencyMilliseconds: Int?
        let deadlineStage: OpenAICompatTemporaryShim.DeadlineStage
        let negotiatedApplicationProtocol: String?

        var bodyData: Data? {
            guard !chunks.isEmpty else { return nil }
            return chunks.reduce(into: Data()) { partial, chunk in
                partial.append(chunk)
            }
        }

        init(
            chunks: [Data],
            response: HTTPURLResponse?,
            error: Error?,
            firstByteLatencyMilliseconds: Int? = nil,
            totalLatencyMilliseconds: Int? = nil,
            deadlineStage: OpenAICompatTemporaryShim.DeadlineStage = .none,
            negotiatedApplicationProtocol: String? = nil
        ) {
            self.chunks = chunks
            self.response = response
            self.error = error
            self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
            self.totalLatencyMilliseconds = totalLatencyMilliseconds
            self.deadlineStage = deadlineStage
            self.negotiatedApplicationProtocol = negotiatedApplicationProtocol
        }
    }

    private enum CoalescedReplayPayload {
        case http(statusCode: Int, headers: [AnyHashable: Any], body: Data, overridingHeaders: [String: String])
        case error(statusCode: Int, message: String, overridingHeaders: [String: String])
    }

    private struct CoalescedReplayEntry {
        let expiresAt: Date
        let payload: CoalescedReplayPayload

        var isExpired: Bool {
            expiresAt <= Date()
        }
    }

    private enum SmartAliasCandidateAttemptOutcome {
        case success(
            requestModel: String,
            statusCode: Int,
            headers: [AnyHashable: Any],
            body: Data,
            telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent
        )
        case liveStreamDelivered(
            requestModel: String,
            telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent,
            cooldownUntil: Date?
        )
        case retryableFailure(
            requestModel: String,
            telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent,
            cooldownUntil: Date?
        )
        case terminalResponse(
            requestModel: String,
            statusCode: Int,
            headers: [AnyHashable: Any],
            body: Data,
            telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent
        )
        case terminalError(
            requestModel: String,
            statusCode: Int,
            message: String,
            telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent?,
            errorBodySnippet: String?
        )
    }

    private enum SmartAliasDeliveryMode {
        case bufferedJSON
        case syntheticSSE
        case bufferedResponsesJSON
        case syntheticResponsesSSE
    }

    private enum FactoryBoundDeliveryMode {
        case bufferedJSON
        case syntheticChatCompletionsSSE
        case syntheticResponsesSSE
    }

    private final class RouteConcurrencyPermit {
        let routeHealthKey: String
        let inflightAtRequest: Int
        private let lock = NSLock()
        private var released = false

        init(routeHealthKey: String, inflightAtRequest: Int) {
            self.routeHealthKey = routeHealthKey
            self.inflightAtRequest = inflightAtRequest
        }

        func release() {
            lock.lock()
            defer { lock.unlock() }
            guard !released else { return }
            released = true
            OpenAICompatTemporaryShim.releaseConcurrencySlot(routeHealthKey: routeHealthKey)
        }

        deinit {
            release()
        }
    }

    private var listener: NWListener?
    let proxyPort: UInt16 = 8317
    private let targetPort: UInt16 = 8318
    private let targetHost = "127.0.0.1"
    private(set) var isRunning = false
    private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.thinking-proxy-state")
    private let nvidiaInflightQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-inflight")
    // NVIDIA race coalescing: maps canonical model ID to waiters awaiting the same upstream response
    private var nvidiaRaceWaiters: [String: [(SmartAliasCandidateAttemptOutcome) -> Void]] = [:]
    private var canaryTimer: DispatchSourceTimer?
    private var maintenanceTimer: DispatchSourceTimer?
    private let canaryQueue = DispatchQueue(label: "io.automaze.vibeproxy.canary")
    private var canarySweepInFlight = false
    private let smartAliasForcedPrimaryRetryLimit = 2
    private let smartAliasMaxLoopRetries = 4
    private var inflightCoalescedRequests: [String: [NWConnection]] = [:]
    private var recentCoalescedReplays: [String: CoalescedReplayEntry] = [:]
    private let coalescedReplayWindow: TimeInterval = 5
    var nvidiaCanaryTransportForTesting: ((String, String, @escaping (Data?, HTTPURLResponse?, Error?) -> Void) -> Void)?
    var nvidiaDirectTransportForTesting: ((URLRequest, @escaping (NVIDIADirectTransportResponse) -> Void) -> (() -> Void))?
    var nvidiaDirectStreamingTransportForTesting: ((URLRequest, @escaping (Data, Date) -> Void, @escaping (NVIDIADirectTransportResponse) -> Void) -> (() -> Void))?
    var bufferedProxyTransportForTesting: ((String, String, [(String, String)], String, TimeInterval, @escaping (BufferedProxyResponse) -> Void) -> Void)?
    var bufferedProxyCancelableTransportForTesting: ((String, String, [(String, String)], String, TimeInterval, @escaping (BufferedProxyResponse) -> Void) -> (() -> Void))?
    var directProxiedTransportForTesting: ((URLRequest, OpenAICompatTemporaryShim.ProviderEndpoint, @escaping (BufferedProxyResponse) -> Void) -> (() -> Void))?
    var metaAIBufferedResponseForTesting: ((String, String, String) -> BufferedProxyResponse)?
    var deliveredHTTPResponseForTesting: ((Int, [AnyHashable: Any], Data) -> Void)?
    var deliveredStreamingResponseStartForTesting: ((Int, [AnyHashable: Any]) -> Void)?
    var deliveredStreamingResponseChunkForTesting: ((Data) -> Void)?
    var deliveredStreamingResponseFinishForTesting: (() -> Void)?
    var deliveredErrorForTesting: ((Int, String) -> Void)?
    var nvidiaDirectTargetHostOverrideForTesting: String?
    var nvidiaDirectTargetPortOverrideForTesting: UInt16?
    var nvidiaDirectTransportPolicyOverrideForTesting: NVIDIATransportPolicy?
    var smartAliasTotalTimeoutOverrideForTesting: TimeInterval?
    var smartAliasLoopRetryLimitOverrideForTesting: Int?
    var forwardRequestInterceptorForTesting: ((String, String, String, [(String, String)], String, Bool, NWConnection, Bool) -> Bool)?

    var vercelConfig = VercelGatewayConfig(enabled: false, apiKey: "")
    
    private enum Config {
        static let hardTokenCap = 32000
        static let minimumHeadroom = 1024
        static let headroomRatio = 0.1
        static let vercelGatewayHost = "ai-gateway.vercel.sh"
        static let anthropicVersion = "2023-06-01"
        static let nvidiaReasoningSemanticRetries = 2
        static let nvidiaReasoningTransportRetries = 2
        static let smartAliasMaxLoopRetryDelay: TimeInterval = 0.5
        static let defaultMitigatedAttemptTimeout: TimeInterval = OpenAICompatTemporaryShim.scaledRequestTimeout(300)
        static let nvidiaCanaryTimeout: TimeInterval = OpenAICompatTemporaryShim.scaledRequestTimeout(300)
        static let healthcheckTimeout: TimeInterval = 0.5
    }

    final class NVIDIAAttemptCoordinator {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-hedge-coordinator")
        private var finished = false
        private var hedgeStarted = false
        private var winnerAttemptLane: Int?
        private var cancelersByAttemptLane: [Int: () -> Void] = [:]

        func shouldStartHedge() -> Bool {
            stateQueue.sync {
                guard !finished, !hedgeStarted else { return false }
                hedgeStarted = true
                return true
            }
        }

        func registerAttempt(attemptLane: Int, cancel: @escaping () -> Void) {
            let cancelImmediately: (() -> Void)? = stateQueue.sync {
                if finished {
                    return cancel
                }
                if let winnerAttemptLane, winnerAttemptLane != attemptLane {
                    return cancel
                }
                cancelersByAttemptLane[attemptLane] = cancel
                return nil
            }
            cancelImmediately?()
        }

        func tryFinish(attemptLane: Int) -> Bool {
            let losersToCancel: [() -> Void]? = stateQueue.sync {
                guard !finished else { return nil }
                finished = true
                winnerAttemptLane = attemptLane
                let losers = cancelersByAttemptLane.compactMap { lane, canceler in
                    lane == attemptLane ? nil : canceler
                }
                cancelersByAttemptLane.removeAll()
                return losers
            }
            losersToCancel?.forEach { $0() }
            return losersToCancel != nil
        }

        func isFinished() -> Bool {
            stateQueue.sync { finished }
        }

        func finishAttemptWithoutWinning(attemptLane: Int) {
            _ = stateQueue.sync {
                cancelersByAttemptLane.removeValue(forKey: attemptLane)
            }
        }

        func winnerAttemptLaneValue() -> Int? {
            stateQueue.sync { winnerAttemptLane }
        }
    }

    final class SmartAliasRaceCoordinator {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.smart-alias-race")
        private var finished = false
        private var winnerAttemptLane: Int?
        private var cancelersByAttemptLane: [Int: () -> Void] = [:]

        func registerAttempt(attemptLane: Int, cancel: @escaping () -> Void) {
            let cancelImmediately: (() -> Void)? = stateQueue.sync {
                if finished {
                    return cancel
                }
                cancelersByAttemptLane[attemptLane] = cancel
                return nil
            }
            cancelImmediately?()
        }

        func tryFinish(attemptLane: Int) -> Bool {
            let losersToCancel: [() -> Void]? = stateQueue.sync {
                guard !finished else { return nil }
                if let winnerAttemptLane, winnerAttemptLane != attemptLane {
                    return nil
                }
                finished = true
                winnerAttemptLane = attemptLane
                let losers = cancelersByAttemptLane.compactMap { lane, canceler in
                    lane == attemptLane ? nil : canceler
                }
                cancelersByAttemptLane.removeAll()
                return losers
            }
            losersToCancel?.forEach { $0() }
            return losersToCancel != nil
        }

        func claimMeaningfulOutput(attemptLane: Int) -> Bool {
            let losersToCancel: [() -> Void]? = stateQueue.sync {
                guard !finished else { return nil }
                if let winnerAttemptLane {
                    guard winnerAttemptLane == attemptLane else { return nil }
                    return []
                }
                winnerAttemptLane = attemptLane
                let losers = cancelersByAttemptLane.compactMap { lane, canceler in
                    lane == attemptLane ? nil : canceler
                }
                cancelersByAttemptLane = cancelersByAttemptLane.filter { $0.key == attemptLane }
                return losers
            }
            losersToCancel?.forEach { $0() }
            return losersToCancel != nil
        }

        func finishAttemptWithoutWinning(attemptLane: Int) {
            _ = stateQueue.sync {
                cancelersByAttemptLane.removeValue(forKey: attemptLane)
            }
        }

        func isFinished() -> Bool {
            stateQueue.sync { finished }
        }

        func winnerAttemptLaneValue() -> Int? {
            stateQueue.sync { winnerAttemptLane }
        }
    }

    final class RequestCancellationController {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.smart-alias-candidate")
        private var cancelled = false
        private var currentCancel: (() -> Void)?
        private var cancelHooks: [() -> Void] = []
        private var scheduledRetryWorkItem: DispatchWorkItem?

        func registerCurrentCancel(_ cancel: @escaping () -> Void) {
            let cancelImmediately: (() -> Void)? = stateQueue.sync {
                if cancelled {
                    return cancel
                }
                currentCancel = cancel
                return nil
            }
            cancelImmediately?()
        }

        func clearCurrentCancel() {
            stateQueue.sync {
                currentCancel = nil
            }
        }

        func registerCancelHook(_ hook: @escaping () -> Void) {
            let runImmediately: (() -> Void)? = stateQueue.sync {
                if cancelled {
                    return hook
                }
                cancelHooks.append(hook)
                return nil
            }
            runImmediately?()
        }

        func scheduleRetry(after delay: DispatchTimeInterval, block: @escaping () -> Void) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !self.isCancelled() else { return }
                block()
            }
            let runImmediately = stateQueue.sync { () -> Bool in
                guard !cancelled else { return false }
                scheduledRetryWorkItem?.cancel()
                scheduledRetryWorkItem = workItem
                return true
            }
            guard runImmediately else { return }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        func cancel() {
            let cancellationWork: (canceler: (() -> Void)?, hooks: [() -> Void])? = stateQueue.sync {
                guard !cancelled else { return nil }
                cancelled = true
                let currentCancel = self.currentCancel
                self.currentCancel = nil
                let hooks = cancelHooks
                cancelHooks.removeAll()
                scheduledRetryWorkItem?.cancel()
                scheduledRetryWorkItem = nil
                return (currentCancel, hooks)
            }
            cancellationWork?.canceler?()
            cancellationWork?.hooks.forEach { $0() }
        }

        func isCancelled() -> Bool {
            stateQueue.sync { cancelled }
        }

        func observeConnectionState(_ state: NWConnection.State) {
            switch state {
            case .failed, .cancelled:
                cancel()
            default:
                break
            }
        }
    }

    private func installClientDisconnectCancellation(
        on connection: NWConnection,
        controller: RequestCancellationController,
        requestTrace: RequestTraceContext? = nil
    ) {
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                if let requestTrace {
                    NSLog(
                        "[ThinkingProxy] Client connection failed before proxy delivery completed: proxy_request_id:%@ %@",
                        requestTrace.proxyRequestID,
                        "\(error)"
                    )
                } else {
                    NSLog("[ThinkingProxy] Client connection failed before proxy delivery completed: \(error)")
                }
            }
            controller.observeConnectionState(state)
        }
        monitorClientDisconnect(on: connection, controller: controller, requestTrace: requestTrace)
    }

    func installClientDisconnectCancellationForTesting(
        on connection: NWConnection,
        controller: RequestCancellationController
    ) {
        installClientDisconnectCancellation(on: connection, controller: controller)
    }

    private func monitorClientDisconnect(
        on connection: NWConnection,
        controller: RequestCancellationController,
        requestTrace: RequestTraceContext? = nil
    ) {
        guard controller.isCancelled() != true else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                if let requestTrace {
                    NSLog(
                        "[ThinkingProxy] Client connection receive failed before proxy delivery completed: proxy_request_id:%@ %@",
                        requestTrace.proxyRequestID,
                        "\(error)"
                    )
                } else {
                    NSLog("[ThinkingProxy] Client connection receive failed before proxy delivery completed: \(error)")
                }
                controller.cancel()
                return
            }
            if isComplete || (data?.isEmpty ?? true) {
                controller.cancel()
                return
            }
            self.monitorClientDisconnect(on: connection, controller: controller, requestTrace: requestTrace)
        }
    }

    private final class ResponseProgressDelegate: NSObject, URLSessionDataDelegate {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-first-response")
        private let onDataReceived: ((Data, Date) -> Void)?
        private var tracker = OpenAICompatTemporaryShim.ResponseDeadlineTracker()
        private var firstResponseDeadlineWorkItem: DispatchWorkItem?
        private var bufferedResponseDeadlineWorkItem: DispatchWorkItem?
        private var interChunkDeadlineWorkItem: DispatchWorkItem?
        private var interChunkReadSeconds: TimeInterval?
        private let startedAt = Date()
        private var firstPayloadAt: Date?
        private var negotiatedApplicationProtocol: String?

        init(onDataReceived: ((Data, Date) -> Void)? = nil) {
            self.onDataReceived = onDataReceived
        }

        func installDeadlines(
            firstResponseSeconds: TimeInterval?,
            bufferedResponseSeconds: TimeInterval?,
            interChunkReadSeconds: TimeInterval? = nil,
            for task: URLSessionTask
        ) {
            if let firstResponseSeconds, firstResponseSeconds > 0 {
                let workItem = DispatchWorkItem { [weak self, weak task] in
                    guard let self else { return }
                    let shouldCancel = self.stateQueue.sync { () -> Bool in
                        self.tracker.firstResponseDeadlineDidFire()
                    }
                    if shouldCancel {
                        task?.cancel()
                    }
                }

                stateQueue.sync {
                    firstResponseDeadlineWorkItem = workItem
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + firstResponseSeconds, execute: workItem)
            }

            if let bufferedResponseSeconds, bufferedResponseSeconds > 0 {
                let workItem = DispatchWorkItem { [weak self, weak task] in
                    guard let self else { return }
                    let shouldCancel = self.stateQueue.sync { () -> Bool in
                        self.tracker.bufferedResponseDeadlineDidFire()
                    }
                    if shouldCancel {
                        task?.cancel()
                    }
                }

                stateQueue.sync {
                    bufferedResponseDeadlineWorkItem = workItem
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + bufferedResponseSeconds, execute: workItem)
            }

            if let interChunkReadSeconds, interChunkReadSeconds > 0 {
                stateQueue.sync {
                    self.interChunkReadSeconds = interChunkReadSeconds
                }
            }
        }

        func finish() {
            stateQueue.sync {
                tracker.finish()
                firstResponseDeadlineWorkItem?.cancel()
                bufferedResponseDeadlineWorkItem?.cancel()
                interChunkDeadlineWorkItem?.cancel()
                firstResponseDeadlineWorkItem = nil
                bufferedResponseDeadlineWorkItem = nil
                interChunkDeadlineWorkItem = nil
                interChunkReadSeconds = nil
            }
        }

        func didExceedDeadline() -> Bool {
            stateQueue.sync { tracker.deadlineExceeded }
        }

        func currentDeadlineStage() -> OpenAICompatTemporaryShim.DeadlineStage {
            stateQueue.sync { tracker.deadlineStage }
        }

        func hasReceivedPayload() -> Bool {
            stateQueue.sync { firstPayloadAt != nil }
        }

        func firstByteLatencyMilliseconds() -> Int? {
            stateQueue.sync {
                guard let firstPayloadAt else { return nil }
                return Int(firstPayloadAt.timeIntervalSince(startedAt) * 1000)
            }
        }

        func totalLatencyMilliseconds() -> Int {
            stateQueue.sync {
                Int(Date().timeIntervalSince(startedAt) * 1000)
            }
        }

        func negotiatedProtocolName() -> String? {
            stateQueue.sync { negotiatedApplicationProtocol }
        }

        private func markPayloadReceived() {
            stateQueue.sync {
                if firstPayloadAt == nil {
                    firstPayloadAt = Date()
                }
                tracker.payloadReceived()
                firstResponseDeadlineWorkItem?.cancel()
                firstResponseDeadlineWorkItem = nil
            }
        }

        func resetInterChunkDeadline(
            seconds: TimeInterval?,
            for task: URLSessionTask
        ) {
            guard let seconds, seconds > 0 else { return }
            let workItem = DispatchWorkItem { [weak self, weak task] in
                guard let self else { return }
                let shouldCancel = self.stateQueue.sync { () -> Bool in
                    self.tracker.interChunkReadDeadlineDidFire()
                }
                if shouldCancel {
                    task?.cancel()
                }
            }
            stateQueue.sync {
                interChunkDeadlineWorkItem?.cancel()
                interChunkDeadlineWorkItem = workItem
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds, execute: workItem)
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !data.isEmpty else { return }
            markPayloadReceived()
            let seconds = stateQueue.sync { interChunkReadSeconds }
            resetInterChunkDeadline(seconds: seconds, for: dataTask)
            onDataReceived?(data, Date())
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            let negotiatedProtocol = metrics.transactionMetrics
                .compactMap(\.networkProtocolName)
                .last
            stateQueue.sync {
                negotiatedApplicationProtocol = negotiatedProtocol
            }
        }
    }

    private static let proxiedPoolQueue = DispatchQueue(label: "io.automaze.vibeproxy.proxied-session-pool")
    private static var proxiedSessionPool: [String: (session: URLSession, delegate: MultiplexedSessionDelegate, lastUsed: Date)] = [:]
    private static let proxiedPoolMaxSize = 8
    private static let proxiedPoolIdleEviction: TimeInterval = 300
    private static let bufferedBackendPoolQueue = DispatchQueue(label: "io.automaze.vibeproxy.buffered-backend-session-pool")
    private static var bufferedBackendSessionPool: [String: (session: URLSession, delegate: MultiplexedSessionDelegate, lastUsed: Date)] = [:]
    private static let bufferedBackendPoolMaxSize = 2
    private static let bufferedBackendPoolIdleEviction: TimeInterval = 300

    private final class TaskIdHolder: @unchecked Sendable {
        var taskIdentifier: Int = 0
    }

    private final class MultiplexedSessionDelegate: NSObject, URLSessionDataDelegate {
        private let lock = NSLock()
        private var delegates: [Int: ResponseProgressDelegate] = [:]

        func register(task: URLSessionTask, delegate: ResponseProgressDelegate) {
            lock.lock()
            delegates[task.taskIdentifier] = delegate
            lock.unlock()
        }

        func unregister(taskIdentifier: Int) -> ResponseProgressDelegate? {
            lock.lock()
            let delegate = delegates.removeValue(forKey: taskIdentifier)
            lock.unlock()
            return delegate
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            lock.lock()
            let delegate = delegates[dataTask.taskIdentifier]
            lock.unlock()
            delegate?.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
                ?? completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard !data.isEmpty else { return }
            lock.lock()
            let delegate = delegates[dataTask.taskIdentifier]
            lock.unlock()
            delegate?.urlSession(session, dataTask: dataTask, didReceive: data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
            lock.lock()
            let delegate = delegates[task.taskIdentifier]
            lock.unlock()
            delegate?.urlSession(session, task: task, didFinishCollecting: metrics)
        }
    }

    private static func bufferedBackendSessionPoolKey(targetHost: String, targetPort: UInt16) -> String {
        "\(targetHost):\(targetPort)"
    }

    private static func acquireBufferedBackendSession(
        targetHost: String,
        targetPort: UInt16
    ) -> (URLSession, MultiplexedSessionDelegate) {
        bufferedBackendPoolQueue.sync {
            evictIdleBufferedBackendSessionsLocked()
            let poolKey = bufferedBackendSessionPoolKey(targetHost: targetHost, targetPort: targetPort)
            if let existing = bufferedBackendSessionPool[poolKey] {
                bufferedBackendSessionPool[poolKey] = (existing.session, existing.delegate, lastUsed: Date())
                return (existing.session, existing.delegate)
            }

            let configuration = URLSessionConfiguration.ephemeral
            let delegate = MultiplexedSessionDelegate()
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

            if bufferedBackendSessionPool.count >= bufferedBackendPoolMaxSize,
               let oldestKey = bufferedBackendSessionPool.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
                bufferedBackendSessionPool[oldestKey]?.session.finishTasksAndInvalidate()
                bufferedBackendSessionPool.removeValue(forKey: oldestKey)
            }

            bufferedBackendSessionPool[poolKey] = (session, delegate, lastUsed: Date())
            return (session, delegate)
        }
    }

    private static func evictIdleBufferedBackendSessionsLocked() {
        let now = Date()
        let stale = bufferedBackendSessionPool.filter { now.timeIntervalSince($0.value.lastUsed) > bufferedBackendPoolIdleEviction }
        for (key, entry) in stale {
            entry.session.finishTasksAndInvalidate()
            bufferedBackendSessionPool.removeValue(forKey: key)
        }
    }

    static func clearBufferedBackendSessionPoolForTesting() {
        bufferedBackendPoolQueue.sync {
            for (_, entry) in bufferedBackendSessionPool {
                entry.session.finishTasksAndInvalidate()
            }
            bufferedBackendSessionPool = [:]
        }
    }

    static func acquireBufferedBackendSessionForTesting(targetHost: String, targetPort: UInt16) -> URLSession {
        acquireBufferedBackendSession(targetHost: targetHost, targetPort: targetPort).0
    }

    private static func acquireProxiedSession(proxyURL: String) -> (URLSession, MultiplexedSessionDelegate)? {
        proxiedPoolQueue.sync {
            evictIdleSessionsLocked()

            if let existing = proxiedSessionPool[proxyURL] {
                proxiedSessionPool[proxyURL] = (existing.session, existing.delegate, lastUsed: Date())
                return (existing.session, existing.delegate)
            }

            guard let proxyComponents = URLComponents(string: proxyURL),
                  let proxyHost = proxyComponents.host,
                  let proxyPort = proxyComponents.port else {
                return nil
            }

            let configuration = URLSessionConfiguration.ephemeral
            var proxyDict: [AnyHashable: Any] = [
                kCFStreamPropertySOCKSProxyHost as String: proxyHost,
                kCFStreamPropertySOCKSProxyPort as String: proxyPort,
                kCFStreamPropertySOCKSVersion as String: kCFStreamSocketSOCKSVersion5 as String
            ]
            if let user = proxyComponents.user, !user.isEmpty {
                proxyDict[kCFStreamPropertySOCKSUser as String] = user
            }
            if let password = proxyComponents.password, !password.isEmpty {
                proxyDict[kCFStreamPropertySOCKSPassword as String] = password
            }
            configuration.connectionProxyDictionary = proxyDict

            let delegate = MultiplexedSessionDelegate()
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)

            if proxiedSessionPool.count >= proxiedPoolMaxSize {
                if let oldestKey = proxiedSessionPool.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
                    proxiedSessionPool[oldestKey]?.session.finishTasksAndInvalidate()
                    proxiedSessionPool.removeValue(forKey: oldestKey)
                }
            }

            proxiedSessionPool[proxyURL] = (session, delegate, lastUsed: Date())
            return (session, delegate)
        }
    }

    private static func evictIdleSessionsLocked() {
        let now = Date()
        let stale = proxiedSessionPool.filter { now.timeIntervalSince($0.value.lastUsed) > proxiedPoolIdleEviction }
        for (key, entry) in stale {
            entry.session.finishTasksAndInvalidate()
            proxiedSessionPool.removeValue(forKey: key)
        }
    }

    static func clearProxiedSessionPoolForTesting() {
        proxiedPoolQueue.sync {
            for (_, entry) in proxiedSessionPool {
                entry.session.finishTasksAndInvalidate()
            }
            proxiedSessionPool = [:]
        }
    }

    static func acquireProxiedSessionForTesting(proxyURL: String) -> URLSession? {
        acquireProxiedSession(proxyURL: proxyURL)?.0
    }

    private static let nvidiaDirectTransportPolicy = NVIDIATransportPolicy.direct

    static func nvidiaDirectTransportPolicyForTesting() -> NVIDIATransportPolicy {
        nvidiaDirectTransportPolicy
    }

    private func effectiveNVIDIADirectTransportPolicy() -> NVIDIATransportPolicy {
        nvidiaDirectTransportPolicyOverrideForTesting ?? Self.nvidiaDirectTransportPolicy
    }

    private var effectiveNVIDIADirectTargetHost: String {
        nvidiaDirectTargetHostOverrideForTesting ?? targetHost
    }

    private var effectiveNVIDIADirectTargetPort: UInt16 {
        nvidiaDirectTargetPortOverrideForTesting ?? targetPort
    }

    private static let nvidiaDirectTransportRuntimeOwner = "nvidia_direct_http11_transport"

    enum NVIDIAHTTP1BodyMode: Equatable {
        case contentLength(Int)
        case chunked
        case untilConnectionClose
    }

    struct NVIDIAHTTP1ParsedHead: Equatable {
        let statusCode: Int
        let httpVersion: String
        let headerFields: [String: String]
        let bodyMode: NVIDIAHTTP1BodyMode
        let consumedBytes: Int

        var negotiatedApplicationProtocol: String {
            httpVersion.lowercased()
        }
    }

    enum NVIDIAHTTP1ParserError: Error {
        case invalidResponseHead
        case unsupportedHTTPVersion(String)
        case invalidChunkFraming
        case incompleteResponseBody
    }

    static func parseNVIDIAHTTP1ResponseHeadForTesting(_ data: Data) throws -> NVIDIAHTTP1ParsedHead {
        try parseNVIDIAHTTP1ResponseHead(from: data)
    }

    static func consumeNVIDIAHTTP1ChunkedBodyForTesting(_ data: Data) throws -> [Data] {
        var buffer = data
        var currentChunkSize: Int?
        var awaitingTrailers = false
        let result = try consumeNVIDIAHTTP1ChunkedBody(
            buffer: &buffer,
            currentChunkSize: &currentChunkSize,
            awaitingTrailers: &awaitingTrailers
        )
        guard result.completed, buffer.isEmpty else {
            throw NVIDIAHTTP1ParserError.incompleteResponseBody
        }
        return result.chunks
    }

    private static func parseNVIDIAHTTP1ResponseHead(from data: Data) throws -> NVIDIAHTTP1ParsedHead {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            throw NVIDIAHTTP1ParserError.invalidResponseHead
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first, !statusLine.isEmpty else {
            throw NVIDIAHTTP1ParserError.invalidResponseHead
        }

        let statusParts = statusLine.split(separator: " ", omittingEmptySubsequences: true)
        guard statusParts.count >= 2,
              let statusCode = Int(statusParts[1]) else {
            throw NVIDIAHTTP1ParserError.invalidResponseHead
        }

        let httpVersion = String(statusParts[0])
        guard httpVersion.uppercased() == "HTTP/1.1" else {
            throw NVIDIAHTTP1ParserError.unsupportedHTTPVersion(httpVersion)
        }

        var headerFields: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let existing = headerFields[name], !existing.isEmpty {
                headerFields[name] = "\(existing), \(value)"
            } else {
                headerFields[name] = value
            }
        }

        let bodyMode: NVIDIAHTTP1BodyMode
        if let transferEncoding = headerFields.first(where: { $0.key.caseInsensitiveCompare("Transfer-Encoding") == .orderedSame })?.value,
           transferEncoding.lowercased().contains("chunked") {
            bodyMode = .chunked
        } else if let contentLengthString = headerFields.first(where: { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame })?.value,
                  let contentLength = Int(contentLengthString) {
            bodyMode = .contentLength(max(0, contentLength))
        } else {
            bodyMode = .untilConnectionClose
        }

        return NVIDIAHTTP1ParsedHead(
            statusCode: statusCode,
            httpVersion: httpVersion,
            headerFields: headerFields,
            bodyMode: bodyMode,
            consumedBytes: headerRange.upperBound
        )
    }

    private static func consumeNVIDIAHTTP1ChunkedBody(
        buffer: inout Data,
        currentChunkSize: inout Int?,
        awaitingTrailers: inout Bool
    ) throws -> (chunks: [Data], completed: Bool) {
        let crlf = Data("\r\n".utf8)
        let doubleCRLF = Data("\r\n\r\n".utf8)
        var emitted: [Data] = []

        while true {
            if awaitingTrailers {
                if buffer.starts(with: crlf) {
                    buffer.removeSubrange(0..<crlf.count)
                    return (emitted, true)
                }
                if let trailerRange = buffer.range(of: doubleCRLF) {
                    buffer.removeSubrange(0..<trailerRange.upperBound)
                    return (emitted, true)
                }
                return (emitted, false)
            }

            if currentChunkSize == nil {
                guard let lineRange = buffer.range(of: crlf) else {
                    return (emitted, false)
                }
                let lineData = buffer[..<lineRange.lowerBound]
                guard let line = String(data: lineData, encoding: .utf8) else {
                    throw NVIDIAHTTP1ParserError.invalidChunkFraming
                }
                let sizeText = line
                    .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard let parsedSize = Int(sizeText, radix: 16) else {
                    throw NVIDIAHTTP1ParserError.invalidChunkFraming
                }
                buffer.removeSubrange(0..<lineRange.upperBound)
                if parsedSize == 0 {
                    awaitingTrailers = true
                    continue
                }
                currentChunkSize = parsedSize
            }

            guard let chunkSize = currentChunkSize else {
                continue
            }
            guard buffer.count >= chunkSize + crlf.count else {
                return (emitted, false)
            }

            let chunk = Data(buffer.prefix(chunkSize))
            let trailingCRLFRange = chunkSize..<(chunkSize + crlf.count)
            guard Data(buffer[trailingCRLFRange]) == crlf else {
                throw NVIDIAHTTP1ParserError.invalidChunkFraming
            }
            emitted.append(chunk)
            buffer.removeSubrange(0..<(chunkSize + crlf.count))
            currentChunkSize = nil
        }
    }

    private final class NVIDIAHTTP1TransportAttempt {
        private let request: URLRequest
        private let host: String
        private let port: UInt16
        private let policy: NVIDIATransportPolicy
        private let firstResponseSeconds: TimeInterval?
        private let bufferedResponseSeconds: TimeInterval?
        private let onChunk: (Data, Date) -> Void
        private let completion: (NVIDIADirectTransportResponse) -> Void

        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-http11-transport")
        private var connection: NWConnection?
        private var tracker = OpenAICompatTemporaryShim.ResponseDeadlineTracker()
        private var firstResponseDeadlineWorkItem: DispatchWorkItem?
        private var bufferedResponseDeadlineWorkItem: DispatchWorkItem?
        private var completed = false
        private var startedAt = Date()
        private var firstPayloadAt: Date?
        private var rawBuffer = Data()
        private var responseChunks: [Data] = []
        private var responseHead: NVIDIAHTTP1ParsedHead?
        private var remainingContentLength: Int?
        private var currentChunkSize: Int?
        private var awaitingChunkTrailers = false

        init(
            request: URLRequest,
            host: String,
            port: UInt16,
            policy: NVIDIATransportPolicy,
            firstResponseSeconds: TimeInterval?,
            bufferedResponseSeconds: TimeInterval?,
            onChunk: @escaping (Data, Date) -> Void,
            completion: @escaping (NVIDIADirectTransportResponse) -> Void
        ) {
            self.request = request
            self.host = host
            self.port = port
            self.policy = policy
            self.firstResponseSeconds = firstResponseSeconds
            self.bufferedResponseSeconds = bufferedResponseSeconds
            self.onChunk = onChunk
            self.completion = completion
        }

        func start() -> (() -> Void)? {
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                return nil
            }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            stateQueue.sync {
                self.connection = connection
                self.startedAt = Date()
                self.scheduleFirstResponseDeadlineLocked()
                self.scheduleBufferedResponseDeadlineLocked()
            }
            connection.stateUpdateHandler = { [weak self] state in
                self?.handleConnectionState(state)
            }
            connection.start(queue: .global(qos: .userInitiated))
            return { [weak self] in
                self?.cancel()
            }
        }

        private func handleConnectionState(_ state: NWConnection.State) {
            switch state {
            case .ready:
                sendRequest()
            case .failed(let error):
                finish(response: nil, error: error, negotiatedApplicationProtocol: nil)
            case .cancelled:
                finish(response: nil, error: URLError(.cancelled), negotiatedApplicationProtocol: nil)
            default:
                break
            }
        }

        private func sendRequest() {
            guard let requestData = buildHTTPRequestData() else {
                finish(response: nil, error: URLError(.badURL), negotiatedApplicationProtocol: nil)
                return
            }

            connection?.send(content: requestData, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    self.finish(response: nil, error: error, negotiatedApplicationProtocol: nil)
                    return
                }
                self.receiveNextChunk()
            })
        }

        private func buildHTTPRequestData() -> Data? {
            guard let url = request.url else { return nil }
            let path = {
                let path = url.path.isEmpty ? "/" : url.path
                if let query = url.query, !query.isEmpty {
                    return "\(path)?\(query)"
                }
                return path
            }()

            var requestText = "\(request.httpMethod ?? "POST") \(path) HTTP/1.1\r\n"
            let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
            for (name, value) in request.allHTTPHeaderFields ?? [:] where !excludedHeaders.contains(name.lowercased()) {
                requestText += "\(name): \(value)\r\n"
            }
            requestText += "Host: \(host):\(port)\r\n"
            requestText += "Connection: close\r\n"

            let body = request.httpBody ?? Data()
            requestText += "Content-Length: \(body.count)\r\n"
            requestText += "\r\n"

            var requestData = Data(requestText.utf8)
            requestData.append(body)
            return requestData
        }

        private func receiveNextChunk() {
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let error {
                    self.finish(response: nil, error: error, negotiatedApplicationProtocol: nil)
                    return
                }

                let receivedAt = Date()
                var emittedChunks: [Data] = []
                var finalResponse: HTTPURLResponse?
                var finalError: Error?
                var finalProtocol: String?
                var shouldContinue = false

                stateQueue.sync {
                    guard !self.completed else { return }

                    if let data, !data.isEmpty {
                        self.rawBuffer.append(data)
                    }

                    do {
                        let processResult = try self.processBufferLocked(receivedAt: receivedAt, connectionIsComplete: isComplete)
                        emittedChunks = processResult.emittedChunks
                        finalResponse = processResult.finalResponse
                        finalError = processResult.finalError
                        finalProtocol = processResult.negotiatedApplicationProtocol
                        shouldContinue = processResult.shouldContinue
                    } catch {
                        finalError = error
                        finalProtocol = self.responseHead?.negotiatedApplicationProtocol
                    }
                }

                for chunk in emittedChunks {
                    self.onChunk(chunk, receivedAt)
                }

                if finalResponse != nil || finalError != nil {
                    self.finish(response: finalResponse, error: finalError, negotiatedApplicationProtocol: finalProtocol)
                    return
                }

                if shouldContinue {
                    self.receiveNextChunk()
                    return
                }

                if isComplete {
                    self.finish(response: finalResponse, error: NVIDIAHTTP1ParserError.incompleteResponseBody, negotiatedApplicationProtocol: finalProtocol)
                }
            }
        }

        private func processBufferLocked(
            receivedAt: Date,
            connectionIsComplete: Bool
        ) throws -> (
            emittedChunks: [Data],
            finalResponse: HTTPURLResponse?,
            finalError: Error?,
            negotiatedApplicationProtocol: String?,
            shouldContinue: Bool
        ) {
            if responseHead == nil {
                do {
                    let parsedHead = try ThinkingProxy.parseNVIDIAHTTP1ResponseHead(from: rawBuffer)
                    responseHead = parsedHead
                    rawBuffer.removeSubrange(0..<parsedHead.consumedBytes)
                    if case .contentLength(let contentLength) = parsedHead.bodyMode {
                        remainingContentLength = contentLength
                    }
                } catch NVIDIAHTTP1ParserError.invalidResponseHead {
                    return (
                        emittedChunks: [],
                        finalResponse: nil,
                        finalError: connectionIsComplete ? NVIDIAHTTP1ParserError.invalidResponseHead : nil,
                        negotiatedApplicationProtocol: nil,
                        shouldContinue: !connectionIsComplete
                    )
                }
            }

            guard let responseHead else {
                return (
                    emittedChunks: [],
                    finalResponse: nil,
                    finalError: nil,
                    negotiatedApplicationProtocol: nil,
                    shouldContinue: !connectionIsComplete
                )
            }

            var emittedChunks: [Data] = []
            var bodyComplete = false

            switch responseHead.bodyMode {
            case .contentLength:
                if let remaining = remainingContentLength, remaining > 0, !rawBuffer.isEmpty {
                    let take = min(remaining, rawBuffer.count)
                    let chunk = Data(rawBuffer.prefix(take))
                    rawBuffer.removeSubrange(0..<take)
                    remainingContentLength = remaining - take
                    if !chunk.isEmpty {
                        recordPayloadReceivedLocked(at: receivedAt)
                        responseChunks.append(chunk)
                        emittedChunks.append(chunk)
                    }
                }
                bodyComplete = (remainingContentLength ?? 0) == 0
            case .chunked:
                let chunkedResult = try ThinkingProxy.consumeNVIDIAHTTP1ChunkedBody(
                    buffer: &rawBuffer,
                    currentChunkSize: &currentChunkSize,
                    awaitingTrailers: &awaitingChunkTrailers
                )
                if !chunkedResult.chunks.isEmpty {
                    recordPayloadReceivedLocked(at: receivedAt)
                    responseChunks.append(contentsOf: chunkedResult.chunks)
                    emittedChunks.append(contentsOf: chunkedResult.chunks)
                }
                bodyComplete = chunkedResult.completed
            case .untilConnectionClose:
                if !rawBuffer.isEmpty {
                    let chunk = rawBuffer
                    rawBuffer.removeAll(keepingCapacity: true)
                    recordPayloadReceivedLocked(at: receivedAt)
                    responseChunks.append(chunk)
                    emittedChunks.append(chunk)
                }
                bodyComplete = connectionIsComplete
            }

            if bodyComplete {
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "http://\(host):\(port)/")!,
                    statusCode: responseHead.statusCode,
                    httpVersion: responseHead.httpVersion,
                    headerFields: responseHead.headerFields
                )
                return (
                    emittedChunks: emittedChunks,
                    finalResponse: response,
                    finalError: nil,
                    negotiatedApplicationProtocol: responseHead.negotiatedApplicationProtocol,
                    shouldContinue: false
                )
            }

            return (
                emittedChunks: emittedChunks,
                finalResponse: nil,
                finalError: nil,
                negotiatedApplicationProtocol: responseHead.negotiatedApplicationProtocol,
                shouldContinue: !connectionIsComplete
            )
        }

        private func recordPayloadReceivedLocked(at receivedAt: Date) {
            if firstPayloadAt == nil {
                firstPayloadAt = receivedAt
            }
            tracker.payloadReceived()
            firstResponseDeadlineWorkItem?.cancel()
            firstResponseDeadlineWorkItem = nil
        }

        private func scheduleFirstResponseDeadlineLocked() {
            guard let firstResponseSeconds, firstResponseSeconds > 0 else { return }
            let workItem = DispatchWorkItem { [weak self] in
                self?.fireFirstResponseDeadline()
            }
            firstResponseDeadlineWorkItem?.cancel()
            firstResponseDeadlineWorkItem = workItem
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + firstResponseSeconds, execute: workItem)
        }

        private func scheduleBufferedResponseDeadlineLocked() {
            guard let bufferedResponseSeconds, bufferedResponseSeconds > 0 else { return }
            let workItem = DispatchWorkItem { [weak self] in
                self?.fireBufferedResponseDeadline()
            }
            bufferedResponseDeadlineWorkItem?.cancel()
            bufferedResponseDeadlineWorkItem = workItem
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + bufferedResponseSeconds, execute: workItem)
        }

        private func fireFirstResponseDeadline() {
            let shouldFinish = stateQueue.sync { tracker.firstResponseDeadlineDidFire() && !completed }
            guard shouldFinish else { return }
            connection?.cancel()
            finish(response: nil, error: URLError(.timedOut), negotiatedApplicationProtocol: responseHead?.negotiatedApplicationProtocol)
        }

        private func fireBufferedResponseDeadline() {
            let shouldFinish = stateQueue.sync { tracker.bufferedResponseDeadlineDidFire() && !completed }
            guard shouldFinish else { return }
            connection?.cancel()
            let response = stateQueue.sync {
                responseHead.flatMap {
                    HTTPURLResponse(
                        url: request.url ?? URL(string: "http://\(host):\(port)/")!,
                        statusCode: $0.statusCode,
                        httpVersion: $0.httpVersion,
                        headerFields: $0.headerFields
                    )
                }
            }
            finish(response: response, error: URLError(.timedOut), negotiatedApplicationProtocol: responseHead?.negotiatedApplicationProtocol)
        }

        private func cancel() {
            connection?.cancel()
            finish(response: nil, error: URLError(.cancelled), negotiatedApplicationProtocol: responseHead?.negotiatedApplicationProtocol)
        }

        private func finish(
            response: HTTPURLResponse?,
            error: Error?,
            negotiatedApplicationProtocol: String?
        ) {
            let result: NVIDIADirectTransportResponse? = stateQueue.sync {
                guard !completed else { return nil }
                completed = true
                firstResponseDeadlineWorkItem?.cancel()
                firstResponseDeadlineWorkItem = nil
                bufferedResponseDeadlineWorkItem?.cancel()
                bufferedResponseDeadlineWorkItem = nil
                tracker.finish()
                return NVIDIADirectTransportResponse(
                    chunks: responseChunks,
                    response: response,
                    error: error,
                    firstByteLatencyMilliseconds: firstPayloadAt.map { Int($0.timeIntervalSince(startedAt) * 1000) },
                    totalLatencyMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000),
                    deadlineStage: tracker.deadlineStage,
                    negotiatedApplicationProtocol: negotiatedApplicationProtocol
                )
            }
            if let result {
                completion(result)
            }
        }
    }

    func setIsRunningForTesting(_ value: Bool) {
        stateQueue.sync { isRunning = value }
    }

    /**
     Starts the thinking proxy server on port 8317
     */
    func start() {
        guard !isRunning else {
            NSLog("[ThinkingProxy] Already running")
            return
        }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            guard let port = NWEndpoint.Port(rawValue: proxyPort) else {
                NSLog("[ThinkingProxy] Invalid port: %d", proxyPort)
                return
            }
            listener = try NWListener(using: parameters, on: port)
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async {
                        self?.isRunning = true
                    }
                    NSLog("[ThinkingProxy] Listening on port \(self?.proxyPort ?? 0)")
                case .failed(let error):
                    NSLog("[ThinkingProxy] Failed: \(error)")
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                case .cancelled:
                    NSLog("[ThinkingProxy] Cancelled")
                    DispatchQueue.main.async {
                        self?.isRunning = false
                    }
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .global(qos: .userInitiated))
            startCanaryLoop()
            startMaintenanceLoop()
            
        } catch {
            NSLog("[ThinkingProxy] Failed to start: \(error)")
        }
    }
    
    /**
     Stops the thinking proxy server
     */
    func stop() {
        stateQueue.sync {
            guard isRunning else { return }

            listener?.cancel()
            listener = nil
            stopCanaryLoopLocked()
            stopMaintenanceLoopLocked()
            isRunning = false
            OpenAICompatTemporaryShim.resetConcurrencyRegistryForTesting()
            Self.clearProxiedSessionPoolForTesting()
            nvidiaInflightQueue.sync {
                nvidiaRaceWaiters.removeAll()
                inflightCoalescedRequests.removeAll()
                recentCoalescedReplays.removeAll()
            }
            NSLog("[ThinkingProxy] Stopped")
        }
    }

    func processRequestForTesting(_ rawHTTPRequest: String, connection: NWConnection) {
        processRequest(data: Data(rawHTTPRequest.utf8), connection: connection)
    }
    
    /**
     Handles an incoming connection from a client
     */
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(from: connection)
    }
    
    /**
     Receives the HTTP request from the client
     Accumulates data until full request is received (handles large payloads)
     */
    private func receiveRequest(from connection: NWConnection, accumulatedData: Data = Data()) {
        // Start the iterative receive loop
        receiveNextChunk(from: connection, accumulatedData: accumulatedData)
    }
    
    /**
     Receives request data iteratively (uses async scheduling instead of recursion to avoid stack buildup)
     */
    private func receiveNextChunk(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive error: \(error)")
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            var newAccumulatedData = accumulatedData
            newAccumulatedData.append(data)
            
            // Check if we have a complete HTTP request
            if let requestString = String(data: newAccumulatedData, encoding: .utf8),
               let headerEndRange = requestString.range(of: "\r\n\r\n") {
                
                // Extract Content-Length if present
                let headerEndIndex = requestString.distance(from: requestString.startIndex, to: headerEndRange.upperBound)
                let headerPart = String(requestString.prefix(headerEndIndex))
                
                if let contentLengthLine = headerPart.components(separatedBy: "\r\n").first(where: { $0.lowercased().starts(with: "content-length:") }) {
                    let contentLengthStr = contentLengthLine.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)
                    if let contentLength = Int(contentLengthStr) {
                        let bodyStartIndex = headerEndIndex
                        let currentBodyLength = newAccumulatedData.count - bodyStartIndex
                        
                        // If we haven't received the full body yet, schedule next iteration
                        if currentBodyLength < contentLength {
                            self.receiveNextChunk(from: connection, accumulatedData: newAccumulatedData)
                            return
                        }
                    }
                }
                
                // We have a complete request, process it
                self.processRequest(data: newAccumulatedData, connection: connection)
            } else if !isComplete {
                // Haven't found header end yet, schedule next iteration
                self.receiveNextChunk(from: connection, accumulatedData: newAccumulatedData)
            } else {
                // Complete but malformed, process what we have
                self.processRequest(data: newAccumulatedData, connection: connection)
            }
        }
    }
    
    /**
     Processes the HTTP request, modifies it if needed, and forwards to CLIProxyAPI
     */
    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendError(to: connection, statusCode: 400, message: "Invalid request")
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(to: connection, statusCode: 400, message: "Invalid request line")
            return
        }
        
        // Extract method, path, and HTTP version
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 3 else {
            sendError(to: connection, statusCode: 400, message: "Invalid request format")
            return
        }
        
        let method = parts[0]
        let path = parts[1]
        let httpVersion = parts[2]

        // Collect headers while preserving original casing
        var headers: [(String, String)] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = line.index(after: separatorIndex)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            headers.append((name, value))
        }
        
        // Find the body start
        guard let bodyStartRange = requestString.range(of: "\r\n\r\n") else {
            NSLog("[ThinkingProxy] Error: Could not find body separator in request")
            sendError(to: connection, statusCode: 400, message: "Invalid request format - no body separator")
            return
        }
        
        let bodyStart = requestString.distance(from: requestString.startIndex, to: bodyStartRange.upperBound)
        let bodyString = String(requestString[requestString.index(requestString.startIndex, offsetBy: bodyStart)...])
        let requestTrace = requestTraceContext(
            method: method,
            path: path,
            headers: headers,
            body: bodyString
        )
        NSLog("[ThinkingProxy] Incoming request [%@]: %@ %@", requestTrace.proxyRequestID, method, path)
        
        // Redirect Amp CLI login directly to ampcode.com to preserve auth state cookies
        if path.starts(with: "/auth/cli-login") || path.starts(with: "/api/auth/cli-login") {
            let loginPath = path.hasPrefix("/api/") ? String(path.dropFirst(4)) : path
            let redirectUrl = "https://ampcode.com" + loginPath
            NSLog("[ThinkingProxy] Redirecting Amp CLI login to: \(redirectUrl)")
            sendRedirect(to: connection, location: redirectUrl)
            return
        }

        if method == "GET" && (path == "/healthz" || path == "/api/healthz") {
            sendHealthResponse(to: connection)
            return
        }

        // Rewrite Amp CLI paths
        var rewrittenPath = path
        if path.starts(with: "/provider/") {
            // Rewrite /provider/* to /api/provider/*
            rewrittenPath = "/api" + path
            NSLog("[ThinkingProxy] Rewriting Amp provider path: \(path) -> \(rewrittenPath)")
        }
        
        // Check if this is an Amp management request (anything not targeting provider or /v1)
        // Note: /provider/ paths are already rewritten to /api/provider/ above
        let isProviderPath = rewrittenPath.starts(with: "/api/provider/")
        let isCliProxyPath = rewrittenPath.starts(with: "/v1/") || rewrittenPath.starts(with: "/api/v1/")
        if !isProviderPath && !isCliProxyPath {
            let ampPath = rewrittenPath
            NSLog("[ThinkingProxy] Amp management request detected, forwarding to ampcode.com: \(ampPath)")
            forwardToAmp(method: method, path: ampPath, version: httpVersion, headers: headers, body: bodyString, originalConnection: connection)
            return
        }

        if method == "GET" && (rewrittenPath == "/v1/models" || rewrittenPath == "/api/v1/models") {
            forwardModelListRequest(
                method: method,
                path: rewrittenPath,
                headers: headers,
                originalConnection: connection
            )
            return
        }
        
        // Try to parse and modify JSON body for POST requests
        var modifiedBody = bodyString
        var thinkingEnabled = false
        var coalescingSourceBody = bodyString
        let callerVisibleRequestedModel = OpenAICompatTemporaryShim.rawModelName(forRequestJSON: bodyString)
        var factoryModelBinding = callerVisibleRequestedModel.flatMap { Self.factoryModelBinding(forIncomingModelID: $0) }
            ?? callerVisibleRequestedModel.flatMap { model in
                OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: model) == nil
                    ? Self.factoryModelBindingByRouteModel(forRouteModel: model)
                    : nil
            }

        // Telemetry: log model resolution path for factory-bound requests
        if let binding = factoryModelBinding, let incoming = callerVisibleRequestedModel {
            NSLog("[ModelResolution] incoming=%@ → routeModel=%@ provider=%@ source=%@", incoming, binding.routeModel, binding.routeProvider, binding.source)
        }
        
        if method == "POST" && !bodyString.isEmpty {
            if let result = processThinkingParameter(jsonString: bodyString) {
                modifiedBody = result.0
                thinkingEnabled = result.1
            }
            // Strip cache_control fields that cause 400 errors via the OAuth route
            if let stripped = stripCacheControl(from: modifiedBody) {
                modifiedBody = stripped
            }

            if let modelRewrite = OpenAICompatTemporaryShim.normalizedRequestModelRewrite(
                method: method,
                path: rewrittenPath,
                jsonString: modifiedBody
            ) {
                modifiedBody = modelRewrite.rewrittenJSONString
                if let binding = Self.factoryModelBinding(forIncomingModelID: modelRewrite.originalModel),
                   binding.routeModel == modelRewrite.normalizedModel {
                    factoryModelBinding = binding
                    NSLog(
                        "[ThinkingProxy] Normalized Factory model ID %@ onto %@ via %@",
                        binding.incomingModelID,
                        binding.routeModel,
                        binding.source
                    )
                }
            } else if let shimmed = OpenAICompatTemporaryShim.transformRequest(
                method: method,
                path: rewrittenPath,
                jsonString: modifiedBody
            ) {
                modifiedBody = shimmed
            }

            coalescingSourceBody = modifiedBody

            if let callerVisibleRequestedModel,
               let factoryBindingError = Self.factoryModelBindingPreflightError(forIncomingModelID: callerVisibleRequestedModel) {
                sendError(
                    to: connection,
                    statusCode: 409,
                    message: factoryBindingError
                )
                return
            }

            if let factoryModelBinding,
               let factoryBindingError = Self.factoryWorkerBindingContractError(for: factoryModelBinding) {
                sendError(
                    to: connection,
                    statusCode: 409,
                    message: factoryBindingError,
                    overridingHeaders: smartAliasResolutionHeaders(
                        publicAlias: factoryModelBinding.incomingModelID,
                        resolvedRequestModel: factoryModelBinding.routeModel
                    )
                )
                return
            }

            if let requestModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: modifiedBody),
               let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: requestModel) {
                let publicAlias = factoryModelBinding?.incomingModelID ?? requestModel
                // Preserve the caller-visible model name as the public alias for response rewriting
                // and audit headers. Even when the explicit pooled alias `glm-5.1` reuses the
                // internal `worker` pool, clients must only see the concrete public alias they
                // asked for, never the proxy-internal pool name.
                if let contractError = OpenAICompatTemporaryShim.smartAliasContractError(forRequestModel: requestModel) {
                    sendError(
                        to: connection,
                        statusCode: contractError.statusCode,
                        message: contractError.message
                    )
                    return
                }
                let clientRequestedStream = OpenAICompatTemporaryShim.requestedStream(forRequestJSON: modifiedBody)
                guard let executionPlan = smartAliasExecutionPlan(
                    path: rewrittenPath,
                    body: modifiedBody,
                    clientRequestedStream: clientRequestedStream
                ) else {
                    let message = OpenAICompatTemporaryShim.isResponsesPath(rewrittenPath)
                        ? "The \(requestModel) pooled alias only supports /v1/responses payloads that can be normalized onto chat-completions in this proxy."
                        : "The \(requestModel) pooled alias only supports /v1/chat/completions and /v1/responses requests in this proxy; use a specific model for unsupported routes."
                    sendError(
                        to: connection,
                        statusCode: 501,
                        message: message
                    )
                    return
                }
                let effectiveCandidateModels = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: requestModel,
                    method: method,
                    path: executionPlan.path,
                    jsonString: executionPlan.body,
                    smartAlias: smartAlias
                )
                let forceProbeCandidateModels = OpenAICompatTemporaryShim.forcedSmartAliasProbeCandidateModels(
                    forPublicAlias: requestModel,
                    method: method,
                    path: executionPlan.path,
                    jsonString: executionPlan.body,
                    smartAlias: smartAlias
                )

                if !clientRequestedStream,
                   smartAlias.requestClass == "plain-chat",
                   smartAlias.failover == "silent",
                   OpenAICompatTemporaryShim.isChatCompletionsPath(rewrittenPath),
                   OpenAICompatTemporaryShim.isSafePlainChatRequest(
                    method: method,
                    path: rewrittenPath,
                    jsonString: modifiedBody
                   ) {
                    let coalescingKey = coalescingKeyForSafeRequest(
                        method: method,
                        path: rewrittenPath,
                        headers: headers,
                        body: modifiedBody,
                        coalescingSourceBody: coalescingSourceBody,
                        requestedModelAlias: publicAlias
                    )
                    if let coalescingKey {
                        if replayCompletedCoalescedRequestIfAvailable(key: coalescingKey, connection: connection) {
                            NSLog("[ThinkingProxy] Replayed completed coalesced smart-alias request for %@", publicAlias)
                            return
                        }
                        if !registerOrJoinInflightRequest(key: coalescingKey, connection: connection) {
                            NSLog("[ThinkingProxy] Joined coalesced smart-alias request for %@", publicAlias)
                            return
                        }
                    }
                    forwardSmartAliasRequest(
                        method: method,
                        path: executionPlan.path,
                        headers: headers,
                        body: executionPlan.body,
                        publicAlias: publicAlias,
                        candidateModels: effectiveCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels,
                        originalConnection: connection,
                        coalescingKey: coalescingKey,
                        deliveryMode: executionPlan.deliveryMode,
                        requestTrace: requestTrace
                    )
                    return
                }

                if method == "POST" {
                    forwardSmartAliasRequest(
                        method: method,
                        path: executionPlan.path,
                        headers: headers,
                        body: executionPlan.body,
                        publicAlias: publicAlias,
                        candidateModels: effectiveCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels,
                        originalConnection: connection,
                        coalescingKey: nil,
                        deliveryMode: executionPlan.deliveryMode,
                        requestTrace: requestTrace
                    )
                    return
                }

                sendError(
                    to: connection,
                    statusCode: 501,
                    message: "The \(requestModel) pooled alias only supports /v1/chat/completions and /v1/responses requests in this proxy; use a specific model for unsupported routes."
                )
                return
            }

            if let preflightError = OpenAICompatTemporaryShim.configuredRoutePreflightError(
                method: method,
                path: rewrittenPath,
                jsonString: modifiedBody,
                headers: headers
            ) {
                if let reasonCode = preflightError.reasonCode {
                    NSLog(
                        "[ThinkingProxy] NVIDIA preflight mitigation blocked request [%@] for %@: %@ (%@)",
                        requestTrace.proxyRequestID,
                        rewrittenPath,
                        preflightError.message,
                        reasonCode
                    )
                } else {
                    NSLog(
                        "[ThinkingProxy] NVIDIA preflight mitigation blocked request [%@] for %@: %@",
                        requestTrace.proxyRequestID,
                        rewrittenPath,
                        preflightError.message
                    )
                }
                sendError(
                    to: connection,
                    statusCode: preflightError.statusCode,
                    message: preflightError.message,
                    overridingHeaders: preflightFailureHeaders(
                        for: preflightError,
                        requestTrace: requestTrace
                    )
                )
                return
            }
        }

        if method == "POST",
           let metaModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: modifiedBody),
           let metaRoute = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: metaModel),
           metaRoute.providerID == MetaAIWebAdapter.providerID {
            NSLog("[ThinkingProxy] Routing %@ via Meta AI web adapter", metaModel)
            forwardMetaAIWebRequest(
                path: rewrittenPath,
                body: modifiedBody,
                publicModel: metaModel,
                originalConnection: connection,
                requestTrace: requestTrace
            )
            return
        }

        // Direct proxied path for providers with per-provider proxy-url.
        // Must be checked before NVIDIA reasoning path to intercept proxied provider requests.
        if method == "POST",
           let directProxyModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: modifiedBody),
           let directProxyRoute = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: directProxyModel),
           let directProxyEndpoint = OpenAICompatTemporaryShim.providerEndpoint(forProviderID: directProxyRoute.providerID) {
            NSLog("[ThinkingProxy] Routing %@ directly via SOCKS5 proxy to %@", directProxyModel, directProxyEndpoint.baseURL)
            forwardDirectProxiedRequest(
                method: method,
                path: rewrittenPath,
                headers: headers,
                body: modifiedBody,
                candidateModel: directProxyModel,
                endpoint: directProxyEndpoint,
                originalConnection: connection,
                requestTrace: requestTrace
            )
            return
        }

        if method == "POST",
           let factoryModelBinding,
           let factoryBoundExecutionPlan = factoryBoundExecutionPlan(
            path: rewrittenPath,
            body: modifiedBody,
            binding: factoryModelBinding
           ) {
            // If the factory binding's route model resolves as a smart alias, the request
            // must enter the smart-alias failover path — not the single-backend factory-bound
            // path. Factory bindings for openai/xai/etc. previously bypassed failover entirely,
            // pinning requests to a dead upstream with no fallback.
            if let routeSmartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: factoryModelBinding.routeModel),
               let routeExecutionPlan = smartAliasExecutionPlan(
                path: rewrittenPath,
                body: factoryBoundExecutionPlan.body,
                clientRequestedStream: OpenAICompatTemporaryShim.requestedStream(forRequestJSON: modifiedBody)
               ) {
                let routeCandidateModels = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: factoryModelBinding.routeModel,
                    method: method,
                    path: routeExecutionPlan.path,
                    jsonString: routeExecutionPlan.body,
                    smartAlias: routeSmartAlias
                )
                let routeForceProbeModels = OpenAICompatTemporaryShim.forcedSmartAliasProbeCandidateModels(
                    forPublicAlias: factoryModelBinding.routeModel,
                    method: method,
                    path: routeExecutionPlan.path,
                    jsonString: routeExecutionPlan.body,
                    smartAlias: routeSmartAlias
                )
                NSLog("[ThinkingProxy] Factory-bound smart-alias redirect: incoming=%@ routeModel=%@ candidates=%@", factoryModelBinding.incomingModelID, factoryModelBinding.routeModel, routeCandidateModels.joined(separator: ","))
                forwardSmartAliasRequest(
                    method: method,
                    path: routeExecutionPlan.path,
                    headers: headers,
                    body: routeExecutionPlan.body,
                    publicAlias: factoryModelBinding.incomingModelID,
                    candidateModels: routeCandidateModels,
                    forceProbeCandidateModels: routeForceProbeModels,
                    originalConnection: connection,
                    coalescingKey: nil,
                    deliveryMode: routeExecutionPlan.deliveryMode,
                    requestTrace: requestTrace
                )
                return
            }

            NSLog("[ThinkingProxy] Factory-bound dispatch: model=%@ path=%@ deliveryMode=%@", factoryModelBinding.routeModel, rewrittenPath, String(describing: factoryBoundExecutionPlan.deliveryMode))
            forwardBufferedFactoryBoundRequest(
                method: method,
                path: rewrittenPath,
                headers: headers,
                body: factoryBoundExecutionPlan.body,
                binding: factoryModelBinding,
                deliveryMode: factoryBoundExecutionPlan.deliveryMode,
                originalConnection: connection,
                requestTrace: requestTrace
            )
            return
        }

        if OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
            method: method,
            path: rewrittenPath,
            jsonString: modifiedBody
        ) {
            let retryBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: modifiedBody)
            let model = OpenAICompatTemporaryShim.modelName(forRequestJSON: modifiedBody) ?? "unknown"
            let coalescingKey = coalescingKeyForSafeRequest(
                method: method,
                path: rewrittenPath,
                headers: headers,
                body: modifiedBody,
                coalescingSourceBody: coalescingSourceBody,
                requestedModelAlias: nil
            )
            if let coalescingKey {
                if replayCompletedCoalescedRequestIfAvailable(key: coalescingKey, connection: connection) {
                    NSLog("[ThinkingProxy] Replayed completed coalesced NVIDIA request for %@", model)
                    return
                }
                if !registerOrJoinInflightRequest(key: coalescingKey, connection: connection) {
                    NSLog("[ThinkingProxy] Joined coalesced NVIDIA request for %@", model)
                    return
                }
            }
            forwardNVIDIAStreamingRequest(
                    method: method,
                    path: rewrittenPath,
                    headers: headers,
                    body: modifiedBody,
                    originalConnection: connection,
                    requestTrace: requestTrace,
                    state: OpenAICompatTemporaryShim.NVIDIARetryState(
                        model: model,
                    requiredToolParameters: OpenAICompatTemporaryShim.requiredToolParametersIndex(forRequestJSON: modifiedBody),
                    initialTransportRetries: retryBudget?.transport ?? Config.nvidiaReasoningTransportRetries,
                    initialSemanticRetries: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    transportRetriesRemaining: retryBudget?.transport ?? Config.nvidiaReasoningTransportRetries,
                    semanticRetriesRemaining: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    retryBackoffMilliseconds: retryBudget?.backoffMilliseconds ?? 0,
                    salvagesBestEffortRepair: retryBudget?.salvagesBestEffortRepair ?? false,
                    bestEffortRepairedBodyData: nil,
                    coalescingKey: coalescingKey
                )
            )
            return
        }

        // Route Claude requests through Vercel AI Gateway when configured
        if vercelConfig.isActive && method == "POST" && isClaudeModelRequest(body: modifiedBody) {
            NSLog("[ThinkingProxy] Routing Claude request via Vercel AI Gateway")
            forwardToVercel(method: method, path: "/v1/messages", version: httpVersion, headers: headers, body: modifiedBody, thinkingEnabled: thinkingEnabled, originalConnection: connection)
            return
        }

        forwardRequest(method: method, path: rewrittenPath, version: httpVersion, headers: headers, body: modifiedBody, thinkingEnabled: thinkingEnabled, originalConnection: connection)
    }
    
    private func isClaudeModelRequest(body: String) -> Bool {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String else { return false }
        return model.starts(with: "claude-") || model.starts(with: "gemini-claude-")
    }

    private func forwardSmartAliasRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        publicAlias: String,
        candidateModels: [String],
        forceProbeCandidateModels: Set<String>,
        originalConnection: NWConnection,
        coalescingKey: String?,
        deliveryMode: SmartAliasDeliveryMode,
        requestTrace: RequestTraceContext
    ) {
        let requestController = RequestCancellationController()
        installClientDisconnectCancellation(on: originalConnection, controller: requestController, requestTrace: requestTrace)
        attemptSmartAliasCandidate(
            method: method,
            path: path,
            headers: headers,
            currentBody: body,
            publicAlias: publicAlias,
            remainingCandidateModels: candidateModels,
            forceProbeCandidateModels: forceProbeCandidateModels,
            primaryProbeRetriesRemaining: smartAliasForcedPrimaryRetryLimit,
            failoverDepth: 0,
            deadlineAt: Date().addingTimeInterval(smartAliasTotalTimeout(forRequestJSON: body)),
            originalConnection: originalConnection,
            coalescingKey: coalescingKey,
            terminalFallbackOutcome: nil,
            exhaustedRetryableOutcome: nil,
            deliveryMode: deliveryMode,
            loopRetriesRemaining: smartAliasLoopRetryLimitOverrideForTesting ?? smartAliasMaxLoopRetries,
            requestController: requestController,
            requestTrace: requestTrace
        )
    }

    private func forwardBufferedFactoryBoundRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        binding: FactoryModelBinding,
        deliveryMode: FactoryBoundDeliveryMode = .bufferedJSON,
        originalConnection: NWConnection,
        requestTrace: RequestTraceContext
    ) {
        let requestController = RequestCancellationController()
        installClientDisconnectCancellation(on: originalConnection, controller: requestController, requestTrace: requestTrace)
        let resolvedRequestModel = binding.routeModel
        let resolutionHeaders = smartAliasResolutionHeaders(
            publicAlias: binding.incomingModelID,
            resolvedRequestModel: resolvedRequestModel,
            requestTrace: requestTrace
        )
        let effectiveHeaders = headersInjectingRouteSpecific(headers, forCandidateModel: resolvedRequestModel)
        let timeoutInterval = smartAliasCandidateTimeout(forRequestJSON: body)

        let preservesNativeResponsesSurface =
            binding.requestSurface == "responses" && OpenAICompatTemporaryShim.isResponsesPath(path)
        let preservesQualifiedGenericChatRouteModel = binding.routeProvider == "generic-chat-completion-api"

        // Only strip reasoning-effort suffixes when bridging onto a chat-completions
        // execution core. Native responses routes own their qualified model IDs.
        let upstreamBody = Self.rewriteModelForUpstream(
            body: body,
            routeModel: binding.routeModel,
            preserveQualifiedRouteModel: preservesNativeResponsesSurface || preservesQualifiedGenericChatRouteModel
        )

        let upstreamPath = preservesNativeResponsesSurface
            ? path
            : (OpenAICompatTemporaryShim.isResponsesPath(path)
                ? OpenAICompatTemporaryShim.chatCompletionsPath(matching: path)
                : path)

        let upstreamModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: upstreamBody) ?? "?"
        NSLog("[ThinkingProxy] Factory-bound upstream: path=%@ model=%@ (binding.routeModel=%@)", upstreamPath, upstreamModel, binding.routeModel)

        // Paid subscription providers (openai) manage their own upstream rate limits;
        // skip the proxy-level concurrency gate to avoid artificial throttling.
        let permit: RouteConcurrencyPermit?
        if binding.routeProvider == "openai" {
            permit = nil
        } else {
            guard let p = acquireRouteConcurrencyPermit(forRequestModel: resolvedRequestModel) else {
                var limitHeaders = resolutionHeaders
                limitHeaders["Retry-After"] = "1"
                sendError(
                    to: originalConnection,
                    statusCode: 429,
                    message: concurrencyLimitErrorMessage(forRequestModel: resolvedRequestModel),
                    overridingHeaders: limitHeaders
                )
                return
            }
            permit = p
        }

        let cancel = sendBufferedProxyRequest(
            method: method,
            path: upstreamPath,
            headers: effectiveHeaders,
            body: upstreamBody,
            timeoutInterval: timeoutInterval
        ) { [weak self] bufferedResponse in
            permit?.release()
            guard let self else { return }
            guard requestController.isCancelled() != true else { return }

            let telemetryEvaluation = self.evaluateDirectBufferedRouteTelemetry(
                path: upstreamPath,
                requestModel: resolvedRequestModel,
                bufferedResponse: bufferedResponse,
                inflightAtRequest: permit?.inflightAtRequest,
                requestTrace: requestTrace
            )
            if telemetryEvaluation.shouldRecordFailure {
                if let permit,
                   let response = bufferedResponse.response {
                    OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest,
                        statusCode: response.statusCode,
                        headers: response.allHeaderFields,
                        bodyData: bufferedResponse.data
                    )
                }
                if let deferredUntil = telemetryEvaluation.deferralUntil {
                    OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                        forRequestModel: resolvedRequestModel,
                        until: deferredUntil
                    )
                }
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: resolvedRequestModel,
                    telemetryEvent: telemetryEvaluation.event,
                    forcedOpenUntil: telemetryEvaluation.forcedOpenUntil
                )
            } else if telemetryEvaluation.shouldRecordSuccess {
                if let permit {
                    OpenAICompatTemporaryShim.recordConcurrencySuccess(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest
                    )
                }
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: resolvedRequestModel,
                    telemetryEvent: telemetryEvaluation.event
                )
            } else {
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvaluation.event)
            }

            if let error = bufferedResponse.error {
                let nsError = error as NSError
                let statusCode = (nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue) ? 504 : 502
                self.sendError(
                    to: originalConnection,
                    statusCode: statusCode,
                    message: statusCode == 504 ? "Gateway Timeout" : "Bad Gateway",
                    overridingHeaders: resolutionHeaders
                )
                return
            }

            guard let response = bufferedResponse.response,
                  let responseData = bufferedResponse.data else {
                self.sendError(
                    to: originalConnection,
                    statusCode: 502,
                    message: "Bad Gateway",
                    overridingHeaders: resolutionHeaders
                )
                return
            }

            if !(200...299).contains(response.statusCode) {
                self.deliverBufferedHTTPResponse(
                    defaultConnection: originalConnection,
                    statusCode: response.statusCode,
                    headers: response.allHeaderFields,
                    body: responseData,
                    coalescingKey: nil,
                    overridingModel: binding.incomingModelID,
                    overridingHeaders: resolutionHeaders
                )
                return
            }

            // Successful buffered response.  When the original request was Responses API,
            // translate the Chat Completions response back to Responses format.
            if deliveryMode == .bufferedJSON {
                let deliveryData: Data
                if OpenAICompatTemporaryShim.isResponsesPath(path),
                   let translated = self.translatedResponsesObject(
                    fromChatCompletionsResponseBody: responseData,
                    publicAlias: binding.incomingModelID
                   ),
                   let translatedData = try? JSONSerialization.data(withJSONObject: translated) {
                    deliveryData = translatedData
                } else {
                    deliveryData = responseData
                }
                self.deliverBufferedHTTPResponse(
                    defaultConnection: originalConnection,
                    statusCode: response.statusCode,
                    headers: response.allHeaderFields,
                    body: deliveryData,
                    coalescingKey: nil,
                    overridingModel: binding.incomingModelID,
                    overridingHeaders: resolutionHeaders
                )
                return
            }

            let syntheticBody: Data?
            switch deliveryMode {
            case .bufferedJSON:
                syntheticBody = nil
            case .syntheticChatCompletionsSSE:
                syntheticBody = self.syntheticChatCompletionsStreamBody(
                    from: responseData,
                    publicAlias: binding.incomingModelID
                )
            case .syntheticResponsesSSE:
                if binding.requestSurface == "responses" {
                    syntheticBody = self.syntheticResponsesStreamBody(
                        fromResponsesResponseBody: responseData,
                        publicAlias: binding.incomingModelID
                    )
                } else {
                    // The upstream returned Chat Completions format (because we converted
                    // /v1/responses → /v1/chat/completions). Translate it to Responses API
                    // format, then wrap in SSE events.
                    syntheticBody = self.syntheticResponsesStreamBody(
                        fromChatCompletionsResponseBody: responseData,
                        publicAlias: binding.incomingModelID
                    )
                }
            }

            guard let syntheticBody else {
                self.sendError(
                    to: originalConnection,
                    statusCode: 502,
                    message: "Factory-bound streaming backend returned an unusable response.",
                    overridingHeaders: resolutionHeaders
                )
                return
            }

            let sseHeaders: [AnyHashable: Any] = [
                "Content-Type": "text/event-stream; charset=utf-8",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no"
            ]
            self.sendHTTPResponse(
                to: originalConnection,
                statusCode: 200,
                headers: sseHeaders,
                body: syntheticBody,
                overridingHeaders: resolutionHeaders
            )
        }
        requestController.registerCurrentCancel {
            permit?.release()
            cancel()
        }
    }

    private func factoryBoundExecutionPlan(
        path: String,
        body: String,
        binding: FactoryModelBinding
    ) -> (body: String, deliveryMode: FactoryBoundDeliveryMode)? {
        // Responses API path: convert to chat completions for upstream,
        // then synthesize back to Responses format on the way down.
        if OpenAICompatTemporaryShim.isResponsesPath(path) {
            if binding.requestSurface == "responses" {
                let clientStream = OpenAICompatTemporaryShim.requestedStream(forRequestJSON: body)
                let finalBody: String
                if clientStream {
                    guard let bufferedBody = Self.forcingNonStreamChatRequestBody(from: body) else {
                        return nil
                    }
                    finalBody = bufferedBody
                } else {
                    finalBody = body
                }
                return (body: finalBody, deliveryMode: clientStream ? .syntheticResponsesSSE : .bufferedJSON)
            }

            guard let chatBody = OpenAICompatTemporaryShim.chatCompletionsRequestJSON(
                fromResponsesRequestJSON: body
            ) else {
                let bodyPreview = String(body.prefix(500))
                NSLog("[ThinkingProxy] factoryBoundExecutionPlan: failed to convert /v1/responses body (first 500 chars): %@", bodyPreview)
                return nil
            }
            let clientStream = OpenAICompatTemporaryShim.requestedStream(forRequestJSON: body)
            let finalBody: String
            if clientStream {
                guard let bufferedBody = Self.forcingNonStreamChatRequestBody(from: chatBody) else {
                    return nil
                }
                finalBody = bufferedBody
            } else {
                finalBody = chatBody
            }
            return (body: finalBody, deliveryMode: clientStream ? .syntheticResponsesSSE : .bufferedJSON)
        }

        guard OpenAICompatTemporaryShim.requestedStream(forRequestJSON: body) else {
            return (body: body, deliveryMode: .bufferedJSON)
        }

        guard let bufferedBody = Self.forcingNonStreamChatRequestBody(from: body) else {
            return nil
        }

        if OpenAICompatTemporaryShim.isChatCompletionsPath(path) {
            return (body: bufferedBody, deliveryMode: .syntheticChatCompletionsSSE)
        }
        return nil
    }

    private func smartAliasExecutionPlan(
        path: String,
        body: String,
        clientRequestedStream: Bool
    ) -> (path: String, body: String, deliveryMode: SmartAliasDeliveryMode)? {
        if OpenAICompatTemporaryShim.isResponsesPath(path) {
            guard let chatBody = OpenAICompatTemporaryShim.chatCompletionsRequestJSON(
                fromResponsesRequestJSON: body
            ) else {
                return nil
            }
            let finalBody: String
            if clientRequestedStream {
                guard let bufferedBody = Self.forcingNonStreamChatRequestBody(from: chatBody) else {
                    return nil
                }
                finalBody = bufferedBody
            } else {
                finalBody = chatBody
            }
            return (
                path: OpenAICompatTemporaryShim.chatCompletionsPath(matching: path),
                body: finalBody,
                deliveryMode: clientRequestedStream ? .syntheticResponsesSSE : .bufferedResponsesJSON
            )
        }

        guard OpenAICompatTemporaryShim.isChatCompletionsPath(path) else {
            return nil
        }

        if clientRequestedStream {
            return (
                path: path,
                body: body,
                deliveryMode: .syntheticSSE
            )
        }

        return (
            path: path,
            body: body,
            deliveryMode: .bufferedJSON
        )
    }

    private func attemptSmartAliasCandidate(
        method: String,
        path: String,
        headers: [(String, String)],
        currentBody: String,
        publicAlias: String,
        remainingCandidateModels: [String],
        forceProbeCandidateModels: Set<String>,
        primaryProbeRetriesRemaining: Int,
        failoverDepth: Int,
        deadlineAt: Date,
        originalConnection: NWConnection,
        coalescingKey: String?,
        terminalFallbackOutcome: SmartAliasCandidateAttemptOutcome?,
        exhaustedRetryableOutcome: SmartAliasCandidateAttemptOutcome?,
        deliveryMode: SmartAliasDeliveryMode,
        loopRetriesRemaining: Int = 0,
        requestController: RequestCancellationController,
        requestTrace: RequestTraceContext
    ) {
        guard requestController.isCancelled() != true else { return }
        let remainingBudget = remainingSmartAliasBudget(until: deadlineAt)
        guard remainingBudget > 0 else {
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 504,
                message: "Worker failover budget exhausted before any backend returned a valid response.",
                coalescingKey: coalescingKey
            )
            return
        }

        // Non-NVIDIA candidates are tried serially. NVIDIA candidates are raced against each other
        // for lowest latency. The prefix scan walks candidates until it finds a contiguous run of
        // NVIDIA reasoning models at the front of the remaining list.
        // NOTE: This races at all failover depths (including depth 0). The health-based ranking
        // ensures only healthy candidates reach the front, so depth-0 racing is safe and avoids
        // serial latency penalties when multiple NVIDIA routes are available.
        let raceableFallbackModels = remainingCandidateModels.prefix { candidateModel in
            guard let candidateRoute = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel),
                  candidateRoute.providerID.hasPrefix("nvidia"),
                  let candidateBody = OpenAICompatTemporaryShim.rewrittenRequestJSON(
                    method: method,
                    path: path,
                    replacingRequestModelIn: currentBody,
                    with: candidateModel
                  ) else {
                return false
            }
            return OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
                method: method,
                path: path,
                jsonString: candidateBody
            )
        }

        if raceableFallbackModels.count >= 2 {
            let deferredCandidateModels = Array(remainingCandidateModels.dropFirst(raceableFallbackModels.count))
            attemptSmartAliasFallbackRace(
                method: method,
                path: path,
                headers: headers,
                currentBody: currentBody,
                publicAlias: publicAlias,
                raceCandidateModels: Array(raceableFallbackModels),
                healthSensitivity: OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias)?.healthSensitivity ?? .balanced,
                deferredCandidateModels: deferredCandidateModels,
                forceProbeCandidateModels: forceProbeCandidateModels,
                primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                failoverDepth: failoverDepth,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                terminalFallbackOutcome: terminalFallbackOutcome,
                exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining,
                requestController: requestController,
                requestTrace: requestTrace
            )
            return
        }

        let selection = OpenAICompatTemporaryShim.nextSmartAliasCandidateSelection(
            method: method,
            path: path,
            currentBody: currentBody,
            candidateModelsRemaining: remainingCandidateModels,
            forceAllowClosedModels: forceProbeCandidateModels,
            proxyRequestID: requestTrace.proxyRequestID
        )
        guard let transition = selection.transition else {
            let exhaustionSummary = selection.exhaustionSummary
            let poolRetryDelay = OpenAICompatTemporaryShim.nextSmartAliasRetryDelay(
                forCandidateModels: remainingCandidateModels,
                forceAllowClosedModels: forceProbeCandidateModels
            )
            if let exhaustedRetryableOutcome,
               case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil) = exhaustedRetryableOutcome {
                let isImmediateRetryClass =
                    telemetryEvent.failureClass == "classified_429_overload" ||
                    telemetryEvent.failureClass == "classified_429_concurrency" ||
                    telemetryEvent.failureClass == "classified_429"
                let nextRetryDelay = poolRetryDelay ?? cooldownUntil.map({ max(0.05, $0.timeIntervalSinceNow) })
                if isImmediateRetryClass,
                   loopRetriesRemaining > 0,
                   let retryDelay = nextRetryDelay,
                   retryDelay <= Config.smartAliasMaxLoopRetryDelay,
                   remainingSmartAliasBudget(until: deadlineAt) > retryDelay {
                    restartSmartAliasLoop(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: currentBody,
                        publicAlias: publicAlias,
                        deadlineAt: deadlineAt,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey,
                        loopRetriesRemaining: loopRetriesRemaining,
                        retryDelaySeconds: retryDelay,
                        exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                        deliveryMode: deliveryMode,
                        requestController: requestController,
                        requestTrace: requestTrace
                    )
                    return
                }

                if telemetryEvent.failureClass == "classified_429_window" ||
                    telemetryEvent.failureClass == "classified_429_overload" ||
                    telemetryEvent.failureClass == "classified_429_concurrency" ||
                    telemetryEvent.failureClass == "classified_429" ||
                    telemetryEvent.upstreamHTTPStatus == 429 {
                    let terminalOutcome: SmartAliasCandidateAttemptOutcome
                    if let nextRetryDelay {
                        terminalOutcome = .retryableFailure(
                            requestModel: requestModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: Date().addingTimeInterval(nextRetryDelay)
                        )
                    } else {
                        terminalOutcome = exhaustedRetryableOutcome
                    }
                    deliverSmartAliasTerminalOutcome(
                        terminalOutcome,
                        publicAlias: publicAlias,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey,
                        deliveryMode: deliveryMode,
                        requestController: requestController,
                        requestTrace: requestTrace
                    )
                    return
                }
            }

            if let terminalPreflightError = selection.terminalPreflightError {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: terminalPreflightError.statusCode,
                    message: terminalPreflightError.message,
                    coalescingKey: coalescingKey,
                    overridingHeaders: preflightFailureHeaders(
                        for: terminalPreflightError,
                        requestTrace: requestTrace
                    )
                )
                return
            }

            if let terminalFallbackOutcome {
                deliverSmartAliasTerminalOutcome(
                    terminalFallbackOutcome,
                    publicAlias: publicAlias,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    deliveryMode: deliveryMode,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
                return
            }

            if let exhaustedRetryableOutcome {
                deliverSmartAliasTerminalOutcome(
                    exhaustedRetryableOutcome,
                    publicAlias: publicAlias,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    deliveryMode: deliveryMode,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
                return
            }

            if let nextRetryDelay = poolRetryDelay {
                let retryUntil = Date().addingTimeInterval(nextRetryDelay)
                let isQuotaWindowDelay = nextRetryDelay >= 300
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 429,
                    message: isQuotaWindowDelay
                        ? quotaWindowErrorMessage(forRequestModel: publicAlias)
                        : concurrencyLimitErrorMessage(forRequestModel: publicAlias),
                    coalescingKey: coalescingKey,
                    overridingHeaders: [
                        "Retry-After": retryAfterHeaderValue(
                            until: retryUntil,
                            fallbackSeconds: max(1, Int(ceil(nextRetryDelay)))
                        )
                    ].merging(requestTrace.responseHeaders) { current, _ in current }
                )
                return
            }

            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: exhaustionSummary?.statusCode ?? 503,
                message: exhaustionSummary?.clientFacingMessage(publicAlias: publicAlias) ?? "All configured worker backends are currently unavailable.",
                coalescingKey: coalescingKey,
                overridingHeaders: smartAliasExhaustionHeaders(
                    for: exhaustionSummary,
                    requestTrace: requestTrace
                )
            )
            return
        }

        NSLog("[ThinkingProxy] Resolved smart alias %@ to candidate %@ at depth %d", publicAlias, transition.model, failoverDepth)

        executeSmartAliasCandidate(
            method: method,
            path: path,
            headers: headers,
            body: transition.body,
            publicAlias: publicAlias,
            candidateModel: transition.model,
            failoverDepth: failoverDepth,
            attemptLane: 1,
            deadlineAt: deadlineAt,
            originalConnection: originalConnection,
            deliveryMode: deliveryMode,
            coalescingKey: coalescingKey,
            controller: requestController,
            onNVIDIAMeaningfulOutput: nil,
            requestTrace: requestTrace
        ) { [weak self] outcome in
            guard let self else { return }
            self.handleSmartAliasSerialCandidateOutcome(
                outcome,
                method: method,
                path: path,
                headers: headers,
                candidateBody: transition.body,
                publicAlias: publicAlias,
                remainingCandidateModels: transition.remainingCandidateModels,
                forceProbeCandidateModels: forceProbeCandidateModels,
                primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                failoverDepth: failoverDepth,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                terminalFallbackOutcome: terminalFallbackOutcome,
                exhaustedRetryableOutcome: nil,
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining,
                requestController: requestController,
                requestTrace: requestTrace
            )
        }
    }

    private func attemptSmartAliasFallbackRace(
        method: String,
        path: String,
        headers: [(String, String)],
        currentBody: String,
        publicAlias: String,
        raceCandidateModels: [String],
        healthSensitivity: OpenAICompatTemporaryShim.HealthSensitivity = .balanced,
        deferredCandidateModels: [String],
        forceProbeCandidateModels: Set<String>,
        primaryProbeRetriesRemaining: Int,
        failoverDepth: Int,
        deadlineAt: Date,
        originalConnection: NWConnection,
        coalescingKey: String?,
        terminalFallbackOutcome: SmartAliasCandidateAttemptOutcome?,
        exhaustedRetryableOutcome: SmartAliasCandidateAttemptOutcome?,
        deliveryMode: SmartAliasDeliveryMode,
        loopRetriesRemaining: Int = 0,
        requestController: RequestCancellationController,
        requestTrace: RequestTraceContext
    ) {
        guard requestController.isCancelled() != true else { return }
        let rankedRaceCandidateModels = OpenAICompatTemporaryShim.rankedSmartAliasFallbackCandidateModels(raceCandidateModels, healthSensitivity: healthSensitivity)
        let raceTransitions = OpenAICompatTemporaryShim.availableSmartAliasCandidateTransitions(
            method: method,
            path: path,
            currentBody: currentBody,
            candidateModelsRemaining: rankedRaceCandidateModels,
            forceAllowClosedModels: forceProbeCandidateModels
        )

        guard raceTransitions.count >= 2 else {
            attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: currentBody,
                publicAlias: publicAlias,
                remainingCandidateModels: raceTransitions.map(\.model) + deferredCandidateModels,
                forceProbeCandidateModels: forceProbeCandidateModels,
                primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                failoverDepth: failoverDepth,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                terminalFallbackOutcome: terminalFallbackOutcome,
                exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining,
                requestController: requestController,
                requestTrace: requestTrace
            )
            return
        }

        NSLog(
            "[ThinkingProxy] Racing smart alias %@ across fallback candidates %@ at depth %d",
            publicAlias,
            raceTransitions.map(\.model).joined(separator: ","),
            failoverDepth
        )

        let coordinator = SmartAliasRaceCoordinator()
        let completionQueue = DispatchQueue(label: "io.automaze.vibeproxy.smart-alias-race-completion")
        var remainingAttempts = raceTransitions.count
        var terminalOutcomesByLane: [Int: SmartAliasCandidateAttemptOutcome] = [:]
        let completionGate = DispatchSemaphore(value: 0)
        requestController.registerCurrentCancel {
            _ = coordinator.tryFinish(attemptLane: 0)
        }

        func finalizeExhaustedRaceIfNeeded() {
            guard remainingAttempts == 0, !coordinator.isFinished() else { return }
            _ = coordinator.tryFinish(attemptLane: 0)

            if !deferredCandidateModels.isEmpty {
                self.attemptSmartAliasCandidate(
                    method: method,
                    path: path,
                    headers: headers,
                    currentBody: currentBody,
                    publicAlias: publicAlias,
                    remainingCandidateModels: deferredCandidateModels,
                    forceProbeCandidateModels: forceProbeCandidateModels,
                    primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                    failoverDepth: failoverDepth + raceTransitions.count,
                    deadlineAt: deadlineAt,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    terminalFallbackOutcome: terminalOutcomesByLane.keys.sorted().compactMap({ terminalOutcomesByLane[$0] }).first ?? terminalFallbackOutcome,
                    exhaustedRetryableOutcome: nil,
                    deliveryMode: deliveryMode,
                    loopRetriesRemaining: loopRetriesRemaining,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
                return
            }

            if let terminalOutcome = terminalOutcomesByLane.keys.sorted().compactMap({ terminalOutcomesByLane[$0] }).first ?? terminalFallbackOutcome {
                self.deliverSmartAliasTerminalOutcome(
                    terminalOutcome,
                    publicAlias: publicAlias,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    deliveryMode: deliveryMode,
                    requestController: requestController
                )
                return
            }

            self.attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: currentBody,
                publicAlias: publicAlias,
                remainingCandidateModels: [],
                forceProbeCandidateModels: forceProbeCandidateModels,
                primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                failoverDepth: failoverDepth + raceTransitions.count,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                terminalFallbackOutcome: nil,
                exhaustedRetryableOutcome: nil,
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining,
                requestController: requestController,
                requestTrace: requestTrace
            )
        }

        func handleRaceOutcome(
            _ outcome: SmartAliasCandidateAttemptOutcome,
            attemptLane: Int,
            fanOutWaitersForModelKey: String?
        ) {
            if let winnerAttemptLane = coordinator.winnerAttemptLaneValue(),
               winnerAttemptLane != attemptLane {
                return
            } else if coordinator.isFinished(),
                      coordinator.winnerAttemptLaneValue() == nil {
                return
            }

            switch outcome {
            case .liveStreamDelivered(let requestModel, let telemetryEvent, let cooldownUntil):
                NSLog("[ThinkingProxy] Warning: .liveStreamDelivered reached in smart-alias race for %@ — smart-alias delivery modes should produce .success or .terminalResponse, not live streams.", requestModel)
                let winningTelemetryEvent = self.annotatedSmartAliasTelemetryEvent(
                    OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                        telemetryEvent,
                        winnerAttemptLane: attemptLane
                    ),
                    requestedAlias: publicAlias,
                    failoverDepth: failoverDepth,
                    finalWinnerRequestModel: requestModel
                )
                if smartAliasLiveStreamTelemetryWasSuccessful(winningTelemetryEvent) {
                    OpenAICompatTemporaryShim.recordRouteSuccess(
                        forRequestModel: requestModel,
                        telemetryEvent: winningTelemetryEvent
                    )
                } else {
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: requestModel,
                        telemetryEvent: winningTelemetryEvent,
                        forcedOpenUntil: cooldownUntil,
                        healthSensitivity: healthSensitivity
                    )
                }
                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
            case .success(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
                guard requestController.isCancelled() != true else {
                    _ = coordinator.tryFinish(attemptLane: attemptLane)
                    return
                }
                let winningTelemetryEvent = self.annotatedSmartAliasTelemetryEvent(
                    OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                        telemetryEvent,
                        winnerAttemptLane: attemptLane
                    ),
                    requestedAlias: publicAlias,
                    failoverDepth: failoverDepth,
                    finalWinnerRequestModel: requestModel
                )
                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: requestModel,
                    telemetryEvent: winningTelemetryEvent
                )
                self.deliverSmartAliasSuccessfulResponse(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    headers: responseHeaders,
                    body: responseBody,
                    publicAlias: publicAlias,
                    resolvedRequestModel: requestModel,
                    coalescingKey: coalescingKey,
                    deliveryMode: deliveryMode,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
            case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil):
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: requestModel,
                    telemetryEvent: telemetryEvent,
                    forcedOpenUntil: cooldownUntil,
                    healthSensitivity: healthSensitivity
                )
                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                remainingAttempts -= 1
            case .terminalResponse(_, _, _, _, let telemetryEvent):
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                terminalOutcomesByLane[attemptLane] = outcome
                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                remainingAttempts -= 1
            case .terminalError(_, _, _, let telemetryEvent, _):
                if let telemetryEvent {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                }
                terminalOutcomesByLane[attemptLane] = outcome
                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                remainingAttempts -= 1
            }

            if let fanOutWaitersForModelKey {
                let waiters = self.nvidiaInflightQueue.sync { () -> [(SmartAliasCandidateAttemptOutcome) -> Void] in
                    self.nvidiaRaceWaiters.removeValue(forKey: fanOutWaitersForModelKey) ?? []
                }
                if !waiters.isEmpty {
                    NSLog(
                        "[ThinkingProxy] Delivering NVIDIA race outcome for %@ to %d coalesced waiter(s)",
                        fanOutWaitersForModelKey,
                        waiters.count
                    )
                    for waiter in waiters {
                        waiter(outcome)
                    }
                }
            }

            finalizeExhaustedRaceIfNeeded()
        }

        for (index, transition) in raceTransitions.enumerated() {
            let attemptLane = index + 1
            if let winnerAttemptLane = coordinator.winnerAttemptLaneValue(),
               winnerAttemptLane != attemptLane {
                remainingAttempts -= 1
                continue
            }
            let controller = RequestCancellationController()
            coordinator.registerAttempt(attemptLane: attemptLane) {
                controller.cancel()
            }
            if controller.isCancelled() {
                remainingAttempts -= 1
                continue
            }

            // NVIDIA race coalescing: if a race for this model is already inflight,
            // join as a waiter instead of opening a duplicate upstream connection.
            let coalescingModelKey = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: transition.model)?.routeHealthKey ?? transition.model
            let joinedExisting = nvidiaInflightQueue.sync { () -> Bool in
                if nvidiaRaceWaiters[coalescingModelKey] != nil {
                    // Already inflight — register completion as waiter
                    nvidiaRaceWaiters[coalescingModelKey]!.append({ [weak self] outcome in
                        guard self != nil else { return }
                        DispatchQueue.global(qos: .userInitiated).async {
                            completionGate.wait()
                            completionQueue.async {
                                handleRaceOutcome(
                                    outcome,
                                    attemptLane: attemptLane,
                                    fanOutWaitersForModelKey: nil
                                )
                            }
                        }
                    })
                    return true
                }
                // First request for this model — mark as inflight
                nvidiaRaceWaiters[coalescingModelKey] = []
                return false
            }

            if joinedExisting {
                NSLog("[ThinkingProxy] Coalesced NVIDIA race for %@ lane %d (joining inflight request)", transition.model, attemptLane)
                continue
            }

            NSLog(
                "[ThinkingProxy] Resolved smart alias %@ to candidate %@ at depth %d lane %d",
                publicAlias,
                transition.model,
                failoverDepth,
                attemptLane
            )

            executeSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                body: transition.body,
                publicAlias: publicAlias,
                candidateModel: transition.model,
                failoverDepth: failoverDepth,
                attemptLane: attemptLane,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                deliveryMode: deliveryMode,
                coalescingKey: coalescingKey,
                controller: controller,
                onNVIDIAMeaningfulOutput: {
                    coordinator.claimMeaningfulOutput(attemptLane: attemptLane)
                },
                requestTrace: requestTrace
            ) { [weak self] outcome in
                guard self != nil else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    completionGate.wait()
                    completionQueue.async {
                        handleRaceOutcome(
                            outcome,
                            attemptLane: attemptLane,
                            fanOutWaitersForModelKey: coalescingModelKey
                        )
                    }
                }
            }
        }
        for _ in raceTransitions {
            completionGate.signal()
        }
    }

    private func handleSmartAliasSerialCandidateOutcome(
        _ outcome: SmartAliasCandidateAttemptOutcome,
        method: String,
        path: String,
        headers: [(String, String)],
        candidateBody: String,
        publicAlias: String,
        remainingCandidateModels: [String],
        forceProbeCandidateModels: Set<String>,
        primaryProbeRetriesRemaining: Int,
        failoverDepth: Int,
        deadlineAt: Date,
        originalConnection: NWConnection,
        coalescingKey: String?,
        terminalFallbackOutcome: SmartAliasCandidateAttemptOutcome?,
        exhaustedRetryableOutcome: SmartAliasCandidateAttemptOutcome?,
        deliveryMode: SmartAliasDeliveryMode,
        loopRetriesRemaining: Int = 0,
        requestController: RequestCancellationController,
        requestTrace: RequestTraceContext
    ) {
        let healthSensitivity = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias)?.healthSensitivity
        guard requestController.isCancelled() != true else { return }
        switch outcome {
        case .liveStreamDelivered(let requestModel, let telemetryEvent, let cooldownUntil):
            let winningTelemetryEvent = annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                    telemetryEvent,
                    winnerAttemptLane: 1
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: requestModel
            )
            if smartAliasLiveStreamTelemetryWasSuccessful(winningTelemetryEvent) {
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: requestModel,
                    telemetryEvent: winningTelemetryEvent
                )
            } else {
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: requestModel,
                    telemetryEvent: winningTelemetryEvent,
                    forcedOpenUntil: cooldownUntil,
                    healthSensitivity: healthSensitivity
                )
            }
        case .success(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
            guard requestController.isCancelled() != true else { return }
            let winningTelemetryEvent = annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                    telemetryEvent,
                    winnerAttemptLane: 1
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: requestModel
            )
            OpenAICompatTemporaryShim.recordRouteSuccess(
                forRequestModel: requestModel,
                telemetryEvent: winningTelemetryEvent
            )
            deliverSmartAliasSuccessfulResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: responseHeaders,
                body: responseBody,
                publicAlias: publicAlias,
                resolvedRequestModel: requestModel,
                coalescingKey: coalescingKey,
                deliveryMode: deliveryMode,
                requestController: requestController,
                requestTrace: requestTrace
            )
        case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil)
            where telemetryEvent.failureClass == "classified_429_overload":
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: telemetryEvent.requestModel,
                telemetryEvent: telemetryEvent,
                forcedOpenUntil: cooldownUntil,
                healthSensitivity: healthSensitivity
            )
            let retryDelay: TimeInterval = 1
            let remainingBudget = max(0, deadlineAt.timeIntervalSinceNow)
            if primaryProbeRetriesRemaining > 0,
               remainingBudget > retryDelay {
                requestController.scheduleRetry(after: .seconds(1)) { [weak self] in
                    guard let self else { return }
                    self.attemptSmartAliasCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: candidateBody,
                        publicAlias: publicAlias,
                        remainingCandidateModels: [requestModel] + remainingCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels.union([requestModel]),
                        primaryProbeRetriesRemaining: primaryProbeRetriesRemaining - 1,
                        failoverDepth: failoverDepth,
                        deadlineAt: deadlineAt,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey,
                        terminalFallbackOutcome: terminalFallbackOutcome,
                        exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                        deliveryMode: deliveryMode,
                        loopRetriesRemaining: loopRetriesRemaining,
                        requestController: requestController,
                        requestTrace: requestTrace
                    )
                }
                return
            }
            if !remainingCandidateModels.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self, requestController.isCancelled() != true else { return }
                    self.attemptSmartAliasCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: candidateBody,
                        publicAlias: publicAlias,
                        remainingCandidateModels: remainingCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels,
                        primaryProbeRetriesRemaining: 0,
                        failoverDepth: failoverDepth + 1,
                        deadlineAt: deadlineAt,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey,
                        terminalFallbackOutcome: terminalFallbackOutcome,
                        exhaustedRetryableOutcome: .retryableFailure(
                            requestModel: requestModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: cooldownUntil
                        ),
                        deliveryMode: deliveryMode,
                        loopRetriesRemaining: loopRetriesRemaining,
                        requestController: requestController,
                        requestTrace: requestTrace
                    )
                }
                return
            }
            deliverSmartAliasTerminalOutcome(
                .retryableFailure(
                    requestModel: requestModel,
                    telemetryEvent: telemetryEvent,
                    cooldownUntil: cooldownUntil
                ),
                publicAlias: publicAlias,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                deliveryMode: deliveryMode,
                requestController: requestController,
                requestTrace: requestTrace
            )
            return
        case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil)
            where telemetryEvent.failureClass == "classified_429_concurrency":
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: telemetryEvent.requestModel,
                telemetryEvent: telemetryEvent,
                forcedOpenUntil: cooldownUntil,
                healthSensitivity: healthSensitivity
            )
            let retryDelay = max(
                0.25,
                min(1.0, cooldownUntil?.timeIntervalSinceNow ?? 0.25)
            )
            let remainingBudget = max(0, deadlineAt.timeIntervalSinceNow)
            if primaryProbeRetriesRemaining > 0,
               remainingBudget > retryDelay {
                requestController.scheduleRetry(after: .milliseconds(max(0, Int(retryDelay * 1000)))) { [weak self] in
                    guard let self else { return }
                    self.attemptSmartAliasCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: candidateBody,
                        publicAlias: publicAlias,
                        remainingCandidateModels: [requestModel] + remainingCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels.union([requestModel]),
                        primaryProbeRetriesRemaining: 0,
                        failoverDepth: failoverDepth,
                        deadlineAt: deadlineAt,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey,
                        terminalFallbackOutcome: terminalFallbackOutcome,
                        exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                        deliveryMode: deliveryMode,
                        loopRetriesRemaining: loopRetriesRemaining,
                        requestController: requestController,
                        requestTrace: requestTrace
                    )
                }
                return
            }
            if !remainingCandidateModels.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self, requestController.isCancelled() != true else { return }
                    self.attemptSmartAliasCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: candidateBody,
                        publicAlias: publicAlias,
                        remainingCandidateModels: remainingCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels,
                        primaryProbeRetriesRemaining: 0,
                        failoverDepth: failoverDepth + 1,
                        deadlineAt: deadlineAt,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey,
                        terminalFallbackOutcome: terminalFallbackOutcome,
                        exhaustedRetryableOutcome: .retryableFailure(
                            requestModel: requestModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: cooldownUntil
                        ),
                        deliveryMode: deliveryMode,
                        loopRetriesRemaining: loopRetriesRemaining,
                        requestController: requestController,
                        requestTrace: requestTrace
                    )
                }
                return
            }
            if remainingBudget <= 0 {
                deliverSmartAliasTerminalOutcome(
                    .retryableFailure(
                        requestModel: requestModel,
                        telemetryEvent: telemetryEvent,
                        cooldownUntil: cooldownUntil
                    ),
                    publicAlias: publicAlias,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    deliveryMode: deliveryMode,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
                return
            }
            deliverSmartAliasTerminalOutcome(
                .retryableFailure(
                    requestModel: requestModel,
                    telemetryEvent: telemetryEvent,
                    cooldownUntil: cooldownUntil
                ),
                publicAlias: publicAlias,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                deliveryMode: deliveryMode,
                requestController: requestController,
                requestTrace: requestTrace
            )
            return
        case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil)
            where remainingCandidateModels.isEmpty &&
                primaryProbeRetriesRemaining > 0 &&
                forceProbeCandidateModels.contains(requestModel) &&
                telemetryEvent.failureClass != "classified_429":
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: telemetryEvent.requestModel,
                telemetryEvent: telemetryEvent,
                forcedOpenUntil: cooldownUntil,
                healthSensitivity: healthSensitivity
            )
            let backoffMs = min(500 * (failoverDepth + 1), 2000)
            requestController.scheduleRetry(after: .milliseconds(backoffMs)) { [weak self] in
                guard let self else { return }
                self.attemptSmartAliasCandidate(
                    method: method,
                    path: path,
                    headers: headers,
                    currentBody: candidateBody,
                    publicAlias: publicAlias,
                    remainingCandidateModels: [requestModel],
                    forceProbeCandidateModels: forceProbeCandidateModels,
                    primaryProbeRetriesRemaining: primaryProbeRetriesRemaining - 1,
                    failoverDepth: failoverDepth,
                    deadlineAt: deadlineAt,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    terminalFallbackOutcome: terminalFallbackOutcome,
                    exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                    deliveryMode: deliveryMode,
                    loopRetriesRemaining: loopRetriesRemaining,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
            }
        case .retryableFailure(_, let telemetryEvent, let cooldownUntil):
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: telemetryEvent.requestModel,
                telemetryEvent: telemetryEvent,
                forcedOpenUntil: cooldownUntil,
                healthSensitivity: healthSensitivity
            )
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, requestController.isCancelled() != true else { return }
                self.attemptSmartAliasCandidate(
                    method: method,
                    path: path,
                    headers: headers,
                    currentBody: candidateBody,
                    publicAlias: publicAlias,
                    remainingCandidateModels: remainingCandidateModels,
                    forceProbeCandidateModels: forceProbeCandidateModels,
                    primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                    failoverDepth: failoverDepth + 1,
                    deadlineAt: deadlineAt,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    terminalFallbackOutcome: terminalFallbackOutcome,
                    exhaustedRetryableOutcome: remainingCandidateModels.isEmpty
                        ? .retryableFailure(
                            requestModel: telemetryEvent.requestModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: cooldownUntil
                        )
                        : exhaustedRetryableOutcome,
                    deliveryMode: deliveryMode,
                    loopRetriesRemaining: loopRetriesRemaining,
                    requestController: requestController,
                    requestTrace: requestTrace
                )
            }
        case .terminalResponse(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
            guard requestController.isCancelled() != true else { return }
            OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
            deliverBufferedHTTPResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: responseHeaders,
                body: responseBody,
                coalescingKey: coalescingKey,
                overridingHeaders: smartAliasResolutionHeaders(
                    publicAlias: publicAlias,
                    resolvedRequestModel: requestModel,
                    requestTrace: requestTrace
                )
            )
        case .terminalError(_, let statusCode, let message, let telemetryEvent, _):
            guard requestController.isCancelled() != true else { return }
            if let telemetryEvent {
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
            }
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                message: message,
                coalescingKey: coalescingKey,
                overridingHeaders: requestTrace.responseHeaders
            )
        }
    }

    private func restartSmartAliasLoop(
        method: String,
        path: String,
        headers: [(String, String)],
        currentBody: String,
        publicAlias: String,
        deadlineAt: Date,
        originalConnection: NWConnection,
        coalescingKey: String?,
        loopRetriesRemaining: Int,
        retryDelaySeconds: TimeInterval = 1,
        exhaustedRetryableOutcome: SmartAliasCandidateAttemptOutcome?,
        deliveryMode: SmartAliasDeliveryMode,
        requestController: RequestCancellationController,
        requestTrace: RequestTraceContext
    ) {
        guard let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias) else {
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 503,
                message: "All configured worker backends are currently unavailable.",
                coalescingKey: coalescingKey,
                overridingHeaders: requestTrace.responseHeaders
            )
            return
        }
        let freshCandidates = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
            forPublicAlias: publicAlias,
            method: method,
            path: path,
            jsonString: currentBody,
            smartAlias: smartAlias
        )
        let freshForceProbe = OpenAICompatTemporaryShim.forcedSmartAliasProbeCandidateModels(
            forPublicAlias: publicAlias,
            method: method,
            path: path,
            jsonString: currentBody,
            smartAlias: smartAlias
        )
        guard !freshCandidates.isEmpty else {
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 503,
                message: "All configured worker backends are currently unavailable.",
                coalescingKey: coalescingKey,
                overridingHeaders: requestTrace.responseHeaders
            )
            return
        }
        let attempt = smartAliasMaxLoopRetries - loopRetriesRemaining + 1
        NSLog("[ThinkingProxy] Smart alias %@ loop retry %d/%d", publicAlias, attempt, smartAliasMaxLoopRetries)
        requestController.scheduleRetry(after: .milliseconds(max(0, Int(retryDelaySeconds * 1000)))) { [weak self] in
            guard let self else { return }
            self.attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: currentBody,
                publicAlias: publicAlias,
                remainingCandidateModels: freshCandidates,
                forceProbeCandidateModels: freshForceProbe,
                primaryProbeRetriesRemaining: self.smartAliasForcedPrimaryRetryLimit,
                failoverDepth: 0,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                terminalFallbackOutcome: nil,
                exhaustedRetryableOutcome: exhaustedRetryableOutcome,
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining - 1,
                requestController: requestController,
                requestTrace: requestTrace
            )
        }
    }

    private func smartAliasLiveStreamTelemetryWasSuccessful(
        _ telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent
    ) -> Bool {
        guard telemetryEvent.transportOutcome == "send_response" else { return false }
        guard let upstreamHTTPStatus = telemetryEvent.upstreamHTTPStatus else { return false }
        return (200...299).contains(upstreamHTTPStatus)
    }

    private func deliverSmartAliasTerminalOutcome(
        _ outcome: SmartAliasCandidateAttemptOutcome,
        publicAlias: String,
        originalConnection: NWConnection,
        coalescingKey: String?,
        deliveryMode: SmartAliasDeliveryMode,
        requestController: RequestCancellationController? = nil,
        requestTrace: RequestTraceContext? = nil
    ) {
        guard requestController?.isCancelled() != true else { return }
        let healthSensitivity = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias)?.healthSensitivity
        switch outcome {
        case .liveStreamDelivered(let requestModel, let telemetryEvent, let cooldownUntil):
            let winningTelemetryEvent = OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                telemetryEvent,
                winnerAttemptLane: telemetryEvent.attemptLane
            )
            if smartAliasLiveStreamTelemetryWasSuccessful(winningTelemetryEvent) {
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: requestModel,
                    telemetryEvent: winningTelemetryEvent
                )
            } else {
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: requestModel,
                    telemetryEvent: winningTelemetryEvent,
                    forcedOpenUntil: cooldownUntil,
                    healthSensitivity: healthSensitivity
                )
            }
        case .terminalResponse(let requestModel, let statusCode, let responseHeaders, let responseBody, _):
            deliverBufferedHTTPResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: responseHeaders,
                body: responseBody,
                coalescingKey: coalescingKey,
                overridingHeaders: smartAliasResolutionHeaders(
                    publicAlias: publicAlias,
                    resolvedRequestModel: requestModel,
                    requestTrace: requestTrace
                )
            )
        case .terminalError(_, let statusCode, let message, _, _):
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                message: message,
                coalescingKey: coalescingKey,
                overridingHeaders: requestTrace?.responseHeaders ?? [:]
            )
        case .success(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
            guard requestController?.isCancelled() != true else { return }
            let winningTelemetryEvent = OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                telemetryEvent,
                winnerAttemptLane: telemetryEvent.attemptLane
            )
            OpenAICompatTemporaryShim.recordRouteSuccess(
                forRequestModel: requestModel,
                telemetryEvent: winningTelemetryEvent
            )
            deliverSmartAliasSuccessfulResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: responseHeaders,
                body: responseBody,
                publicAlias: publicAlias,
                resolvedRequestModel: requestModel,
                coalescingKey: coalescingKey,
                deliveryMode: deliveryMode,
                requestController: requestController,
                requestTrace: requestTrace
            )
        case .retryableFailure(_, let telemetryEvent, let cooldownUntil):
            guard requestController?.isCancelled() != true else { return }
            if telemetryEvent.failureClass == "classified_429_window" {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 429,
                    message: quotaWindowErrorMessage(forRequestModel: publicAlias),
                    coalescingKey: coalescingKey,
                    overridingHeaders: ["Retry-After": retryAfterHeaderValue(until: cooldownUntil, fallbackSeconds: 300)]
                        .merging(requestTrace?.responseHeaders ?? [:]) { current, _ in current }
                )
            } else if telemetryEvent.failureClass == "classified_429_overload" {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 429,
                    message: overloadErrorMessage(forRequestModel: publicAlias),
                    coalescingKey: coalescingKey,
                    overridingHeaders: ["Retry-After": retryAfterHeaderValue(until: cooldownUntil, fallbackSeconds: 1)]
                        .merging(requestTrace?.responseHeaders ?? [:]) { current, _ in current }
                )
            } else if telemetryEvent.failureClass == "classified_429" ||
                telemetryEvent.failureClass == "classified_429_concurrency" ||
                telemetryEvent.upstreamHTTPStatus == 429 {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 429,
                    message: concurrencyLimitErrorMessage(forRequestModel: publicAlias),
                    coalescingKey: coalescingKey,
                    overridingHeaders: ["Retry-After": retryAfterHeaderValue(until: cooldownUntil, fallbackSeconds: 30)]
                        .merging(requestTrace?.responseHeaders ?? [:]) { current, _ in current }
                )
            } else if telemetryEvent.upstreamHTTPStatus == 402 {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 402,
                    message: "Worker backend reported billing or entitlement exhaustion.",
                    coalescingKey: coalescingKey,
                    overridingHeaders: requestTrace?.responseHeaders ?? [:]
                )
            } else if telemetryEvent.upstreamHTTPStatus == 403 {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 403,
                    message: "Worker backend rejected the request with 403 Forbidden.",
                    coalescingKey: coalescingKey,
                    overridingHeaders: requestTrace?.responseHeaders ?? [:]
                )
            } else {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 503,
                    message: "All configured worker backends are currently unavailable.",
                    coalescingKey: coalescingKey,
                    overridingHeaders: requestTrace?.responseHeaders ?? [:]
                )
            }
        }
        }

    private func deliverSmartAliasSuccessfulResponse(
        defaultConnection: NWConnection,
        statusCode: Int,
        headers: [AnyHashable: Any],
        body: Data,
        publicAlias: String,
        resolvedRequestModel: String,
        coalescingKey: String?,
        deliveryMode: SmartAliasDeliveryMode,
        requestController: RequestCancellationController? = nil,
        requestTrace: RequestTraceContext? = nil
    ) {
        guard requestController?.isCancelled() != true else { return }
        let overridingHeaders = smartAliasResolutionHeaders(
            publicAlias: publicAlias,
            resolvedRequestModel: resolvedRequestModel,
            requestTrace: requestTrace
        )

        switch deliveryMode {
        case .bufferedJSON:
            deliverBufferedHTTPResponse(
                defaultConnection: defaultConnection,
                statusCode: statusCode,
                headers: headers,
                body: body,
                coalescingKey: coalescingKey,
                overridingModel: publicAlias,
                overridingHeaders: overridingHeaders
            )
        case .bufferedResponsesJSON:
            guard let bufferedResponsesBody = responsesBody(
                fromChatCompletionsResponseBody: body,
                publicAlias: publicAlias
            ) else {
                deliverBufferedError(
                    defaultConnection: defaultConnection,
                    statusCode: 502,
                    message: "Worker Responses backend returned an unusable response.",
                    coalescingKey: coalescingKey
                )
                return
            }

            deliverBufferedHTTPResponse(
                defaultConnection: defaultConnection,
                statusCode: statusCode,
                headers: headers,
                body: bufferedResponsesBody,
                coalescingKey: coalescingKey,
                overridingHeaders: overridingHeaders
            )
        case .syntheticSSE:
            guard let syntheticBody = syntheticChatCompletionsStreamBody(
                from: body,
                publicAlias: publicAlias
            ) else {
                deliverBufferedError(
                    defaultConnection: defaultConnection,
                    statusCode: 502,
                    message: "Worker streaming backend returned an unusable response.",
                    coalescingKey: coalescingKey
                )
                return
            }

            let sseHeaders: [AnyHashable: Any] = [
                "Content-Type": "text/event-stream; charset=utf-8",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no"
            ]
            sendHTTPResponse(
                to: defaultConnection,
                statusCode: 200,
                headers: sseHeaders,
                body: syntheticBody,
                overridingHeaders: overridingHeaders
            )
        case .syntheticResponsesSSE:
            guard let syntheticBody = syntheticResponsesStreamBody(
                fromChatCompletionsResponseBody: body,
                publicAlias: publicAlias
            ) else {
                deliverBufferedError(
                    defaultConnection: defaultConnection,
                    statusCode: 502,
                    message: "Worker Responses backend returned an unusable response.",
                    coalescingKey: coalescingKey
                )
                return
            }

            let sseHeaders: [AnyHashable: Any] = [
                "Content-Type": "text/event-stream; charset=utf-8",
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no"
            ]
            sendHTTPResponse(
                to: defaultConnection,
                statusCode: 200,
                headers: sseHeaders,
                body: syntheticBody,
                overridingHeaders: overridingHeaders
            )
        }
    }

    /// Rewrites the model name in the request body for upstream consumption.
    /// Factory bindings may carry reasoning-effort annotations like "gpt-5.4(high)"
    /// that the upstream backend does not recognise.  Strips the parenthesised
    /// suffix so the upstream only sees the base model name (e.g. "gpt-5.4").
    private static func rewriteModelForUpstream(
        body: String,
        routeModel: String,
        preserveQualifiedRouteModel: Bool = false
    ) -> String {
        if preserveQualifiedRouteModel {
            return body
        }

        // Derive base model name by stripping reasoning-effort suffix like "(high)"
        let baseModel: String
        if let parenOpen = routeModel.firstIndex(of: "("),
           parenOpen > routeModel.startIndex,
           routeModel.last == ")" {
            baseModel = String(routeModel[..<parenOpen])
        } else {
            return body  // no suffix to strip
        }

        guard let data = body.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestModel = json["model"] as? String,
              requestModel == routeModel else {
            return body
        }

        json["model"] = baseModel
        guard let normalized = try? JSONSerialization.data(withJSONObject: json),
              let result = String(data: normalized, encoding: .utf8) else {
            return body
        }
        return result
    }

    private static func forcingNonStreamChatRequestBody(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        json["stream"] = false
        guard let normalized = try? JSONSerialization.data(withJSONObject: json),
              let normalizedString = String(data: normalized, encoding: .utf8) else {
            return nil
        }
        return normalizedString
    }

    private func syntheticChatCompletionsStreamBody(from responseBody: Data, publicAlias: String) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any] else {
            return nil
        }

        let id = (root["id"] as? String) ?? "chatcmpl-worker"
        let created = (root["created"] as? Int) ?? Int(Date().timeIntervalSince1970)
        let choices = (root["choices"] as? [[String: Any]]) ?? []
        guard !choices.isEmpty else {
            return nil
        }

        var lines: [String] = []
        for (fallbackIndex, choice) in choices.enumerated() {
            let index = choice["index"] as? Int ?? fallbackIndex
            let message = choice["message"] as? [String: Any] ?? [:]
            var delta: [String: Any] = ["role": "assistant"]

            if let content = message["content"] as? String, !content.isEmpty {
                delta["content"] = content
            }
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                delta["tool_calls"] = toolCalls
            }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                delta["refusal"] = refusal
            }

            let initialChunk: [String: Any] = [
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicAlias,
                "choices": [[
                    "index": index,
                    "delta": delta,
                    "finish_reason": NSNull()
                ]]
            ]
            guard let initialData = try? JSONSerialization.data(withJSONObject: initialChunk),
                  let initialString = String(data: initialData, encoding: .utf8) else {
                return nil
            }
            lines.append("data: \(initialString)\n\n")

            let finalChunk: [String: Any] = [
                "id": id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": publicAlias,
                "choices": [[
                    "index": index,
                    "delta": [:],
                    "finish_reason": choice["finish_reason"] ?? "stop"
                ]]
            ]
            guard let finalData = try? JSONSerialization.data(withJSONObject: finalChunk),
                  let finalString = String(data: finalData, encoding: .utf8) else {
                return nil
            }
            lines.append("data: \(finalString)\n\n")
        }

        lines.append("data: [DONE]\n\n")
        return Data(lines.joined().utf8)
    }

    private func responsesBody(
        fromChatCompletionsResponseBody responseBody: Data,
        publicAlias: String
    ) -> Data? {
        guard let translatedResponse = translatedResponsesObject(
            fromChatCompletionsResponseBody: responseBody,
            publicAlias: publicAlias
        ) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: translatedResponse)
    }

    private func syntheticResponsesStreamBody(
        fromChatCompletionsResponseBody responseBody: Data,
        publicAlias: String
    ) -> Data? {
        guard let translatedResponse = translatedResponsesObject(
            fromChatCompletionsResponseBody: responseBody,
            publicAlias: publicAlias
        ) else {
            return nil
        }

        return syntheticResponsesStreamBody(
            fromResponsesObject: translatedResponse,
            publicAlias: publicAlias
        )
    }

    private func syntheticResponsesStreamBody(
        fromResponsesResponseBody responseBody: Data,
        publicAlias: String
    ) -> Data? {
        guard var responseObject = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any] else {
            return nil
        }
        responseObject["model"] = publicAlias

        return syntheticResponsesStreamBody(
            fromResponsesObject: responseObject,
            publicAlias: publicAlias
        )
    }

    private func syntheticResponsesStreamBody(
        fromResponsesObject responseObject: [String: Any],
        publicAlias: String
    ) -> Data? {
        var translatedResponse = responseObject
        translatedResponse["model"] = publicAlias

        let outputItems = (translatedResponse["output"] as? [[String: Any]]) ?? []
        var createdResponse = translatedResponse
        createdResponse["status"] = "in_progress"
        createdResponse["output"] = []

        var lines: [String] = []
        guard let createdLine = sseDataLine(for: [
            "type": "response.created",
            "response": createdResponse
        ]) else {
            return nil
        }
        lines.append(createdLine)

        for (outputIndex, outputItem) in outputItems.enumerated() {
            guard let type = outputItem["type"] as? String else {
                return nil
            }

            switch type {
            case "message":
                guard let itemID = outputItem["id"] as? String,
                      let addedLine = sseDataLine(for: [
                        "type": "response.output_item.added",
                        "output_index": outputIndex,
                        "item": outputItem
                      ]) else {
                    return nil
                }
                lines.append(addedLine)

                let contentArray = (outputItem["content"] as? [[String: Any]]) ?? []
                let outputText = contentArray.compactMap { $0["text"] as? String }.joined()
                if !outputText.isEmpty {
                    guard let deltaLine = sseDataLine(for: [
                        "type": "response.output_text.delta",
                        "output_index": outputIndex,
                        "item_id": itemID,
                        "content_index": 0,
                        "delta": outputText
                    ]),
                    let doneTextLine = sseDataLine(for: [
                        "type": "response.output_text.done",
                        "output_index": outputIndex,
                        "item_id": itemID,
                        "content_index": 0,
                        "text": outputText
                    ]) else {
                        return nil
                    }
                    lines.append(deltaLine)
                    lines.append(doneTextLine)
                }

                guard let doneItemLine = sseDataLine(for: [
                    "type": "response.output_item.done",
                    "output_index": outputIndex,
                    "item": outputItem
                ]) else {
                    return nil
                }
                lines.append(doneItemLine)
            case "function_call":
                var addedItem = outputItem
                let arguments = (outputItem["arguments"] as? String) ?? ""
                addedItem["arguments"] = ""

                guard let addedLine = sseDataLine(for: [
                    "type": "response.output_item.added",
                    "output_index": outputIndex,
                    "item": addedItem
                ]) else {
                    return nil
                }
                lines.append(addedLine)

                if !arguments.isEmpty {
                    guard let deltaLine = sseDataLine(for: [
                        "type": "response.function_call_arguments.delta",
                        "output_index": outputIndex,
                        "delta": arguments
                    ]),
                    let doneArgumentsLine = sseDataLine(for: [
                        "type": "response.function_call_arguments.done",
                        "output_index": outputIndex,
                        "arguments": arguments
                    ]) else {
                        return nil
                    }
                    lines.append(deltaLine)
                    lines.append(doneArgumentsLine)
                }

                guard let doneItemLine = sseDataLine(for: [
                    "type": "response.output_item.done",
                    "output_index": outputIndex,
                    "item": outputItem
                ]) else {
                    return nil
                }
                lines.append(doneItemLine)
            case "reasoning":
                guard let addedLine = sseDataLine(for: [
                    "type": "response.output_item.added",
                    "output_index": outputIndex,
                    "item": outputItem
                ]) else {
                    return nil
                }
                lines.append(addedLine)

                guard let doneItemLine = sseDataLine(for: [
                    "type": "response.output_item.done",
                    "output_index": outputIndex,
                    "item": outputItem
                ]) else {
                    return nil
                }
                lines.append(doneItemLine)
            default:
                // Preserve newer Responses output-item variants without forcing
                // the caller through a synthetic 502 just because this proxy
                // does not yet have bespoke delta events for that item type.
                guard let addedLine = sseDataLine(for: [
                    "type": "response.output_item.added",
                    "output_index": outputIndex,
                    "item": outputItem
                ]) else {
                    return nil
                }
                lines.append(addedLine)

                guard let doneItemLine = sseDataLine(for: [
                    "type": "response.output_item.done",
                    "output_index": outputIndex,
                    "item": outputItem
                ]) else {
                    return nil
                }
                lines.append(doneItemLine)
            }
        }

        let finalEventType = ((translatedResponse["status"] as? String) == "incomplete")
            ? "response.incomplete"
            : "response.completed"
        guard let finalLine = sseDataLine(for: [
            "type": finalEventType,
            "response": translatedResponse
        ]) else {
            return nil
        }
        lines.append(finalLine)
        lines.append("data: [DONE]\n\n")

        return Data(lines.joined().utf8)
    }

    private func translatedResponsesObject(
        fromChatCompletionsResponseBody responseBody: Data,
        publicAlias: String
    ) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        let created = (root["created"] as? Int) ?? Int(Date().timeIntervalSince1970)
        let responseID = translatedResponsesID(fromChatCompletionsID: root["id"] as? String)
        let finishReason = ((firstChoice["finish_reason"] as? String) ?? "stop").lowercased()
        let message = firstChoice["message"] as? [String: Any] ?? [:]

        var outputItems: [[String: Any]] = []
        let rawContent = (message["content"] as? String) ?? ""
        if !rawContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputItems.append([
                "id": "msg_\(responseID)",
                "type": "message",
                "role": "assistant",
                "status": "completed",
                "content": [[
                    "type": "output_text",
                    "text": rawContent,
                    "annotations": []
                ]]
            ])
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            for (toolIndex, toolCall) in toolCalls.enumerated() {
                guard let function = toolCall["function"] as? [String: Any],
                      let functionName = function["name"] as? String,
                      let functionArguments = function["arguments"] as? String else {
                    return nil
                }
                let callID = (toolCall["id"] as? String) ?? "call_\(toolIndex)"
                outputItems.append([
                    "id": "fc_\(callID)",
                    "type": "function_call",
                    "call_id": callID,
                    "name": functionName,
                    "arguments": functionArguments,
                    "status": "completed"
                ])
            }
        }

        guard !outputItems.isEmpty else {
            return nil
        }

        let status = finishReason == "length" ? "incomplete" : "completed"
        var response: [String: Any] = [
            "id": responseID,
            "object": "response",
            "created": created,
            "status": status,
            "model": publicAlias,
            "output": outputItems
        ]

        if status == "incomplete" {
            response["incomplete_details"] = [
                "reason": "max_output_tokens"
            ]
        }

        if let usage = translatedResponsesUsage(fromChatCompletionsUsage: root["usage"] as? [String: Any]) {
            response["usage"] = usage
        }

        return response
    }

    private func translatedResponsesUsage(fromChatCompletionsUsage usage: [String: Any]?) -> [String: Any]? {
        guard let usage else {
            return nil
        }

        let inputTokens = OpenAICompatTemporaryShim.integerValue(usage["prompt_tokens"]) ?? 0
        let outputTokens = OpenAICompatTemporaryShim.integerValue(usage["completion_tokens"]) ?? 0
        let totalTokens = OpenAICompatTemporaryShim.integerValue(usage["total_tokens"]) ?? (inputTokens + outputTokens)

        var translatedUsage: [String: Any] = [
            "input_tokens": inputTokens,
            "output_tokens": outputTokens,
            "total_tokens": totalTokens
        ]

        if let promptDetails = usage["prompt_tokens_details"] as? [String: Any],
           let cachedTokens = OpenAICompatTemporaryShim.integerValue(promptDetails["cached_tokens"]) {
            translatedUsage["input_tokens_details"] = [
                "cached_tokens": cachedTokens
            ]
        }

        if let completionDetails = usage["completion_tokens_details"] as? [String: Any] {
            var outputDetails: [String: Any] = [:]
            if let reasoningTokens = OpenAICompatTemporaryShim.integerValue(completionDetails["reasoning_tokens"]) {
                outputDetails["reasoning_tokens"] = reasoningTokens
            }
            if !outputDetails.isEmpty {
                translatedUsage["output_tokens_details"] = outputDetails
            }
        }

        return translatedUsage
    }

    private func translatedResponsesID(fromChatCompletionsID chatCompletionID: String?) -> String {
        let normalizedID = (chatCompletionID?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "chatcmpl-worker"
        if normalizedID.hasPrefix("resp_") {
            return normalizedID
        }
        return "resp_\(normalizedID)"
    }

    private func sseDataLine(for json: [String: Any]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: json),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return "data: \(jsonString)\n\n"
    }

    private func rewriteNVIDIAStreamOutput(
        _ output: NVIDIAStreamParserOutput,
        publicAlias: String
    ) -> NVIDIAStreamParserOutput {
        switch output {
        case .comment, .done:
            return output
        case .message(var message):
            message.dataLines = message.dataLines.map { dataLine in
                guard let jsonData = dataLine.data(using: .utf8),
                      var json = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
                      json["model"] != nil else {
                    return dataLine
                }
                json["model"] = publicAlias
                guard let rewrittenData = try? JSONSerialization.data(withJSONObject: json),
                      let rewrittenLine = String(data: rewrittenData, encoding: .utf8) else {
                    return dataLine
                }
                return rewrittenLine
            }
            return .message(message)
        }
    }

    private func executeSmartAliasCandidate(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        publicAlias: String,
        candidateModel: String,
        failoverDepth: Int,
        attemptLane: Int,
        deadlineAt: Date,
        originalConnection: NWConnection,
        deliveryMode: SmartAliasDeliveryMode,
        coalescingKey: String?,
        controller: RequestCancellationController?,
        onNVIDIAMeaningfulOutput: (() -> Bool)? = nil,
        requestTrace: RequestTraceContext,
        completion: @escaping (SmartAliasCandidateAttemptOutcome) -> Void
    ) {
        let remainingBudget = remainingSmartAliasBudget(until: deadlineAt)
        guard remainingBudget > 0 else {
            completion(
                .terminalError(
                    requestModel: candidateModel,
                    statusCode: 504,
                    message: "Worker failover budget exhausted before any backend returned a valid response.",
                    telemetryEvent: nil,
                    errorBodySnippet: nil
                )
            )
            return
        }

        let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel)
        let requiredToolParameters = OpenAICompatTemporaryShim.requiredToolParametersIndex(forRequestJSON: body)
        let telemetrySource = smartAliasTelemetrySource(headers: headers)
        OpenAICompatTemporaryShim.recordRecentSmartAliasDispatch(
            requestedAlias: publicAlias,
            requestModel: candidateModel,
            requestShape: requestTrace.requestShape,
            callerRequestID: requestTrace.callerRequestID,
            callerSessionID: requestTrace.callerSessionID
        )
        let bufferedSyntheticBody: String = {
            switch deliveryMode {
            case .syntheticSSE, .syntheticResponsesSSE:
                return Self.forcingNonStreamChatRequestBody(from: body) ?? body
            case .bufferedJSON, .bufferedResponsesJSON:
                return body
            }
        }()
        let concurrencyRetryUntil = Date().addingTimeInterval(1)
        let concurrencyLimitedTelemetry = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: "retry",
                attemptLane: attemptLane,
                failoverDepth: failoverDepth,
                failureClass: "classified_429_concurrency",
                timeoutStage: .none,
                upstreamHTTPStatus: 429,
                retryCount: 0,
                source: telemetrySource,
                firstByteLatencyMilliseconds: nil,
                totalLatencyMilliseconds: nil,
                inflightAtRequest: route.map { OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: $0.routeHealthKey) },
                proxyRequestID: requestTrace.proxyRequestID,
                callerRequestID: requestTrace.callerRequestID,
                callerSessionID: requestTrace.callerSessionID,
                requestShape: requestTrace.requestShape
            ),
            requestedAlias: publicAlias,
            failoverDepth: failoverDepth,
            finalWinnerRequestModel: nil
        )

        if let candidateRoute = route,
           candidateRoute.providerID.hasPrefix("nvidia"),
           OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
            method: method,
            path: path,
            jsonString: body
           ) {
            let retryBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: body)
            executeSmartAliasMitigatedCandidate(
                method: method,
                path: path,
                headers: headers,
                body: body,
                publicAlias: publicAlias,
                candidateModel: candidateModel,
                failoverDepth: failoverDepth,
                attemptLane: attemptLane,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                deliveryMode: deliveryMode,
                controller: controller,
                onNVIDIAMeaningfulOutput: onNVIDIAMeaningfulOutput,
                state: OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: candidateModel,
                    requiredToolParameters: requiredToolParameters,
                    initialTransportRetries: retryBudget?.transport ?? Config.nvidiaReasoningTransportRetries,
                    initialSemanticRetries: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    transportRetriesRemaining: retryBudget?.transport ?? Config.nvidiaReasoningTransportRetries,
                    semanticRetriesRemaining: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    retryBackoffMilliseconds: retryBudget?.backoffMilliseconds ?? 0,
                    salvagesBestEffortRepair: retryBudget?.salvagesBestEffortRepair ?? false,
                    bestEffortRepairedBodyData: nil,
                    coalescingKey: coalescingKey
                ),
                requestTrace: requestTrace,
                completion: completion
            )
            return
        }

        // Meta AI web adapter: muse-spark is not an OpenAI-compatible endpoint.
        // The GraphQL adapter must handle it directly, not through HTTP proxy forwarding.
        if let candidateRoute = route,
           candidateRoute.providerID == MetaAIWebAdapter.providerID {
            let metaBufferedResponse = executeMetaAIAdapterBufferedResponse(
                path: path,
                body: bufferedSyntheticBody,
                publicModel: candidateModel
            )
            handleSmartAliasBufferedCandidateResult(
                metaBufferedResponse,
                path: path,
                headers: headers,
                publicAlias: publicAlias,
                candidateModel: candidateModel,
                failoverDepth: failoverDepth,
                attemptLane: attemptLane,
                inflightAtRequest: nil,
                requiredToolParameters: requiredToolParameters,
                requestTrace: requestTrace,
                completion: completion
            )
            return
        }

        let timeoutInterval = min(
            smartAliasCandidateTimeout(forRequestJSON: body, publicAlias: publicAlias, candidateModel: candidateModel),
            remainingBudget
        )
        let effectiveHeaders = headersInjectingRouteSpecific(headers, forCandidateModel: candidateModel)
        guard let permit = acquireRouteConcurrencyPermit(forRequestModel: candidateModel) else {
            completion(
                .retryableFailure(
                    requestModel: candidateModel,
                    telemetryEvent: concurrencyLimitedTelemetry,
                    cooldownUntil: concurrencyRetryUntil
                )
            )
            return
        }

        // Direct proxied path for providers with per-provider proxy-url (e.g., opencode via SOCKS5)
        if let route,
           let endpoint = OpenAICompatTemporaryShim.providerEndpoint(forProviderID: route.providerID) {
            let directCancel = sendDirectProxiedRequest(
                method: method,
                path: path,
                headers: effectiveHeaders,
                body: bufferedSyntheticBody,
                candidateModel: candidateModel,
                timeoutInterval: timeoutInterval,
                endpoint: endpoint,
                firstResponseDeadlineSeconds: OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                    forRequestJSON: body,
                    routeHealthStatus: OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: candidateModel)
                ),
                bufferedResponseDeadlineSeconds: OpenAICompatTemporaryShim.effectiveBufferedResponseDeadline(forRequestJSON: body)
            ) { [weak self] bufferedResponse in
                permit.release()
                guard let self, controller?.isCancelled() != true else { return }
                self.handleSmartAliasBufferedCandidateResult(
                    bufferedResponse,
                    path: path,
                    headers: headers,
                    publicAlias: publicAlias,
                    candidateModel: candidateModel,
                    failoverDepth: failoverDepth,
                    attemptLane: attemptLane,
                    inflightAtRequest: permit.inflightAtRequest,
                    requiredToolParameters: requiredToolParameters,
                    requestTrace: requestTrace,
                    completion: completion
                )
            }
            controller?.registerCurrentCancel {
                permit.release()
                directCancel()
            }
            return
        }

        let cancel = sendBufferedProxyRequest(
            method: method,
            path: path,
            headers: effectiveHeaders,
            body: bufferedSyntheticBody,
            timeoutInterval: timeoutInterval,
            firstResponseDeadlineSeconds: OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                forRequestJSON: body,
                routeHealthStatus: OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: candidateModel)
            ),
            bufferedResponseDeadlineSeconds: OpenAICompatTemporaryShim.effectiveBufferedResponseDeadline(forRequestJSON: body)
        ) { [weak self] bufferedResponse in
            permit.release()
            guard let self, controller?.isCancelled() != true else { return }
            self.handleSmartAliasBufferedCandidateResult(
                bufferedResponse,
                path: path,
                headers: headers,
                publicAlias: publicAlias,
                candidateModel: candidateModel,
                failoverDepth: failoverDepth,
                attemptLane: attemptLane,
                inflightAtRequest: permit.inflightAtRequest,
                requiredToolParameters: requiredToolParameters,
                requestTrace: requestTrace,
                completion: completion
            )
        }
        controller?.registerCurrentCancel {
            permit.release()
            cancel()
        }
    }

    private func executeSmartAliasMitigatedCandidate(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        publicAlias: String,
        candidateModel: String,
        failoverDepth: Int,
        attemptLane: Int,
        deadlineAt: Date,
        originalConnection: NWConnection,
        deliveryMode: SmartAliasDeliveryMode,
        controller: RequestCancellationController?,
        onNVIDIAMeaningfulOutput: (() -> Bool)?,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        requestTrace: RequestTraceContext,
        completion: @escaping (SmartAliasCandidateAttemptOutcome) -> Void
    ) {
        let remainingBudget = remainingSmartAliasBudget(until: deadlineAt)
        guard remainingBudget > 0 else {
            completion(
                .terminalError(
                    requestModel: candidateModel,
                    statusCode: 504,
                    message: "Worker failover budget exhausted before any backend returned a valid response.",
                    telemetryEvent: nil,
                    errorBodySnippet: nil
                )
            )
            return
        }

        let timeoutInterval = min(
            smartAliasCandidateTimeout(forRequestJSON: body, publicAlias: publicAlias, candidateModel: candidateModel),
            remainingBudget
        )
        let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel)
        let telemetrySource = smartAliasTelemetrySource(headers: headers)
        let concurrencyRetryUntil = Date().addingTimeInterval(1)
        let concurrencyLimitedTelemetry = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: "retry",
                attemptLane: attemptLane,
                failoverDepth: failoverDepth,
                failureClass: "classified_429_concurrency",
                timeoutStage: .none,
                upstreamHTTPStatus: 429,
                retryCount: 0,
                source: telemetrySource,
                firstByteLatencyMilliseconds: nil,
                totalLatencyMilliseconds: nil,
                inflightAtRequest: route.map { OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: $0.routeHealthKey) },
                proxyRequestID: requestTrace.proxyRequestID,
                callerRequestID: requestTrace.callerRequestID,
                callerSessionID: requestTrace.callerSessionID,
                requestShape: requestTrace.requestShape
            ),
            requestedAlias: publicAlias,
            failoverDepth: failoverDepth,
            finalWinnerRequestModel: nil
        )
        guard let permit = acquireRouteConcurrencyPermit(forRequestModel: candidateModel) else {
            completion(
                .retryableFailure(
                    requestModel: candidateModel,
                    telemetryEvent: concurrencyLimitedTelemetry,
                    cooldownUntil: concurrencyRetryUntil
                )
            )
            return
        }
        guard let url = URL(string: "http://\(effectiveNVIDIADirectTargetHost):\(effectiveNVIDIADirectTargetPort)\(path)") else {
            permit.release()
            completion(
                .terminalError(
                    requestModel: candidateModel,
                    statusCode: 500,
                    message: "Internal Server Error",
                    telemetryEvent: nil,
                    errorBodySnippet: nil
                )
            )
            return
        }

        let effectiveHeaders = headersInjectingRouteSpecific(headers, forCandidateModel: candidateModel)
        let internalStreaming = OpenAICompatTemporaryShim.requestedStream(forRequestJSON: body)
        let upstreamBody = OpenAICompatTemporaryShim.rewrittenNVIDIADirectUpstreamRequestJSON(
            method: method,
            path: path,
            jsonString: body
        ) ?? body
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = Data(upstreamBody.utf8)
        request.timeoutInterval = timeoutInterval
        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in effectiveHeaders where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("close", forHTTPHeaderField: "Connection")

        let transportPolicy = effectiveNVIDIADirectTransportPolicy()
        let liveStreamingEnabled = internalStreaming && deliveryMode == .syntheticSSE
        let lockingQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-smart-alias-locking")
        var lockingEngine = NVIDIAStreamEngine()
        var meaningfulOutputLocked = false
        var receivedChunkCount = 0
        var liveStreamStarted = false
        var liveStreamFinished = false
        var liveStreamFailed = false
        var interChunkTimeoutTriggered = false
        var keepaliveTimer: DispatchSourceTimer?
        var interChunkDeadlineWorkItem: DispatchWorkItem?
        var transportCancel: (() -> Void)?
        var liveStreamingSink = NVIDIAEventStreamSink(policy: transportPolicy.sinkPolicy)
        let resolutionHeaders = smartAliasResolutionHeaders(
            publicAlias: publicAlias,
            resolvedRequestModel: candidateModel,
            requestTrace: requestTrace
        )

        func cancelStreamingTimersLocked() {
            interChunkDeadlineWorkItem?.cancel()
            interChunkDeadlineWorkItem = nil
            keepaliveTimer?.cancel()
            keepaliveTimer = nil
        }

        let scheduleKeepaliveTimerIfNeeded: () -> Void = { [weak self] in
            guard let self else { return }
            let timerToStart: DispatchSourceTimer? = lockingQueue.sync {
                guard liveStreamingEnabled,
                      transportPolicy.sinkPolicy.emitsDownstreamKeepalives,
                      transportPolicy.sinkPolicy.keepaliveIntervalSeconds > 0,
                      liveStreamStarted,
                      !liveStreamFinished,
                      keepaliveTimer == nil else {
                    return nil
                }
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
                timer.schedule(
                    deadline: .now() + transportPolicy.sinkPolicy.keepaliveIntervalSeconds,
                    repeating: transportPolicy.sinkPolicy.keepaliveIntervalSeconds
                )
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    let keepaliveFrame: Data? = lockingQueue.sync {
                        guard liveStreamStarted,
                              !liveStreamFinished,
                              !liveStreamFailed,
                              controller?.isCancelled() != true,
                              let keepalive = liveStreamingSink.emitKeepaliveIfIdle(now: Date()) else {
                            return nil
                        }
                        return Data(keepalive.utf8)
                    }
                    if let keepaliveFrame {
                        self.sendStreamingHTTPChunk(to: originalConnection, chunk: keepaliveFrame)
                    }
                }
                keepaliveTimer = timer
                return timer
            }
            timerToStart?.resume()
        }

        let resetInterChunkDeadline: () -> Void = {
            guard liveStreamingEnabled, transportPolicy.interChunkReadTimeoutSeconds > 0 else { return }
            let workItemToSchedule: DispatchWorkItem? = lockingQueue.sync {
                guard !liveStreamFinished else { return nil }
                interChunkDeadlineWorkItem?.cancel()
                let workItem = DispatchWorkItem {
                    let cancelAction: (() -> Void)? = lockingQueue.sync {
                        guard !liveStreamFinished,
                              !liveStreamFailed,
                              controller?.isCancelled() != true else {
                            return nil
                        }
                        interChunkTimeoutTriggered = true
                        liveStreamFailed = true
                        return transportCancel
                    }
                    cancelAction?()
                }
                interChunkDeadlineWorkItem = workItem
                return workItem
            }
            if let workItemToSchedule {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + transportPolicy.interChunkReadTimeoutSeconds,
                    execute: workItemToSchedule
                )
            }
        }

        let lockMeaningfulOutputIfNeeded: (Data, Date) -> Void = { [weak self] chunk, receivedAt in
            guard internalStreaming else { return }
            resetInterChunkDeadline()
            guard let self else { return }
            let emittedFrames: [Data]? = lockingQueue.sync {
                guard !liveStreamFailed else { return nil }
                do {
                    receivedChunkCount += 1
                    let outputs = try lockingEngine.ingest(
                        chunk,
                        receivedAt: receivedAt,
                        surface: .smartAlias,
                        attemptLane: attemptLane
                    )
                    if !meaningfulOutputLocked,
                       lockingEngine.ownsMeaningfulOutput(surface: .smartAlias, attemptLane: attemptLane) {
                        meaningfulOutputLocked = onNVIDIAMeaningfulOutput?() ?? true
                    }
                    guard liveStreamingEnabled, meaningfulOutputLocked, !outputs.isEmpty else {
                        return []
                    }

                    var frames: [Data] = []
                    for output in outputs {
                        let outwardOutput = self.rewriteNVIDIAStreamOutput(output, publicAlias: publicAlias)
                        switch outwardOutput {
                        case .comment:
                            continue
                        case .message, .done:
                            if !liveStreamStarted {
                                let sseHeaders: [AnyHashable: Any] = [
                                    "Content-Type": "text/event-stream; charset=utf-8",
                                    "Cache-Control": "no-cache",
                                    "X-Accel-Buffering": "no"
                                ]
                                self.startStreamingHTTPResponse(
                                    to: originalConnection,
                                    statusCode: 200,
                                    headers: sseHeaders,
                                    overridingHeaders: resolutionHeaders
                                )
                                liveStreamStarted = true
                            }
                            let previousFrameCount = liveStreamingSink.emittedFrames.count
                            try liveStreamingSink.consume(outwardOutput, receivedAt: receivedAt)
                            let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                            if let emittedFrame = newFrames.last {
                                frames.append(Data(emittedFrame.utf8))
                            }
                        }
                    }
                    return frames
                } catch {
                    liveStreamFailed = true
                    cancelStreamingTimersLocked()
                    return nil
                }
            }

            guard let emittedFrames else { return }
            scheduleKeepaliveTimerIfNeeded()
            for frame in emittedFrames {
                self.sendStreamingHTTPChunk(to: originalConnection, chunk: frame)
            }
        }

        let handleTransportResponse: (NVIDIADirectTransportResponse) -> Void = { [weak self] transportResponse in
            permit.release()
            guard let self, controller?.isCancelled() != true else { return }

            let effectiveTransportResponse: NVIDIADirectTransportResponse = lockingQueue.sync {
                liveStreamFinished = true
                cancelStreamingTimersLocked()
                if interChunkTimeoutTriggered && transportResponse.deadlineStage == .none {
                    return NVIDIADirectTransportResponse(
                        chunks: transportResponse.chunks,
                        response: transportResponse.response,
                        error: transportResponse.error ?? URLError(.timedOut),
                        firstByteLatencyMilliseconds: transportResponse.firstByteLatencyMilliseconds,
                        totalLatencyMilliseconds: transportResponse.totalLatencyMilliseconds,
                        deadlineStage: .interChunkRead
                    )
                }
                return transportResponse
            }

            if liveStreamingEnabled {
                let trailingFrames: [Data]? = lockingQueue.sync {
                    guard liveStreamStarted, meaningfulOutputLocked, !liveStreamFailed else { return nil }
                    do {
                        var frames: [Data] = []
                        let remainingChunks = effectiveTransportResponse.chunks.dropFirst(receivedChunkCount)
                        for chunk in remainingChunks {
                            let outputs = try lockingEngine.ingest(
                                chunk,
                                receivedAt: Date(),
                                surface: .smartAlias,
                                attemptLane: attemptLane
                            )
                            for output in outputs {
                                let outwardOutput = self.rewriteNVIDIAStreamOutput(output, publicAlias: publicAlias)
                                switch outwardOutput {
                                case .comment:
                                    continue
                                case .message, .done:
                                    let previousFrameCount = liveStreamingSink.emittedFrames.count
                                    try liveStreamingSink.consume(outwardOutput)
                                    let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                                    if let emittedFrame = newFrames.last {
                                        frames.append(Data(emittedFrame.utf8))
                                    }
                                }
                            }
                        }
                        receivedChunkCount = effectiveTransportResponse.chunks.count
                        let trailingOutputs = try lockingEngine.finish(
                            surface: .smartAlias,
                            attemptLane: attemptLane
                        )
                        for output in trailingOutputs {
                            let outwardOutput = self.rewriteNVIDIAStreamOutput(output, publicAlias: publicAlias)
                            switch outwardOutput {
                            case .comment:
                                continue
                            case .message, .done:
                                let previousFrameCount = liveStreamingSink.emittedFrames.count
                                try liveStreamingSink.consume(outwardOutput)
                                let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                                if let emittedFrame = newFrames.last {
                                    frames.append(Data(emittedFrame.utf8))
                                }
                            }
                        }
                        if !liveStreamingSink.terminalReceived {
                            let previousFrameCount = liveStreamingSink.emittedFrames.count
                            try liveStreamingSink.consume(.done)
                            let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                            if let emittedFrame = newFrames.last {
                                frames.append(Data(emittedFrame.utf8))
                            }
                        }
                        return frames
                    } catch {
                        liveStreamFailed = true
                        return nil
                    }
                }
                if let trailingFrames {
                    for frame in trailingFrames {
                        self.sendStreamingHTTPChunk(to: originalConnection, chunk: frame)
                    }
                }
            }

            let processedAttempt = self.processNVIDIAStreamingAttemptResponse(
                effectiveTransportResponse,
                state: state,
                attemptLane: attemptLane,
                clientRequestedStream: false,
                surface: .smartAlias
            )
            let attempt = processedAttempt.attempt
            let rawOutcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                path: path,
                state: state,
                attempt: attempt
            )
            let effectiveOutcome: OpenAICompatTemporaryShim.NVIDIARuntimeOutcome
            if meaningfulOutputLocked,
               case .retry = rawOutcome {
                var exhaustedState = state
                exhaustedState.transportRetriesRemaining = 0
                exhaustedState.semanticRetriesRemaining = 0
                effectiveOutcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: path,
                    state: exhaustedState,
                    attempt: attempt
                )
            } else {
                effectiveOutcome = rawOutcome
            }

            let telemetryEvent = self.annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.telemetryEvent(
                    path: path,
                    state: state,
                    attempt: attempt,
                    outcome: effectiveOutcome,
                    source: telemetrySource,
                    attemptLane: attemptLane,
                    proxyRequestID: requestTrace.proxyRequestID,
                    callerRequestID: requestTrace.callerRequestID,
                    callerSessionID: requestTrace.callerSessionID,
                    requestShape: requestTrace.requestShape
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )

            switch effectiveOutcome {
            case .retry(let nextState):
                if let response = attempt.response {
                    OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest,
                        statusCode: response.statusCode,
                        headers: response.allHeaderFields,
                        bodyData: attempt.data
                    )
                }
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                let liveStreamWasDelivered = lockingQueue.sync { liveStreamStarted && meaningfulOutputLocked }
                if liveStreamWasDelivered {
                    self.finishStreamingHTTPResponse(to: originalConnection)
                    completion(
                        .liveStreamDelivered(
                            requestModel: candidateModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: attempt.response.flatMap {
                                OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                                    failureClass: telemetryEvent.failureClass,
                                    statusCode: $0.statusCode,
                                    headers: $0.allHeaderFields,
                                    bodyData: attempt.data
                                )
                            }
                        )
                    )
                    return
                }
                let delay = DispatchTimeInterval.milliseconds(
                    OpenAICompatTemporaryShim.jitteredRetryBackoffMilliseconds(nextState.retryBackoffMilliseconds)
                )
                let retryBlock = { [weak self] in
                    guard let self, controller?.isCancelled() != true else { return }
                    self.executeSmartAliasMitigatedCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        body: body,
                        publicAlias: publicAlias,
                        candidateModel: candidateModel,
                        failoverDepth: failoverDepth,
                        attemptLane: attemptLane,
                        deadlineAt: deadlineAt,
                        originalConnection: originalConnection,
                        deliveryMode: deliveryMode,
                        controller: controller,
                        onNVIDIAMeaningfulOutput: onNVIDIAMeaningfulOutput,
                        state: nextState,
                        requestTrace: requestTrace,
                        completion: completion
                    )
                }
                if nextState.retryBackoffMilliseconds > 0 {
                    controller?.scheduleRetry(after: delay, block: retryBlock)
                } else {
                    retryBlock()
                }
            case .sendResponse(let statusCode, let responseHeaders, let responseBody):
                let classifiedFailure = self.classifySmartAliasCandidateFailure(
                    statusCode: statusCode,
                    headers: responseHeaders,
                    bodyData: responseBody,
                    path: path,
                    requiredToolParameters: state.requiredToolParameters
                )
                if classifiedFailure.shouldFailover, !meaningfulOutputLocked {
                    OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest,
                        statusCode: statusCode,
                        headers: responseHeaders,
                        bodyData: responseBody
                    )
                    let cooldownUntil = OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                        failureClass: telemetryEvent.failureClass,
                        statusCode: statusCode,
                        headers: responseHeaders,
                        bodyData: responseBody
                    )
                    if let deferredUntil = OpenAICompatTemporaryShim.smartAliasAvailabilityDeferralUntil(
                        failureClass: telemetryEvent.failureClass,
                        statusCode: statusCode,
                        headers: responseHeaders,
                        bodyData: responseBody
                    ) {
                        OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                            forRequestModel: candidateModel,
                            until: deferredUntil
                        )
                    }
                    completion(
                        .retryableFailure(
                            requestModel: candidateModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: cooldownUntil
                        )
                    )
                    return
                }

                let liveStreamWasDelivered = lockingQueue.sync { liveStreamStarted && meaningfulOutputLocked }
                if liveStreamWasDelivered {
                    self.finishStreamingHTTPResponse(to: originalConnection)
                    completion(
                        .liveStreamDelivered(
                            requestModel: candidateModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: classifiedFailure.shouldFailover
                                ? OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                                    failureClass: telemetryEvent.failureClass,
                                    statusCode: statusCode,
                                    headers: responseHeaders,
                                    bodyData: responseBody
                                )
                                : nil
                        )
                    )
                    return
                }

                if liveStreamingEnabled,
                   statusCode >= 200,
                   statusCode < 300 {
                    completion(
                        .terminalError(
                            requestModel: candidateModel,
                            statusCode: 502,
                            message: "Bad Gateway - NVIDIA stream finished without live SSE delivery",
                            telemetryEvent: telemetryEvent,
                            errorBodySnippet: OpenAICompatTemporaryShim.sanitizeErrorBodySnippet(responseBody)
                        )
                    )
                    return
                }

                if statusCode >= 200 && statusCode < 300 {
                    OpenAICompatTemporaryShim.recordConcurrencySuccess(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest
                    )
                    completion(
                        .success(
                            requestModel: candidateModel,
                            statusCode: statusCode,
                            headers: responseHeaders,
                            body: responseBody,
                            telemetryEvent: telemetryEvent
                        )
                    )
                    return
                }

                completion(
                    .terminalResponse(
                        requestModel: candidateModel,
                        statusCode: statusCode,
                        headers: responseHeaders,
                        body: responseBody,
                        telemetryEvent: telemetryEvent
                    )
                )
            case .sendError(let statusCode, let message):
                let classifiedFailure = self.classifySmartAliasCandidateFailure(
                    statusCode: statusCode,
                    headers: attempt.response?.allHeaderFields ?? [:],
                    bodyData: nil,
                    path: path,
                    requiredToolParameters: state.requiredToolParameters
                )
                if classifiedFailure.shouldFailover, !meaningfulOutputLocked {
                    let cooldownUntil = attempt.response.flatMap {
                        OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                            failureClass: telemetryEvent.failureClass,
                            statusCode: statusCode,
                            headers: $0.allHeaderFields
                        )
                    } ?? nil
                    if let response = attempt.response,
                       let deferredUntil = OpenAICompatTemporaryShim.smartAliasAvailabilityDeferralUntil(
                        failureClass: telemetryEvent.failureClass,
                        statusCode: statusCode,
                        headers: response.allHeaderFields
                       ) {
                        OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                            forRequestModel: candidateModel,
                            until: deferredUntil
                        )
                    }
                    completion(
                        .retryableFailure(
                            requestModel: candidateModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: cooldownUntil
                        )
                    )
                    return
                }

                let liveStreamWasDelivered = lockingQueue.sync { liveStreamStarted && meaningfulOutputLocked }
                if liveStreamWasDelivered {
                    self.finishStreamingHTTPResponse(to: originalConnection)
                    completion(
                        .liveStreamDelivered(
                            requestModel: candidateModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: attempt.response.flatMap {
                                OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                                    failureClass: telemetryEvent.failureClass,
                                    statusCode: statusCode,
                                    headers: $0.allHeaderFields
                                )
                            }
                        )
                    )
                    return
                }

                completion(
                    .terminalError(
                        requestModel: candidateModel,
                        statusCode: statusCode,
                        message: message,
                        telemetryEvent: telemetryEvent,
                        errorBodySnippet: nil
                    )
                )
            }
        }

        guard let cancel = startNVIDIATransportAttempt(
            request: request,
            requestJSON: body,
            requestModel: candidateModel,
            clientRequestedStream: internalStreaming,
            onChunk: lockMeaningfulOutputIfNeeded,
            completion: handleTransportResponse
        ) else {
            permit.release()
            completion(
                .terminalError(
                    requestModel: candidateModel,
                    statusCode: 502,
                    message: "upstream session unavailable",
                    telemetryEvent: nil,
                    errorBodySnippet: nil
                )
            )
            return
        }
        lockingQueue.sync {
            transportCancel = cancel
        }
        controller?.registerCurrentCancel {
            permit.release()
            let cancelAction: (() -> Void)? = lockingQueue.sync {
                liveStreamFinished = true
                cancelStreamingTimersLocked()
                return transportCancel
            }
            cancelAction?()
        }
    }

    private func handleSmartAliasBufferedCandidateResult(
        _ bufferedResponse: BufferedProxyResponse,
        path: String,
        headers: [(String, String)],
        publicAlias: String,
        candidateModel: String,
        failoverDepth: Int,
        attemptLane: Int,
        inflightAtRequest: Int? = nil,
        requiredToolParameters: [String: [String]]? = nil,
        requestTrace: RequestTraceContext,
        completion: @escaping (SmartAliasCandidateAttemptOutcome) -> Void
    ) {
        let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel)
        let telemetrySource = smartAliasTelemetrySource(headers: headers)

        if let error = bufferedResponse.error {
            let telemetryEvent = annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: Date(),
                    requestModel: candidateModel,
                    requestedAlias: publicAlias,
                    canonicalModelID: route?.canonicalModelID ?? candidateModel,
                    transportOutcome: "retry",
                    attemptLane: attemptLane,
                    failoverDepth: failoverDepth,
                    failureClass: transportFailureClass(error),
                    timeoutStage: bufferedResponse.deadlineStage,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: telemetrySource,
                    firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                    totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
                    inflightAtRequest: inflightAtRequest,
                    proxyRequestID: requestTrace.proxyRequestID,
                    callerRequestID: requestTrace.callerRequestID,
                    callerSessionID: requestTrace.callerSessionID,
                    requestShape: requestTrace.requestShape
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )
            completion(
                .retryableFailure(
                    requestModel: candidateModel,
                    telemetryEvent: telemetryEvent,
                    cooldownUntil: nil
                )
            )
            return
        }

        guard let response = bufferedResponse.response,
              let responseData = bufferedResponse.data else {
            let telemetryEvent = annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: Date(),
                    requestModel: candidateModel,
                    requestedAlias: publicAlias,
                    canonicalModelID: route?.canonicalModelID ?? candidateModel,
                    transportOutcome: "retry",
                    attemptLane: attemptLane,
                    failoverDepth: failoverDepth,
                    failureClass: "missing_response_material",
                    timeoutStage: bufferedResponse.deadlineStage,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: telemetrySource,
                    firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                    totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
                    inflightAtRequest: inflightAtRequest,
                    proxyRequestID: requestTrace.proxyRequestID,
                    callerRequestID: requestTrace.callerRequestID,
                    callerSessionID: requestTrace.callerSessionID,
                    requestShape: requestTrace.requestShape
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )
            completion(
                .retryableFailure(
                    requestModel: candidateModel,
                    telemetryEvent: telemetryEvent,
                    cooldownUntil: nil
                )
            )
            return
        }

        let statusCode = response.statusCode
        let failureClassification = classifySmartAliasCandidateFailure(
            statusCode: statusCode,
            headers: response.allHeaderFields,
            bodyData: responseData,
            path: path,
            requiredToolParameters: requiredToolParameters
        )
        let shouldFailover = failureClassification.shouldFailover
        let failureClass = failureClassification.failureClass
        let telemetryEvent = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: shouldFailover
                    ? "retry"
                    : (statusCode >= 200 && statusCode < 300 ? "send_response" : "send_error"),
                attemptLane: attemptLane,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: (!shouldFailover && statusCode >= 200 && statusCode < 300) ? candidateModel : nil,
                failureClass: failureClass,
                timeoutStage: bufferedResponse.deadlineStage,
                upstreamHTTPStatus: statusCode,
                retryCount: 0,
                source: telemetrySource,
                firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
                inflightAtRequest: inflightAtRequest,
                proxyRequestID: requestTrace.proxyRequestID,
                callerRequestID: requestTrace.callerRequestID,
                callerSessionID: requestTrace.callerSessionID,
                requestShape: requestTrace.requestShape
            ),
            requestedAlias: publicAlias,
            failoverDepth: failoverDepth,
            finalWinnerRequestModel: (!shouldFailover && statusCode >= 200 && statusCode < 300) ? candidateModel : nil
        )

        if shouldFailover {
            // Record 429 in concurrency registry for auto-discovery of provider limits
            if let routeHealthKey = route?.routeHealthKey {
                OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                    routeHealthKey: routeHealthKey,
                    inflightAtRequest: inflightAtRequest,
                    statusCode: statusCode,
                    headers: response.allHeaderFields,
                    bodyData: responseData
                )
            }
            let cooldownUntil = OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                failureClass: failureClass,
                statusCode: statusCode,
                headers: response.allHeaderFields,
                bodyData: responseData
            )
            if let deferredUntil = OpenAICompatTemporaryShim.smartAliasAvailabilityDeferralUntil(
                failureClass: failureClass,
                statusCode: statusCode,
                headers: response.allHeaderFields,
                bodyData: responseData
            ) {
                OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                    forRequestModel: candidateModel,
                    until: deferredUntil
                )
            }
            completion(
                .retryableFailure(
                    requestModel: candidateModel,
                    telemetryEvent: telemetryEvent,
                    cooldownUntil: cooldownUntil
                )
            )
            return
        }

        if statusCode >= 200 && statusCode < 300 {
            // Record success in concurrency registry for auto-limit growth
            if let route {
                OpenAICompatTemporaryShim.recordConcurrencySuccess(
                    routeHealthKey: route.routeHealthKey,
                    inflightAtRequest: inflightAtRequest
                )
            }
            completion(
                .success(
                    requestModel: candidateModel,
                    statusCode: statusCode,
                    headers: response.allHeaderFields,
                    body: responseData,
                    telemetryEvent: telemetryEvent
                )
            )
            return
        }

        completion(
            .terminalResponse(
                requestModel: candidateModel,
                statusCode: statusCode,
                headers: response.allHeaderFields,
                body: responseData,
                telemetryEvent: telemetryEvent
            )
        )
    }

    private func classifySmartAliasCandidateFailure(
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data?,
        path: String,
        requiredToolParameters: [String: [String]]? = nil
    ) -> (shouldFailover: Bool, failureClass: String?) {
        if let bodyData,
           let failureClass = classifyRetryableSmartAliasErrorBody(statusCode: statusCode, path: path, bodyData: bodyData) {
            return (true, failureClass)
        }
        if statusCode >= 200 && statusCode < 300,
           let bodyData,
           let failureClass = classifySmartAliasSuccessBodyFailure(path: path, bodyData: bodyData, requiredToolParameters: requiredToolParameters) {
            return (true, failureClass)
        }
        switch statusCode {
        case 402, 408, 403, 404:
            return (true, "classified_\(statusCode)")
        case 429:
            return (
                true,
                OpenAICompatTemporaryShim.failureClassFor429(
                    headers: headers,
                    bodyData: bodyData
                )
            )
        case 500...599:
            return (true, "classified_\(statusCode)")
        default:
            return (false, nil)
        }
    }

    private func classifyRetryableSmartAliasErrorBody(statusCode: Int, path: String, bodyData: Data) -> String? {
        guard statusCode == 400,
              path == "/v1/chat/completions" || path == "/api/v1/chat/completions" else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        let message = ((error["message"] as? String) ?? "").lowercased()
        let code = String(describing: error["code"] ?? "").lowercased()
        let looksLikeRetryableNetworkMask = message.contains("network error")
            && (message.contains("please contact customer service") || message.contains("error id:") || code == "1234")
        if looksLikeRetryableNetworkMask {
            return "classified_retryable_400_network_error"
        }

        // The Meta web bridge returns 400 when the adapter cannot coerce a given
        // worker turn into a valid synthetic tool invocation. That is lane-specific
        // incompatibility, not a caller bug, so the worker pool should fail over
        // and penalize the route instead of surfacing a terminal 400.
        if message.contains("meta web adapter") {
            return "classified_retryable_400_meta_adapter"
        }

        return nil
    }

    private func classifySmartAliasSuccessBodyFailure(path: String, bodyData: Data, requiredToolParameters: [String: [String]]? = nil) -> String? {
        if bodyData.isEmpty {
            return "empty_body"
        }

        guard path == "/v1/chat/completions" || path == "/api/v1/chat/completions" else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return "invalid_json"
        }
        guard let choices = json["choices"] as? [[String: Any]], !choices.isEmpty else {
            return "missing_choices"
        }
        let message = choices[0]["message"] as? [String: Any] ?? [:]
        switch OpenAICompatTemporaryShim.validateToolCalls(in: message, requiredToolParameters: requiredToolParameters) {
        case .invalid:
            return "malformed_tool_arguments"
        case .valid:
            return nil
        case .none:
            break
        }
        let content = ((message["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reasoning = ((message["reasoning"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            // Distinguish: reasoning model that produced reasoning but no visible content
            if !reasoning.isEmpty {
                return "reasoning_only_content_missing"
            }
            return "empty_content"
        }
        if content.contains("<think>") {
            return "reasoning_leak_content"
        }
        return nil
    }

    private func transportFailureClass(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.Code.timedOut.rawValue {
            return "transport_timeout"
        }
        return "transport_error"
    }

    private func requestHeaderValue(_ name: String, in headers: [(String, String)]) -> String? {
        for (headerName, headerValue) in headers.reversed() {
            if headerName.caseInsensitiveCompare(name) == .orderedSame {
                return headerValue
            }
        }
        return nil
    }

    private func mergingResponseHeaders(
        _ headers: [String: String],
        with requestTrace: RequestTraceContext? = nil
    ) -> [String: String] {
        guard let requestTrace else { return headers }
        return headers.merging(requestTrace.responseHeaders) { current, _ in current }
    }

    private func preflightFailureHeaders(
        for failure: OpenAICompatTemporaryShim.ClientFacingNVIDIAFailure,
        requestTrace: RequestTraceContext? = nil
    ) -> [String: String] {
        var headers: [String: String] = [:]
        if let reasonCode = failure.reasonCode {
            headers["X-VibeProxy-Preflight-Reason"] = reasonCode
        }
        return mergingResponseHeaders(headers, with: requestTrace)
    }

    private func smartAliasExhaustionHeaders(
        for exhaustionSummary: OpenAICompatTemporaryShim.SmartAliasExhaustionSummary?,
        requestTrace: RequestTraceContext? = nil
    ) -> [String: String] {
        var headers: [String: String] = [:]
        if let exhaustionSummary {
            headers["X-VibeProxy-Smart-Alias-Exhaustion"] = exhaustionSummary.classification.rawValue
        }
        return mergingResponseHeaders(headers, with: requestTrace)
    }

    private func smartAliasTelemetrySource(headers: [(String, String)]) -> String {
        guard let probeHeader = requestHeaderValue("X-VibeProxy-Probe", in: headers)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !probeHeader.isEmpty else {
            return "smart_alias"
        }
        return "smart_alias_probe"
    }

    private func annotatedSmartAliasTelemetryEvent(
        _ event: OpenAICompatTemporaryShim.RouteTelemetryEvent,
        requestedAlias: String,
        failoverDepth: Int,
        finalWinnerRequestModel: String?
    ) -> OpenAICompatTemporaryShim.RouteTelemetryEvent {
        OpenAICompatTemporaryShim.RouteTelemetryEvent(
            timestamp: event.timestamp,
            requestModel: event.requestModel,
            requestedAlias: requestedAlias,
            canonicalModelID: event.canonicalModelID,
            transportOutcome: event.transportOutcome,
            healthTransition: event.healthTransition,
            attemptLane: event.attemptLane,
            winnerAttemptLane: event.winnerAttemptLane,
            failoverDepth: failoverDepth,
            finalWinnerRequestModel: finalWinnerRequestModel ?? event.finalWinnerRequestModel,
            failureClass: event.failureClass,
            timeoutStage: event.timeoutStage,
            upstreamHTTPStatus: event.upstreamHTTPStatus,
            retryCount: event.retryCount,
            source: event.source,
            firstByteLatencyMilliseconds: event.firstByteLatencyMilliseconds,
            totalLatencyMilliseconds: event.totalLatencyMilliseconds,
            inflightAtRequest: event.inflightAtRequest,
            proxyRequestID: event.proxyRequestID,
            callerRequestID: event.callerRequestID,
            callerSessionID: event.callerSessionID,
            requestShape: event.requestShape,
            errorBodySnippet: event.errorBodySnippet
        )
    }

    @discardableResult
    private func sendBufferedProxyRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        timeoutInterval: TimeInterval,
        firstResponseDeadlineSeconds: TimeInterval? = nil,
        bufferedResponseDeadlineSeconds: TimeInterval? = nil,
        completion: @escaping (BufferedProxyResponse) -> Void
    ) -> (() -> Void) {
        if let bufferedProxyCancelableTransportForTesting {
            return bufferedProxyCancelableTransportForTesting(method, path, headers, body, timeoutInterval, completion)
        }

        if let bufferedProxyTransportForTesting {
            bufferedProxyTransportForTesting(method, path, headers, body, timeoutInterval, completion)
            return {}
        }

        guard let url = URL(string: "http://\(targetHost):\(targetPort)\(path)") else {
            completion(
                BufferedProxyResponse(
                    data: nil,
                    response: nil,
                    error: URLError(.badURL),
                    firstByteLatencyMilliseconds: nil,
                    totalLatencyMilliseconds: nil
                )
            )
            return {}
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = timeoutInterval

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (session, poolDelegate) = Self.acquireBufferedBackendSession(
            targetHost: targetHost,
            targetPort: targetPort
        )
        let responseProgress = ResponseProgressDelegate()
        let taskHolder = TaskIdHolder()
        let (task, exception) = SafeDataTask.create(on: session, with: request) { data, response, error in
            _ = poolDelegate.unregister(taskIdentifier: taskHolder.taskIdentifier)
            responseProgress.finish()
            completion(
                BufferedProxyResponse(
                    data: data,
                    response: response as? HTTPURLResponse,
                    error: error,
                    firstByteLatencyMilliseconds: responseProgress.firstByteLatencyMilliseconds(),
                    totalLatencyMilliseconds: responseProgress.totalLatencyMilliseconds(),
                    deadlineStage: responseProgress.currentDeadlineStage()
                )
            )
        }
        guard let task else {
            NSLog("[SafeDataTask] sendBufferedProxyRequest: session invalidated during dataTask creation — \(exception?.reason ?? "unknown")")
            completion(BufferedProxyResponse(data: nil, response: nil, error: URLError(.cancelled), firstByteLatencyMilliseconds: nil, totalLatencyMilliseconds: nil))
            return {}
        }
        taskHolder.taskIdentifier = task.taskIdentifier
        poolDelegate.register(task: task, delegate: responseProgress)
        responseProgress.installDeadlines(
            firstResponseSeconds: firstResponseDeadlineSeconds,
            bufferedResponseSeconds: bufferedResponseDeadlineSeconds,
            for: task
        )
        task.resume()
        return {
            task.cancel()
        }
    }

    private func sendDirectProxiedRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        candidateModel: String,
        timeoutInterval: TimeInterval,
        endpoint: OpenAICompatTemporaryShim.ProviderEndpoint,
        firstResponseDeadlineSeconds: TimeInterval? = nil,
        bufferedResponseDeadlineSeconds: TimeInterval? = nil,
        completion: @escaping (BufferedProxyResponse) -> Void
    ) -> (() -> Void) {
        // Strip /v1 prefix from path when base URL already ends with a versioned API path
        let basePath = endpoint.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let effectivePath: String
        if basePath.hasSuffix("/v1") {
            let stripped = path.hasPrefix("/v1") ? String(path.dropFirst(3)) : path
            effectivePath = stripped.isEmpty ? "" : (stripped.hasPrefix("/") ? stripped : "/" + stripped)
        } else {
            effectivePath = path.hasPrefix("/") ? path : "/" + path
        }
        let upstreamURL = basePath + effectivePath
        guard let url = URL(string: upstreamURL) else {
            completion(BufferedProxyResponse(data: nil, response: nil, error: URLError(.badURL), firstByteLatencyMilliseconds: nil, totalLatencyMilliseconds: nil))
            return {}
        }

        // Rewrite model alias to canonical model ID for upstream
        var upstreamBody = body
        if let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel),
           let rewritten = OpenAICompatTemporaryShim.rewrittenRequestJSON(
            method: method,
            path: path,
            replacingRequestModelIn: body,
            with: route.canonicalModelID
           ) {
            upstreamBody = rewritten
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = Data(upstreamBody.utf8)
        request.timeoutInterval = timeoutInterval

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding", "authorization"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let bearerToken = endpoint.apiKey, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        if let directProxiedTransportForTesting {
            return directProxiedTransportForTesting(request, endpoint, completion)
        }
        if let bufferedProxyTransportForTesting {
            let requestHeaders = (request.allHTTPHeaderFields ?? [:]).map { ($0.key, $0.value) }
            bufferedProxyTransportForTesting(
                method,
                path,
                requestHeaders,
                upstreamBody,
                timeoutInterval,
                completion
            )
            return {}
        }

        // Use pooled session keyed by proxy URL for TCP connection reuse
        guard let (session, poolDelegate) = Self.acquireProxiedSession(proxyURL: endpoint.proxyURL) else {
            completion(BufferedProxyResponse(data: nil, response: nil, error: URLError(.badURL), firstByteLatencyMilliseconds: nil, totalLatencyMilliseconds: nil))
            return {}
        }

        let responseProgress = ResponseProgressDelegate()
        let taskHolder = TaskIdHolder()
        let (task, exception) = SafeDataTask.create(on: session, with: request) { data, response, error in
            _ = poolDelegate.unregister(taskIdentifier: taskHolder.taskIdentifier)
            responseProgress.finish()
            completion(
                BufferedProxyResponse(
                    data: data,
                    response: response as? HTTPURLResponse,
                    error: error,
                    firstByteLatencyMilliseconds: responseProgress.firstByteLatencyMilliseconds(),
                    totalLatencyMilliseconds: responseProgress.totalLatencyMilliseconds(),
                    deadlineStage: responseProgress.currentDeadlineStage()
                )
            )
        }
        guard let task else {
            NSLog("[SafeDataTask] sendDirectProxiedRequest: pooled proxied session invalidated — evicting from pool. \(exception?.reason ?? "unknown")")
            Self.clearProxiedSessionPoolForTesting()
            completion(BufferedProxyResponse(data: nil, response: nil, error: URLError(.cancelled), firstByteLatencyMilliseconds: nil, totalLatencyMilliseconds: nil))
            return {}
        }
        poolDelegate.register(task: task, delegate: responseProgress)
        taskHolder.taskIdentifier = task.taskIdentifier
        responseProgress.installDeadlines(
            firstResponseSeconds: firstResponseDeadlineSeconds,
            bufferedResponseSeconds: bufferedResponseDeadlineSeconds,
            for: task
        )
        task.resume()
        return {
            task.cancel()
        }
    }

    private func forwardDirectProxiedRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        candidateModel: String,
        endpoint: OpenAICompatTemporaryShim.ProviderEndpoint,
        originalConnection: NWConnection,
        requestTrace: RequestTraceContext
    ) {
        let requestController = RequestCancellationController()
        installClientDisconnectCancellation(on: originalConnection, controller: requestController, requestTrace: requestTrace)
        let timeoutInterval = OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: body) ?? Config.defaultMitigatedAttemptTimeout
        let effectiveHeaders = headersInjectingRouteSpecific(headers, forCandidateModel: candidateModel)
        guard let permit = acquireRouteConcurrencyPermit(forRequestModel: candidateModel) else {
            let telemetryEvaluation = evaluateDirectBufferedRouteTelemetry(
                path: path,
                requestModel: candidateModel,
                bufferedResponse: BufferedProxyResponse(data: nil, response: nil, error: nil),
                forcedFailureClass: "classified_429_concurrency",
                forcedTransportOutcome: "send_error",
                forcedUpstreamStatus: 429,
                inflightAtRequest: OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: candidateModel).map {
                    OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: $0.routeHealthKey)
                },
                requestTrace: requestTrace
            )
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: candidateModel,
                telemetryEvent: telemetryEvaluation.event,
                forcedOpenUntil: telemetryEvaluation.forcedOpenUntil
            )
            var limitHeaders = smartAliasResolutionHeaders(
                publicAlias: candidateModel,
                resolvedRequestModel: candidateModel,
                requestTrace: requestTrace
            )
            limitHeaders["Retry-After"] = "1"
            sendError(
                to: originalConnection,
                statusCode: 429,
                message: concurrencyLimitErrorMessage(forRequestModel: candidateModel),
                overridingHeaders: limitHeaders
            )
            return
        }
        let cancel = sendDirectProxiedRequest(
            method: method,
            path: path,
            headers: effectiveHeaders,
            body: body,
            candidateModel: candidateModel,
            timeoutInterval: timeoutInterval,
            endpoint: endpoint,
            firstResponseDeadlineSeconds: OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                forRequestJSON: body,
                routeHealthStatus: OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: candidateModel)
            ),
            bufferedResponseDeadlineSeconds: OpenAICompatTemporaryShim.effectiveBufferedResponseDeadline(forRequestJSON: body)
        ) { [weak self] bufferedResponse in
            permit.release()
            guard let self else { return }
            guard requestController.isCancelled() != true else { return }
            let telemetryEvaluation = self.evaluateDirectBufferedRouteTelemetry(
                path: path,
                requestModel: candidateModel,
                bufferedResponse: bufferedResponse,
                inflightAtRequest: permit.inflightAtRequest,
                requestTrace: requestTrace
            )
            if telemetryEvaluation.shouldRecordFailure {
                if let response = bufferedResponse.response {
                    OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest,
                        statusCode: response.statusCode,
                        headers: response.allHeaderFields,
                        bodyData: bufferedResponse.data
                    )
                }
                if let deferredUntil = telemetryEvaluation.deferralUntil {
                    OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                        forRequestModel: candidateModel,
                        until: deferredUntil
                    )
                }
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: candidateModel,
                    telemetryEvent: telemetryEvaluation.event,
                    forcedOpenUntil: telemetryEvaluation.forcedOpenUntil
                )
            } else if telemetryEvaluation.shouldRecordSuccess {
                OpenAICompatTemporaryShim.recordConcurrencySuccess(
                    routeHealthKey: permit.routeHealthKey,
                    inflightAtRequest: permit.inflightAtRequest
                )
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: candidateModel,
                    telemetryEvent: telemetryEvaluation.event
                )
            } else {
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvaluation.event)
            }
            if let error = bufferedResponse.error {
                let nsError = error as NSError
                let statusCode = (nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue) ? 504 : 502
                self.sendError(
                    to: originalConnection,
                    statusCode: statusCode,
                    message: statusCode == 504 ? "Gateway Timeout" : "Bad Gateway",
                    overridingHeaders: requestTrace.responseHeaders
                )
                return
            }
            guard let response = bufferedResponse.response,
                  let data = bufferedResponse.data else {
                self.sendError(
                    to: originalConnection,
                    statusCode: 502,
                    message: "Bad Gateway",
                    overridingHeaders: requestTrace.responseHeaders
                )
                return
            }
            var responseHeaders: [AnyHashable: Any] = [:]
            for (key, value) in response.allHeaderFields {
                responseHeaders[key] = value
            }
            let overridingModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: body)
            self.deliverBufferedHTTPResponse(
                defaultConnection: originalConnection,
                statusCode: response.statusCode,
                headers: responseHeaders,
                body: data,
                coalescingKey: nil,
                overridingModel: overridingModel,
                overridingHeaders: requestTrace.responseHeaders
            )
        }
        requestController.registerCurrentCancel {
            permit.release()
            cancel()
        }
    }

    private func forwardMetaAIWebRequest(
        path: String,
        body: String,
        publicModel: String,
        originalConnection: NWConnection,
        requestTrace: RequestTraceContext
    ) {
        let requestController = RequestCancellationController()
        installClientDisconnectCancellation(on: originalConnection, controller: requestController, requestTrace: requestTrace)
        let resolutionHeaders = smartAliasResolutionHeaders(
            publicAlias: publicModel,
            resolvedRequestModel: publicModel,
            requestTrace: requestTrace
        )
        let bufferedResponse = executeMetaAIAdapterBufferedResponse(
            path: path,
            body: body,
            publicModel: publicModel
        )
        guard requestController.isCancelled() != true else { return }
        let telemetryEvaluation = evaluateDirectBufferedRouteTelemetry(
            path: path,
            requestModel: publicModel,
            bufferedResponse: bufferedResponse,
            requestTrace: requestTrace
        )
        if telemetryEvaluation.shouldRecordFailure {
            if let deferredUntil = telemetryEvaluation.deferralUntil {
                OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                    forRequestModel: publicModel,
                    until: deferredUntil
                )
            }
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: publicModel,
                telemetryEvent: telemetryEvaluation.event,
                forcedOpenUntil: telemetryEvaluation.forcedOpenUntil
            )
        } else if telemetryEvaluation.shouldRecordSuccess {
            OpenAICompatTemporaryShim.recordRouteSuccess(
                forRequestModel: publicModel,
                telemetryEvent: telemetryEvaluation.event
            )
        } else {
            OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvaluation.event)
        }
        if let response = bufferedResponse.response,
           (200 ..< 300).contains(response.statusCode) {
            sendHTTPResponse(
                to: originalConnection,
                statusCode: response.statusCode,
                headers: response.allHeaderFields,
                body: bufferedResponse.data ?? Data(),
                overridingHeaders: resolutionHeaders
            )
            return
        }

        let failureBody = bufferedResponse.data.flatMap { String(data: $0, encoding: .utf8) }
        let failureMessage: String
        if let failureBody,
           let failureData = failureBody.data(using: .utf8),
           let failureJSON = try? JSONSerialization.jsonObject(with: failureData) as? [String: Any],
           let error = failureJSON["error"] as? [String: Any],
           let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            failureMessage = message
        } else if let failureBody = failureBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !failureBody.isEmpty {
            failureMessage = failureBody
        } else {
            failureMessage = "Meta web adapter failed while handling the request."
        }
        let statusCode = bufferedResponse.response?.statusCode ?? 502
        sendError(
            to: originalConnection,
            statusCode: statusCode,
            message: failureMessage,
            overridingHeaders: resolutionHeaders
        )
    }

    private func executeMetaAIAdapterBufferedResponse(
        path: String,
        body: String,
        publicModel: String
    ) -> BufferedProxyResponse {
        if let metaAIBufferedResponseForTesting {
            return metaAIBufferedResponseForTesting(path, body, publicModel)
        }

        let startTime = Date()
        switch MetaAIWebAdapter.execute(path: path, body: body, publicModel: publicModel) {
        case .success(let result):
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://www.meta.ai/api/graphql")!,
                statusCode: result.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
            )
            return BufferedProxyResponse(
                data: result.body,
                response: httpResponse,
                error: nil,
                firstByteLatencyMilliseconds: elapsed,
                totalLatencyMilliseconds: elapsed
            )
        case .failure(let failure):
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            let httpResponse = HTTPURLResponse(
                url: URL(string: "https://www.meta.ai/api/graphql")!,
                statusCode: failure.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            let errorBody = try? JSONSerialization.data(withJSONObject: [
                "error": ["message": failure.message, "type": "server_error", "code": "internal_server_error"]
            ])
            return BufferedProxyResponse(
                data: errorBody,
                response: httpResponse,
                error: nil,
                firstByteLatencyMilliseconds: elapsed,
                totalLatencyMilliseconds: elapsed
            )
        }
    }

    private func evaluateDirectBufferedRouteTelemetry(
        path: String,
        requestModel: String,
        bufferedResponse: BufferedProxyResponse,
        source: String = "live_request",
        forcedFailureClass: String? = nil,
        forcedTransportOutcome: String? = nil,
        forcedUpstreamStatus: Int? = nil,
        inflightAtRequest: Int? = nil,
        requestTrace: RequestTraceContext? = nil
    ) -> (
        event: OpenAICompatTemporaryShim.RouteTelemetryEvent,
        shouldRecordSuccess: Bool,
        shouldRecordFailure: Bool,
        forcedOpenUntil: Date?,
        deferralUntil: Date?
    ) {
        let route = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: requestModel)
        let canonicalModelID = route?.canonicalModelID ?? requestModel

        if let forcedFailureClass {
            let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: requestModel,
                canonicalModelID: canonicalModelID,
                transportOutcome: forcedTransportOutcome ?? "send_error",
                failureClass: forcedFailureClass,
                timeoutStage: bufferedResponse.deadlineStage,
                upstreamHTTPStatus: forcedUpstreamStatus,
                retryCount: 0,
                source: source,
                firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
                inflightAtRequest: inflightAtRequest,
                proxyRequestID: requestTrace?.proxyRequestID,
                callerRequestID: requestTrace?.callerRequestID,
                callerSessionID: requestTrace?.callerSessionID,
                requestShape: requestTrace?.requestShape
            )
            return (
                event: event,
                shouldRecordSuccess: false,
                shouldRecordFailure: true,
                forcedOpenUntil: OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                    failureClass: forcedFailureClass,
                    statusCode: forcedUpstreamStatus ?? 429,
                    headers: [:]
                ),
                deferralUntil: OpenAICompatTemporaryShim.smartAliasAvailabilityDeferralUntil(
                    failureClass: forcedFailureClass,
                    statusCode: forcedUpstreamStatus ?? 429,
                    headers: [:]
                )
            )
        }

        if let error = bufferedResponse.error {
            let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: requestModel,
                canonicalModelID: canonicalModelID,
                transportOutcome: "send_error",
                failureClass: transportFailureClass(error),
                timeoutStage: bufferedResponse.deadlineStage,
                upstreamHTTPStatus: nil,
                retryCount: 0,
                source: source,
                firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
                inflightAtRequest: inflightAtRequest,
                proxyRequestID: requestTrace?.proxyRequestID,
                callerRequestID: requestTrace?.callerRequestID,
                callerSessionID: requestTrace?.callerSessionID,
                requestShape: requestTrace?.requestShape
            )
            return (
                event: event,
                shouldRecordSuccess: false,
                shouldRecordFailure: true,
                forcedOpenUntil: nil,
                deferralUntil: nil
            )
        }

        guard let response = bufferedResponse.response,
              let responseData = bufferedResponse.data else {
            let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: requestModel,
                canonicalModelID: canonicalModelID,
                transportOutcome: "send_error",
                failureClass: "missing_response_material",
                timeoutStage: bufferedResponse.deadlineStage,
                upstreamHTTPStatus: nil,
                retryCount: 0,
                source: source,
                firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
                inflightAtRequest: inflightAtRequest,
                proxyRequestID: requestTrace?.proxyRequestID,
                callerRequestID: requestTrace?.callerRequestID,
                callerSessionID: requestTrace?.callerSessionID,
                requestShape: requestTrace?.requestShape
            )
            return (
                event: event,
                shouldRecordSuccess: false,
                shouldRecordFailure: true,
                forcedOpenUntil: nil,
                deferralUntil: nil
            )
        }

        let classification = classifySmartAliasCandidateFailure(
            statusCode: response.statusCode,
            headers: response.allHeaderFields,
            bodyData: responseData,
            path: path
        )
        let shouldRecordSuccess = !classification.shouldFailover && (200 ..< 300).contains(response.statusCode)
        let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
            timestamp: Date(),
            requestModel: requestModel,
            canonicalModelID: canonicalModelID,
            transportOutcome: shouldRecordSuccess ? "send_response" : "send_error",
            finalWinnerRequestModel: shouldRecordSuccess ? requestModel : nil,
            failureClass: classification.failureClass,
            timeoutStage: bufferedResponse.deadlineStage,
            upstreamHTTPStatus: response.statusCode,
            retryCount: 0,
            source: source,
            firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
            totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds,
            inflightAtRequest: inflightAtRequest
        )
        return (
            event: event,
            shouldRecordSuccess: shouldRecordSuccess,
            shouldRecordFailure: classification.shouldFailover,
            forcedOpenUntil: classification.shouldFailover
                ? OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                    failureClass: classification.failureClass,
                    statusCode: response.statusCode,
                    headers: response.allHeaderFields,
                    bodyData: responseData
                )
                : nil,
            deferralUntil: classification.shouldFailover
                ? OpenAICompatTemporaryShim.smartAliasAvailabilityDeferralUntil(
                    failureClass: classification.failureClass,
                    statusCode: response.statusCode,
                    headers: response.allHeaderFields,
                    bodyData: responseData
                )
                : nil
        )
    }

    private func smartAliasCandidateTimeout(forRequestJSON jsonString: String, publicAlias: String? = nil, candidateModel: String? = nil) -> TimeInterval {
        let bodyTimeout = OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: jsonString) ?? 0
        let aliasTimeout = publicAlias.flatMap { OpenAICompatTemporaryShim.attemptTimeout(forRequestModel: $0) } ?? 0
        let candidatePolicyTimeout = candidateModel.flatMap { OpenAICompatTemporaryShim.attemptTimeout(forRequestModel: $0) } ?? 0
        let resolvedTimeout = max(bodyTimeout, max(aliasTimeout, candidatePolicyTimeout))
        return resolvedTimeout > 0 ? resolvedTimeout : Config.defaultMitigatedAttemptTimeout
    }

    private func smartAliasTotalTimeout(forRequestJSON jsonString: String) -> TimeInterval {
        if let smartAliasTotalTimeoutOverrideForTesting {
            return smartAliasTotalTimeoutOverrideForTesting
        }
        return min(
            smartAliasCandidateTimeout(forRequestJSON: jsonString) + OpenAICompatTemporaryShim.scaledRequestTimeout(60),
            OpenAICompatTemporaryShim.scaledRequestTimeout(360)
        )
    }

    private func remainingSmartAliasBudget(until deadlineAt: Date) -> TimeInterval {
        max(0, deadlineAt.timeIntervalSinceNow)
    }

    private func coalescingKeyForSafeRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        coalescingSourceBody: String,
        requestedModelAlias: String?
    ) -> String? {
        guard let identityPartition = coalescingIdentityPartition(headers: headers) else {
            return nil
        }

        let canonicalCoalescingSourceBody = canonicalJSONStringForCoalescing(coalescingSourceBody)
        let canonicalBody = canonicalJSONStringForCoalescing(body)

        if let requestedModelAlias,
           OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: requestedModelAlias) != nil,
           OpenAICompatTemporaryShim.isSafePlainChatRequest(
                method: method,
                path: path,
                jsonString: coalescingSourceBody
           ) {
            return "\(identityPartition)\n\(method) \(path)\n\(canonicalCoalescingSourceBody)"
        }

        guard OpenAICompatTemporaryShim.allowsPlainSafeNVIDIARequest(
            method: method,
            path: path,
            jsonString: body
        ),
        let model = OpenAICompatTemporaryShim.modelName(forRequestJSON: body),
        OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: model) == .suspect else {
            return nil
        }
        return "\(identityPartition)\n\(method) \(path)\n\(canonicalBody)"
    }

    private func canonicalJSONStringForCoalescing(_ jsonString: String) -> String {
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
              let canonicalData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]),
              let canonicalString = String(data: canonicalData, encoding: .utf8) else {
            return jsonString
        }
        return canonicalString
    }

    private func coalescingIdentityPartition(headers: [(String, String)]) -> String? {
        let identityHeaderNames = Set([
            "authorization",
            "x-factory-session",
            "x-session-id",
            "x-assistant-message-id",
            "x-api-provider",
            "cookie"
        ])

        let selectedPairs = headers.compactMap { name, value -> String? in
            let normalizedName = name.lowercased()
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard identityHeaderNames.contains(normalizedName), !normalizedValue.isEmpty else {
                return nil
            }
            return "\(normalizedName)=\(normalizedValue)"
        }

        guard !selectedPairs.isEmpty else {
            return nil
        }

        return selectedPairs.sorted().joined(separator: "\n")
    }

    private func registerOrJoinInflightRequest(
        key: String,
        connection: NWConnection
    ) -> Bool {
        nvidiaInflightQueue.sync {
            evictExpiredCoalescedReplaysLocked()
            if inflightCoalescedRequests[key] != nil {
                inflightCoalescedRequests[key, default: []].append(connection)
                return false
            }
            inflightCoalescedRequests[key] = [connection]
            return true
        }
    }

    private func evictExpiredCoalescedReplaysLocked(now: Date = Date()) {
        recentCoalescedReplays = recentCoalescedReplays.filter { $0.value.expiresAt > now }
    }

    private func replayCompletedCoalescedRequestIfAvailable(
        key: String,
        connection: NWConnection
    ) -> Bool {
        let replayEntry = nvidiaInflightQueue.sync { () -> CoalescedReplayEntry? in
            evictExpiredCoalescedReplaysLocked()
            guard let entry = recentCoalescedReplays[key], !entry.isExpired else {
                recentCoalescedReplays.removeValue(forKey: key)
                return nil
            }
            return entry
        }

        guard let replayEntry else {
            return false
        }

        switch replayEntry.payload {
        case .http(let statusCode, let headers, let body, let overridingHeaders):
            sendHTTPResponse(
                to: connection,
                statusCode: statusCode,
                headers: headers,
                body: body,
                overridingHeaders: overridingHeaders
            )
        case .error(let statusCode, let message, let overridingHeaders):
            sendError(
                to: connection,
                statusCode: statusCode,
                message: message,
                overridingHeaders: overridingHeaders
            )
        }
        return true
    }

    private func rememberCompletedCoalescedHTTPResponse(
        key: String,
        statusCode: Int,
        headers: [AnyHashable: Any],
        body: Data,
        overridingHeaders: [String: String]
    ) {
        nvidiaInflightQueue.sync {
            evictExpiredCoalescedReplaysLocked()
            recentCoalescedReplays[key] = CoalescedReplayEntry(
                expiresAt: Date().addingTimeInterval(coalescedReplayWindow),
                payload: .http(
                    statusCode: statusCode,
                    headers: headers,
                    body: body,
                    overridingHeaders: overridingHeaders
                )
            )
        }
    }

    private func rememberCompletedCoalescedError(
        key: String,
        statusCode: Int,
        message: String,
        overridingHeaders: [String: String]
    ) {
        nvidiaInflightQueue.sync {
            evictExpiredCoalescedReplaysLocked()
            recentCoalescedReplays[key] = CoalescedReplayEntry(
                expiresAt: Date().addingTimeInterval(coalescedReplayWindow),
                payload: .error(
                    statusCode: statusCode,
                    message: message,
                    overridingHeaders: overridingHeaders
                )
            )
        }
    }

    func registerOrJoinInflightRequestForTesting(key: String, connection: NWConnection) -> Bool {
        registerOrJoinInflightRequest(key: key, connection: connection)
    }

    func rememberCompletedCoalescedHTTPResponseForTesting(
        key: String,
        statusCode: Int,
        headers: [AnyHashable: Any],
        body: Data,
        overridingHeaders: [String: String] = [:]
    ) {
        rememberCompletedCoalescedHTTPResponse(
            key: key,
            statusCode: statusCode,
            headers: headers,
            body: body,
            overridingHeaders: overridingHeaders
        )
    }

    func replayCompletedCoalescedRequestIfAvailableForTesting(
        key: String,
        connection: NWConnection
    ) -> Bool {
        replayCompletedCoalescedRequestIfAvailable(key: key, connection: connection)
    }

    func inflightRequestWaiterCount(for key: String) -> Int {
        nvidiaInflightQueue.sync {
            inflightCoalescedRequests[key]?.count ?? 0
        }
    }

    func takeInflightRequestConnectionsForTesting(for key: String) -> [NWConnection]? {
        takeInflightRequestConnections(for: key)
    }

    private func takeInflightRequestConnections(for key: String?) -> [NWConnection]? {
        guard let key else { return nil }
        return nvidiaInflightQueue.sync {
            let connections = inflightCoalescedRequests.removeValue(forKey: key)
            return connections
        }
    }

    private func deliverBufferedHTTPResponse(
        defaultConnection: NWConnection,
        statusCode: Int,
        headers: [AnyHashable: Any],
        body: Data,
        coalescingKey: String?,
        overridingModel: String? = nil,
        overridingHeaders: [String: String] = [:]
    ) {
        let deliveredBody = rewrittenResponseBody(
            body,
            overridingModelWith: overridingModel,
            statusCode: statusCode
        ) ?? body
        if let coalescingKey {
            rememberCompletedCoalescedHTTPResponse(
                key: coalescingKey,
                statusCode: statusCode,
                headers: headers,
                body: deliveredBody,
                overridingHeaders: overridingHeaders
            )
        }
        let connections = takeInflightRequestConnections(for: coalescingKey) ?? [defaultConnection]
        for connection in connections {
            sendHTTPResponse(
                to: connection,
                statusCode: statusCode,
                headers: headers,
                body: deliveredBody,
                overridingHeaders: overridingHeaders
            )
        }
    }

    private func smartAliasResolutionHeaders(
        publicAlias: String,
        resolvedRequestModel: String,
        requestTrace: RequestTraceContext? = nil
    ) -> [String: String] {
        var headers: [String: String] = [
            "X-Public-Model": publicAlias,
            "X-Resolved-Model": resolvedRequestModel
        ]
        if let requestTrace {
            for (name, value) in requestTrace.responseHeaders {
                headers[name] = value
            }
        }
        if let route = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: resolvedRequestModel) {
            headers["X-Resolved-Provider"] = route.providerID
            headers["X-Resolved-Canonical-Model"] = route.canonicalModelID
        }
        if let factoryBinding = Self.factoryModelBinding(forIncomingModelID: publicAlias) {
            headers["X-Factory-Authoritative-Model-ID"] = factoryBinding.authoritativeModelID
            headers["X-Factory-Model-Binding"] = factoryBinding.source
            headers["X-Factory-Request-Surface"] = factoryBinding.requestSurface
        }
        return headers
    }

    private func acquireRouteConcurrencyPermit(forRequestModel requestModel: String) -> RouteConcurrencyPermit? {
        guard let route = OpenAICompatTemporaryShim.routeIdentityForHealthTracking(forRequestModel: requestModel),
              OpenAICompatTemporaryShim.acquireConcurrencySlot(routeHealthKey: route.routeHealthKey) else {
            return nil
        }
        let inflightAtRequest = OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: route.routeHealthKey)
        return RouteConcurrencyPermit(routeHealthKey: route.routeHealthKey, inflightAtRequest: inflightAtRequest)
    }

    private func concurrencyLimitErrorMessage(forRequestModel requestModel: String) -> String {
        "Upstream concurrency limit reached for \(requestModel); retry shortly."
    }

    private func overloadErrorMessage(forRequestModel requestModel: String) -> String {
        "Upstream provider is temporarily overloaded for \(requestModel); retry shortly."
    }

    private func quotaWindowErrorMessage(forRequestModel requestModel: String) -> String {
        "Upstream rate-limit window reached for \(requestModel); retry when the provider window resets."
    }

    private func retryAfterHeaderValue(until cooldownUntil: Date?, fallbackSeconds: Int) -> String {
        guard let cooldownUntil else {
            return String(fallbackSeconds)
        }
        let seconds = max(1, Int(ceil(cooldownUntil.timeIntervalSinceNow)))
        return String(seconds)
    }

    private func deliverBufferedError(
        defaultConnection: NWConnection,
        statusCode: Int,
        message: String,
        coalescingKey: String?,
        overridingHeaders: [String: String] = [:]
    ) {
        if let coalescingKey {
            rememberCompletedCoalescedError(
                key: coalescingKey,
                statusCode: statusCode,
                message: message,
                overridingHeaders: overridingHeaders
            )
        }
        let connections = takeInflightRequestConnections(for: coalescingKey) ?? [defaultConnection]
        for connection in connections {
            sendError(
                to: connection,
                statusCode: statusCode,
                message: message,
                overridingHeaders: overridingHeaders
            )
        }
    }

    private func headerTuples(from headers: [AnyHashable: Any]) -> [(String, String)] {
        headers.map { key, value in
            ("\(key)", "\(value)")
        }
    }

    private func headersInjectingRouteSpecific(
        _ headers: [(String, String)],
        forCandidateModel candidateModel: String
    ) -> [(String, String)] {
        headers
    }

    private func rewrittenResponseBody(
        _ body: Data,
        overridingModelWith model: String?,
        statusCode: Int
    ) -> Data? {
        guard let model,
              statusCode >= 200,
              statusCode < 300,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        var rewrittenJSON = json
        rewrittenJSON["model"] = model
        return try? JSONSerialization.data(withJSONObject: rewrittenJSON)
    }

    /// Strips `cache_control` fields from the request body that cause 400 errors via the OAuth route
    private func stripCacheControl(from jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        var modified = false

        func stripFromDictArray(_ array: inout [[String: Any]]) {
            for i in array.indices {
                if array[i]["cache_control"] != nil {
                    array[i].removeValue(forKey: "cache_control")
                    modified = true
                }
                // Recurse into nested content arrays
                if var nested = array[i]["content"] as? [[String: Any]] {
                    stripFromDictArray(&nested)
                    array[i]["content"] = nested
                }
            }
        }

        if var system = json["system"] as? [[String: Any]] {
            stripFromDictArray(&system)
            if modified { json["system"] = system }
        }

        if var messages = json["messages"] as? [[String: Any]] {
            stripFromDictArray(&messages)
            if modified { json["messages"] = messages }
        }

        if var tools = json["tools"] as? [[String: Any]] {
            stripFromDictArray(&tools)
            if modified { json["tools"] = tools }
        }

        guard modified else { return nil }

        guard let modifiedData = try? JSONSerialization.data(withJSONObject: json),
              let modifiedString = String(data: modifiedData, encoding: .utf8) else {
            return nil
        }

        NSLog("[ThinkingProxy] Stripped cache_control fields from request body")
        return modifiedString
    }
    
    /**
     Processes the JSON body to add thinking parameter if model name has a thinking suffix
     Returns tuple of (modifiedJSON, needsTransformation)
     */
    private func processThinkingParameter(jsonString: String) -> (String, Bool)? {
        guard let jsonData = jsonString.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return nil
        }
        
        // Only process Claude models (including gemini-claude variants)
        guard model.starts(with: "claude-") || model.starts(with: "gemini-claude-") else {
            return (jsonString, false)  // Not Claude, pass through
        }
        
        // Check for thinking suffix pattern: -thinking-NUMBER
        let thinkingPrefix = "-thinking-"
        if let thinkingRange = model.range(of: thinkingPrefix, options: .backwards),
           thinkingRange.upperBound < model.endIndex {
            
            // Extract the number after "-thinking-"
            let budgetString = String(model[thinkingRange.upperBound...])
            
            // For gemini-claude-* models, preserve "-thinking" and only strip the number
            // e.g. gemini-claude-opus-4-5-thinking-10000 -> gemini-claude-opus-4-5-thinking
            // For claude-* models, strip the entire suffix
            // e.g. claude-opus-4-5-20251101-thinking-10000 -> claude-opus-4-5-20251101
            let cleanModel: String
            if model.starts(with: "gemini-claude-") {
                cleanModel = String(model[..<thinkingRange.upperBound].dropLast(1))  // Keep "-thinking", drop trailing "-"
            } else {
                cleanModel = String(model[..<thinkingRange.lowerBound])
            }
            json["model"] = cleanModel
            
            // Only add thinking parameter if it's a valid integer
            if let budget = Int(budgetString), budget > 0 {
                let effectiveBudget = min(budget, Config.hardTokenCap - 1)
                if effectiveBudget != budget {
                    NSLog("[ThinkingProxy] Adjusted thinking budget from \(budget) to \(effectiveBudget) to stay within limits")
                }

                // Claude Opus 4.6+ requires adaptive thinking; older models use enabled+budget_tokens
                let isAdaptiveModel = cleanModel.contains("opus-4-6") || cleanModel.contains("opus-4-7")
                if isAdaptiveModel {
                    json["thinking"] = ["type": "adaptive"]
                    NSLog("[ThinkingProxy] Using adaptive thinking for model '\(cleanModel)'")
                } else {
                    json["thinking"] = [
                        "type": "enabled",
                        "budget_tokens": effectiveBudget
                    ]
                }
                
                // Ensure max token limits are greater than the thinking budget
                // Claude requires: max_output_tokens (or legacy max_tokens) > thinking.budget_tokens
                // (only relevant for non-adaptive models, but safe to set for all)
                let tokenHeadroom = max(Config.minimumHeadroom, Int(Double(effectiveBudget) * Config.headroomRatio))
                let desiredMaxTokens = effectiveBudget + tokenHeadroom
                var requiredMaxTokens = min(desiredMaxTokens, Config.hardTokenCap)
                if requiredMaxTokens <= effectiveBudget {
                    requiredMaxTokens = min(effectiveBudget + 1, Config.hardTokenCap)
                }
                
                let hasMaxOutputTokensField = json.keys.contains("max_output_tokens")
                var adjusted = false
                
                if let currentMaxTokens = json["max_tokens"] as? Int {
                    if currentMaxTokens <= effectiveBudget {
                        json["max_tokens"] = requiredMaxTokens
                    }
                    adjusted = true
                }
                
                if let currentMaxOutputTokens = json["max_output_tokens"] as? Int {
                    if currentMaxOutputTokens <= effectiveBudget {
                        json["max_output_tokens"] = requiredMaxTokens
                    }
                    adjusted = true
                }
                
                if !adjusted {
                    if hasMaxOutputTokensField {
                        json["max_output_tokens"] = requiredMaxTokens
                    } else {
                        json["max_tokens"] = requiredMaxTokens
                    }
                }
                
                NSLog("[ThinkingProxy] Transformed model '\(model)' → '\(cleanModel)' with thinking budget \(effectiveBudget)")
            } else {
                // Invalid number - just strip suffix and use vanilla model
                NSLog("[ThinkingProxy] Stripped invalid thinking suffix from '\(model)' → '\(cleanModel)' (no thinking)")
            }
            
            // Convert back to JSON
            if let modifiedData = try? JSONSerialization.data(withJSONObject: json),
               let modifiedString = String(data: modifiedData, encoding: .utf8) {
                return (modifiedString, true)
            }
        } else if model.hasSuffix("-thinking") || model.contains("-thinking(") {
            // Model ends with -thinking or uses -thinking(budget) syntax (e.g. gemini-claude-opus-4-5-thinking, gemini-claude-opus-4-5-thinking(32768))
            // Enable beta header but don't modify body - let backend handle thinking budget
            NSLog("[ThinkingProxy] Detected thinking model '\(model)' - enabling beta header, passing through to backend")
            return (jsonString, true)
        }
        
        return (jsonString, false)  // No transformation needed
    }
    
    /**
     Forwards Amp API requests to ampcode.com, stripping the /api/ prefix
     */
    private func forwardToAmp(method: String, path: String, version: String, headers: [(String, String)], body: String, originalConnection: NWConnection) {
        // Create TLS parameters for HTTPS
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        
        // Create connection to ampcode.com:443
        let endpoint = NWEndpoint.hostPort(host: "ampcode.com", port: 443)
        let targetConnection = NWConnection(to: endpoint, using: parameters)
        
        targetConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Build the forwarded request
                var forwardedRequest = "\(method) \(path) \(version)\r\n"
                
                // Forward most headers, excluding some that need to be overridden
                let excludedHeaders: Set<String> = ["host", "content-length", "connection", "transfer-encoding"]
                for (name, value) in headers {
                    if !excludedHeaders.contains(name.lowercased()) {
                        forwardedRequest += "\(name): \(value)\r\n"
                    }
                }
                
                // Override Host header for ampcode.com
                forwardedRequest += "Host: ampcode.com\r\n"
                forwardedRequest += "Connection: close\r\n"
                
                let contentLength = body.utf8.count
                forwardedRequest += "Content-Length: \(contentLength)\r\n"
                forwardedRequest += "\r\n"
                forwardedRequest += body
                
                // Send to ampcode.com
                if let requestData = forwardedRequest.data(using: .utf8) {
                    targetConnection.send(content: requestData, completion: .contentProcessed({ error in
                        if let error = error {
                            NSLog("[ThinkingProxy] Send error to ampcode.com: \(error)")
                            targetConnection.cancel()
                            originalConnection.cancel()
                        } else {
                            // Receive response from ampcode.com and rewrite Location headers
                            self.receiveAmpResponse(from: targetConnection, originalConnection: originalConnection)
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Connection to ampcode.com failed: \(error)")
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway - Could not connect to ampcode.com")
                targetConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global(qos: .userInitiated))
    }

    private struct NVIDIADirectAttemptExecutionResult {
        let attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult
    }

    private func normalizedNVIDIAChatCompletionsBody(
        fromStreamMessages messages: [NVIDIAStreamMessage],
        fallbackBody rawBodyData: Data?,
        requestModel: String
    ) -> Data? {
        guard !messages.isEmpty else { return rawBodyData }

        var lastCompleteResponse: [String: Any]?
        var responseID: String?
        var responseCreated: Int?
        var responseModel: String?
        var responseUsage: [String: Any]?

        struct ToolCallAccumulator {
            var id: String?
            var type: String?
            var functionName = ""
            var functionArguments = ""
        }

        struct ChoiceAccumulator {
            var role = "assistant"
            var content = ""
            var refusal = ""
            var finishReason: Any?
            var toolCalls: [Int: ToolCallAccumulator] = [:]
        }

        var accumulatedChoices: [Int: ChoiceAccumulator] = [:]

        for message in messages {
            let payload = message.joinedData.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty,
                  let payloadData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }

            if let id = object["id"] as? String, !id.isEmpty {
                responseID = id
            }
            if let created = OpenAICompatTemporaryShim.integerValue(object["created"]) {
                responseCreated = created
            }
            if let model = object["model"] as? String, !model.isEmpty {
                responseModel = model
            }
            if let usage = object["usage"] as? [String: Any] {
                responseUsage = usage
            }

            if let choices = object["choices"] as? [[String: Any]], !choices.isEmpty {
                let containsFullMessage = choices.contains { choice in
                    (choice["message"] as? [String: Any]) != nil
                }
                if containsFullMessage {
                    lastCompleteResponse = object
                }

                for (fallbackIndex, choice) in choices.enumerated() {
                    let choiceIndex = OpenAICompatTemporaryShim.integerValue(choice["index"]) ?? fallbackIndex
                    var accumulator = accumulatedChoices[choiceIndex] ?? ChoiceAccumulator()

                    if let message = choice["message"] as? [String: Any] {
                        if let role = message["role"] as? String, !role.isEmpty {
                            accumulator.role = role
                        }
                        if let content = message["content"] as? String {
                            accumulator.content = content
                        }
                        if let refusal = message["refusal"] as? String {
                            accumulator.refusal = refusal
                        }
                        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                            for (toolFallbackIndex, toolCall) in toolCalls.enumerated() {
                                let toolIndex = OpenAICompatTemporaryShim.integerValue(toolCall["index"]) ?? toolFallbackIndex
                                var toolAccumulator = accumulator.toolCalls[toolIndex] ?? ToolCallAccumulator()
                                toolAccumulator.id = (toolCall["id"] as? String) ?? toolAccumulator.id
                                toolAccumulator.type = (toolCall["type"] as? String) ?? toolAccumulator.type
                                if let function = toolCall["function"] as? [String: Any] {
                                    if let name = function["name"] as? String {
                                        toolAccumulator.functionName = name
                                    }
                                    if let arguments = function["arguments"] as? String {
                                        toolAccumulator.functionArguments = arguments
                                    }
                                }
                                accumulator.toolCalls[toolIndex] = toolAccumulator
                            }
                        }
                    }

                    if let delta = choice["delta"] as? [String: Any] {
                        if let role = delta["role"] as? String, !role.isEmpty {
                            accumulator.role = role
                        }
                        if let content = delta["content"] as? String, !content.isEmpty {
                            accumulator.content += content
                        }
                        if let refusal = delta["refusal"] as? String, !refusal.isEmpty {
                            accumulator.refusal += refusal
                        }
                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for (toolFallbackIndex, toolCall) in toolCalls.enumerated() {
                                let toolIndex = OpenAICompatTemporaryShim.integerValue(toolCall["index"]) ?? toolFallbackIndex
                                var toolAccumulator = accumulator.toolCalls[toolIndex] ?? ToolCallAccumulator()
                                toolAccumulator.id = (toolCall["id"] as? String) ?? toolAccumulator.id
                                toolAccumulator.type = (toolCall["type"] as? String) ?? toolAccumulator.type
                                if let function = toolCall["function"] as? [String: Any] {
                                    if let name = function["name"] as? String, !name.isEmpty {
                                        toolAccumulator.functionName += name
                                    }
                                    if let arguments = function["arguments"] as? String, !arguments.isEmpty {
                                        toolAccumulator.functionArguments += arguments
                                    }
                                }
                                accumulator.toolCalls[toolIndex] = toolAccumulator
                            }
                        }
                    }

                    if let finishReason = choice["finish_reason"], !(finishReason is NSNull) {
                        accumulator.finishReason = finishReason
                    }
                    accumulatedChoices[choiceIndex] = accumulator
                }
            }
        }

        if var lastCompleteResponse {
            if let usage = responseUsage {
                lastCompleteResponse["usage"] = usage
            }
            return try? JSONSerialization.data(withJSONObject: lastCompleteResponse)
        }

        let sortedChoices = accumulatedChoices.keys.sorted()
        guard !sortedChoices.isEmpty else { return rawBodyData }

        let reducedChoices: [[String: Any]] = sortedChoices.map { choiceIndex in
            let accumulator = accumulatedChoices[choiceIndex] ?? ChoiceAccumulator()
            var message: [String: Any] = [
                "role": accumulator.role,
                "content": accumulator.content
            ]
            if !accumulator.refusal.isEmpty {
                message["refusal"] = accumulator.refusal
            }
            if !accumulator.toolCalls.isEmpty {
                let mergedToolCalls = accumulator.toolCalls.keys.sorted().map { toolIndex -> [String: Any] in
                    let toolAccumulator = accumulator.toolCalls[toolIndex] ?? ToolCallAccumulator()
                    return [
                        "id": toolAccumulator.id ?? "call_\(toolIndex)",
                        "type": toolAccumulator.type ?? "function",
                        "function": [
                            "name": toolAccumulator.functionName,
                            "arguments": toolAccumulator.functionArguments
                        ]
                    ]
                }
                message["tool_calls"] = mergedToolCalls
            }

            let derivedFinishReason: Any = accumulator.finishReason
                ?? (!accumulator.toolCalls.isEmpty ? "tool_calls" : "stop")
            return [
                "index": choiceIndex,
                "message": message,
                "finish_reason": derivedFinishReason
            ]
        }

        var reducedResponse: [String: Any] = [
            "id": responseID ?? "chatcmpl_nvidia_\(UUID().uuidString)",
            "object": "chat.completion",
            "created": responseCreated ?? Int(Date().timeIntervalSince1970),
            "model": responseModel ?? requestModel,
            "choices": reducedChoices
        ]
        if let usage = responseUsage {
            reducedResponse["usage"] = usage
        }
        return try? JSONSerialization.data(withJSONObject: reducedResponse)
    }

    private func processNVIDIAStreamingAttemptResponse(
        _ transportResponse: NVIDIADirectTransportResponse,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        attemptLane: Int,
        clientRequestedStream: Bool,
        surface: NVIDIAExecutionSurface = .direct
    ) -> NVIDIADirectAttemptExecutionResult {
        guard transportResponse.error == nil,
              let response = transportResponse.response,
              let rawBodyData = transportResponse.bodyData else {
            return NVIDIADirectAttemptExecutionResult(
                attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                    data: transportResponse.bodyData,
                    response: transportResponse.response,
                    error: transportResponse.error,
                    deadlineStage: transportResponse.deadlineStage,
                    firstByteLatencyMilliseconds: transportResponse.firstByteLatencyMilliseconds,
                    totalLatencyMilliseconds: transportResponse.totalLatencyMilliseconds,
                    negotiatedApplicationProtocol: transportResponse.negotiatedApplicationProtocol
                )
            )
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let parserChunks: [Data]
        if contentType.contains("text/event-stream") {
            parserChunks = transportResponse.chunks.isEmpty ? [rawBodyData] : transportResponse.chunks
        } else {
            parserChunks = []
        }

        var normalizedBodyData = rawBodyData
        if !parserChunks.isEmpty {
            var engine = NVIDIAStreamEngine()
            var bufferedSink = NVIDIABufferedAccumulatorSink()

            do {
                for chunk in parserChunks {
                    let outputs = try engine.ingest(
                        chunk,
                        surface: surface,
                        attemptLane: attemptLane
                    )
                    for output in outputs {
                        try bufferedSink.consume(output)
                    }
                }
                let trailingOutputs = try engine.finish(
                    surface: surface,
                    attemptLane: attemptLane
                )
                for output in trailingOutputs {
                    try bufferedSink.consume(output)
                }
                if let finalData = normalizedNVIDIAChatCompletionsBody(
                    fromStreamMessages: bufferedSink.messages,
                    fallbackBody: rawBodyData,
                    requestModel: state.model
                ) {
                    normalizedBodyData = finalData
                }
            } catch {
                normalizedBodyData = rawBodyData
            }
        }

        return NVIDIADirectAttemptExecutionResult(
            attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                data: normalizedBodyData,
                response: response,
                error: nil,
                deadlineStage: transportResponse.deadlineStage,
                firstByteLatencyMilliseconds: transportResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: transportResponse.totalLatencyMilliseconds,
                negotiatedApplicationProtocol: transportResponse.negotiatedApplicationProtocol
            )
        )
    }

    @discardableResult
    private func startNVIDIATransportAttempt(
        request: URLRequest,
        requestJSON: String,
        requestModel: String,
        clientRequestedStream: Bool,
        onChunk: ((Data, Date) -> Void)? = nil,
        completion: @escaping (NVIDIADirectTransportResponse) -> Void
    ) -> (() -> Void)? {
        if let nvidiaDirectStreamingTransportForTesting {
            return nvidiaDirectStreamingTransportForTesting(
                request,
                onChunk ?? { _, _ in },
                completion
            )
        }

        if let nvidiaDirectTransportForTesting {
            return nvidiaDirectTransportForTesting(request, completion)
        }

        let transportAttempt = NVIDIAHTTP1TransportAttempt(
            request: request,
            host: effectiveNVIDIADirectTargetHost,
            port: effectiveNVIDIADirectTargetPort,
            policy: effectiveNVIDIADirectTransportPolicy(),
            firstResponseSeconds: OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                forRequestJSON: requestJSON,
                routeHealthStatus: OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: requestModel)
            ),
            bufferedResponseSeconds: clientRequestedStream
                ? nil
                : OpenAICompatTemporaryShim.effectiveBufferedResponseDeadline(forRequestJSON: requestJSON),
            onChunk: onChunk ?? { _, _ in },
            completion: completion
        )
        guard let cancel = transportAttempt.start() else {
            return nil
        }
        return {
            withExtendedLifetime(transportAttempt) {
                cancel()
            }
        }
    }

    private func forwardNVIDIAStreamingRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        requestTrace: RequestTraceContext,
        state: OpenAICompatTemporaryShim.NVIDIARetryState
    ) {
        let coordinator = NVIDIAAttemptCoordinator()
        let requestController = RequestCancellationController()
        installClientDisconnectCancellation(on: originalConnection, controller: requestController, requestTrace: requestTrace)
        let requestDeadline = OpenAICompatTemporaryShim.untrustedNVIDIADirectRequestDeadline(forRequestJSON: body)
        let requestDeadlineQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-direct-request-deadline")
        var requestDeadlineCompleted = false
        var requestDeadlineWorkItem: DispatchWorkItem?
        func cancelRequestDeadline() {
            requestDeadlineQueue.sync {
                requestDeadlineCompleted = true
                requestDeadlineWorkItem?.cancel()
                requestDeadlineWorkItem = nil
            }
        }
        requestController.registerCancelHook {
            cancelRequestDeadline()
        }
        if let requestDeadline, requestDeadline.seconds > 0 {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let shouldFire = requestDeadlineQueue.sync { () -> Bool in
                    guard !requestDeadlineCompleted else { return false }
                    requestDeadlineCompleted = true
                    requestDeadlineWorkItem = nil
                    return true
                }
                guard shouldFire else { return }
                guard coordinator.tryFinish(attemptLane: 0) else { return }
                let route = OpenAICompatTemporaryShim.routeIdentityForHealthTracking(forRequestModel: state.model)
                let telemetryEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: Date(),
                    requestModel: state.model,
                    canonicalModelID: route?.canonicalModelID ?? state.model,
                    transportOutcome: "send_error",
                    attemptLane: 1,
                    failureClass: requestDeadline.stage == .firstResponse
                        ? "transport_timeout_first_byte"
                        : "transport_timeout",
                    timeoutStage: requestDeadline.stage,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "live_request",
                    firstByteLatencyMilliseconds: nil,
                    totalLatencyMilliseconds: Int(requestDeadline.seconds * 1000),
                    inflightAtRequest: route.map {
                        OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: $0.routeHealthKey)
                    },
                    proxyRequestID: requestTrace.proxyRequestID,
                    callerRequestID: requestTrace.callerRequestID,
                    callerSessionID: requestTrace.callerSessionID,
                    requestShape: requestTrace.requestShape
                )
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: telemetryEvent)
                NSLog(
                    "[ThinkingProxy] Untrusted NVIDIA direct request exceeded %@ deadline after %.2fs. proxy_request_id:%@",
                    requestDeadline.stage.rawValue,
                    requestDeadline.seconds,
                    requestTrace.proxyRequestID
                )
                let clientStillConnected = requestController.isCancelled() != true
                requestController.cancel()
                guard clientStillConnected else { return }
                self.deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 504,
                    message: "Gateway Timeout",
                    coalescingKey: state.coalescingKey,
                    overridingHeaders: requestTrace.responseHeaders
                )
            }
            requestDeadlineQueue.sync {
                requestDeadlineWorkItem = workItem
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + requestDeadline.seconds,
                execute: workItem
            )
        }
        let routeHealthStatus = OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: state.model)
        let hedgeEligible = OpenAICompatTemporaryShim.allowsHedgedNVIDIARequest(
            method: method,
            path: path,
            jsonString: body,
            routeHealthStatus: routeHealthStatus
        )
        executeNVIDIADirectAttempt(
            method: method,
            path: path,
            headers: headers,
            body: body,
            originalConnection: originalConnection,
            state: state,
            coordinator: coordinator,
            requestController: requestController,
            attemptLane: 1,
            hedgeEligible: hedgeEligible,
            requestTrace: requestTrace,
            onMeaningfulOutput: requestDeadline?.stage == .firstResponse ? cancelRequestDeadline : nil,
            onRequestResolved: cancelRequestDeadline
        )
    }

    private func executeNVIDIADirectAttempt(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        coordinator: NVIDIAAttemptCoordinator,
        requestController: RequestCancellationController,
        attemptLane: Int,
        hedgeEligible: Bool,
        requestTrace: RequestTraceContext,
        onMeaningfulOutput: (() -> Void)? = nil,
        onRequestResolved: (() -> Void)? = nil
    ) {
        guard requestController.isCancelled() != true else { return }
        guard !coordinator.isFinished() else { return }
        guard let url = URL(string: "http://\(effectiveNVIDIADirectTargetHost):\(effectiveNVIDIADirectTargetPort)\(path)") else {
            if coordinator.tryFinish(attemptLane: attemptLane) {
                onRequestResolved?()
                sendError(
                    to: originalConnection,
                    statusCode: 500,
                    message: "Internal Server Error",
                    overridingHeaders: requestTrace.responseHeaders
                )
            }
            return
        }

        let clientRequestedStream = OpenAICompatTemporaryShim.requestedStream(forRequestJSON: body)
        let transportPolicy = effectiveNVIDIADirectTransportPolicy()
        let upstreamBody = OpenAICompatTemporaryShim.rewrittenNVIDIADirectUpstreamRequestJSON(
            method: method,
            path: path,
            jsonString: body
        ) ?? body

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = Data(upstreamBody.utf8)
        request.timeoutInterval = OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: body) ?? Config.defaultMitigatedAttemptTimeout
        guard let permit = acquireRouteConcurrencyPermit(forRequestModel: state.model) else {
            guard attemptLane == 1 else { return }
            let retryDelay = DispatchTimeInterval.milliseconds(
                OpenAICompatTemporaryShim.jitteredRetryBackoffMilliseconds(250)
            )
            requestController.scheduleRetry(after: retryDelay) { [weak self] in
                guard let self, !coordinator.isFinished() else { return }
                self.executeNVIDIADirectAttempt(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    originalConnection: originalConnection,
                    state: state,
                    coordinator: coordinator,
                    requestController: requestController,
                    attemptLane: attemptLane,
                    hedgeEligible: hedgeEligible,
                    requestTrace: requestTrace,
                    onMeaningfulOutput: onMeaningfulOutput,
                    onRequestResolved: onRequestResolved
                )
            }
            return
        }

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("close", forHTTPHeaderField: "Connection")
        let attemptStateQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-direct-attempt-state")
        var attemptReceivedPayload = false
        var receivedChunkCount = 0
        var liveStreamStarted = false
        var liveStreamFailed = false
        var liveStreamFinished = false
        var interChunkTimeoutTriggered = false
        var keepaliveTimer: DispatchSourceTimer?
        var interChunkDeadlineWorkItem: DispatchWorkItem?
        var transportCancel: (() -> Void)?
        var liveStreamingEngine = NVIDIAStreamEngine()
        var liveStreamingSink = NVIDIAEventStreamSink(policy: transportPolicy.sinkPolicy)
        func cancelStreamingTimersLocked() {
            interChunkDeadlineWorkItem?.cancel()
            interChunkDeadlineWorkItem = nil
            keepaliveTimer?.cancel()
            keepaliveTimer = nil
        }
        let scheduleKeepaliveTimerIfNeeded: () -> Void = { [weak self] in
            guard let self else { return }
            let timerToStart: DispatchSourceTimer? = attemptStateQueue.sync {
                guard clientRequestedStream,
                      transportPolicy.sinkPolicy.emitsDownstreamKeepalives,
                      transportPolicy.sinkPolicy.keepaliveIntervalSeconds > 0,
                      liveStreamStarted,
                      !liveStreamFinished,
                      keepaliveTimer == nil else {
                    return nil
                }
                let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
                timer.schedule(
                    deadline: .now() + transportPolicy.sinkPolicy.keepaliveIntervalSeconds,
                    repeating: transportPolicy.sinkPolicy.keepaliveIntervalSeconds
                )
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    let keepaliveFrame: Data? = attemptStateQueue.sync {
                        guard liveStreamStarted,
                              !liveStreamFinished,
                              !liveStreamFailed,
                              !requestController.isCancelled(),
                              !coordinator.isFinished(),
                              let keepalive = liveStreamingSink.emitKeepaliveIfIdle(now: Date()) else {
                            return nil
                        }
                        return Data(keepalive.utf8)
                    }
                    if let keepaliveFrame {
                        self.sendStreamingHTTPChunk(to: originalConnection, chunk: keepaliveFrame)
                    }
                }
                keepaliveTimer = timer
                return timer
            }
            timerToStart?.resume()
        }
        let resetInterChunkDeadline: () -> Void = {
            guard clientRequestedStream, transportPolicy.interChunkReadTimeoutSeconds > 0 else { return }
            let workItemToSchedule: DispatchWorkItem? = attemptStateQueue.sync {
                guard !liveStreamFinished else { return nil }
                interChunkDeadlineWorkItem?.cancel()
                let workItem = DispatchWorkItem {
                    let cancelAction: (() -> Void)? = attemptStateQueue.sync {
                        guard !liveStreamFinished,
                              !liveStreamFailed,
                              attemptReceivedPayload,
                              !requestController.isCancelled(),
                              !coordinator.isFinished() else {
                            return nil
                        }
                        interChunkTimeoutTriggered = true
                        liveStreamFailed = true
                        return transportCancel
                    }
                    cancelAction?()
                }
                interChunkDeadlineWorkItem = workItem
                return workItem
            }
            if let workItemToSchedule {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + transportPolicy.interChunkReadTimeoutSeconds,
                    execute: workItemToSchedule
                )
            }
        }
        let markAttemptPayloadReceived: (Data, Date) -> Void = { _, _ in
            let firstPayloadArrived = attemptStateQueue.sync { () -> Bool in
                let firstPayload = !attemptReceivedPayload
                attemptReceivedPayload = true
                return firstPayload
            }
            if firstPayloadArrived {
                onMeaningfulOutput?()
            }
        }
        let handleLiveStreamingChunk: (Data, Date) -> Void = { [weak self] chunk, receivedAt in
            markAttemptPayloadReceived(chunk, receivedAt)
            guard let self, clientRequestedStream else { return }
            resetInterChunkDeadline()

            let emittedFrames: [Data]? = attemptStateQueue.sync {
                guard !liveStreamFailed else { return nil }
                do {
                    receivedChunkCount += 1
                    let outputs = try liveStreamingEngine.ingest(
                        chunk,
                        receivedAt: receivedAt,
                        surface: .direct,
                        attemptLane: attemptLane
                    )
                    guard !outputs.isEmpty else { return [] }

                    var frames: [Data] = []
                    for output in outputs {
                        let emittedFrame: String?
                        switch output {
                        case .comment:
                            emittedFrame = nil
                        case .message, .done:
                            if !liveStreamStarted {
                                let sseHeaders: [AnyHashable: Any] = [
                                    "Content-Type": "text/event-stream; charset=utf-8",
                                    "Cache-Control": "no-cache",
                                    "X-Accel-Buffering": "no"
                                ]
                                self.startStreamingHTTPResponse(
                                    to: originalConnection,
                                    statusCode: 200,
                                    headers: sseHeaders,
                                    overridingHeaders: requestTrace.responseHeaders
                                )
                                liveStreamStarted = true
                            }
                            let previousFrameCount = liveStreamingSink.emittedFrames.count
                            try liveStreamingSink.consume(output, receivedAt: receivedAt)
                            let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                            emittedFrame = newFrames.last
                        }
                        if let emittedFrame {
                            frames.append(Data(emittedFrame.utf8))
                        }
                    }
                    return frames
                } catch {
                    liveStreamFailed = true
                    cancelStreamingTimersLocked()
                    return nil
                }
            }

            guard let emittedFrames else { return }
            scheduleKeepaliveTimerIfNeeded()
            for frame in emittedFrames {
                self.sendStreamingHTTPChunk(to: originalConnection, chunk: frame)
            }
        }

        let handleTransportResponse: (NVIDIADirectTransportResponse) -> Void = { [weak self] transportResponse in
            guard let self else { return }
            defer {
                permit.release()
                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
            }
            guard requestController.isCancelled() != true else { return }

            let effectiveTransportResponse: NVIDIADirectTransportResponse = attemptStateQueue.sync {
                liveStreamFinished = true
                cancelStreamingTimersLocked()
                if interChunkTimeoutTriggered && transportResponse.deadlineStage == .none {
                    return NVIDIADirectTransportResponse(
                        chunks: transportResponse.chunks,
                        response: transportResponse.response,
                        error: transportResponse.error ?? URLError(.timedOut),
                        firstByteLatencyMilliseconds: transportResponse.firstByteLatencyMilliseconds,
                        totalLatencyMilliseconds: transportResponse.totalLatencyMilliseconds,
                        deadlineStage: .interChunkRead
                    )
                }
                return transportResponse
            }

            let processedAttempt = self.processNVIDIAStreamingAttemptResponse(
                effectiveTransportResponse,
                state: state,
                attemptLane: attemptLane,
                clientRequestedStream: clientRequestedStream
            )
            if clientRequestedStream {
                let trailingFrames: [Data]? = attemptStateQueue.sync {
                    guard liveStreamStarted, !liveStreamFailed else { return nil }
                    do {
                        var frames: [Data] = []
                        let remainingChunks = effectiveTransportResponse.chunks.dropFirst(receivedChunkCount)
                        for chunk in remainingChunks {
                            let outputs = try liveStreamingEngine.ingest(
                                chunk,
                                receivedAt: Date(),
                                surface: .direct,
                                attemptLane: attemptLane
                            )
                            for output in outputs {
                                let previousFrameCount = liveStreamingSink.emittedFrames.count
                                try liveStreamingSink.consume(output)
                                let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                                if let emittedFrame = newFrames.last {
                                    frames.append(Data(emittedFrame.utf8))
                                }
                            }
                        }
                        receivedChunkCount = effectiveTransportResponse.chunks.count
                        let trailingOutputs = try liveStreamingEngine.finish(
                            surface: .direct,
                            attemptLane: attemptLane
                        )
                        for output in trailingOutputs {
                            let previousFrameCount = liveStreamingSink.emittedFrames.count
                            try liveStreamingSink.consume(output)
                            let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                            if let emittedFrame = newFrames.last {
                                frames.append(Data(emittedFrame.utf8))
                            }
                        }
                        if !liveStreamingSink.terminalReceived {
                            let previousFrameCount = liveStreamingSink.emittedFrames.count
                            try liveStreamingSink.consume(.done)
                            let newFrames = liveStreamingSink.emittedFrames.dropFirst(previousFrameCount)
                            if let emittedFrame = newFrames.last {
                                frames.append(Data(emittedFrame.utf8))
                            }
                        }
                        return frames
                    } catch {
                        liveStreamFailed = true
                        return nil
                    }
                }
                if let trailingFrames {
                    for frame in trailingFrames {
                        self.sendStreamingHTTPChunk(to: originalConnection, chunk: frame)
                    }
                }
            }
            let attempt = processedAttempt.attempt
            let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                path: path,
                state: state,
                attempt: attempt
            )
            let telemetryEvent = OpenAICompatTemporaryShim.telemetryEvent(
                path: path,
                state: state,
                attempt: attempt,
                outcome: outcome,
                source: "live_request",
                attemptLane: attemptLane,
                proxyRequestID: requestTrace.proxyRequestID,
                callerRequestID: requestTrace.callerRequestID,
                callerSessionID: requestTrace.callerSessionID,
                requestShape: requestTrace.requestShape
            )

            switch outcome {
            case .retry(let nextState):
                if let response = attempt.response {
                    OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest,
                        statusCode: response.statusCode,
                        headers: response.allHeaderFields,
                        bodyData: attempt.data
                    )
                }
                guard !coordinator.isFinished() else { return }
                let isFirstByteTimeout = attempt.deadlineStage == .firstResponse
                if attemptLane == 1,
                   hedgeEligible,
                   coordinator.shouldStartHedge() {
                    if isFirstByteTimeout {
                        OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: telemetryEvent)
                    } else {
                        OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                    }
                    self.executeNVIDIADirectAttempt(
                        method: method,
                        path: path,
                        headers: headers,
                        body: body,
                        originalConnection: originalConnection,
                        state: nextState,
                        coordinator: coordinator,
                        requestController: requestController,
                        attemptLane: 2,
                        hedgeEligible: false,
                        requestTrace: requestTrace,
                        onMeaningfulOutput: onMeaningfulOutput,
                        onRequestResolved: onRequestResolved
                    )
                    return
                }
                if isFirstByteTimeout {
                    OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: telemetryEvent)
                } else {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                }
                if attemptStateQueue.sync(execute: { liveStreamStarted }) {
                    self.finishStreamingHTTPResponse(to: originalConnection)
                    return
                }
                self.scheduleNVIDIADirectRetry(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    originalConnection: originalConnection,
                    state: nextState,
                    coordinator: coordinator,
                    requestController: requestController,
                    attemptLane: attemptLane,
                    hedgeEligible: hedgeEligible,
                    requestTrace: requestTrace,
                    onMeaningfulOutput: onMeaningfulOutput,
                    onRequestResolved: onRequestResolved
                )
            case .sendResponse(let statusCode, let headers, let bodyData):
                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
                onRequestResolved?()
                guard requestController.isCancelled() != true else { return }
                let winningTelemetryEvent = OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                    telemetryEvent,
                    winnerAttemptLane: attemptLane
                )
                if statusCode >= 200 && statusCode < 300 {
                    OpenAICompatTemporaryShim.recordConcurrencySuccess(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest
                    )
                    OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
                } else if statusCode == 429 || statusCode == 403 || statusCode == 404 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
                    OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest,
                        statusCode: statusCode,
                        headers: headers,
                        bodyData: bodyData
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
                } else {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(winningTelemetryEvent)
                }

                if clientRequestedStream,
                   attemptStateQueue.sync(execute: { liveStreamStarted }),
                   statusCode >= 200,
                   statusCode < 300 {
                    self.finishStreamingHTTPResponse(to: originalConnection)
                    return
                }

                if clientRequestedStream,
                   statusCode >= 200,
                   statusCode < 300 {
                    self.deliverBufferedError(
                        defaultConnection: originalConnection,
                        statusCode: 502,
                        message: "Bad Gateway - NVIDIA stream finished without live SSE delivery",
                        coalescingKey: state.coalescingKey,
                        overridingHeaders: requestTrace.responseHeaders
                    )
                    return
                }

                self.deliverBufferedHTTPResponse(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    headers: headers,
                    body: bodyData,
                    coalescingKey: state.coalescingKey,
                    overridingModel: state.model,
                    overridingHeaders: requestTrace.responseHeaders
                )
            case .sendError(let statusCode, let message):
                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
                onRequestResolved?()
                guard requestController.isCancelled() != true else { return }
                let winningTelemetryEvent = OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                    telemetryEvent,
                    winnerAttemptLane: attemptLane
                )
                if statusCode == 429 || statusCode == 403 || statusCode == 404 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
                    if let response = attempt.response {
                        OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                            routeHealthKey: permit.routeHealthKey,
                            inflightAtRequest: permit.inflightAtRequest,
                            statusCode: response.statusCode,
                            headers: response.allHeaderFields,
                            bodyData: attempt.data
                        )
                    }
                    OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
                } else {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(winningTelemetryEvent)
                }
                if attemptStateQueue.sync(execute: { liveStreamStarted }) {
                    self.finishStreamingHTTPResponse(to: originalConnection)
                    return
                }
                self.deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    message: message,
                    coalescingKey: state.coalescingKey,
                    overridingHeaders: requestTrace.responseHeaders
                )
            }
        }
        guard let cancel = startNVIDIATransportAttempt(
            request: request,
            requestJSON: body,
            requestModel: state.model,
            clientRequestedStream: clientRequestedStream,
            onChunk: handleLiveStreamingChunk,
            completion: handleTransportResponse
        ) else {
            permit.release()
            coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
            guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
            onRequestResolved?()
            self.deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 502,
                message: "upstream session unavailable",
                coalescingKey: state.coalescingKey,
                overridingHeaders: requestTrace.responseHeaders
            )
            return
        }
        attemptStateQueue.sync {
            transportCancel = cancel
        }
        coordinator.registerAttempt(attemptLane: attemptLane) {
            permit.release()
            let cancelAction: (() -> Void)? = attemptStateQueue.sync {
                liveStreamFinished = true
                cancelStreamingTimersLocked()
                return transportCancel
            }
            cancelAction?()
        }
        requestController.registerCurrentCancel {
            let cancelAction: (() -> Void)? = attemptStateQueue.sync {
                liveStreamFinished = true
                cancelStreamingTimersLocked()
                return transportCancel
            }
            cancelAction?()
            _ = coordinator.tryFinish(attemptLane: 0)
        }
        if attemptLane == 1, hedgeEligible {
            let hedgeDelay = OpenAICompatTemporaryShim.recommendedNVIDIAHedgeDelay(forRequestModel: state.model)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + hedgeDelay) { [weak self] in
                let payloadAlreadyStarted = attemptStateQueue.sync { attemptReceivedPayload }
                guard let self,
                      requestController.isCancelled() != true,
                      !coordinator.isFinished(),
                      !payloadAlreadyStarted,
                      coordinator.shouldStartHedge() else { return }
                NSLog("[ThinkingProxy] Starting hedged NVIDIA attempt for suspect route %@ after %.2fs without first byte", state.model, hedgeDelay)
                self.executeNVIDIADirectAttempt(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    originalConnection: originalConnection,
                    state: state,
                    coordinator: coordinator,
                    requestController: requestController,
                    attemptLane: 2,
                    hedgeEligible: false,
                    requestTrace: requestTrace,
                    onMeaningfulOutput: onMeaningfulOutput,
                    onRequestResolved: onRequestResolved
                )
            }
        }
    }

    private func forwardModelListRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        originalConnection: NWConnection
    ) {
        guard let url = URL(string: "http://\(targetHost):\(targetPort)\(path)") else {
            sendError(to: originalConnection, statusCode: 500, message: "Internal Server Error")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("close", forHTTPHeaderField: "Connection")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                NSLog("[ThinkingProxy] Model-list request failed: \(error)")
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let bodyData = data else {
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
                return
            }

            let filteredBody = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(bodyData) ?? bodyData
            self.sendHTTPResponse(
                to: originalConnection,
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields,
                body: filteredBody
            )
        }.resume()
    }

    private func startCanaryLoop() {
        stateQueue.sync {
            guard canaryTimer == nil else { return }
            scheduleNextCanaryLocked(after: OpenAICompatTemporaryShim.recommendedCanaryInterval())
        }
    }

    private func scheduleNextCanaryLocked(after interval: TimeInterval) {
        canaryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: canaryQueue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            self?.performCanariesOnce { [weak self] in
                guard let self else { return }
                self.stateQueue.sync {
                    guard self.isRunning else { return }
                    self.scheduleNextCanaryLocked(after: OpenAICompatTemporaryShim.recommendedCanaryInterval())
                }
            }
        }
        canaryTimer = timer
        timer.resume()
    }

    // Called while already holding stateQueue — must not re-enter the queue.
    private func stopCanaryLoopLocked() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        canaryTimer?.cancel()
        canaryTimer = nil
        canarySweepInFlight = false
    }

    private func stopCanaryLoop() {
        stateQueue.sync { stopCanaryLoopLocked() }
    }

    private func startMaintenanceLoop() {
        stateQueue.sync {
            guard maintenanceTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: canaryQueue)
            timer.schedule(deadline: .now() + 300, repeating: 300)
            timer.setEventHandler { [weak self] in
                guard let self, self.isRunning else { return }
                OpenAICompatTemporaryShim.maintenanceRouteHealthPass()
            }
            maintenanceTimer = timer
            timer.resume()
        }
    }

    // Called while already holding stateQueue — must not re-enter the queue.
    private func stopMaintenanceLoopLocked() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        maintenanceTimer?.cancel()
        maintenanceTimer = nil
    }

    private func stopMaintenanceLoop() {
        stateQueue.sync { stopMaintenanceLoopLocked() }
    }

    func performCanariesOnce(completion: (() -> Void)? = nil) {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !canarySweepInFlight else { return false }
            canarySweepInFlight = true
            return true
        }
        guard shouldStart else {
            completion?()
            return
        }

        let requestModels = OpenAICompatTemporaryShim.canaryProbeRequestModels()
            .filter { model in
                guard let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: model) else {
                    return true
                }
                return !OpenAICompatTemporaryShim.canaryDisabledCanonicalModelIDs.contains(route.canonicalModelID)
            }
        guard !requestModels.isEmpty else {
            stateQueue.sync { canarySweepInFlight = false }
            completion?()
            return
        }

        runCanary(at: 0, requestModels: requestModels) { [weak self] in
            self?.stateQueue.sync { self?.canarySweepInFlight = false }
            completion?()
        }
    }

    private func runCanary(at index: Int, requestModels: [String], completion: @escaping () -> Void) {
        guard index < requestModels.count else {
            completion()
            return
        }

        let requestModel = requestModels[index]
        let requestJSON = canaryRequestJSON(forRequestModel: requestModel)
        let transformedJSON = OpenAICompatTemporaryShim.transformRequest(
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: requestJSON
        ) ?? requestJSON

        sendCanaryRequest(requestModel: requestModel, requestJSON: transformedJSON) { [weak self] data, response, error in
            guard let self else { return }
            let canaryState = OpenAICompatTemporaryShim.NVIDIARetryState(
                model: requestModel,
                initialTransportRetries: 0,
                initialSemanticRetries: 0,
                transportRetriesRemaining: 0,
                semanticRetriesRemaining: 0,
                retryBackoffMilliseconds: 0,
                salvagesBestEffortRepair: false,
                bestEffortRepairedBodyData: nil
            )
            let attempt = OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                data: data,
                response: response,
                error: error,
                deadlineStage: .none
            )
            let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                path: "/v1/chat/completions",
                state: canaryState,
                attempt: attempt
            )
            let telemetryEvent = OpenAICompatTemporaryShim.telemetryEvent(
                path: "/v1/chat/completions",
                state: canaryState,
                attempt: attempt,
                outcome: outcome,
                source: "canary"
            )

            switch outcome {
            case .sendResponse(let statusCode, _, _):
                if statusCode >= 200 && statusCode < 300 {
                    OpenAICompatTemporaryShim.recordRouteSuccess(
                        forRequestModel: requestModel,
                        telemetryEvent: telemetryEvent
                    )
                } else {
                    let forcedOpenUntil = OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                        failureClass: telemetryEvent.failureClass,
                        statusCode: statusCode,
                        headers: response?.allHeaderFields ?? [:],
                        bodyData: data
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: requestModel,
                        telemetryEvent: telemetryEvent,
                        forcedOpenUntil: forcedOpenUntil
                    )
                }
            case .retry, .sendError:
                let forcedOpenUntil = response.map {
                    OpenAICompatTemporaryShim.smartAliasForcedOpenUntil(
                        failureClass: telemetryEvent.failureClass,
                        statusCode: $0.statusCode,
                        headers: $0.allHeaderFields,
                        bodyData: data
                    )
                } ?? nil
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: requestModel,
                    telemetryEvent: telemetryEvent,
                    forcedOpenUntil: forcedOpenUntil
                )
            }

            self.runCanary(at: index + 1, requestModels: requestModels, completion: completion)
        }
    }

    private func sendCanaryRequest(
        requestModel: String,
        requestJSON: String,
        completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void
    ) {
        if let nvidiaCanaryTransportForTesting {
            nvidiaCanaryTransportForTesting(requestModel, requestJSON, completion)
            return
        }

        guard let url = URL(string: "http://\(targetHost):\(targetPort)/v1/chat/completions") else {
            completion(nil, nil, URLError(.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(requestJSON.utf8)
        request.timeoutInterval = OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: requestJSON) ?? Config.nvidiaCanaryTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("close", forHTTPHeaderField: "Connection")
        request.setValue("canary", forHTTPHeaderField: "X-VibeProxy-Probe")

        URLSession.shared.dataTask(with: request) { data, response, error in
            completion(data, response as? HTTPURLResponse, error)
        }.resume()
    }

    private func canaryRequestJSON(forRequestModel requestModel: String) -> String {
        return """
        {
          "model": "\(requestModel)",
          "messages": [
            {"role": "user", "content": "Hi"}
          ],
          "max_tokens": 1,
          "stream": false
        }
        """
    }

    private func scheduleNVIDIADirectRetry(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        coordinator: NVIDIAAttemptCoordinator,
        requestController: RequestCancellationController,
        attemptLane: Int,
        hedgeEligible: Bool,
        requestTrace: RequestTraceContext,
        onMeaningfulOutput: (() -> Void)? = nil,
        onRequestResolved: (() -> Void)? = nil
    ) {
        let delay = DispatchTimeInterval.milliseconds(
            OpenAICompatTemporaryShim.jitteredRetryBackoffMilliseconds(state.retryBackoffMilliseconds)
        )
        requestController.scheduleRetry(after: delay) { [weak self] in
            guard let self, !coordinator.isFinished() else { return }
            self.executeNVIDIADirectAttempt(
                method: method,
                path: path,
                headers: headers,
                body: body,
                originalConnection: originalConnection,
                state: state,
                coordinator: coordinator,
                requestController: requestController,
                attemptLane: attemptLane,
                hedgeEligible: hedgeEligible,
                requestTrace: requestTrace,
                onMeaningfulOutput: onMeaningfulOutput,
                onRequestResolved: onRequestResolved
            )
        }
    }
    
    /**
     Receives response from ampcode.com and rewrites Location headers to add /api/ prefix
     */
    private func receiveAmpResponse(from targetConnection: NWConnection, originalConnection: NWConnection) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive Amp response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Convert to string to rewrite headers
                if var responseString = String(data: data, encoding: .utf8) {
                    // Rewrite Location headers to prepend /api/
                    responseString = responseString.replacingOccurrences(
                        of: "\r\nlocation: /",
                        with: "\r\nlocation: /api/",
                        options: .caseInsensitive
                    )
                    responseString = responseString.replacingOccurrences(
                        of: "\r\nLocation: /",
                        with: "\r\nLocation: /api/"
                    )

                    // Rewrite absolute Location headers to keep browser on localhost proxy
                    responseString = responseString.replacingOccurrences(
                        of: "\r\nLocation: https://ampcode.com/",
                        with: "\r\nLocation: /api/",
                        options: .caseInsensitive
                    )
                    responseString = responseString.replacingOccurrences(
                        of: "\r\nLocation: http://ampcode.com/",
                        with: "\r\nLocation: /api/",
                        options: .caseInsensitive
                    )

                    // Rewrite cookie domain so browser accepts cookies from localhost
                    responseString = responseString.replacingOccurrences(
                        of: "Domain=.ampcode.com",
                        with: "Domain=localhost",
                        options: .caseInsensitive
                    )
                    responseString = responseString.replacingOccurrences(
                        of: "Domain=ampcode.com",
                        with: "Domain=localhost",
                        options: .caseInsensitive
                    )
                    
                    if let modifiedData = responseString.data(using: .utf8) {
                        originalConnection.send(content: modifiedData, completion: .contentProcessed({ sendError in
                            if let sendError = sendError {
                                NSLog("[ThinkingProxy] Send Amp response error: \(sendError)")
                            }
                            
                            if isComplete {
                                targetConnection.cancel()
                                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                                    originalConnection.cancel()
                                }))
                            } else {
                                // Continue receiving more data
                                self.receiveAmpResponse(from: targetConnection, originalConnection: originalConnection)
                            }
                        }))
                    }
                } else {
                    // Not UTF-8, forward as-is
                    originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                        if let sendError = sendError {
                            NSLog("[ThinkingProxy] Send Amp response error: \(sendError)")
                        }
                        
                        if isComplete {
                            targetConnection.cancel()
                            originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                                originalConnection.cancel()
                            }))
                        } else {
                            self.receiveAmpResponse(from: targetConnection, originalConnection: originalConnection)
                        }
                    }))
                }
            } else if isComplete {
                targetConnection.cancel()
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }
    
    /**
     Forwards Claude requests to Vercel AI Gateway (ai-gateway.vercel.sh)
     */
    private func forwardToVercel(method: String, path: String, version: String, headers: [(String, String)], body: String, thinkingEnabled: Bool, originalConnection: NWConnection) {
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(Config.vercelGatewayHost), port: 443)
        let targetConnection = NWConnection(to: endpoint, using: parameters)
        let apiKey = vercelConfig.apiKey
        
        targetConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                var forwardedRequest = "\(method) \(path) \(version)\r\n"
                
                let excludedHeaders: Set<String> = ["host", "content-length", "connection", "transfer-encoding", "authorization", "x-api-key"]
                var existingBetaHeader: String? = nil
                
                for (name, value) in headers {
                    let lower = name.lowercased()
                    if excludedHeaders.contains(lower) { continue }
                    if lower == "anthropic-beta" {
                        existingBetaHeader = value
                        continue
                    }
                    forwardedRequest += "\(name): \(value)\r\n"
                }
                
                // Vercel auth
                forwardedRequest += "x-api-key: \(apiKey)\r\n"
                forwardedRequest += "anthropic-version: \(Config.anthropicVersion)\r\n"
                forwardedRequest += "content-type: application/json\r\n"
                
                // Thinking beta header
                if thinkingEnabled {
                    var betaValue = BetaHeaders.interleavedThinking
                    if let existing = existingBetaHeader, !existing.contains(BetaHeaders.interleavedThinking) {
                        betaValue = "\(existing),\(BetaHeaders.interleavedThinking)"
                    }
                    forwardedRequest += "anthropic-beta: \(betaValue)\r\n"
                } else if let existing = existingBetaHeader {
                    forwardedRequest += "anthropic-beta: \(existing)\r\n"
                }
                
                forwardedRequest += "Host: \(Config.vercelGatewayHost)\r\n"
                forwardedRequest += "Connection: close\r\n"
                
                let contentLength = body.utf8.count
                forwardedRequest += "Content-Length: \(contentLength)\r\n"
                forwardedRequest += "\r\n"
                forwardedRequest += body
                
                if let requestData = forwardedRequest.data(using: .utf8) {
                    targetConnection.send(content: requestData, completion: .contentProcessed({ error in
                        if let error = error {
                            NSLog("[ThinkingProxy] Vercel send error: \(error)")
                            targetConnection.cancel()
                            originalConnection.cancel()
                        } else {
                            self.receiveResponse(from: targetConnection, originalConnection: originalConnection)
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Vercel connection failed: \(error)")
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway - Could not connect to Vercel AI Gateway")
                targetConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global(qos: .userInitiated))
    }
    
    private enum BetaHeaders {
        static let interleavedThinking = "interleaved-thinking-2025-05-14"
    }
    
    /**
     Forwards the request to CLIProxyAPI on port 8318 (pass-through for non-thinking requests)
     Records route health telemetry for tracked models based on upstream response status.
     */
    private func forwardRequest(method: String, path: String, version: String, headers: [(String, String)], body: String, thinkingEnabled: Bool = false, originalConnection: NWConnection, retryWithApiPrefix: Bool = false) {
        // Extract model for route health tracking before dispatching
        let routeHealthModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: body).flatMap {
            OpenAICompatTemporaryShim.routeIdentityForHealthTracking(forRequestModel: $0)
        }
        let routeHealthTelemetryStart = routeHealthModel != nil ? Date() : nil
        if let forwardRequestInterceptorForTesting,
           forwardRequestInterceptorForTesting(
            method,
            path,
            version,
            headers,
            body,
            thinkingEnabled,
            originalConnection,
            retryWithApiPrefix
           ) {
            return
        }

        // Create connection to CLIProxyAPI
        guard let port = NWEndpoint.Port(rawValue: targetPort) else {
            NSLog("[ThinkingProxy] Invalid target port: %d", targetPort)
            sendError(to: originalConnection, statusCode: 500, message: "Internal Server Error")
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(targetHost), port: port)
        let parameters = NWParameters.tcp
        let targetConnection = NWConnection(to: endpoint, using: parameters)
        
        targetConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Build the forwarded request
                var forwardedRequest = "\(method) \(path) \(version)\r\n"
                let excludedHeaders: Set<String> = ["content-length", "host", "transfer-encoding"]
                var existingBetaHeader: String? = nil
                
                for (name, value) in headers {
                    let lowercasedName = name.lowercased()
                    if excludedHeaders.contains(lowercasedName) {
                        continue
                    }
                    // Capture existing anthropic-beta header for merging
                    if lowercasedName == "anthropic-beta" {
                        existingBetaHeader = value
                        continue
                    }
                    forwardedRequest += "\(name): \(value)\r\n"
                }
                
                // Add/merge anthropic-beta header when thinking is enabled
                if thinkingEnabled {
                    var betaValue = BetaHeaders.interleavedThinking
                    if let existing = existingBetaHeader {
                        // Merge with existing header if not already present
                        if !existing.contains(BetaHeaders.interleavedThinking) {
                            betaValue = "\(existing),\(BetaHeaders.interleavedThinking)"
                        } else {
                            betaValue = existing
                        }
                    }
                    forwardedRequest += "anthropic-beta: \(betaValue)\r\n"
                    NSLog("[ThinkingProxy] Added interleaved thinking beta header")
                } else if let existing = existingBetaHeader {
                    // Pass through existing header when thinking not enabled
                    forwardedRequest += "anthropic-beta: \(existing)\r\n"
                }
                
                // Override Host header
                forwardedRequest += "Host: \(self.targetHost):\(self.targetPort)\r\n"
                // Always close connections - this proxy doesn't support keep-alive/pipelining
                forwardedRequest += "Connection: close\r\n"
                
                let contentLength = body.utf8.count
                forwardedRequest += "Content-Length: \(contentLength)\r\n"
                forwardedRequest += "\r\n"
                forwardedRequest += body
                
                // Send to CLIProxyAPI
                if let requestData = forwardedRequest.data(using: .utf8) {
                    targetConnection.send(content: requestData, completion: .contentProcessed({ error in
                        if let error = error {
                            NSLog("[ThinkingProxy] Send error: \(error)")
                            targetConnection.cancel()
                            originalConnection.cancel()
                        } else {
                            // Receive response from CLIProxyAPI (with 404 retry capability)
                            if retryWithApiPrefix {
                                self.receiveResponseWith404Retry(from: targetConnection, originalConnection: originalConnection,
                                                                 method: method, path: path, version: version,
                                                                 headers: headers, body: body)
                            } else {
                                self.receiveResponseWithRouteHealth(
                                    from: targetConnection,
                                    originalConnection: originalConnection,
                                    routeHealthModel: routeHealthModel,
                                    routeHealthStart: routeHealthTelemetryStart
                                )
                            }
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Target connection failed: \(error)")
                if let route = routeHealthModel {
                    let telemetryEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: Date(),
                        requestModel: route.canonicalModelID,
                        canonicalModelID: route.canonicalModelID,
                        transportOutcome: "send_error",
                        failureClass: "transport_error",
                        timeoutStage: .none,
                        upstreamHTTPStatus: nil,
                        retryCount: 0,
                        source: "live_request"
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: route.canonicalModelID,
                        telemetryEvent: telemetryEvent
                    )
                }
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
                targetConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global(qos: .userInitiated))
    }
    
    /**
     Receives response and retries with /api/ prefix on 404
     */
    private func receiveResponseWith404Retry(from targetConnection: NWConnection, originalConnection: NWConnection, 
                                             method: String, path: String, version: String, 
                                             headers: [(String, String)], body: String) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Check if response is a 404
                if let responseString = String(data: data, encoding: .utf8) {
                    // Log first 200 chars to debug
                    let preview = String(responseString.prefix(200))
                    NSLog("[ThinkingProxy] Response preview for \(path): \(preview)")
                    
                    // Check for 404 in status line OR in body
                    let is404 = responseString.contains("HTTP/1.1 404") || 
                               responseString.contains("HTTP/1.0 404") ||
                               responseString.contains("404 page not found")
                    
                    if is404 {
                        // Check if path doesn't already start with /api/
                        if !path.starts(with: "/api/") && !path.starts(with: "/v1/") {
                            NSLog("[ThinkingProxy] Got 404 for \(path), retrying with /api prefix")
                            targetConnection.cancel()
                            
                            // Retry with /api/ prefix
                            let newPath = "/api" + path
                            self.forwardRequest(method: method, path: newPath, version: version, headers: headers, 
                                              body: body, originalConnection: originalConnection, retryWithApiPrefix: false)
                            return
                        }
                    }
                }
                
                // Not a 404 or already has /api/, forward response as-is
                originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                    if let sendError = sendError {
                        NSLog("[ThinkingProxy] Send error: \(sendError)")
                    }
                    
                    if isComplete {
                        targetConnection.cancel()
                        originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                            originalConnection.cancel()
                        }))
                    } else {
                        // Continue streaming
                        self.streamNextChunk(from: targetConnection, to: originalConnection)
                    }
                }))
            } else if isComplete {
                targetConnection.cancel()
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }
    
    /**
     Receives response from CLIProxyAPI
     Starts the streaming loop for response data
     */
    /**
     Receives response with route health telemetry recording for the first chunk.
     Parses the HTTP status line from the first response chunk to determine success/failure,
     records route health, then delegates to the standard streaming loop.
     */
    private func receiveResponseWithRouteHealth(
        from targetConnection: NWConnection,
        originalConnection: NWConnection,
        routeHealthModel: OpenAICompatTemporaryShim.RouteIdentity?,
        routeHealthStart: Date?
    ) {
        guard let route = routeHealthModel, let start = routeHealthStart else {
            // No route to track — use standard streaming
            streamNextChunk(from: targetConnection, to: originalConnection)
            return
        }

        var routeHealthRecorded = false

        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                NSLog("[ThinkingProxy] Receive response error: \(error)")
                if !routeHealthRecorded {
                    let telemetryEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: Date(),
                        requestModel: route.canonicalModelID,
                        canonicalModelID: route.canonicalModelID,
                        transportOutcome: "send_error",
                        failureClass: "transport_error",
                        timeoutStage: .none,
                        upstreamHTTPStatus: nil,
                        retryCount: 0,
                        source: "live_request",
                        totalLatencyMilliseconds: Int(Date().timeIntervalSince(start) * 1000)
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: route.canonicalModelID,
                        telemetryEvent: telemetryEvent
                    )
                    routeHealthRecorded = true
                }
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }

            if let data = data, !data.isEmpty {
                // Parse HTTP status from first chunk for route health
                if !routeHealthRecorded, let responseString = String(data: data, encoding: .utf8) {
                    let statusCode = Self.parseHTTPStatus(from: responseString)
                    let latency = Int(Date().timeIntervalSince(start) * 1000)
                    if let statusCode {
                        if statusCode >= 200 && statusCode < 400 {
                            OpenAICompatTemporaryShim.recordRouteSuccess(
                                forRequestModel: route.canonicalModelID,
                                telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                                    timestamp: Date(),
                                    requestModel: route.canonicalModelID,
                                    canonicalModelID: route.canonicalModelID,
                                    transportOutcome: "send_response",
                                    failureClass: nil,
                                    timeoutStage: .none,
                                    upstreamHTTPStatus: statusCode,
                                    retryCount: 0,
                                    source: "live_request",
                                    firstByteLatencyMilliseconds: latency,
                                    totalLatencyMilliseconds: latency
                                )
                            )
                        } else {
                            let failureClass = statusCode == 429 ? "classified_429" :
                                               statusCode >= 500 ? "classified_\(statusCode)" :
                                               "classified_\(statusCode)"
                            let telemetryEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                                timestamp: Date(),
                                requestModel: route.canonicalModelID,
                                canonicalModelID: route.canonicalModelID,
                                transportOutcome: "send_error",
                                failureClass: failureClass,
                                timeoutStage: .none,
                                upstreamHTTPStatus: statusCode,
                                retryCount: 0,
                                source: "live_request",
                                firstByteLatencyMilliseconds: latency,
                                totalLatencyMilliseconds: latency
                            )
                            OpenAICompatTemporaryShim.recordRouteFailure(
                                forRequestModel: route.canonicalModelID,
                                telemetryEvent: telemetryEvent
                            )
                        }
                        routeHealthRecorded = true
                    }
                }

                // Forward response chunk to original client
                originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                    if let sendError = sendError {
                        NSLog("[ThinkingProxy] Send response error: \(sendError)")
                    }

                    if isComplete {
                        targetConnection.cancel()
                        originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                            originalConnection.cancel()
                        }))
                    } else {
                        // Continue with standard streaming (no more health tracking needed)
                        self.streamNextChunk(from: targetConnection, to: originalConnection)
                    }
                }))
            } else if isComplete {
                targetConnection.cancel()
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }

    private static func parseHTTPStatus(from responseHead: String) -> Int? {
        // HTTP/1.1 200 OK → extract 200
        guard let firstSpace = responseHead.firstIndex(of: " "),
              let secondSpace = responseHead[firstSpace...].dropFirst().firstIndex(of: " ") else {
            return nil
        }
        let statusStart = responseHead.index(after: firstSpace)
        let statusString = String(responseHead[statusStart..<secondSpace])
        return Int(statusString.trimmingCharacters(in: .whitespaces))
    }

    private func receiveResponse(from targetConnection: NWConnection, originalConnection: NWConnection) {
        // Start the streaming loop
        streamNextChunk(from: targetConnection, to: originalConnection)
    }
    
    /**
     Streams response chunks iteratively (uses async scheduling instead of recursion to avoid stack buildup)
     */
    private func streamNextChunk(from targetConnection: NWConnection, to originalConnection: NWConnection) {
        targetConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                NSLog("[ThinkingProxy] Receive response error: \(error)")
                targetConnection.cancel()
                originalConnection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty {
                // Forward response chunk to original client
                originalConnection.send(content: data, completion: .contentProcessed({ sendError in
                    if let sendError = sendError {
                        NSLog("[ThinkingProxy] Send response error: \(sendError)")
                    }
                    
                    if isComplete {
                        targetConnection.cancel()
                        // Always close client connection - no keep-alive/pipelining support
                        originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                            originalConnection.cancel()
                        }))
                    } else {
                        // Schedule next iteration of the streaming loop
                        self.streamNextChunk(from: targetConnection, to: originalConnection)
                    }
                }))
            } else if isComplete {
                targetConnection.cancel()
                // Always close client connection - no keep-alive/pipelining support
                originalConnection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
                    originalConnection.cancel()
                }))
            }
        }
    }
    
    /**
     Sends an error response to the client
     */
    private func sendError(
        to connection: NWConnection,
        statusCode: Int,
        message: String,
        overridingHeaders: [String: String] = [:]
    ) {
        if let deliveredErrorForTesting {
            deliveredErrorForTesting(statusCode, message)
            connection.cancel()
            return
        }
        // Build response with proper CRLF line endings and correct byte count
        guard let bodyData = message.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        var headers = "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)\r\n" +
            "Content-Type: text/plain\r\n"
        var effectiveHeaders = proxyMetadataHeaders()
        for (name, value) in overridingHeaders {
            effectiveHeaders[name] = value
        }
        for (name, value) in effectiveHeaders {
            headers += "\(name): \(value)\r\n"
        }
        headers += "Content-Length: \(bodyData.count)\r\n" +
            "Connection: close\r\n" +
            "\r\n"
        
        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        var responseData = Data()
        responseData.append(headerData)
        responseData.append(bodyData)
        
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendRedirect(to connection: NWConnection, location: String) {
        let headers = "HTTP/1.1 302 Found\r\n" +
                     "Location: \(location)\r\n" +
                     "Content-Length: 0\r\n" +
                     "Connection: close\r\n" +
                     "\r\n"

        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendHTTPResponse(
        to connection: NWConnection,
        statusCode: Int,
        headers: [AnyHashable: Any],
        body: Data,
        overridingHeaders: [String: String] = [:]
    ) {
        var effectiveOverridingHeaders = proxyMetadataHeaders()
        for (name, value) in overridingHeaders {
            effectiveOverridingHeaders[name] = value
        }
        if let deliveredHTTPResponseForTesting {
            var deliveredHeaders = headers
            for (name, value) in effectiveOverridingHeaders {
                deliveredHeaders[name] = value
            }
            deliveredHTTPResponseForTesting(statusCode, deliveredHeaders, body)
            connection.cancel()
            return
        }
        var response = "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)\r\n"
        var excludedHeaders: Set<String> = ["content-length", "connection", "transfer-encoding"]
        excludedHeaders.formUnion(effectiveOverridingHeaders.keys.map { $0.lowercased() })

        for (rawName, rawValue) in headers {
            guard let name = rawName as? String,
                  !excludedHeaders.contains(name.lowercased()) else {
                continue
            }
            response += "\(name): \(String(describing: rawValue))\r\n"
        }

        for (name, value) in effectiveOverridingHeaders {
            response += "\(name): \(value)\r\n"
        }

        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"

        guard let headerData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }

        var responseData = Data()
        responseData.append(headerData)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func startStreamingHTTPResponse(
        to connection: NWConnection,
        statusCode: Int,
        headers: [AnyHashable: Any],
        overridingHeaders: [String: String] = [:]
    ) {
        var effectiveOverridingHeaders = proxyMetadataHeaders()
        for (name, value) in overridingHeaders {
            effectiveOverridingHeaders[name] = value
        }
        if let deliveredStreamingResponseStartForTesting {
            var deliveredHeaders = headers
            for (name, value) in effectiveOverridingHeaders {
                deliveredHeaders[name] = value
            }
            deliveredStreamingResponseStartForTesting(statusCode, deliveredHeaders)
            return
        }

        var response = "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)\r\n"
        var excludedHeaders: Set<String> = ["content-length", "connection", "transfer-encoding"]
        excludedHeaders.formUnion(effectiveOverridingHeaders.keys.map { $0.lowercased() })

        for (rawName, rawValue) in headers {
            guard let name = rawName as? String,
                  !excludedHeaders.contains(name.lowercased()) else {
                continue
            }
            response += "\(name): \(String(describing: rawValue))\r\n"
        }

        for (name, value) in effectiveOverridingHeaders {
            response += "\(name): \(value)\r\n"
        }

        response += "Connection: close\r\n"
        response += "\r\n"

        guard let headerData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed({ error in
            if error != nil {
                connection.cancel()
            }
        }))
    }

    private func sendStreamingHTTPChunk(
        to connection: NWConnection,
        chunk: Data
    ) {
        guard !chunk.isEmpty else { return }
        if let deliveredStreamingResponseChunkForTesting {
            deliveredStreamingResponseChunkForTesting(chunk)
            return
        }
        connection.send(content: chunk, completion: .contentProcessed({ error in
            if error != nil {
                connection.cancel()
            }
        }))
    }

    private func finishStreamingHTTPResponse(to connection: NWConnection) {
        if let deliveredStreamingResponseFinishForTesting {
            deliveredStreamingResponseFinishForTesting()
            connection.cancel()
            return
        }
        connection.send(content: nil, isComplete: true, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func sendHealthResponse(to connection: NWConnection) {
        let backendReachable = isBackendReachable(timeout: Config.healthcheckTimeout)
        let provenance = runtimeProvenance()
        var payload: [String: Any] = [
            "status": backendReachable ? "ok" : "degraded",
            "frontend": [
                "port": Int(proxyPort)
            ],
            "backend": [
                "host": targetHost,
                "port": Int(targetPort),
                "reachable": backendReachable
            ],
            "provenance": provenanceDictionary(from: provenance)
        ]

        if let factoryWorkerContract = ThinkingProxy.factoryWorkerContract() {
            payload["factory_worker"] = factoryWorkerContractDictionary(
                from: factoryWorkerContract,
                backendReachable: backendReachable
            )
        }

        // Config drift: compare Factory's effective route model against proxy's authoritative worker candidates
        if let factoryWorkerContract = ThinkingProxy.factoryWorkerContract(),
           let workerCandidates = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "worker")?.candidates {
            let factoryRoute = factoryWorkerContract.authoritativeRouteModel
            let routeIsWorkerAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: factoryRoute) != nil
            let inPool = routeIsWorkerAlias || workerCandidates.contains(factoryRoute)
            let severity: String
            let warning: String?
            if inPool {
                severity = "none"
                warning = nil
            } else {
                severity = "critical"
                warning = "Factory route model '\(factoryRoute)' is not in proxy worker pool. Direct requests will bypass smart failover."
            }
            var drift: [String: Any] = [
                "factory_route_model": factoryRoute,
                "proxy_worker_candidates": workerCandidates,
                "route_in_pool": inPool,
                "severity": severity
            ]
            if factoryWorkerContract.routeModel != factoryRoute {
                drift["configured_factory_route_model"] = factoryWorkerContract.routeModel
            }
            if let warning = warning {
                drift["warning"] = warning
            }
            payload["config_drift"] = drift
        }
        if let factoryRoleContracts = ThinkingProxy.factoryRoleContracts() {
            payload["factory_roles"] = factoryRoleContractsDictionary(
                from: factoryRoleContracts,
                backendReachable: backendReachable
            )
        }

        let routeHealthSnapshot = OpenAICompatTemporaryShim.routeHealthSnapshotByRequestModel()
        if !routeHealthSnapshot.isEmpty {
            let routes = routeHealthSnapshot.keys.sorted().reduce(into: [String: [String: Any]]()) { result, requestModel in
                guard let state = routeHealthSnapshot[requestModel] else { return }
                var routePayload: [String: Any] = [
                    "status": state.status.rawValue,
                    "failure_score": OpenAICompatTemporaryShim.jsonNumberPreservingIntegers(state.failureScore),
                    "recovery_successes": state.recoverySuccesses
                ]
                if let lastSuccessAt = state.lastSuccessAt {
                    routePayload["last_success_at"] = ISO8601DateFormatter().string(from: lastSuccessAt)
                }
                if let lastLiveSuccessAt = state.lastLiveSuccessAt {
                    routePayload["last_live_success_at"] = ISO8601DateFormatter().string(from: lastLiveSuccessAt)
                }
                if let lastSuccessRequestID = state.lastSuccessRequestID {
                    routePayload["last_success_request_id"] = lastSuccessRequestID
                }
                if let lastFailureAt = state.lastFailureAt {
                    routePayload["last_failure_at"] = ISO8601DateFormatter().string(from: lastFailureAt)
                }
                if let lastFailureClass = state.lastFailureClass {
                    routePayload["last_failure_class"] = lastFailureClass
                }
                if let lastEvent = state.lastTelemetryEvent {
                    var lastEventPayload: [String: Any] = [
                        "timestamp": ISO8601DateFormatter().string(from: lastEvent.timestamp),
                        "request_model": lastEvent.requestModel,
                        "transport_outcome": lastEvent.transportOutcome
                    ]
                    if let failureClass = lastEvent.failureClass {
                        lastEventPayload["failure_class"] = failureClass
                    }
                    if let upstreamHTTPStatus = lastEvent.upstreamHTTPStatus {
                        lastEventPayload["upstream_http_status"] = upstreamHTTPStatus
                    }
                    if let proxyRequestID = lastEvent.proxyRequestID {
                        lastEventPayload["proxy_request_id"] = proxyRequestID
                    }
                    if let callerRequestID = lastEvent.callerRequestID {
                        lastEventPayload["caller_request_id"] = callerRequestID
                    }
                    if let callerSessionID = lastEvent.callerSessionID {
                        lastEventPayload["caller_session_id"] = callerSessionID
                    }
                    if let requestShape = lastEvent.requestShape {
                        lastEventPayload["request_shape"] = requestShape
                    }
                    if let negotiatedApplicationProtocol = lastEvent.negotiatedApplicationProtocol {
                        lastEventPayload["negotiated_application_protocol"] = negotiatedApplicationProtocol
                    }
                    routePayload["last_event"] = lastEventPayload
                }
                if let route = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) {
                    routePayload["provider"] = route.providerID
                    routePayload["canonical_model_id"] = route.canonicalModelID
                    routePayload["route_health_key"] = route.routeHealthKey
                    routePayload["concurrency_limit"] = OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: route.routeHealthKey)
                    routePayload["inflight"] = OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: route.routeHealthKey)
                    if route.providerID == "nvidia" {
                        let transportPolicy = effectiveNVIDIADirectTransportPolicy()
                        let recentLiveSuccess = OpenAICompatTemporaryShim.hasRecentLiveInferenceSuccess(forRequestModel: requestModel)
                        var streamDiagnostics: [String: Any] = [
                            "transport_protocol_preference": transportPolicy.protocolPreference.rawValue,
                            "inter_chunk_read_timeout_seconds": Int(transportPolicy.interChunkReadTimeoutSeconds),
                            "downstream_keepalives_enabled": transportPolicy.sinkPolicy.emitsDownstreamKeepalives,
                            "downstream_keepalive_interval_seconds": Int(transportPolicy.sinkPolicy.keepaliveIntervalSeconds),
                            "chunk_gap_timeout_runtime_owner": "nvidia_direct_live_stream",
                            "downstream_keepalive_runtime_owner": "nvidia_direct_live_stream",
                            "protocol_observation_runtime_owner": Self.nvidiaDirectTransportRuntimeOwner,
                            "protocol_guarantee_runtime_owner": Self.nvidiaDirectTransportRuntimeOwner
                        ]
                        if let negotiatedApplicationProtocol = state.lastTelemetryEvent?.negotiatedApplicationProtocol {
                            streamDiagnostics["last_negotiated_application_protocol"] = negotiatedApplicationProtocol
                        }
                        routePayload["nvidia_stream_diagnostics"] = streamDiagnostics
                        var livenessPayload: [String: Any] = [
                            "trusted": OpenAICompatTemporaryShim.hasRecentNVIDIAInferenceEvidence(forRequestModel: requestModel),
                            "recent_live_success": recentLiveSuccess,
                            "recent_probe_success": OpenAICompatTemporaryShim.hasRecentNVIDIAInferenceProbeSuccess(forRequestModel: requestModel),
                            "freshness_window_seconds": Int(OpenAICompatTemporaryShim.nvidiaInferenceProbeFreshnessWindow)
                        ]
                        if let lastLiveSuccessAt = state.lastLiveSuccessAt {
                            livenessPayload["last_live_success_at"] = ISO8601DateFormatter().string(from: lastLiveSuccessAt)
                        }
                        if let probe = state.nvidiaInferenceProbe {
                            var probePayload: [String: Any] = [
                                "last_probe_at": ISO8601DateFormatter().string(from: probe.lastProbeAt),
                                "last_status": probe.lastStatus.rawValue,
                                "last_timeout_stage": probe.lastTimeoutStage.rawValue,
                                "last_transport_outcome": probe.lastTransportOutcome
                            ]
                            if let lastSuccessAt = probe.lastSuccessAt {
                                probePayload["last_success_at"] = ISO8601DateFormatter().string(from: lastSuccessAt)
                            }
                            if let lastFailureAt = probe.lastFailureAt {
                                probePayload["last_failure_at"] = ISO8601DateFormatter().string(from: lastFailureAt)
                            }
                            if let lastFailureClass = probe.lastFailureClass {
                                probePayload["last_failure_class"] = lastFailureClass
                            }
                            if let lastUpstreamHTTPStatus = probe.lastUpstreamHTTPStatus {
                                probePayload["last_upstream_http_status"] = lastUpstreamHTTPStatus
                            }
                            if let lastFirstByteLatencyMilliseconds = probe.lastFirstByteLatencyMilliseconds {
                                probePayload["last_first_byte_latency_ms"] = lastFirstByteLatencyMilliseconds
                            }
                            if let lastTotalLatencyMilliseconds = probe.lastTotalLatencyMilliseconds {
                                probePayload["last_total_latency_ms"] = lastTotalLatencyMilliseconds
                            }
                            livenessPayload["probe"] = probePayload
                        }
                        routePayload["nvidia_inference_liveness"] = livenessPayload
                    }
                }
                if let cooldownUntil = OpenAICompatTemporaryShim.routeCooldownUntil(forRequestModel: requestModel) {
                    routePayload["cooldown_until"] = ISO8601DateFormatter().string(from: cooldownUntil)
                }
                if let retryHint = OpenAICompatTemporaryShim.nextRetryHint(forRequestModel: requestModel) {
                    routePayload["retry_after_seconds"] = retryHint.seconds
                    routePayload["retry_hint_reason"] = retryHint.reason
                }
                if let latencyDiagnostics = OpenAICompatTemporaryShim.latencyDiagnostics(forRequestModel: requestModel) {
                    routePayload["latency_pressure_status"] = latencyDiagnostics.pressureStatus
                    if let averageFirstByte = latencyDiagnostics.averageFirstByteLatencyMilliseconds {
                        routePayload["recent_average_first_byte_latency_ms"] = averageFirstByte
                    }
                    if let p95FirstByte = latencyDiagnostics.p95FirstByteLatencyMilliseconds {
                        routePayload["recent_p95_first_byte_latency_ms"] = p95FirstByte
                    }
                    if let averageTotal = latencyDiagnostics.averageTotalLatencyMilliseconds {
                        routePayload["recent_average_total_latency_ms"] = averageTotal
                    }
                    if let p95Total = latencyDiagnostics.p95TotalLatencyMilliseconds {
                        routePayload["recent_p95_total_latency_ms"] = p95Total
                    }
                    if let slowFirstByte = latencyDiagnostics.slowFirstByteThresholdMilliseconds {
                        routePayload["slow_first_byte_threshold_ms"] = slowFirstByte
                    }
                    if let slowTotal = latencyDiagnostics.slowTotalThresholdMilliseconds {
                        routePayload["slow_total_threshold_ms"] = slowTotal
                    }
                }
                result[requestModel] = routePayload
            }
            payload["route_health"] = [
                "routes": routes,
                "quarantined_models": OpenAICompatTemporaryShim.quarantinedRequestModels(),
                "quarantined_canonical_models": OpenAICompatTemporaryShim.quarantinedNVIDIAHostedRequestModels()
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            sendError(to: connection, statusCode: 500, message: "Internal Server Error")
            return
        }

        sendHTTPResponse(
            to: connection,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: body
        )
    }

    private func proxyMetadataHeaders() -> [String: String] {
        let provenance = runtimeProvenance()
        var headers: [String: String] = [
            "X-VibeProxy-App-Version": provenance.appVersion,
            "X-VibeProxy-App-Build": provenance.appBuild
        ]
        if let backendBinaryFingerprint = provenance.backendBinaryFingerprint {
            headers["X-VibeProxy-Backend-Fingerprint"] = backendBinaryFingerprint
        }
        if let mergedConfigFingerprint = provenance.mergedConfigFingerprint {
            headers["X-VibeProxy-Config-Fingerprint"] = mergedConfigFingerprint
        }
        return headers
    }

    private func requestShapeDescriptor(method: String, path: String, body: String) -> String {
        guard let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return "\(method):\(path):opaque"
        }

        let model = (json["model"] as? String) ?? "unknown"
        let stream = (json["stream"] as? Bool) == true ? "stream" : "buffered"
        let toolsCount = (json["tools"] as? [Any])?.count ?? 0
        let strictToolChoice = OpenAICompatTemporaryShim.hasStrictToolChoice(in: json) ? "strict_tool_choice" : "tool_choice_auto"
        let typedContent = OpenAICompatTemporaryShim.containsUnsupportedTypedMessageContent(in: json) ? "typed_content" : "string_content"
        let surface = OpenAICompatTemporaryShim.isResponsesPath(path) ? "responses" : (OpenAICompatTemporaryShim.isChatCompletionsPath(path) ? "chat" : "other")
        return "\(method):\(surface):\(model):\(stream):tools=\(toolsCount):\(strictToolChoice):\(typedContent)"
    }

    private func requestTraceContext(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String
    ) -> RequestTraceContext {
        RequestTraceContext(
            proxyRequestID: UUID().uuidString,
            callerRequestID: requestHeaderValue("X-Request-ID", in: headers)
                ?? requestHeaderValue("X-Client-Request-ID", in: headers),
            callerSessionID: requestHeaderValue("X-Session-ID", in: headers)
                ?? requestHeaderValue("X-Factory-Session-ID", in: headers)
                ?? requestHeaderValue("X-Droid-Session-ID", in: headers),
            requestShape: requestShapeDescriptor(method: method, path: path, body: body)
        )
    }

    private func runtimeProvenance() -> RuntimeProvenance {
        let infoDictionary = Bundle.main.infoDictionary
        let appVersion = infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let appBuild = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let backendBinaryPath = Bundle.main.resourcePath.map {
            ($0 as NSString).appendingPathComponent("cli-proxy-api-plus")
        }
        let mergedConfigPath = OpenAICompatTemporaryShim.mergedConfigPath()

        return RuntimeProvenance(
            appVersion: appVersion,
            appBuild: appBuild,
            backendBinaryPath: backendBinaryPath,
            backendBinaryFingerprint: ThinkingProxy.fileFingerprint(at: backendBinaryPath),
            mergedConfigPath: mergedConfigPath,
            mergedConfigFingerprint: ThinkingProxy.fileFingerprint(at: mergedConfigPath)
        )
    }

    private func provenanceDictionary(from provenance: RuntimeProvenance) -> [String: Any] {
        var dict: [String: Any] = [
            "app_version": provenance.appVersion,
            "app_build": provenance.appBuild
        ]
        if let backendBinaryPath = provenance.backendBinaryPath {
            dict["backend_binary_path"] = backendBinaryPath
        }
        if let backendBinaryFingerprint = provenance.backendBinaryFingerprint {
            dict["backend_binary_fingerprint"] = backendBinaryFingerprint
        }
        if let mergedConfigPath = provenance.mergedConfigPath {
            dict["merged_config_path"] = mergedConfigPath
        }
        if let mergedConfigFingerprint = provenance.mergedConfigFingerprint {
            dict["merged_config_fingerprint"] = mergedConfigFingerprint
        }
        return dict
    }

    private func factoryWorkerContractDictionary(
        from contract: FactoryWorkerContract,
        backendReachable: Bool
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "worker_model_id": contract.workerModelID,
            "route_model": contract.routeModel,
            "route_provider": contract.routeProvider,
            "request_surface": contract.requestSurface,
            "authoritative_settings_path": contract.authoritativeSettingsPath,
            "settings_available": contract.settingsAvailable,
            "snapshot_sync_ok": contract.snapshotDriftPaths.isEmpty,
            "snapshot_drift_count": contract.snapshotDriftPaths.count,
            "snapshot_blocking_sync_ok": contract.blockingSnapshotDriftPaths.isEmpty,
            "snapshot_blocking_drift_count": contract.blockingSnapshotDriftPaths.count,
            "ready": backendReachable && contract.ready
        ]
        if let effectiveRouteModel = contract.effectiveRouteModel {
            dict["effective_route_model"] = effectiveRouteModel
        }
        if let effectiveRouteModelSource = contract.effectiveRouteModelSource {
            dict["effective_route_model_source"] = effectiveRouteModelSource.rawValue
        }
        if contract.authoritativeRouteModel != contract.routeModel {
            dict["authoritative_route_model"] = contract.authoritativeRouteModel
        }
        if let validationWorkerModelID = contract.validationWorkerModelID {
            dict["validation_worker_model_id"] = validationWorkerModelID
        }
        if let workerReasoningEffort = contract.workerReasoningEffort {
            dict["worker_reasoning_effort"] = workerReasoningEffort
        }
        if let validationWorkerReasoningEffort = contract.validationWorkerReasoningEffort {
            dict["validation_worker_reasoning_effort"] = validationWorkerReasoningEffort
        }
        if let displayName = contract.displayName {
            dict["display_name"] = displayName
        }
        if let baseURL = contract.baseURL {
            dict["base_url"] = baseURL
        }
        if let routeHealthStatus = contract.routeHealthStatus {
            dict["route_health_status"] = routeHealthStatus
        }
        if let effectiveRouteProvider = contract.effectiveRouteProvider {
            dict["effective_route_provider"] = effectiveRouteProvider
        }
        if !contract.requestShapeContracts.isEmpty {
            dict["request_shapes"] = Dictionary(
                uniqueKeysWithValues: contract.requestShapeContracts.map { shapeContract in
                    var shapeDict: [String: Any] = [
                        "candidate_models": shapeContract.candidateModels,
                        "dispatchable_candidate_models": shapeContract.dispatchableCandidateModels,
                        "effective_route_model": shapeContract.effectiveRouteModel,
                        "effective_route_model_source": shapeContract.effectiveRouteModelSource.rawValue,
                        "ready": backendReachable && shapeContract.ready
                    ]
                    if let dispatchableRouteModel = shapeContract.dispatchableRouteModel {
                        shapeDict["dispatchable_route_model"] = dispatchableRouteModel
                    }
                    if let effectiveRouteProvider = shapeContract.effectiveRouteProvider {
                        shapeDict["effective_route_provider"] = effectiveRouteProvider
                    }
                    if let routeHealthStatus = shapeContract.routeHealthStatus {
                        shapeDict["route_health_status"] = routeHealthStatus
                    }
                    return (shapeContract.id, shapeDict)
                }
            )
            dict["dispatchable_request_shapes"] = contract.requestShapeContracts.compactMap {
                $0.ready ? $0.id : nil
            }.sorted()
        }
        if let recentLiveRouteModel = contract.recentLiveRouteModel {
            dict["recent_live_route_model"] = recentLiveRouteModel
        }
        if let recentDispatchedRouteModel = contract.recentDispatchedRouteModel {
            dict["recent_dispatched_route_model"] = recentDispatchedRouteModel
        }
        if let recentDispatchedRouteProvider = contract.recentDispatchedRouteProvider {
            dict["recent_dispatched_route_provider"] = recentDispatchedRouteProvider
        }
        if let recentDispatchedRequestShape = contract.recentDispatchedRequestShape {
            dict["recent_dispatched_request_shape"] = recentDispatchedRequestShape
        }
        if let recentDispatchedRouteAt = contract.recentDispatchedRouteAt {
            dict["recent_dispatched_route_at"] = ISO8601DateFormatter().string(from: recentDispatchedRouteAt)
        }
        if let recentDispatchedCallerRequestID = contract.recentDispatchedCallerRequestID {
            dict["recent_dispatched_caller_request_id"] = recentDispatchedCallerRequestID
        }
        if let recentDispatchedCallerSessionID = contract.recentDispatchedCallerSessionID {
            dict["recent_dispatched_caller_session_id"] = recentDispatchedCallerSessionID
        }
        if let recentLiveRouteProvider = contract.recentLiveRouteProvider {
            dict["recent_live_route_provider"] = recentLiveRouteProvider
        }
        if let recentLiveRequestShape = contract.recentLiveRequestShape {
            dict["recent_live_request_shape"] = recentLiveRequestShape
        }
        if let recentLiveRouteAt = contract.recentLiveRouteAt {
            dict["recent_live_route_at"] = ISO8601DateFormatter().string(from: recentLiveRouteAt)
        }
        if let recentLiveCallerRequestID = contract.recentLiveCallerRequestID {
            dict["recent_live_caller_request_id"] = recentLiveCallerRequestID
        }
        if let recentLiveCallerSessionID = contract.recentLiveCallerSessionID {
            dict["recent_live_caller_session_id"] = recentLiveCallerSessionID
        }
        if let effectiveRouteModel = contract.effectiveRouteModel,
           let latencyDiagnostics = OpenAICompatTemporaryShim.latencyDiagnostics(forRequestModel: effectiveRouteModel) {
            dict["effective_route_latency_pressure_status"] = latencyDiagnostics.pressureStatus
            if let p95Total = latencyDiagnostics.p95TotalLatencyMilliseconds {
                dict["effective_route_recent_p95_total_latency_ms"] = p95Total
            }
        }
        if !contract.acceptedRequestModelIDs.isEmpty {
            dict["accepted_request_model_ids"] = contract.acceptedRequestModelIDs
        }
        if !contract.rescuedRequestModelIDs.isEmpty {
            dict["rescued_request_model_ids"] = contract.rescuedRequestModelIDs
        }
        if !contract.snapshotDriftPaths.isEmpty {
            dict["snapshot_drift_paths"] = contract.snapshotDriftPaths
        }
        if !contract.blockingSnapshotDriftPaths.isEmpty {
            dict["snapshot_blocking_drift_paths"] = contract.blockingSnapshotDriftPaths
        }
        return dict
    }

    private func factoryRoleContractsDictionary(
        from contracts: (orchestration: FactoryRoleContract?, verification: FactoryRoleContract?),
        backendReachable: Bool
    ) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let orchestration = contracts.orchestration {
            dict["orchestration"] = factoryRoleContractDictionary(
                from: orchestration,
                backendReachable: backendReachable
            )
        }
        if let verification = contracts.verification {
            dict["verification"] = factoryRoleContractDictionary(
                from: verification,
                backendReachable: backendReachable
            )
        }
        return dict
    }

    private func factoryRoleContractDictionary(
        from contract: FactoryRoleContract,
        backendReachable: Bool
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "model_id": contract.modelID,
            "route_model": contract.routeModel,
            "route_provider": contract.routeProvider,
            "request_surface": contract.requestSurface,
            "effective_route_model": contract.effectiveRouteModel,
            "effective_route_model_source": contract.effectiveRouteModelSource.rawValue,
            "ready": backendReachable && contract.ready
        ]
        if let reasoningEffort = contract.reasoningEffort {
            dict["reasoning_effort"] = reasoningEffort
        }
        if let effectiveRouteProvider = contract.effectiveRouteProvider {
            dict["effective_route_provider"] = effectiveRouteProvider
        }
        if let latencyDiagnostics = OpenAICompatTemporaryShim.latencyDiagnostics(forRequestModel: contract.effectiveRouteModel) {
            dict["effective_route_latency_pressure_status"] = latencyDiagnostics.pressureStatus
            if let p95Total = latencyDiagnostics.p95TotalLatencyMilliseconds {
                dict["effective_route_recent_p95_total_latency_ms"] = p95Total
            }
        }
        if let displayName = contract.displayName {
            dict["display_name"] = displayName
        }
        if let baseURL = contract.baseURL {
            dict["base_url"] = baseURL
        }
        if let routeHealthStatus = contract.routeHealthStatus {
            dict["route_health_status"] = routeHealthStatus
        }
        return dict
    }

    private static func factoryWorkerRequestSurface(forProvider provider: String) -> String {
        switch provider {
        case "generic-chat-completion-api":
            return "chat_completions"
        case "openai", "xai":
            return "responses"
        case "anthropic":
            return "messages"
        default:
            return "unknown"
        }
    }

    private static func authoritativeFactoryWorkerRouteModel(
        workerModelID: String,
        configuredRouteModel: String,
        routeProvider: String
    ) -> String {
        guard routeProvider == "generic-chat-completion-api" else {
            return configuredRouteModel
        }
        if OpenAICompatTemporaryShim.isCodeOwnedFactoryWorkerIncomingModelID(workerModelID) {
            return OpenAICompatTemporaryShim.publicWorkerSmartRouterAlias()
        }
        return configuredRouteModel
    }

    private static func recentSmartAliasWinnerForFactoryWorker(
        workerModelID: String,
        routeModel: String
    ) -> OpenAICompatTemporaryShim.RecentSmartAliasWinner? {
        if let winner = OpenAICompatTemporaryShim.recentSmartAliasWinner(forRequestedAlias: workerModelID) {
            return winner
        }
        guard routeModel != workerModelID else { return nil }
        return OpenAICompatTemporaryShim.recentSmartAliasWinner(forRequestedAlias: routeModel)
    }

    private static func recentSmartAliasDispatchForFactoryWorker(
        workerModelID: String,
        routeModel: String
    ) -> OpenAICompatTemporaryShim.RecentSmartAliasDispatch? {
        if let dispatch = OpenAICompatTemporaryShim.recentSmartAliasDispatch(forRequestedAlias: workerModelID) {
            return dispatch
        }
        guard routeModel != workerModelID else { return nil }
        return OpenAICompatTemporaryShim.recentSmartAliasDispatch(forRequestedAlias: routeModel)
    }

    private static func firstAvailableFactoryWorkerCandidateModel(from candidateModels: [String]) -> String? {
        if let availableCandidate = candidateModels.first(where: {
            OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: $0) != .open
        }) {
            return availableCandidate
        }
        return candidateModels.first
    }

    private static func effectiveFactoryWorkerCandidateModels(
        routeModel: String,
        requestSurface: String,
        requestShape: FactoryWorkerHealthRequestShape
    ) -> [String] {
        guard requestSurface == "chat_completions",
              let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) else {
            return [routeModel]
        }

        let syntheticWorkerRequest = syntheticFactoryWorkerHealthRequest(
            routeModel: routeModel,
            requestShape: requestShape
        )

        return OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
            forPublicAlias: routeModel,
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: syntheticWorkerRequest,
            smartAlias: smartAlias
        )
    }

    private static func dispatchableFactoryWorkerCandidateModel(
        routeModel: String,
        requestSurface: String,
        requestShape: FactoryWorkerHealthRequestShape
    ) -> String? {
        guard requestSurface == "chat_completions",
              let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) else {
            return routeModel
        }

        let syntheticWorkerRequest = syntheticFactoryWorkerHealthRequest(
            routeModel: routeModel,
            requestShape: requestShape
        )

        let orderedCandidateModels = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
            forPublicAlias: routeModel,
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: syntheticWorkerRequest,
            smartAlias: smartAlias
        )

        for candidateModel in orderedCandidateModels {
            if factoryWorkerHealthCandidateIsDispatchable(
                candidateModel: candidateModel,
                routeModel: routeModel,
                requestSurface: requestSurface,
                requestShape: requestShape
            ) {
                return candidateModel
            }
        }

        return nil
    }

    private static func syntheticFactoryWorkerHealthRequest(
        routeModel: String,
        requestShape: FactoryWorkerHealthRequestShape = .toolChat
    ) -> String {
        let contentJSON: String
        let toolsJSON: String
        switch requestShape {
        case .plainChat:
            contentJSON = "\"Hi\""
            toolsJSON = ""
        case .toolChat:
            contentJSON = "\"Hi\""
            toolsJSON = """
            ,
              "tools": [
                {
                  "type": "function",
                  "function": {
                    "name": "noop",
                    "parameters": {
                      "type": "object",
                      "properties": {}
                    }
                  }
                }
              ]
            """
        case .typedToolChat:
            contentJSON = """
            [
              {
                "type": "text",
                "text": "Hi"
              }
            ]
            """
            toolsJSON = """
            ,
              "tools": [
                {
                  "type": "function",
                  "function": {
                    "name": "noop",
                    "parameters": {
                      "type": "object",
                      "properties": {}
                    }
                  }
                }
              ]
            """
        }

        return """
        {
          "model": "\(routeModel)",
          "messages": [
            {
              "role": "user",
              "content": \(contentJSON)
            }
          ],
          "max_tokens": 1\(toolsJSON)
        }
        """
    }

    static func syntheticFactoryWorkerHealthRequestForTesting(
        routeModel: String,
        requestShape: String? = nil
    ) -> String {
        let shape = requestShape.flatMap { FactoryWorkerHealthRequestShape(rawValue: $0) } ?? .toolChat
        return syntheticFactoryWorkerHealthRequest(routeModel: routeModel, requestShape: shape)
    }

    private static func factoryWorkerHealthCandidateIsDispatchable(
        candidateModel: String,
        routeModel: String,
        requestSurface: String,
        requestShape: FactoryWorkerHealthRequestShape
    ) -> Bool {
        guard requestSurface == "chat_completions",
              let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) else {
            return candidateModel == routeModel
        }

        let syntheticWorkerRequest = syntheticFactoryWorkerHealthRequest(
            routeModel: routeModel,
            requestShape: requestShape
        )
        let orderedCandidateModels = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
            forPublicAlias: routeModel,
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: syntheticWorkerRequest,
            smartAlias: smartAlias
        )

        guard orderedCandidateModels.contains(candidateModel) else {
            return false
        }

        if let routeState = OpenAICompatTemporaryShim.routeHealthState(forRequestModel: candidateModel),
           routeState.status == .open || routeState.status == .suspect || routeState.status == .halfOpen {
            if let candidateRoute = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: candidateModel),
               candidateRoute.providerID == "nvidia" {
                guard OpenAICompatTemporaryShim.hasRecentNVIDIAInferenceEvidence(forRequestModel: candidateModel) else {
                    return false
                }
            } else if !OpenAICompatTemporaryShim.hasRecentInferenceSuccess(forRequestModel: candidateModel) {
                return false
            }
        }

        return OpenAICompatTemporaryShim.nextSmartAliasCandidateTransition(
            method: "POST",
            path: "/v1/chat/completions",
            currentBody: syntheticWorkerRequest,
            candidateModelsRemaining: [candidateModel]
        ) != nil
    }

    private static func effectiveFactoryContractHealthStatus(
        routeModel: String,
        requestSurface: String,
        requestShape: FactoryWorkerHealthRequestShape
    ) -> String? {
        guard requestSurface == "chat_completions",
              OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) != nil else {
            return OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: routeModel)?.rawValue
        }

        if dispatchableFactoryWorkerCandidateModel(
            routeModel: routeModel,
            requestSurface: requestSurface,
            requestShape: requestShape
        ) != nil {
            return nil
        }

        let syntheticWorkerRequest = syntheticFactoryWorkerHealthRequest(
            routeModel: routeModel,
            requestShape: requestShape
        )
        let orderedCandidateModels = effectiveFactoryWorkerCandidateModels(
            routeModel: routeModel,
            requestSurface: requestSurface,
            requestShape: requestShape
        )
        let selection = OpenAICompatTemporaryShim.nextSmartAliasCandidateSelection(
            method: "POST",
            path: "/v1/chat/completions",
            currentBody: syntheticWorkerRequest,
            candidateModelsRemaining: orderedCandidateModels
        )
        if let exhaustionSummary = selection.exhaustionSummary {
            return exhaustionSummary.classification.rawValue
        }
        if selection.terminalPreflightError != nil {
            return "policy_exhausted"
        }
        return "route_unavailable"
    }

    private static func factoryWorkerRequestShapeContracts(
        routeModel: String,
        routeProvider: String,
        requestSurface: String,
        requestedAlias: String? = nil
    ) -> [FactoryWorkerRequestShapeContract] {
        guard requestSurface == "chat_completions",
              OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) != nil else {
            let routeHealthStatus = OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: routeModel)?.rawValue
            let dispatchableRouteModel = routeHealthStatus == nil ? routeModel : nil
            return [
                FactoryWorkerRequestShapeContract(
                    id: "direct",
                    candidateModels: [routeModel],
                    dispatchableCandidateModels: dispatchableRouteModel.map { [$0] } ?? [],
                    dispatchableRouteModel: dispatchableRouteModel,
                    effectiveRouteModel: dispatchableRouteModel ?? routeModel,
                    effectiveRouteModelSource: .configuredRoute,
                    effectiveRouteProvider: dispatchableRouteModel.flatMap {
                        OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: $0)?.providerID
                    },
                    routeHealthStatus: routeHealthStatus,
                    recentDispatchedRouteModel: nil,
                    recentDispatchedRouteProvider: nil,
                    recentDispatchedRouteAt: nil
                )
            ]
        }

        let recentWinnerAliases = [requestedAlias, routeModel].compactMap { $0 }

        return FactoryWorkerHealthRequestShape.allCases.map { requestShape in
            let candidateModels = effectiveFactoryWorkerCandidateModels(
                routeModel: routeModel,
                requestSurface: requestSurface,
                requestShape: requestShape
            )
            let dispatchableCandidateModels = candidateModels.filter { candidateModel in
                factoryWorkerHealthCandidateIsDispatchable(
                    candidateModel: candidateModel,
                    routeModel: routeModel,
                    requestSurface: requestSurface,
                    requestShape: requestShape
                )
            }

            let recentWinner = recentWinnerAliases.lazy.compactMap { alias in
                OpenAICompatTemporaryShim.recentSmartAliasWinner(forRequestedAlias: alias)
            }.first(where: { recentWinner in
                dispatchableCandidateModels.contains(recentWinner.requestModel)
            })
            let recentDispatch = recentWinnerAliases.lazy.compactMap { alias in
                OpenAICompatTemporaryShim.recentSmartAliasDispatch(forRequestedAlias: alias)
            }.first(where: { recentDispatch in
                candidateModels.contains(recentDispatch.requestModel)
            })

            let dispatchableRouteModel = recentWinner?.requestModel ?? dispatchableCandidateModels.first
            let effectiveRouteModel = dispatchableRouteModel ?? routeModel
            let effectiveRouteModelSource: OpenAICompatTemporaryShim.FactoryEffectiveRouteModelSource
            if recentWinner != nil {
                effectiveRouteModelSource = .observedRecentWinner
            } else if dispatchableRouteModel != nil {
                effectiveRouteModelSource = .dispatchablePrediction
            } else {
                effectiveRouteModelSource = .authoritativeFallback
            }
            let effectiveRouteProvider = dispatchableRouteModel.flatMap {
                OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: $0)?.providerID
            }

            return FactoryWorkerRequestShapeContract(
                id: requestShape.rawValue,
                candidateModels: candidateModels,
                dispatchableCandidateModels: dispatchableCandidateModels,
                dispatchableRouteModel: dispatchableRouteModel,
                effectiveRouteModel: effectiveRouteModel,
                effectiveRouteModelSource: effectiveRouteModelSource,
                effectiveRouteProvider: effectiveRouteProvider,
                routeHealthStatus: effectiveFactoryContractHealthStatus(
                    routeModel: routeModel,
                    requestSurface: requestSurface,
                    requestShape: requestShape
                ),
                recentDispatchedRouteModel: recentDispatch?.requestModel,
                recentDispatchedRouteProvider: recentDispatch.flatMap {
                    OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: $0.requestModel)?.providerID
                },
                recentDispatchedRouteAt: recentDispatch?.timestamp
            )
        }
    }

    private static func summarizedFactoryWorkerEffectiveRouteModel(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> String? {
        let effectiveRouteModels = Array(Set(requestShapeContracts.map(\.effectiveRouteModel))).sorted()
        guard effectiveRouteModels.count == 1 else {
            return nil
        }
        return effectiveRouteModels.first
    }

    private static func summarizedFactoryWorkerEffectiveRouteModelSource(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> OpenAICompatTemporaryShim.FactoryEffectiveRouteModelSource? {
        let effectiveRouteModelSources = Array(Set(requestShapeContracts.map(\.effectiveRouteModelSource))).sorted { $0.rawValue < $1.rawValue }
        guard effectiveRouteModelSources.count == 1 else {
            return .requestShapeDivergent
        }
        return effectiveRouteModelSources.first
    }

    private static func summarizedFactoryWorkerEffectiveRouteProvider(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> String? {
        let effectiveRouteProviders = Array(Set(requestShapeContracts.compactMap(\.effectiveRouteProvider))).sorted()
        guard effectiveRouteProviders.count == 1,
              requestShapeContracts.allSatisfy({ $0.effectiveRouteProvider == effectiveRouteProviders.first }) else {
            return nil
        }
        return effectiveRouteProviders.first
    }

    private static func summarizedFactoryWorkerRecentDispatchedRouteModel(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> String? {
        let recentDispatchedRouteModels = Array(Set(requestShapeContracts.compactMap(\.recentDispatchedRouteModel))).sorted()
        guard recentDispatchedRouteModels.count == 1,
              requestShapeContracts.allSatisfy({ $0.recentDispatchedRouteModel == recentDispatchedRouteModels.first }) else {
            return nil
        }
        return recentDispatchedRouteModels.first
    }

    private static func summarizedFactoryWorkerRecentDispatchedRouteProvider(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> String? {
        let recentDispatchedRouteProviders = Array(Set(requestShapeContracts.compactMap(\.recentDispatchedRouteProvider))).sorted()
        guard recentDispatchedRouteProviders.count == 1,
              requestShapeContracts.allSatisfy({ $0.recentDispatchedRouteProvider == recentDispatchedRouteProviders.first }) else {
            return nil
        }
        return recentDispatchedRouteProviders.first
    }

    private static func summarizedFactoryWorkerRecentDispatchedRouteAt(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> Date? {
        let timestamps = Array(Set(requestShapeContracts.compactMap(\.recentDispatchedRouteAt))).sorted()
        guard timestamps.count == 1,
              requestShapeContracts.allSatisfy({ $0.recentDispatchedRouteAt == timestamps.first }) else {
            return nil
        }
        return timestamps.first
    }

    private static func summarizedFactoryWorkerDispatchableRouteModel(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> String? {
        let dispatchableRouteModels = Array(Set(requestShapeContracts.compactMap(\.dispatchableRouteModel))).sorted()
        guard dispatchableRouteModels.count == 1,
              requestShapeContracts.allSatisfy({ $0.dispatchableRouteModel == dispatchableRouteModels.first }) else {
            return nil
        }
        return dispatchableRouteModels.first
    }

    private static func summarizedFactoryWorkerHealthStatus(
        from requestShapeContracts: [FactoryWorkerRequestShapeContract]
    ) -> String? {
        let failingStatuses = requestShapeContracts.compactMap { contract in
            contract.ready ? nil : (contract.routeHealthStatus ?? "route_unavailable")
        }
        guard !failingStatuses.isEmpty else {
            return nil
        }
        let uniqueStatuses = Array(Set(failingStatuses)).sorted()
        return uniqueStatuses.count == 1 ? uniqueStatuses.first : "request_shape_divergent"
    }

    private static func effectiveFactoryCandidateModels(
        routeModel: String,
        routeProvider: String,
        requestSurface: String
    ) -> [String] {
        if OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) != nil {
            return effectiveFactoryWorkerCandidateModels(
                routeModel: routeModel,
                requestSurface: requestSurface,
                requestShape: .toolChat
            )
        }
        return [routeModel]
    }

    private static func effectiveFactoryRouteModel(
        routeModel: String,
        routeProvider: String,
        requestSurface: String,
        requestedAlias: String? = nil
    ) -> String {
        if requestSurface == "chat_completions",
           OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) != nil {
            let requestShapeContracts = factoryWorkerRequestShapeContracts(
                routeModel: routeModel,
                routeProvider: routeProvider,
                requestSurface: requestSurface,
                requestedAlias: requestedAlias
            )
            return summarizedFactoryWorkerEffectiveRouteModel(from: requestShapeContracts) ?? routeModel
        }
        let candidateModels = effectiveFactoryCandidateModels(
            routeModel: routeModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface
        )
        return firstAvailableFactoryWorkerCandidateModel(from: candidateModels) ?? routeModel
    }

    private static func factoryRoleContract(
        modelID: String?,
        reasoningEffort: String?,
        customModels: [[String: Any]]
    ) -> FactoryRoleContract? {
        guard let modelID,
              let customModel = customModels.first(where: { ($0["id"] as? String) == modelID }),
              let routeModel = customModel["model"] as? String,
              let routeProvider = customModel["provider"] as? String else {
            return nil
        }

        let requestSurface = factoryWorkerRequestSurface(forProvider: routeProvider)
        let directEffectiveRouteModel = effectiveFactoryRouteModel(
            routeModel: routeModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface
        )
        let directEffectiveRouteProvider =
            OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: directEffectiveRouteModel)?.providerID
        let directRouteHealthStatus =
            OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: directEffectiveRouteModel)?.rawValue

        return FactoryRoleContract(
            modelID: modelID,
            reasoningEffort: reasoningEffort,
            routeModel: routeModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface,
            effectiveRouteModel: directEffectiveRouteModel,
            effectiveRouteModelSource: .configuredRoute,
            effectiveRouteProvider: directEffectiveRouteProvider,
            displayName: customModel["displayName"] as? String,
            baseURL: customModel["baseUrl"] as? String,
            routeHealthStatus: directRouteHealthStatus
        )
    }

    private static func factoryRoleContracts() -> (orchestration: FactoryRoleContract?, verification: FactoryRoleContract?)? {
        guard let settingsPath = ThinkingProxy.factorySettingsPath(),
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionDefaultSettings = root["sessionDefaultSettings"] as? [String: Any],
              let missionModelSettings = root["missionModelSettings"] as? [String: Any],
              let customModels = root["customModels"] as? [[String: Any]] else {
            return nil
        }

        return (
            orchestration: factoryRoleContract(
                modelID: sessionDefaultSettings["model"] as? String,
                reasoningEffort: sessionDefaultSettings["reasoningEffort"] as? String,
                customModels: customModels
            ),
            verification: factoryRoleContract(
                modelID: missionModelSettings["validationWorkerModel"] as? String,
                reasoningEffort: missionModelSettings["validationWorkerReasoningEffort"] as? String,
                customModels: customModels
            )
        )
    }

    private static func factoryWorkerContract() -> FactoryWorkerContract? {
        let settingsPath = ThinkingProxy.factorySettingsPath()
        let settingsRoot: [String: Any]? = settingsPath.flatMap { path in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return root
        }
        let missionModelSettings = settingsRoot?["missionModelSettings"] as? [String: Any] ?? [:]
        let sessionDefaultSettings = settingsRoot?["sessionDefaultSettings"] as? [String: Any] ?? [:]
        let customModels = settingsRoot?["customModels"] as? [[String: Any]] ?? []
        let workerModelID = (missionModelSettings["workerModel"] as? String) ?? OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID
        let workerModel = customModels.first(where: { ($0["id"] as? String) == workerModelID })
        let configuredRouteModel: String = (workerModel?["model"] as? String) ?? OpenAICompatTemporaryShim.publicWorkerSmartRouterAlias()
        let routeProvider: String = (workerModel?["provider"] as? String) ?? "generic-chat-completion-api"
        let authoritativeSettingsPath = settingsPath ?? "src/Sources/ThinkingProxy.swift"

        let authoritativeRouteModel = authoritativeFactoryWorkerRouteModel(
            workerModelID: workerModelID,
            configuredRouteModel: configuredRouteModel,
            routeProvider: routeProvider
        )
        let requestSurface = factoryWorkerRequestSurface(forProvider: routeProvider)
        let requestShapeContracts = factoryWorkerRequestShapeContracts(
            routeModel: authoritativeRouteModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface,
            requestedAlias: workerModelID
        )
        let dispatchableRouteModel = summarizedFactoryWorkerDispatchableRouteModel(
            from: requestShapeContracts
        )
        let effectiveRouteModel = summarizedFactoryWorkerEffectiveRouteModel(
            from: requestShapeContracts
        )
        let effectiveRouteModelSource = summarizedFactoryWorkerEffectiveRouteModelSource(
            from: requestShapeContracts
        )
        let recentDispatchedRouteModel = summarizedFactoryWorkerRecentDispatchedRouteModel(
            from: requestShapeContracts
        )
        let recentDispatchedRouteProvider = summarizedFactoryWorkerRecentDispatchedRouteProvider(
            from: requestShapeContracts
        )
        let recentDispatchedRouteAt = summarizedFactoryWorkerRecentDispatchedRouteAt(
            from: requestShapeContracts
        )
        let recentDispatched = recentSmartAliasDispatchForFactoryWorker(
            workerModelID: workerModelID,
            routeModel: authoritativeRouteModel
        )
        let recentLiveDispatch = recentSmartAliasWinnerForFactoryWorker(
            workerModelID: workerModelID,
            routeModel: authoritativeRouteModel
        )
        let effectiveRouteProvider = summarizedFactoryWorkerEffectiveRouteProvider(
            from: requestShapeContracts
        )
        let recentLiveRouteProvider = recentLiveDispatch.flatMap {
            OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: $0.requestModel)?.providerID
        }

        let snapshotDriftPaths: [String]
        if let settingsPath,
           let workerModel {
            snapshotDriftPaths = factoryWorkerSnapshotDriftPaths(
                settingsPath: settingsPath,
                sessionModelID: sessionDefaultSettings["model"] as? String,
                sessionReasoningEffort: sessionDefaultSettings["reasoningEffort"] as? String,
                sessionAutonomyMode: sessionDefaultSettings["autonomyMode"] as? String,
                workerModelID: workerModelID,
                validationWorkerModelID: missionModelSettings["validationWorkerModel"] as? String,
                workerReasoningEffort: missionModelSettings["workerReasoningEffort"] as? String,
                validationWorkerReasoningEffort: missionModelSettings["validationWorkerReasoningEffort"] as? String,
                workerModel: workerModel,
                canonicalCustomModels: customModels
            )
        } else {
            snapshotDriftPaths = []
        }

        let acceptsRetiredWorkerRescues = acceptsRetiredFactoryWorkerRescues(
            authoritativeWorkerModelID: workerModelID
        )
        let acceptedRequestModelIDs = acceptedFactoryWorkerRequestModelIDs(
            acceptsRetiredRescues: acceptsRetiredWorkerRescues
        )
        let rescuedRequestModelIDs = rescuedFactoryWorkerRequestModelIDs(
            acceptsRetiredRescues: acceptsRetiredWorkerRescues
        )

        return FactoryWorkerContract(
            workerModelID: workerModelID,
            validationWorkerModelID: missionModelSettings["validationWorkerModel"] as? String,
            workerReasoningEffort: missionModelSettings["workerReasoningEffort"] as? String,
            validationWorkerReasoningEffort: missionModelSettings["validationWorkerReasoningEffort"] as? String,
            configuredRouteModel: configuredRouteModel,
            routeModel: configuredRouteModel,
            authoritativeRouteModel: authoritativeRouteModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface,
            requestShapeContracts: requestShapeContracts,
            dispatchableRouteModel: dispatchableRouteModel,
            effectiveRouteModel: effectiveRouteModel,
            effectiveRouteModelSource: effectiveRouteModelSource,
            effectiveRouteProvider: effectiveRouteProvider,
            recentDispatchedRouteModel: recentDispatchedRouteModel ?? recentDispatched?.requestModel,
            recentDispatchedRouteProvider: recentDispatchedRouteProvider ?? recentDispatched.flatMap {
                OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: $0.requestModel)?.providerID
            },
            recentDispatchedRequestShape: recentDispatched?.requestShape,
            recentDispatchedRouteAt: recentDispatchedRouteAt ?? recentDispatched?.timestamp,
            recentDispatchedCallerRequestID: recentDispatched?.callerRequestID,
            recentDispatchedCallerSessionID: recentDispatched?.callerSessionID,
            recentLiveRouteModel: recentLiveDispatch?.requestModel,
            recentLiveRouteProvider: recentLiveRouteProvider,
            recentLiveRequestShape: recentLiveDispatch?.requestShape,
            recentLiveRouteAt: recentLiveDispatch?.timestamp,
            recentLiveCallerRequestID: recentLiveDispatch?.callerRequestID,
            recentLiveCallerSessionID: recentLiveDispatch?.callerSessionID,
            displayName: workerModel.flatMap { $0["displayName"] as? String },
            baseURL: workerModel.flatMap { $0["baseUrl"] as? String },
            routeHealthStatus: summarizedFactoryWorkerHealthStatus(
                from: requestShapeContracts
            ),
            authoritativeSettingsPath: authoritativeSettingsPath,
            snapshotDriftPaths: snapshotDriftPaths,
            acceptedRequestModelIDs: acceptedRequestModelIDs,
            rescuedRequestModelIDs: rescuedRequestModelIDs,
            settingsAvailable: settingsRoot != nil
        )
    }

    private static func retiredFactoryWorkerModelIDs(excluding currentWorkerModelID: String) -> Set<String> {
        let retiredIDs = OpenAICompatTemporaryShim.codeOwnedFactoryWorkerRescueModelIDs.union([OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID])
        return retiredIDs.subtracting([currentWorkerModelID])
    }

    private static func acceptsRetiredFactoryWorkerRescues(authoritativeWorkerModelID: String?) -> Bool {
        guard let authoritativeWorkerModelID else {
            return true
        }
        return OpenAICompatTemporaryShim.isCodeOwnedFactoryWorkerIncomingModelID(authoritativeWorkerModelID)
    }

    private static func acceptedFactoryWorkerRequestModelIDs(acceptsRetiredRescues: Bool) -> [String] {
        var acceptedModelIDs = [OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID]
        if acceptsRetiredRescues {
            acceptedModelIDs.append(contentsOf: OpenAICompatTemporaryShim.codeOwnedFactoryWorkerRescueModelIDs)
        }
        return acceptedModelIDs.sorted()
    }

    private static func rescuedFactoryWorkerRequestModelIDs(acceptsRetiredRescues: Bool) -> [String] {
        guard acceptsRetiredRescues else {
            return []
        }
        return Array(OpenAICompatTemporaryShim.codeOwnedFactoryWorkerRescueModelIDs).sorted()
    }

    private static func codeOwnedFactoryWorkerBindings(
        settingsPath: String?,
        authoritativeWorkerModelID: String?
    ) -> [String: FactoryModelBinding] {
        let authoritativeSettingsPath = settingsPath ?? "src/Sources/ThinkingProxy.swift"
        let routeModel = OpenAICompatTemporaryShim.publicWorkerSmartRouterAlias()
        let routeProvider = "generic-chat-completion-api"
        let requestSurface = factoryWorkerRequestSurface(forProvider: routeProvider)
        var bindingsByIncomingModelID: [String: FactoryModelBinding] = [
            OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID: FactoryModelBinding(
                incomingModelID: OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID,
                authoritativeModelID: OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID,
                routeModel: routeModel,
                routeProvider: routeProvider,
                requestSurface: requestSurface,
                displayName: "Factory Worker via Proxy",
                baseURL: "http://127.0.0.1:8317/v1",
                authoritativeSettingsPath: authoritativeSettingsPath,
                source: "code_owned_worker_alias"
            )
        ]

        if acceptsRetiredFactoryWorkerRescues(authoritativeWorkerModelID: authoritativeWorkerModelID) {
            for retiredModelID in OpenAICompatTemporaryShim.codeOwnedFactoryWorkerRescueModelIDs {
                bindingsByIncomingModelID[retiredModelID] = FactoryModelBinding(
                    incomingModelID: retiredModelID,
                    authoritativeModelID: OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID,
                    routeModel: routeModel,
                    routeProvider: routeProvider,
                    requestSurface: requestSurface,
                    displayName: "Factory Worker via Proxy",
                    baseURL: "http://127.0.0.1:8317/v1",
                    authoritativeSettingsPath: authoritativeSettingsPath,
                    source: "retired_worker_alias_rescue"
                )
            }
        }

        return bindingsByIncomingModelID
    }

    static func factoryResolvedRouteModel(forIncomingModelID incomingModelID: String) -> String? {
        factoryModelBinding(forIncomingModelID: incomingModelID)?.routeModel
    }

    private static func factoryModelBindingPreflightError(forIncomingModelID incomingModelID: String) -> String? {
        guard incomingModelID.hasPrefix("custom:"),
              factoryModelBinding(forIncomingModelID: incomingModelID) == nil else {
            return nil
        }

        let retiredWorkerModelIDs: Set<String>
        if let contract = factoryWorkerContract() {
            retiredWorkerModelIDs = retiredFactoryWorkerModelIDs(excluding: contract.workerModelID)
        } else {
            retiredWorkerModelIDs = [
                "custom:Proxy-WorkerPool-8",
                "custom:Factory-Worker-GPT-5.4-High-8",
                "custom:Proxy-Worker-Smart-Router-8"
            ]
        }

        if let settingsPath = factorySettingsPath(),
           let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let missionModelSettings = root["missionModelSettings"] as? [String: Any],
           let customModels = root["customModels"] as? [[String: Any]],
           let workerModelID = missionModelSettings["workerModel"] as? String,
           incomingModelID == workerModelID,
           let workerModel = customModels.first(where: { ($0["id"] as? String) == workerModelID }),
           let configuredRouteModel = workerModel["model"] as? String,
           let routeProvider = workerModel["provider"] as? String,
           routeProvider == "generic-chat-completion-api",
           (
            OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: configuredRouteModel) != nil ||
            configuredRouteModel == workerModelID
           ) {
            return "Factory worker model \(incomingModelID) is not a code-owned worker entrypoint. Use the public worker alias \(OpenAICompatTemporaryShim.publicWorkerSmartRouterAlias()) or the built-in Factory worker ID \(OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID)."
        }

        guard retiredWorkerModelIDs.contains(incomingModelID) else {
            return nil
        }

        if let contract = factoryWorkerContract() {
            return "Factory sent retired worker model \(incomingModelID), but VibeProxy could not bind it onto the authoritative worker contract for model \(contract.workerModelID). Check /healthz factory_worker snapshot drift and resync Factory settings."
        }

        if let settingsPath = factorySettingsPath() {
            return "Factory sent retired worker model \(incomingModelID), but VibeProxy could not derive an authoritative worker contract from \(settingsPath). Check that missionModelSettings.workerModel and its customModels entry are present."
        }

        return "Factory sent retired worker model \(incomingModelID), but VibeProxy could not find ~/.factory/settings.json (or FACTORY_SETTINGS_PATH) to derive the authoritative worker contract."
    }

    private static func factoryWorkerBindingContractError(for binding: FactoryModelBinding) -> String? {
        guard let contract = factoryWorkerContract(),
              binding.authoritativeModelID == contract.workerModelID else {
            return nil
        }

        let blockingDriftPaths: [String]
        if binding.incomingModelID == contract.workerModelID {
            blockingDriftPaths = contract.blockingSnapshotDriftPaths
        } else {
            blockingDriftPaths = contract.snapshotDriftPaths
        }

        guard !blockingDriftPaths.isEmpty else {
            return nil
        }

        let driftedPaths = blockingDriftPaths.joined(separator: ", ")
        return "Factory worker snapshot drift detected for \(binding.incomingModelID) against authoritative worker model \(contract.workerModelID). Refusing to proxy the request until Factory settings are resynced. Drifted paths: \(driftedPaths)"
    }

    fileprivate static func factoryModelBinding(forIncomingModelID incomingModelID: String) -> FactoryModelBinding? {
        factoryModelBindings()?.bindingsByIncomingModelID[incomingModelID]
    }

    fileprivate static func factoryModelBindingByRouteModel(forRouteModel routeModel: String) -> FactoryModelBinding? {
        factoryModelBindings()?.bindingsByIncomingModelID.values.first { $0.routeModel == routeModel }
    }

    fileprivate static func factoryModelBindings() -> CachedFactoryModelBindings? {
        let settingsPath = ThinkingProxy.factorySettingsPath() ?? "<code-owned-worker-bindings>"
        let settingsFingerprint = settingsPath == "<code-owned-worker-bindings>"
            ? nil
            : ThinkingProxy.fileFingerprint(at: settingsPath)
        if let cached = factoryBindingsCacheQueue.sync(execute: { cachedFactoryModelBindings }),
           cached.settingsPath == settingsPath,
           cached.settingsFingerprint == settingsFingerprint {
            return cached
        }

        guard settingsPath != "<code-owned-worker-bindings>",
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let bindingsByIncomingModelID = codeOwnedFactoryWorkerBindings(
                settingsPath: settingsPath == "<code-owned-worker-bindings>" ? nil : settingsPath,
                authoritativeWorkerModelID: nil
            )
            let cached = CachedFactoryModelBindings(
                settingsPath: settingsPath,
                settingsFingerprint: settingsFingerprint,
                bindingsByIncomingModelID: bindingsByIncomingModelID,
                authoritativeWorkerModelID: OpenAICompatTemporaryShim.canonicalFactoryWorkerModelID
            )
            factoryBindingsCacheQueue.sync {
                cachedFactoryModelBindings = cached
            }
            return cached
        }

        let customModels = root["customModels"] as? [[String: Any]] ?? []
        let authoritativeWorkerModelID = (root["missionModelSettings"] as? [String: Any])?["workerModel"] as? String
        var bindingsByIncomingModelID = codeOwnedFactoryWorkerBindings(
            settingsPath: settingsPath,
            authoritativeWorkerModelID: authoritativeWorkerModelID
        )

        for customModel in customModels {
            guard let incomingModelID = customModel["id"] as? String,
                  let configuredRouteModel = customModel["model"] as? String,
                  let routeProvider = customModel["provider"] as? String else {
                continue
            }

            if OpenAICompatTemporaryShim.isCodeOwnedFactoryWorkerIncomingModelID(incomingModelID) {
                continue
            }

            let routeModel: String
            if incomingModelID == authoritativeWorkerModelID,
               let authoritativeWorkerModelID {
                routeModel = authoritativeFactoryWorkerRouteModel(
                    workerModelID: authoritativeWorkerModelID,
                    configuredRouteModel: configuredRouteModel,
                    routeProvider: routeProvider
                )
            } else {
                routeModel = configuredRouteModel
            }

            let routesToWorkerSmartAlias =
                routeProvider == "generic-chat-completion-api" &&
                OpenAICompatTemporaryShim.isWorkerPoolPublicAlias(routeModel)
            if routesToWorkerSmartAlias && !OpenAICompatTemporaryShim.isCodeOwnedFactoryWorkerIncomingModelID(incomingModelID) {
                continue
            }

            bindingsByIncomingModelID[incomingModelID] = FactoryModelBinding(
                incomingModelID: incomingModelID,
                authoritativeModelID: incomingModelID,
                routeModel: routeModel,
                routeProvider: routeProvider,
                requestSurface: factoryWorkerRequestSurface(forProvider: routeProvider),
                displayName: customModel["displayName"] as? String,
                baseURL: customModel["baseUrl"] as? String,
                authoritativeSettingsPath: settingsPath,
                source: "authoritative_custom_model"
            )

            let supportsRawRouteRescue = routeProvider == "openai" || routeProvider == "xai"
            if supportsRawRouteRescue,
               routeModel != incomingModelID,
               !routeModel.isEmpty,
               bindingsByIncomingModelID[routeModel] == nil {
                bindingsByIncomingModelID[routeModel] = FactoryModelBinding(
                    incomingModelID: routeModel,
                    authoritativeModelID: incomingModelID,
                    routeModel: routeModel,
                    routeProvider: routeProvider,
                    requestSurface: factoryWorkerRequestSurface(forProvider: routeProvider),
                    displayName: customModel["displayName"] as? String,
                    baseURL: customModel["baseUrl"] as? String,
                    authoritativeSettingsPath: settingsPath,
                    source: "raw_managed_route_rescue"
                )
            }
        }

        let cached = CachedFactoryModelBindings(
            settingsPath: settingsPath,
            settingsFingerprint: settingsFingerprint,
            bindingsByIncomingModelID: bindingsByIncomingModelID,
            authoritativeWorkerModelID: authoritativeWorkerModelID
        )
        factoryBindingsCacheQueue.sync {
            cachedFactoryModelBindings = cached
        }
        return cached
    }

    private static func factoryWorkerSnapshotDriftPaths(
        settingsPath: String,
        sessionModelID: String?,
        sessionReasoningEffort: String?,
        sessionAutonomyMode: String?,
        workerModelID: String,
        validationWorkerModelID: String?,
        workerReasoningEffort: String?,
        validationWorkerReasoningEffort: String?,
        workerModel: [String: Any],
        canonicalCustomModels: [[String: Any]]
    ) -> [String] {
        let fileManager = FileManager.default
        let factoryRoot = ((settingsPath as NSString).deletingLastPathComponent as NSString).standardizingPath
        var driftedPaths: [String] = []
        let retiredWorkerModelIDs = retiredFactoryWorkerModelIDs(excluding: workerModelID)

        func recordDrift(_ path: String) {
            driftedPaths.append((path as NSString).standardizingPath)
        }

        func loadJSONObject(at path: String) -> [String: Any]? {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }

        func canonicalJSONData(for object: Any) -> Data? {
            guard JSONSerialization.isValidJSONObject(object) else {
                return nil
            }
            return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }

        func jsonObjectsEqual(_ lhs: Any, _ rhs: Any) -> Bool {
            canonicalJSONData(for: lhs) == canonicalJSONData(for: rhs)
        }

        func containsRetiredWorkerModelID(_ customModels: [[String: Any]]) -> Bool {
            customModels.contains { model in
                guard let id = model["id"] as? String else {
                    return false
                }
                return retiredWorkerModelIDs.contains(id)
            }
        }

        func expectedMissionSettingsMatch(_ object: [String: Any]) -> Bool {
            object["workerModel"] as? String == workerModelID &&
                object["validationWorkerModel"] as? String == validationWorkerModelID &&
                object["workerReasoningEffort"] as? String == workerReasoningEffort &&
                object["validationWorkerReasoningEffort"] as? String == validationWorkerReasoningEffort
        }

        func expectedSettingsMatch(_ object: [String: Any], requireWorkerModelDefinition: Bool) -> Bool {
            guard let sessionDefaultSettings = object["sessionDefaultSettings"] as? [String: Any],
                  sessionDefaultSettings["model"] as? String == sessionModelID,
                  sessionDefaultSettings["reasoningEffort"] as? String == sessionReasoningEffort,
                  sessionDefaultSettings["autonomyMode"] as? String == sessionAutonomyMode,
                  let missionModelSettings = object["missionModelSettings"] as? [String: Any],
                  missionModelSettings["workerModel"] as? String == workerModelID,
                  missionModelSettings["validationWorkerModel"] as? String == validationWorkerModelID,
                  missionModelSettings["workerReasoningEffort"] as? String == workerReasoningEffort,
                  missionModelSettings["validationWorkerReasoningEffort"] as? String == validationWorkerReasoningEffort else {
                return false
            }

            guard let customModels = object["customModels"] as? [[String: Any]],
                  !containsRetiredWorkerModelID(customModels),
                  jsonObjectsEqual(customModels, canonicalCustomModels) else {
                return false
            }

            guard requireWorkerModelDefinition else {
                return true
            }

            guard let definedWorkerModel = customModels.first(where: { ($0["id"] as? String) == workerModelID }) else {
                return false
            }
            return jsonObjectsEqual(definedWorkerModel, workerModel)
        }

        func expectedRuntimeCatalogMatch(_ object: [String: Any]) -> Bool {
            guard let customModels = object["customModels"] as? [[String: Any]],
                  !containsRetiredWorkerModelID(customModels),
                  jsonObjectsEqual(customModels, canonicalCustomModels),
                  let definedWorkerModel = customModels.first(where: { ($0["id"] as? String) == workerModelID }) else {
                return false
            }
            return jsonObjectsEqual(definedWorkerModel, workerModel)
        }

        let localSettingsPath = (factoryRoot as NSString).appendingPathComponent("settings.local.json")
        if fileManager.fileExists(atPath: localSettingsPath) {
            if let object = loadJSONObject(at: localSettingsPath),
               expectedSettingsMatch(object, requireWorkerModelDefinition: true) {
                // Expected snapshot.
            } else {
                recordDrift(localSettingsPath)
            }
        }

        for projectSettingsPath in ThinkingProxy.factoryProjectSettingsPaths() where fileManager.fileExists(atPath: projectSettingsPath) {
            if let object = loadJSONObject(at: projectSettingsPath),
               expectedSettingsMatch(object, requireWorkerModelDefinition: false) {
                // Expected snapshot.
            } else {
                recordDrift(projectSettingsPath)
            }
        }

        for missionSettingsPath in ThinkingProxy.factoryMissionFilePaths(root: factoryRoot, name: "model-settings.json") {
            if let object = loadJSONObject(at: missionSettingsPath),
               expectedMissionSettingsMatch(object) {
                // Expected snapshot.
            } else {
                recordDrift(missionSettingsPath)
            }
        }

        for runtimeCatalogPath in ThinkingProxy.factoryMissionFilePaths(root: factoryRoot, name: "runtime-custom-models.json") {
            if let object = loadJSONObject(at: runtimeCatalogPath),
               expectedRuntimeCatalogMatch(object) {
                // Expected snapshot.
            } else {
                recordDrift(runtimeCatalogPath)
            }
        }

        return Array(Set(driftedPaths)).sorted()
    }

    private static func isMissionModelSettingsSnapshotPath(_ path: String) -> Bool {
        let standardizedPath = (path as NSString).standardizingPath
        let pathComponents = standardizedPath.split(separator: "/")
        return pathComponents.contains("missions") &&
            (standardizedPath as NSString).lastPathComponent == "model-settings.json"
    }

    private static func blockingFactoryWorkerSnapshotDriftPaths(_ paths: [String]) -> [String] {
        paths.filter { !isMissionModelSettingsSnapshotPath($0) }
    }

    private static func fileFingerprint(at path: String?) -> String? {
        guard let path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\((path as NSString).lastPathComponent):\(size):\(Int(modifiedAt))"
    }

    private static func factorySettingsPath() -> String? {
        if let overridePath = ProcessInfo.processInfo.environment["FACTORY_SETTINGS_PATH"],
           !overridePath.isEmpty {
            return overridePath
        }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".factory/settings.json")
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static func factoryProjectSettingsPaths() -> [String] {
        if let overrideValue = ProcessInfo.processInfo.environment["FACTORY_PROJECT_SETTINGS_PATHS"] {
            return overrideValue
                .split(separator: ":")
                .map { String($0) }
                .filter { !$0.isEmpty }
        }

        return [
            (NSHomeDirectory() as NSString).appendingPathComponent("CascadeProjects/songbird4/.factory/settings.json"),
            (NSHomeDirectory() as NSString).appendingPathComponent("CascadeProjects/voc/.factory/settings.json"),
            (NSHomeDirectory() as NSString).appendingPathComponent("CascadeProjects/merchant-warrior2/.factory/settings.json"),
            (NSHomeDirectory() as NSString).appendingPathComponent("CascadeProjects/pi_agent_rust/.factory/settings.json")
        ]
    }

    private static func factoryMissionFilePaths(root: String, name: String) -> [String] {
        let missionRoot = (root as NSString).appendingPathComponent("missions")
        guard FileManager.default.fileExists(atPath: missionRoot),
              let enumerator = FileManager.default.enumerator(atPath: missionRoot) else {
            return []
        }

        var paths: [String] = []
        for case let relativePath as String in enumerator where (relativePath as NSString).lastPathComponent == name {
            paths.append((missionRoot as NSString).appendingPathComponent(relativePath))
        }
        return paths.sorted()
    }

    private func isBackendReachable(timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let port = NWEndpoint.Port(rawValue: targetPort)!
        let connection = NWConnection(host: NWEndpoint.Host(targetHost), port: port, using: .tcp)
        let probeQueue = DispatchQueue(label: "io.automaze.vibeproxy.healthcheck-probe")
        var reachable = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                reachable = true
                semaphore.signal()
            case .failed, .waiting, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: probeQueue)
        _ = semaphore.wait(timeout: .now() + timeout)
        connection.cancel()
        return reachable
    }
}
