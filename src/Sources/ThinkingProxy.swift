import Foundation
import Network

enum OpenAICompatTemporaryShim {
    struct ClientFacingNVIDIAFailure {
        let statusCode: Int
        let message: String
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
            inflightAtRequest: Int? = nil
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
        }
    }

    struct NVIDIARetryState: Equatable {
        let model: String
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

        init(
            data: Data?,
            response: HTTPURLResponse?,
            error: Error?,
            deadlineStage: DeadlineStage,
            firstByteLatencyMilliseconds: Int? = nil,
            totalLatencyMilliseconds: Int? = nil
        ) {
            self.data = data
            self.response = response
            self.error = error
            self.deadlineStage = deadlineStage
            self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
            self.totalLatencyMilliseconds = totalLatencyMilliseconds
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
        let requestCount: Int
        let successCount: Int
        let timeoutCount: Int
        let invalidSuccessCount: Int
        let recentOutcomes: [String]
        let recentFirstByteLatencyMilliseconds: [Int]

        static let empty = RouteRollingMetrics(
            requestCount: 0,
            successCount: 0,
            timeoutCount: 0,
            invalidSuccessCount: 0,
            recentOutcomes: [],
            recentFirstByteLatencyMilliseconds: []
        )

        var timeoutRate: Double {
            guard !recentOutcomes.isEmpty else { return 0 }
            let timeouts = recentOutcomes.filter { $0.hasSuffix(":transport_timeout") }.count
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

    struct RouteCircuitState: Equatable {
        let status: RouteHealthStatus
        let failureScore: Int
        let recoverySuccesses: Int
        let openUntil: Date?
        let lastScoreUpdatedAt: Date?
        let lastTelemetryEvent: RouteTelemetryEvent?
        let rollingMetrics: RouteRollingMetrics
        let emaMetrics: RouteEMAMetrics
        let recoveredAt: Date?

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
        let failureThreshold: Int
        let cooldown: TimeInterval
        let recoverySuccessThreshold: Int
    }

    private struct PersistentRouteHealthEntry {
        let status: RouteHealthStatus
        let failureScore: Int
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

    private static let knownNVIDIARoutePoliciesByCanonicalModelID: [String: RequestPolicy] = [
        "z-ai/glm5": RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 300,
            firstResponseDeadline: 240,
            bufferedResponseDeadline: 285,
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
        ),
        "moonshotai/kimi-k2.5": RequestPolicy(
            minimumMaxTokens: 384,
            maximumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 180,
            firstResponseDeadline: 120,
            bufferedResponseDeadline: 150,
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
        ),
        "minimaxai/minimax-m2.5": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: 65536,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 300,
            firstResponseDeadline: 240,
            bufferedResponseDeadline: 285,
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
        )
    ]
    #if DEBUG
    private static let _assertKnownNVIDIARoutesHaveNoDuplicates: Void = {
        let keys = Array(knownNVIDIARoutePoliciesByCanonicalModelID.keys)
        Swift.assert(Set(keys).count == keys.count, "Duplicate key in knownNVIDIARoutePoliciesByCanonicalModelID")
    }()
    #endif
    private static let modelTierByCanonicalModelID: [String: ModelTier] = [
        "z-ai/glm5": .standard,
        "moonshotai/kimi-k2.5": .reasoning,
        "minimaxai/minimax-m2.5": .standard,
        "mimo-v2-pro-free": .economy,
        "xiaomi/mimo-v2-pro:free": .economy,
        "minimax-m2.5-free": .standard,
    ]
    #if DEBUG
    private static let _assertModelTiersHaveNoDuplicates: Void = {
        let keys = Array(modelTierByCanonicalModelID.keys)
        Swift.assert(Set(keys).count == keys.count, "Duplicate key in modelTierByCanonicalModelID")
    }()
    #endif
    static let canaryDisabledCanonicalModelIDs: Set<String> = []
    private static let nonNVIDIAMitigationPoliciesByRequestModel: [String: RequestPolicy] = [
        "glm-4.7": RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
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
        ),
        "glm-5": RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
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
        ),
        "glm-5.1": RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
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
        ),
        "proxy-worker-smart-router": RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 300,
            firstResponseDeadline: 60,
            bufferedResponseDeadline: 180,
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
        ),
        "mimo-v2-pro-kilocode": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ),
        "xiaomi/mimo-v2-pro:free": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ),
        "mimo-v2-pro-opencode": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ),
        "mimo-v2-pro-free": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: false,
            salvagesBestEffortRepair: false,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ),
        "minimax-m2.5-free": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: true,
            salvagesBestEffortRepair: true,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ),
        "minimax-m2.5-opencode": RequestPolicy(
            minimumMaxTokens: 128,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            bufferedResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryableFailureClasses: [.emptyBody, .emptyContent, .reasoningOnlyContentMissing, .reasoningLeakLength, .malformedToolArguments],
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            allowsThinkLeakRepair: true,
            salvagesBestEffortRepair: true,
            clientStreamingMode: .preserve,
            toolChoiceMode: .preserve,
            forcesKimiInstantMode: false
        ),
        "gpt-5.4(high)": RequestPolicy(
            minimumMaxTokens: nil,
            maximumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 300,
            firstResponseDeadline: 60,
            bufferedResponseDeadline: 180,
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
        )
    ]
    #if DEBUG
    private static let _assertNonNVIDIAPoliciesHaveNoDuplicates: Void = {
        let keys = Array(nonNVIDIAMitigationPoliciesByRequestModel.keys)
        Swift.assert(Set(keys).count == keys.count, "Duplicate key in nonNVIDIAMitigationPoliciesByRequestModel")
    }()
    #endif

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
    private static var hasLoadedPersistedRouteHealth = false
    static var routeTelemetryHookForTesting: ((RouteTelemetryEvent) -> Void)?
    private static let routeCircuitBreakerPolicy = RouteCircuitBreakerPolicy(
        failureThreshold: 4,
        cooldown: 120,
        recoverySuccessThreshold: 1
    )
    private static let routeRollingWindow = 8
    private static let fastCanaryInterval: TimeInterval = 30
    private static let defaultCanaryInterval: TimeInterval = 60
    private static let defaultSuspectHedgeDelay: TimeInterval = 45
    private static let routeFailureScoreDecayInterval: TimeInterval = 180
    private static let legacyRequestModelRewrites: [String: String] = [
        "glm-5": "glm-5.1",
        "glm-5-turbo": "glm-5.1"
    ]
    #if DEBUG
    private static let _assertLegacyRewritesHaveNoDuplicates: Void = {
        let keys = Array(legacyRequestModelRewrites.keys)
        Swift.assert(Set(keys).count == keys.count, "Duplicate key in legacyRequestModelRewrites")
    }()
    #endif

    // MARK: - Provider Concurrency Tracker

    final class ProviderConcurrencyRegistry {
        private let queue = DispatchQueue(label: "io.automaze.vibeproxy.concurrency-registry")
        private var inflightCounts: [String: Int] = [:]
        private var discoveredLimits: [String: Int] = [:]
        private var consecutiveSuccessesAtLimit: [String: Int] = [:]
        private var concurrent429Buckets: [String: (inflightLevel: Int, count: Int)] = [:]

        private let defaultConcurrencyLimit = 3
        private let maxConcurrencyLimit = 8
        private let successGrowthThreshold = 20

        func resetForTesting() {
            queue.sync {
                inflightCounts.removeAll()
                discoveredLimits.removeAll()
                consecutiveSuccessesAtLimit.removeAll()
                concurrent429Buckets.removeAll()
            }
        }

        func acquireSlot(routeHealthKey: String) -> Bool {
            queue.sync {
                let limit = discoveredLimits[routeHealthKey] ?? defaultConcurrencyLimit
                let current = inflightCounts[routeHealthKey] ?? 0
                guard current < limit else {
                    return false
                }
                inflightCounts[routeHealthKey] = current + 1
                return true
            }
        }

        func releaseSlot(routeHealthKey: String) {
            queue.sync {
                let current = inflightCounts[routeHealthKey] ?? 0
                inflightCounts[routeHealthKey] = max(0, current - 1)
            }
        }

        func record429(routeHealthKey: String, inflightAtRequest: Int) {
            queue.sync {
                let currentLimit = discoveredLimits[routeHealthKey] ?? defaultConcurrencyLimit

                // If we were at or above the limit when the 429 arrived, the limit is too high
                if inflightAtRequest >= currentLimit {
                    discoveredLimits[routeHealthKey] = max(1, inflightAtRequest - 1)
                    consecutiveSuccessesAtLimit[routeHealthKey] = 0
                    return
                }

                // Track 429s at the same inflight level — repeated hits suggest a lower limit
                let bucket = concurrent429Buckets[routeHealthKey]
                if let bucket, bucket.inflightLevel == inflightAtRequest {
                    let newCount = bucket.count + 1
                    if newCount >= 3 {
                        discoveredLimits[routeHealthKey] = max(1, inflightAtRequest - 1)
                        consecutiveSuccessesAtLimit[routeHealthKey] = 0
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
                let currentLimit = discoveredLimits[routeHealthKey] ?? defaultConcurrencyLimit
                let currentInflight = inflightAtRequest ?? (inflightCounts[routeHealthKey] ?? 0)

                // Only count as "at-limit" success if we were near the limit
                guard currentInflight >= currentLimit - 1 else { return }

                let successes = (consecutiveSuccessesAtLimit[routeHealthKey] ?? 0) + 1
                consecutiveSuccessesAtLimit[routeHealthKey] = successes

                // After sustained success at current limit, try growing
                if successes >= successGrowthThreshold, currentLimit < maxConcurrencyLimit {
                    discoveredLimits[routeHealthKey] = currentLimit + 1
                    consecutiveSuccessesAtLimit[routeHealthKey] = 0
                }
            }
        }

        func currentInflight(routeHealthKey: String) -> Int {
            queue.sync { inflightCounts[routeHealthKey] ?? 0 }
        }

        func isAtCapacity(routeHealthKey: String) -> Bool {
            queue.sync {
                let limit = discoveredLimits[routeHealthKey] ?? defaultConcurrencyLimit
                return (inflightCounts[routeHealthKey] ?? 0) >= limit
            }
        }

        func currentLimit(routeHealthKey: String) -> Int {
            queue.sync { discoveredLimits[routeHealthKey] ?? defaultConcurrencyLimit }
        }

        // MARK: - Persistence

        func persistLocked(into payload: inout [String: Any]) {
            // Already on caller's queue — safe to read synchronously
            let limits = queue.sync { discoveredLimits }
            guard !limits.isEmpty else { return }
            payload["discovered_concurrency_limits"] = limits
        }

        func loadLocked(from json: [String: Any]) {
            guard let limits = json["discovered_concurrency_limits"] as? [String: Int] else { return }
            queue.sync {
                discoveredLimits = limits
            }
        }

        func forceDiscoveredLimitForTesting(routeHealthKey: String, limit: Int) {
            queue.sync {
                discoveredLimits[routeHealthKey] = limit
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

    private static let proxyPoolToolWorkerPrimaryCandidate = "gpt-5.4(high)"
    private static let publicFactoryWorkerSmartRouterAlias = "proxy-worker-smart-router"
    private static let publicWorkerPoolAliases: Set<String> = [
        "worker",
        "glm-5.1",
        publicFactoryWorkerSmartRouterAlias
    ]
    static func workerPrimaryCandidateModel() -> String {
        smartAliasDefinition(forRequestModel: "worker")?.candidates.first ?? "glm-5.1-zai"
    }

    private static func selfRoutedFactoryWorkerPoolModelID() -> String? {
        guard let bindings = ThinkingProxy.factoryModelBindings(),
              let workerModelID = bindings.authoritativeWorkerModelID,
              let binding = bindings.bindingsByIncomingModelID[workerModelID],
              binding.requestSurface == "chat_completions",
              binding.routeProvider == "generic-chat-completion-api",
              binding.routeModel == workerModelID else {
            return nil
        }
        return workerModelID
    }

    private static func isWorkerPoolPublicAlias(_ requestModel: String) -> Bool {
        if publicWorkerPoolAliases.contains(requestModel) {
            return true
        }
        return selfRoutedFactoryWorkerPoolModelID() == requestModel
    }

    static func smartAliasDefinition(forRequestModel requestModel: String) -> SmartAliasDefinition? {
        let requestModel = normalizedRequestModel(requestModel)
        let smartAliases = configuredRouteConfiguration().smartAliasesByAlias
        if let exact = smartAliases[requestModel] {
            return exact
        }

        // Factory's current worker contract can be self-routed, meaning the custom model ID is both
        // the caller-visible identity and the inner wire model. VibeProxy still owns worker routing,
        // so that self-routed custom ID must inherit the proxy's worker pool even when the merged
        // config only declares the canonical `worker` alias.
        if selfRoutedFactoryWorkerPoolModelID() == requestModel {
            return smartAliases["worker"]
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
        // Factory can also self-route the current worker custom model ID onto the worker pool. In
        // both cases the user-facing worker contract stays stable while VibeProxy still chooses the
        // best runtime lane per request class. These aliases must therefore behave like real smart
        // routers, not single hard-coded backends with friendlier names.
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
        guard isWorkerPoolPublicAlias(publicAlias),
              method == "POST" else {
            return smartAlias.candidates
        }

        guard isChatCompletionsPath(path),
              let primaryCandidate = smartAlias.candidates.first else {
            return smartAlias.candidates
        }

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return [primaryCandidate]
        }

        let hasTools = (json["tools"] as? [Any])?.isEmpty == false
        let hasStructuredOutput = json["response_format"] != nil
        let isOversizedExecPayload = jsonString.utf8.count >= 65536
        let isToolHeavyWorkerRequest = hasTools || hasStructuredOutput || isOversizedExecPayload

        // Factory mission workers send large tool-bearing Exec payloads. Those requests have
        // repeatedly produced success-shaped 200s with empty assistant content from the GLM lane,
        // which breaks the worker contract even though the transport technically succeeded.
        //
        // Tool-heavy worker/smart-router requests use the same health-ranked pool as plain chat.
        // The GPT-5.4 lane was removed after sustained 402/500 failures made it a latency penalty
        // with no reliability upside — the pool candidates (glm-5.1-zai, minimax, kimi, mimo)
        // now carry the full tool-heavy workload with health-ranked failover.
        if isToolHeavyWorkerRequest {
            // Self-routed Factory worker IDs (for example `custom:Proxy-Worker-Smart-Router-8`)
            // must inherit the exact same health-ranked worker pool behavior as the public pooled
            // aliases. If this path falls back to `[primaryCandidate]`, tool-heavy mission workers
            // get pinned back onto GLM even after the route is already quarantined.
            let rankedCandidates = rankedSmartAliasFallbackCandidateModels(
                smartAlias.candidates,
                healthSensitivity: smartAlias.healthSensitivity,
                stickyPrimaryCandidate: primaryCandidate
            )
            if !rankedCandidates.isEmpty {
                return rankedCandidates
            }
            return [primaryCandidate]
        }

        return smartAlias.candidates
    }

    static func forcedSmartAliasProbeCandidateModels(
        forPublicAlias publicAlias: String,
        method: String,
        path: String,
        jsonString: String,
        smartAlias: SmartAliasDefinition
    ) -> Set<String> {
        let effectiveCandidates = effectiveSmartAliasCandidateModels(
            forPublicAlias: publicAlias,
            method: method,
            path: path,
            jsonString: jsonString,
            smartAlias: smartAlias
        )

        guard isWorkerPoolPublicAlias(publicAlias),
              method == "POST",
              isChatCompletionsPath(path),
              effectiveCandidates.count == 1,
              let validatedCandidate = effectiveCandidates.first else {
            return []
        }

        // When a Factory-style worker request is pinned to a single validated lane because the
        // broader pool is not a valid contract for that request class, stale circuit state must
        // not suppress that only safe backend entirely. Probe it directly and let the live attempt
        // decide whether the route is still bad; a success will close the circuit immediately.
        return [validatedCandidate]
    }

    static func smartAliasContractError(forRequestModel requestModel: String) -> ClientFacingNVIDIAFailure? {
        // Validate the internal alias and the one explicit public pooled entrypoint against the same
        // underlying pool contract. `worker` stays proxy-internal; `glm-5.1` is the only remaining
        // external pooled alias.
        guard isWorkerPoolPublicAlias(requestModel),
              let smartAlias = smartAliasDefinition(forRequestModel: requestModel) else {
            return nil
        }

        guard smartAlias.candidates.first == "glm-5.1-zai",
              let primaryRoute = resolveConfiguredRoute(forRequestModel: "glm-5.1-zai"),
              primaryRoute.providerID == "zai",
              primaryRoute.canonicalModelID == "glm-5.1",
              isAnthropicConfiguredRoute(forRequestModel: "glm-5.1-zai") else {
            return ClientFacingNVIDIAFailure(
                statusCode: 500,
                message: "The \(requestModel) pooled alias is misconfigured: primary candidate must resolve to Anthropic-backed Z.AI glm-5.1."
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

    static func nextSmartAliasCandidateTransition(
        method: String,
        path: String,
        currentBody: String,
        candidateModelsRemaining: [String],
        forceAllowClosedModels: Set<String> = []
    ) -> (body: String, model: String, remainingCandidateModels: [String])? {
        var remainingCandidateModels = candidateModelsRemaining
        var skippedReasons: [(model: String, reason: String)] = []

        while !remainingCandidateModels.isEmpty {
            let nextCandidateModel = remainingCandidateModels.removeFirst()
            guard resolveConfiguredRoute(forRequestModel: nextCandidateModel) != nil else {
                skippedReasons.append((nextCandidateModel, "no_route"))
                continue
            }
            guard let candidateBody = rewrittenRequestJSON(
                method: method,
                path: path,
                replacingRequestModelIn: currentBody,
                    with: nextCandidateModel
            ) else {
                skippedReasons.append((nextCandidateModel, "rewrite_failed"))
                continue
            }
            if isConfiguredRouteOpen(forRequestModel: nextCandidateModel) &&
                !forceAllowClosedModels.contains(nextCandidateModel) {
                skippedReasons.append((nextCandidateModel, "route_closed"))
                continue
            }
            if !forceAllowClosedModels.contains(nextCandidateModel),
               let candidateRoute = resolveConfiguredRoute(forRequestModel: nextCandidateModel),
               let cooldownUntil = routeCooldownsByRouteHealthKey[candidateRoute.routeHealthKey],
               Date() < cooldownUntil {
                skippedReasons.append((nextCandidateModel, "provider_cooldown"))
                continue
            }
            if !forceAllowClosedModels.contains(nextCandidateModel),
               let candidateRoute = resolveConfiguredRoute(forRequestModel: nextCandidateModel),
               Self.concurrencyRegistry.isAtCapacity(routeHealthKey: candidateRoute.routeHealthKey) {
                skippedReasons.append((nextCandidateModel, "concurrency_capacity"))
                continue
            }
            return (candidateBody, nextCandidateModel, remainingCandidateModels)
        }

        NSLog("[ThinkingProxy] nextSmartAliasCandidateTransition: no valid candidates. Skipped: %@", skippedReasons)
        return nil
    }

    static func availableSmartAliasCandidateTransitions(
        method: String,
        path: String,
        currentBody: String,
        candidateModelsRemaining: [String],
        forceAllowClosedModels: Set<String> = []
    ) -> [(body: String, model: String)] {
        candidateModelsRemaining.compactMap { candidateModel in
            guard resolveConfiguredRoute(forRequestModel: candidateModel) != nil,
                  (!isConfiguredRouteOpen(forRequestModel: candidateModel) ||
                    forceAllowClosedModels.contains(candidateModel)),
                  let candidateBody = rewrittenRequestJSON(
                    method: method,
                    path: path,
                    replacingRequestModelIn: currentBody,
                    with: candidateModel
                  ) else {
                return nil
            }
            if !forceAllowClosedModels.contains(candidateModel),
               let route = resolveConfiguredRoute(forRequestModel: candidateModel),
               let cooldownUntil = routeCooldownsByRouteHealthKey[route.routeHealthKey],
               Date() < cooldownUntil {
                return nil
            }
            return (candidateBody, candidateModel)
        }
    }

    private static func candidateIsAvailableForStickyPrimaryPreference(_ requestModel: String) -> Bool {
        let now = Date()
        guard let route = resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) else {
            return true
        }

        if let cooldownUntil = routeCooldownsByRouteHealthKey[route.routeHealthKey],
           now < cooldownUntil {
            return false
        }

        guard let state = routeCircuitStatesByRouteHealthKey[route.routeHealthKey] else {
            return true
        }

        return !state.isUnavailable(at: now)
    }

    static func rankedSmartAliasFallbackCandidateModels(
        _ candidateModels: [String],
        healthSensitivity: HealthSensitivity = .balanced,
        stickyPrimaryCandidate: String? = nil
    ) -> [String] {
        let indexedModels = Array(candidateModels.enumerated())
        return routeHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            var rankedModels = indexedModels.sorted { lhs, rhs in
                let lhsScore = smartAliasFallbackRankingScore(forRequestModel: lhs.element, originalIndex: lhs.offset)
                let rhsScore = smartAliasFallbackRankingScore(forRequestModel: rhs.element, originalIndex: rhs.offset)
                if lhsScore.healthPriority != rhsScore.healthPriority {
                    return lhsScore.healthPriority < rhsScore.healthPriority
                }
                // Proven-perfect preference: a model with zero observed failures always
                // beats a model that has seen failures, regardless of score or tier.
                if lhsScore.isProvenPerfect != rhsScore.isProvenPerfect {
                    return lhsScore.isProvenPerfect
                }
                // Hysteresis: only reorder if score gap exceeds sensitivity threshold.
                let scoreGap = lhsScore.compositeScore - rhsScore.compositeScore
                if abs(scoreGap) >= healthSensitivity.scoreGapThreshold {
                    return scoreGap > 0
                }
                return lhsScore.originalIndex < rhsScore.originalIndex
            }.map(\.element)

            if let stickyPrimaryCandidate,
               rankedModels.contains(stickyPrimaryCandidate),
               candidateIsAvailableForStickyPrimaryPreference(stickyPrimaryCandidate) {
                rankedModels.removeAll { $0 == stickyPrimaryCandidate }
                rankedModels.insert(stickyPrimaryCandidate, at: 0)
            }

            return rankedModels
        }
    }

    static func preflightError(method: String, path: String, jsonString: String) -> ClientFacingNVIDIAFailure? {
        guard method == "POST",
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              let route = resolveNVIDIAHostedRoute(forRequestModel: model) else {
            return nil
        }

        if isResponsesPath(path) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "NVIDIA hosted inference does not reliably support /v1/responses via this proxy; use /v1/chat/completions."
            )
        }

        if isNVIDIAHostedRouteOpen(forRequestModel: model) {
            return ClientFacingNVIDIAFailure(
                statusCode: 503,
                message: "This NVIDIA route is temporarily quarantined by the proxy due to repeated upstream failures. Retry later or use another model."
            )
        }

        if isChatCompletionsPath(path),
           containsUnsupportedTypedMessageContent(in: json) {
            return ClientFacingNVIDIAFailure(
                statusCode: 400,
                message: "NVIDIA hosted chat completions currently require string message content; typed content arrays are not supported on this route."
            )
        }

        guard isChatCompletionsPath(path),
              let policy = policy(forModel: model) else {
            return nil
        }

        if policy.clientStreamingMode == .rejectBufferedMitigation,
           requestedStream(forRequestJSON: jsonString) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "Streaming is temporarily disabled for this NVIDIA route in the proxy because full-response normalization is required; use non-streaming chat completions."
            )
        }

        if let tools = json["tools"] as? [Any],
           !tools.isEmpty,
           requestedStream(forRequestJSON: jsonString) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "Streaming NVIDIA tool calls are not reliably supported through this proxy; use non-streaming chat completions."
            )
        }

        if policy.toolChoiceMode == .rejectRequiredOrFunctionChoice,
           hasStrictToolChoice(in: json) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "This NVIDIA route does not reliably preserve required/function tool-choice semantics through the proxy; use tool_choice=auto or another provider."
            )
        }

        _ = route
        return nil
    }

    static func configuredRoutePreflightError(method: String, path: String, jsonString: String) -> ClientFacingNVIDIAFailure? {
        guard method == "POST",
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              let route = resolveConfiguredRoute(forRequestModel: model) else {
            return nil
        }

        if route.providerID == "zai",
           route.canonicalModelID == "glm-5.1",
           isResponsesPath(path) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "Z.AI glm-5.1 does not provide a reliable /v1/responses surface via this proxy; use Anthropic /v1/messages or /v1/chat/completions."
            )
        }

        return preflightError(method: method, path: path, jsonString: jsonString)
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
        // in their policy but must NOT enter this path — the NVIDIA path delivers
        // buffered responses and cannot synthesize SSE for streaming clients.
        guard resolveNVIDIAHostedRoute(forRequestModel: normalizedRequestModel(model)) != nil else {
            return false
        }

        guard let policy = policy(forModel: model) else {
            return false
        }
        return policy.clientStreamingMode == .rejectBufferedMitigation || !policy.retryableFailureClasses.isEmpty
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

    static func attemptTimeout(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.attemptTimeout
    }

    static func attemptTimeout(forRequestModel requestModel: String) -> TimeInterval? {
        policy(forModel: requestModel)?.attemptTimeout
    }

    static func firstResponseDeadline(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.firstResponseDeadline
    }

    static func effectiveFirstResponseDeadline(
        forRequestJSON jsonString: String,
        routeHealthStatus: RouteHealthStatus?
    ) -> TimeInterval? {
        // Note: Previously this applied deadline reduction for suspect/open routes.
        // That behavior caused premature timeouts on slow but valid NVIDIA lanes.
        // Now we preserve the base deadline regardless of health status - the circuit
        // breaker already handles route selection, so deadlines shouldn't shrink.
        return firstResponseDeadline(forRequestJSON: jsonString)
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
            bodyData: bodyData
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
        attemptLane: Int = 1
    ) -> RouteTelemetryEvent {
        let canonicalModelID = resolveConfiguredRoute(forRequestModel: state.model)?.canonicalModelID ?? state.model
        let retryCount = max(0, state.initialTransportRetries - state.transportRetriesRemaining) +
            max(0, state.initialSemanticRetries - state.semanticRetriesRemaining)
        let upstreamHTTPStatus = attempt.response?.statusCode

        if let error = attempt.error {
            let failureClass: String
            if attempt.deadlineStage != .none {
                failureClass = "transport_timeout"
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
                totalLatencyMilliseconds: attempt.totalLatencyMilliseconds
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
            return RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: state.model,
                canonicalModelID: canonicalModelID,
                transportOutcome: outcomeTelemetryLabel(outcome),
                attemptLane: attemptLane,
                failureClass: "classified_\(classifiedFailure.statusCode)",
                timeoutStage: attempt.deadlineStage,
                upstreamHTTPStatus: response.statusCode,
                retryCount: retryCount,
                source: source,
                firstByteLatencyMilliseconds: attempt.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: attempt.totalLatencyMilliseconds
            )
        }

        if let response = attempt.response,
           let bodyData = attempt.data {
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
                totalLatencyMilliseconds: attempt.totalLatencyMilliseconds
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
            totalLatencyMilliseconds: attempt.totalLatencyMilliseconds
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
                    return candidates.sorted { lhs, rhs in
                        let lhsIsCanonical = routes[lhs]?.canonicalModelID == lhs
                        let rhsIsCanonical = routes[rhs]?.canonicalModelID == rhs
                        if lhsIsCanonical != rhsIsCanonical {
                            return !lhsIsCanonical
                        }
                        if lhs.count != rhs.count {
                            return lhs.count < rhs.count
                        }
                        return lhs < rhs
                    }.first
                }
                return routeHealthKey.components(separatedBy: "::").last
            }.sorted()
        }
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
            // halfOpen routes are probeable — allow them through for candidate selection
            // so the circuit breaker recovery mechanism can test the route.
            if state.status == .halfOpen { return nil }
            return state.isUnavailable(at: now) ? state.status : nil
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
    private static let failureDedupWindow: TimeInterval = 0.5  // 0.5 second window for burst deduplication
    private static var disableFailureDedupForTesting = false
    
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
            
            // Always count failures — the circuit breaker threshold dampens rapid failures naturally
            
            // Feed concurrency registry for 429 responses
            if let fc = telemetryEvent?.failureClass, fc == "classified_429",
               let inflight = telemetryEvent?.inflightAtRequest {
                concurrencyRegistry.record429(routeHealthKey: route.routeHealthKey, inflightAtRequest: inflight)
            }

            var nextState = nextRouteCircuitState(
                current: current,
                afterFailureAt: now,
                telemetryEvent: telemetryEvent,
                policy: routeCircuitBreakerPolicy,
                forcedOpenUntil: forcedOpenUntil,
                healthSensitivity: healthSensitivity
            )
            let enrichedTelemetryEvent = telemetryEvent.map {
                enrichTelemetryEvent($0, from: current?.status ?? .closed, to: nextState.status)
            }
            nextState = routeCircuitState(
                nextState,
                replacingLastTelemetryEvent: enrichedTelemetryEvent
            )
            routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = nextState
            if let cooldownUntil = forcedOpenUntil, now < cooldownUntil {
                routeCooldownsByRouteHealthKey[route.routeHealthKey] = cooldownUntil
            }
            scheduleRouteHealthPersistLocked()
            if let enrichedTelemetryEvent {
                logNVIDIARouteTelemetry(enrichedTelemetryEvent)
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
            nextState = routeCircuitState(
                nextState,
                replacingLastTelemetryEvent: enrichedTelemetryEvent
            )
            routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = nextState
            concurrencyRegistry.recordSuccess(routeHealthKey: route.routeHealthKey)
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
            hasLoadedPersistedRouteHealth = true
            persistRouteHealthLocked()
        }
        routeFailureDedupQueue.sync {
            recentFailureTimestampsByRoute = [:]
        }
    }

    static func forceOpenRouteForTesting(requestModel: String, until: Date) {
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
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
                recoveredAt: nil
            )
            persistRouteHealthLocked()
        }
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

    static func reloadPersistedRouteHealthForTesting() {
        routeHealthQueue.sync {
            routeHealthPersistWorkItem?.cancel()
            routeHealthPersistWorkItem = nil
            routeHealthDirty = false
            hasLoadedPersistedRouteHealth = false
            routeCircuitStatesByRouteHealthKey = [:]
            routeCooldownsByRouteHealthKey = [:]
            loadPersistedRouteHealthIfNeededLocked()
        }
    }

    static func forcePersistRouteHealthForTesting() {
        routeHealthQueue.sync {
            forcePersistRouteHealthLocked()
        }
    }

    static func evaluateNvidiaReasoningResponse(model: String, statusCode: Int, bodyData: Data) -> NvidiaReasoningEvaluation {
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
        switch validateToolCalls(in: message) {
        case .invalid:
            return retryEvaluation(
                for: .malformedToolArguments,
                policy: policy,
                repairedBodyData: nil,
                normalizedBodyData: nil
            )
        case .valid:
            return NvidiaReasoningEvaluation(
                failureClass: nil,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
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

    static func providerCooldownUntil(
        statusCode: Int,
        headers: [AnyHashable: Any],
        bodyData: Data? = nil,
        now: Date = Date()
    ) -> Date? {
        guard statusCode == 429 else { return nil }

        let concurrencyThreshold: TimeInterval = 300
        let maxProviderCooldown: TimeInterval = 600

        // --- Retry-After header ---
        if let retryAfter = headerValue("Retry-After", in: headers)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !retryAfter.isEmpty {
            if let seconds = TimeInterval(retryAfter), seconds > 0 {
                if seconds < concurrencyThreshold {
                    NSLog("[ThinkingProxy] Concurrency 429 detected (Retry-After: %.0fs < %.0fs threshold) - not cooling down route", seconds, concurrencyThreshold)
                    return nil
                }
                let capped = min(seconds, maxProviderCooldown)
                NSLog("[ThinkingProxy] Provider 429 Retry-After: %.0fs — capping cooldown to %.0fs", seconds, capped)
                return now.addingTimeInterval(capped)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: retryAfter) {
                let seconds = date.timeIntervalSince(now)
                if seconds <= 0 { return nil }
                if seconds < concurrencyThreshold {
                    NSLog("[ThinkingProxy] Concurrency 429 detected (Retry-After HTTP-date %.0fs < %.0fs threshold) - not cooling down route", seconds, concurrencyThreshold)
                    return nil
                }
                let cappedSeconds = min(seconds, maxProviderCooldown)
                NSLog("[ThinkingProxy] Provider 429 Retry-After HTTP-date: %.0fs — capping cooldown to %.0fs", seconds, cappedSeconds)
                return now.addingTimeInterval(cappedSeconds)
            }
        }

        // --- Body-embedded reset time (e.g. GLM: "will reset at YYYY-MM-DD HH:mm:ss") ---
        if let bodyData,
           let bodyString = String(data: bodyData, encoding: .utf8),
           let range = bodyString.range(of: #"will reset at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"#,
                                        options: .regularExpression) {
            let full = String(bodyString[range])
            let timestamp = String(full.dropFirst("will reset at ".count))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            // GLM timestamps are in CST (UTC+8)
            formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
            if let resetDate = formatter.date(from: timestamp) {
                let seconds = resetDate.timeIntervalSince(now)
                if seconds > 0 {
                    let cappedSeconds = min(seconds, maxProviderCooldown)
                    NSLog("[ThinkingProxy] GLM rate-limit 429: cooldown until %@ (%.0fs — capping to %.0fs)", timestamp, seconds, cappedSeconds)
                    return now.addingTimeInterval(cappedSeconds)
                }
            }
        }

        return nil
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
        telemetryEvent: RouteTelemetryEvent?,
        policy: RouteCircuitBreakerPolicy? = nil,
        forcedOpenUntil: Date? = nil,
        healthSensitivity: HealthSensitivity? = nil
    ) -> RouteCircuitState {
        let effectivePolicy = policy ?? routeCircuitBreakerPolicy
        let failurePenalty = failurePenalty(for: telemetryEvent)
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
                recoveredAt: nil
            )
        }

        switch current?.status ?? .closed {
        case .closed, .suspect:
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
                    recoveredAt: nil
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
                recoveredAt: nil
            )
        case .open, .halfOpen:
            return RouteCircuitState(
                status: .open,
                failureScore: failureThreshold,
                recoverySuccesses: 0,
                openUntil: now.addingTimeInterval(effectivePolicy.cooldown),
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics,
                emaMetrics: nextEMA,
                recoveredAt: nil
            )
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
                recoveredAt: nil
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
                    recoveredAt: nil
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
                recoveredAt: nil
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
                    recoveredAt: now
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
                recoveredAt: nil
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
                    recoveredAt: now
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
                recoveredAt: nil
            )
        }
    }

    private static func routeCircuitState(
        _ state: RouteCircuitState,
        replacingLastTelemetryEvent telemetryEvent: RouteTelemetryEvent?
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
            recoveredAt: state.recoveredAt
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
            totalLatencyMilliseconds: event.totalLatencyMilliseconds
        )
    }

    private static func healthTransitionLabel(from previousStatus: RouteHealthStatus, to nextStatus: RouteHealthStatus) -> String? {
        guard previousStatus != nextStatus else { return nil }
        return "\(previousStatus.rawValue)->\(nextStatus.rawValue)"
    }

    private static func failurePenalty(for telemetryEvent: RouteTelemetryEvent?) -> Int {
        guard let failureClass = telemetryEvent?.failureClass?.lowercased() else {
            return 1
        }

        // 429 rate-limit responses indicate concurrency oversubscription, not route health issues.
        // The concurrency registry handles backing off; the circuit breaker should not penalize.
        if failureClass == "classified_429" {
            return 0
        }

        if failureClass == "transport_error" ||
            failureClass == "missing_response_material" ||
            failureClass.hasPrefix("classified_5") {
            return 2
        }

        return 1
    }

    private static func decayedFailureScore(
        _ failureScore: Int,
        lastUpdatedAt: Date?,
        now: Date
    ) -> Int {
        guard failureScore > 0,
              let lastUpdatedAt else {
            return failureScore
        }
        let elapsed = max(0, now.timeIntervalSince(lastUpdatedAt))
        guard elapsed >= routeFailureScoreDecayInterval else {
            return failureScore
        }
        let decaySteps = Int(elapsed / routeFailureScoreDecayInterval)
        return max(0, failureScore - decaySteps)
    }

    private static func effectiveFailureThreshold(
        policy: RouteCircuitBreakerPolicy,
        healthSensitivity: HealthSensitivity? = nil
    ) -> Int {
        let baseThreshold = policy.failureThreshold
        guard let sensitivity = healthSensitivity, sensitivity != .balanced else {
            return baseThreshold
        }
        return max(1, Int(Double(baseThreshold) * sensitivity.failureThresholdScaleFactor))
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

        return RouteRollingMetrics(
            requestCount: prior.requestCount + 1,
            successCount: prior.successCount + (telemetryEvent.failureClass == nil ? 1 : 0),
            timeoutCount: prior.timeoutCount + (telemetryEvent.failureClass == "transport_timeout" ? 1 : 0),
            invalidSuccessCount: prior.invalidSuccessCount + (isInvalidSuccessFailureClass(telemetryEvent.failureClass) ? 1 : 0),
            recentOutcomes: recentOutcomes,
            recentFirstByteLatencyMilliseconds: recentFirstByteLatencyMilliseconds
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
            return 90
        }
        if metrics.invalidSuccessRate >= 0.5 {
            return 15
        }
        if let averageFirstByteLatencyMilliseconds = metrics.averageFirstByteLatencyMilliseconds,
           averageFirstByteLatencyMilliseconds >= 60_000 {
            return 60
        }
        if metrics.timeoutRate >= 0.5 {
            return 45
        }
        if let averageFirstByteLatencyMilliseconds = metrics.averageFirstByteLatencyMilliseconds,
           averageFirstByteLatencyMilliseconds >= 20_000 {
            return 45
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
        let adjustedScore = (ema.compositeScore + momentum) * tier.rawValue
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
        #if DEBUG
        _ = _assertKnownNVIDIARoutesHaveNoDuplicates
        _ = _assertModelTiersHaveNoDuplicates
        _ = _assertNonNVIDIAPoliciesHaveNoDuplicates
        _ = _assertLegacyRewritesHaveNoDuplicates
        #endif
        guard let path = routeHealthStatePath(),
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? Int, version >= 1, version <= 3,
              let routes = json["routes"] as? [String: [String: Any]] else {
            routeCircuitStatesByRouteHealthKey = [:]
            return
        }

        var loaded: [String: RouteCircuitState] = [:]
        let configuredRouteHealthKeys = Set(resolvedRoutesByRequestModel().values.map(\.routeHealthKey))
        let oauthProviderIDs = Set(ProviderCatalog.oauthPassthroughPrefixes.map(\.providerID))
        var prunedUnknownEntries = false
        for (routeHealthKey, entry) in routes {
            let components = routeHealthKey.components(separatedBy: "::")
            let providerID = components.first
            let isKnownRoute = configuredRouteHealthKeys.contains(routeHealthKey)
            let isOAuthRoute = (components.count == 2 && providerID.map { oauthProviderIDs.contains($0) } == true)
            guard isKnownRoute || isOAuthRoute else {
                prunedUnknownEntries = true
                continue
            }
            let status = (entry["status"] as? String)
                .flatMap(RouteHealthStatus.init(rawValue:))
                ?? ((parseISO8601Date(entry["open_until"]) != nil) ? .open : .closed)
            let failureScore = entry["failure_score"] as? Int ?? entry["consecutive_failures"] as? Int ?? 0
            let recoverySuccesses = entry["recovery_successes"] as? Int ?? 0
            let openUntil = parseISO8601Date(entry["open_until"])
            let lastScoreUpdatedAt = parseISO8601Date(entry["last_score_updated_at"])
            let lastTelemetryEvent = parseTelemetryEvent(entry["last_event"])
            let rollingMetrics = parseRollingMetrics(entry["rolling_metrics"])
            loaded[routeHealthKey] = RouteCircuitState(
                status: status,
                failureScore: failureScore,
                recoverySuccesses: recoverySuccesses,
                openUntil: openUntil,
                lastScoreUpdatedAt: lastScoreUpdatedAt,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: rollingMetrics,
                emaMetrics: parseEMAMetrics(entry["ema_metrics"]),
                recoveredAt: parseISO8601Date(entry["recovered_at"] as? String)
            )
        }
        routeCircuitStatesByRouteHealthKey = loaded
        // Load cooldowns — prefer new route-level key, fall back to legacy provider-level key
        let cooldownSource: [String: String] = (json["route_cooldowns"] as? [String: String])
            ?? (json["provider_cooldowns"] as? [String: String])
            ?? [:]
        if !cooldownSource.isEmpty {
            let now = Date()
            let maxLoadedCooldown: TimeInterval = 3600
            for (routeKey, dateString) in cooldownSource {
                if let date = parseISO8601Date(dateString), date > now {
                    let capped = min(date, now.addingTimeInterval(maxLoadedCooldown))
                    routeCooldownsByRouteHealthKey[routeKey] = capped
                }
            }
        }
        concurrencyRegistry.loadLocked(from: json)
        if prunedUnknownEntries {
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

        healStaleSuspectRoutesLocked()
        healStaleOpenRoutesLocked()
    }

    /// On startup, promote stale `open` routes to `suspect` so they can be
    /// re-evaluated by the self-heal pass instead of remaining permanently
    /// circuit-broken from a prior proxy lifecycle.
    private static func healStaleOpenRoutesLocked() {
        let cooldownThreshold: TimeInterval = 120  // match RouteCircuitBreakerPolicy.cooldown
        let now = Date()
        var healedAny = false
        for key in routeCircuitStatesByRouteHealthKey.keys {
            guard let state = routeCircuitStatesByRouteHealthKey[key],
                  state.status == .open else { continue }

            // If the open-until deadline has already passed, or the route has
            // been stale longer than the cooldown, demote to suspect so the
            // normal self-heal logic can evaluate it.
            let openExpired = state.openUntil.map { now >= $0 } ?? true
            let lastActivity = state.lastTelemetryEvent?.timestamp ?? state.lastScoreUpdatedAt
            let staleness = lastActivity.map { now.timeIntervalSince($0) } ?? 0
            guard openExpired || staleness > cooldownThreshold else { continue }

            NSLog("[ThinkingProxy] Startup heal: demoting stale open route %@ to suspect (staleness: %.0fs, openExpired: %@)", key, staleness, String(describing: openExpired))
            routeCircuitStatesByRouteHealthKey[key] = RouteCircuitState(
                status: .suspect,
                failureScore: min(state.failureScore, 2),  // cap so it can recover quickly
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: state.lastTelemetryEvent,
                rollingMetrics: state.rollingMetrics,
                emaMetrics: state.emaMetrics,
                recoveredAt: nil
            )
            healedAny = true
        }
        if healedAny {
            healStaleSuspectRoutesLocked()  // immediately evaluate the freshly demoted routes
        }
    }

    /// Heal suspect routes whose last telemetry event is older than the stale threshold.
    /// Must be called on routeHealthQueue. Used by both startup load and background maintenance.
    /// Routes with strong EMA success rates (>80%) get a shorter threshold (60s) since a single
    /// transient failure is unlikely to indicate a sustained outage.
    private static func healStaleSuspectRoutesLocked() {
        let defaultStaleThreshold: TimeInterval = 5 * 60  // 5 minutes
        let healthyEmaStaleThreshold: TimeInterval = 60    // 1 minute for historically healthy routes
        let healthyEmaThreshold: Double = 0.8
        let now = Date()
        var healedAny = false
        for key in routeCircuitStatesByRouteHealthKey.keys {
            guard let state = routeCircuitStatesByRouteHealthKey[key],
                  state.status == .suspect else { continue }

            let lastActivityDate: Date
            if let lastEvent = state.lastTelemetryEvent {
                lastActivityDate = lastEvent.timestamp
            } else if let lastUpdate = state.lastScoreUpdatedAt {
                lastActivityDate = lastUpdate
            } else {
                continue
            }

            let emaSuccessRate = state.emaMetrics.successRate
            let staleThreshold = emaSuccessRate >= healthyEmaThreshold ? healthyEmaStaleThreshold : defaultStaleThreshold

            let age = now.timeIntervalSince(lastActivityDate)
            guard age > staleThreshold else {
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
                recoveredAt: now
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
        }
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

    private static func persistRouteHealthLocked() {
        dispatchPrecondition(condition: .onQueue(routeHealthQueue))
        guard let path = routeHealthStatePath() else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var routes: [String: [String: Any]] = [:]
        for (routeHealthKey, state) in routeCircuitStatesByRouteHealthKey {
            var entry: [String: Any] = [
                "status": state.status.rawValue,
                "failure_score": state.failureScore,
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
            routes[routeHealthKey] = entry
        }

        let activeCooldowns = routeCooldownsByRouteHealthKey.filter { $0.value > Date() }.mapValues { iso8601String(from: $0) }
        var payload: [String: Any] = [
            "version": 3,
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
            totalLatencyMilliseconds: integerValue(dict["total_latency_ms"])
        )
    }

    private static func rollingMetricsDictionary(_ metrics: RouteRollingMetrics) -> [String: Any] {
        [
            "request_count": metrics.requestCount,
            "success_count": metrics.successCount,
            "timeout_count": metrics.timeoutCount,
            "invalid_success_count": metrics.invalidSuccessCount,
            "recent_outcomes": metrics.recentOutcomes,
            "recent_first_byte_latency_ms": metrics.recentFirstByteLatencyMilliseconds
        ]
    }

    private static func emaMetricsDictionary(_ metrics: RouteEMAMetrics) -> [String: Any] {
        [
            "success_rate": metrics.successRate,
            "average_latency_ms": metrics.averageLatencyMs,
            "observation_count": metrics.observationCount
        ]
    }

    private static func parseRollingMetrics(_ rawValue: Any?) -> RouteRollingMetrics {
        guard let dict = rawValue as? [String: Any] else {
            return .empty
        }
        return RouteRollingMetrics(
            requestCount: integerValue(dict["request_count"]) ?? 0,
            successCount: integerValue(dict["success_count"]) ?? 0,
            timeoutCount: integerValue(dict["timeout_count"]) ?? 0,
            invalidSuccessCount: integerValue(dict["invalid_success_count"]) ?? 0,
            recentOutcomes: dict["recent_outcomes"] as? [String] ?? [],
            recentFirstByteLatencyMilliseconds: dict["recent_first_byte_latency_ms"] as? [Int] ?? []
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
            totalLatencyMilliseconds: event.totalLatencyMilliseconds
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

    private static func containsUnsupportedTypedMessageContent(in json: [String: Any]) -> Bool {
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
        guard let segments = content as? [Any] else {
            return .unchanged
        }

        var collectedSegments: [String] = []
        for segment in segments {
            if let textSegment = segment as? String {
                collectedSegments.append(textSegment)
                continue
            }

            guard let dictionary = segment as? [String: Any] else {
                return .unsupported
            }

            let type = (dictionary["type"] as? String)?.lowercased()
            let textValue = dictionary["text"] as? String

            if let textValue,
               type == nil || type == "text" || type == "input_text" {
                collectedSegments.append(textValue)
                continue
            }

            return .unsupported
        }

        guard !collectedSegments.isEmpty else {
            return .unsupported
        }

        return .flattened(collectedSegments.joined())
    }

    fileprivate static func validateToolCalls(in message: [String: Any]) -> ToolCallValidation {
        guard let toolCalls = message["tool_calls"] as? [[String: Any]],
              !toolCalls.isEmpty else {
            return .none
        }

        for toolCall in toolCalls {
            guard let function = toolCall["function"] as? [String: Any],
                  let arguments = function["arguments"] as? String else {
                return .invalid
            }

            let trimmedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedArguments.isEmpty else {
                return .invalid
            }
            guard let argumentsData = trimmedArguments.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: argumentsData),
                  jsonObject is [String: Any] else {
                return .invalid
            }
        }

        return .valid
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

    private static let managedResolvedRoutesByRequestModel: [String: RouteIdentity] = [
        proxyPoolToolWorkerPrimaryCandidate: RouteIdentity(
            providerID: "openai",
            canonicalModelID: proxyPoolToolWorkerPrimaryCandidate
        )
    ]

    private static func resolvedRoutesByRequestModel() -> [String: RouteIdentity] {
        var routes = configuredRouteConfiguration().routesByRequestModel
        for (requestModel, routeIdentity) in managedResolvedRoutesByRequestModel {
            routes[requestModel] = routeIdentity
        }
        return routes
    }

    static func resolveConfiguredRoute(forRequestModel model: String) -> RouteIdentity? {
        resolvedRoutesByRequestModel()[normalizedRequestModel(model)]
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

            var provider = currentProvider ?? ParsedProvider()
            provider.models.append(ParsedModel(alias: trimmedAlias, name: canonicalModelID))
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
                routesByRequestModel[canonicalModelID] = routeIdentity
                if isNVIDIAProvider {
                    nvidiaRoutesByRequestModel[canonicalModelID] = routeIdentity
                }
                if section == .claudeAPIKey {
                    anthropicRequestModels.insert(canonicalModelID)
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
                        apiKey: provider.apiKey
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

            // Capture first API key from api-key-entries (for direct proxied requests)
            if indent == 4, trimmed.hasPrefix("api-key: "), let value = scalarValue(from: trimmed),
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

    private static func hasStrictToolChoice(in json: [String: Any]) -> Bool {
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

    private struct FactoryWorkerContract {
        let workerModelID: String
        let validationWorkerModelID: String?
        let workerReasoningEffort: String?
        let validationWorkerReasoningEffort: String?
        let routeModel: String
        let routeProvider: String
        let requestSurface: String
        let effectiveRouteModel: String
        let effectiveRouteProvider: String?
        let displayName: String?
        let baseURL: String?
        let routeHealthStatus: String?
        let authoritativeSettingsPath: String
        let snapshotDriftPaths: [String]

        var blockingSnapshotDriftPaths: [String] {
            ThinkingProxy.blockingFactoryWorkerSnapshotDriftPaths(snapshotDriftPaths)
        }

        var ready: Bool {
            blockingSnapshotDriftPaths.isEmpty &&
                routeHealthStatus != OpenAICompatTemporaryShim.RouteHealthStatus.open.rawValue
        }
    }

    private struct FactoryRoleContract {
        let modelID: String
        let reasoningEffort: String?
        let routeModel: String
        let routeProvider: String
        let requestSurface: String
        let effectiveRouteModel: String
        let effectiveRouteProvider: String?
        let displayName: String?
        let baseURL: String?
        let routeHealthStatus: String?

        var ready: Bool {
            routeHealthStatus != OpenAICompatTemporaryShim.RouteHealthStatus.open.rawValue
        }
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

        init(
            data: Data?,
            response: HTTPURLResponse?,
            error: Error?,
            firstByteLatencyMilliseconds: Int? = nil,
            totalLatencyMilliseconds: Int? = nil
        ) {
            self.data = data
            self.response = response
            self.error = error
            self.firstByteLatencyMilliseconds = firstByteLatencyMilliseconds
            self.totalLatencyMilliseconds = totalLatencyMilliseconds
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
            telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent?
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
    var nvidiaCanaryTransportForTesting: ((String, String, @escaping (Data?, HTTPURLResponse?, Error?) -> Void) -> Void)?
    var bufferedProxyTransportForTesting: ((String, String, [(String, String)], String, TimeInterval, @escaping (BufferedProxyResponse) -> Void) -> Void)?
    var bufferedProxyCancelableTransportForTesting: ((String, String, [(String, String)], String, TimeInterval, @escaping (BufferedProxyResponse) -> Void) -> (() -> Void))?
    var directProxiedTransportForTesting: ((URLRequest, OpenAICompatTemporaryShim.ProviderEndpoint, @escaping (BufferedProxyResponse) -> Void) -> (() -> Void))?
    var deliveredHTTPResponseForTesting: ((Int, [AnyHashable: Any], Data) -> Void)?
    var deliveredErrorForTesting: ((Int, String) -> Void)?
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
        static let defaultMitigatedAttemptTimeout: TimeInterval = 30
        static let nvidiaCanaryTimeout: TimeInterval = 300
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

    final class SmartAliasCandidateController {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.smart-alias-candidate")
        private var cancelled = false
        private var currentCancel: (() -> Void)?
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
            let canceler: (() -> Void)? = stateQueue.sync {
                guard !cancelled else { return nil }
                cancelled = true
                let currentCancel = self.currentCancel
                self.currentCancel = nil
                scheduledRetryWorkItem?.cancel()
                scheduledRetryWorkItem = nil
                return currentCancel
            }
            canceler?()
        }

        func isCancelled() -> Bool {
            stateQueue.sync { cancelled }
        }
    }

    private final class ResponseProgressDelegate: NSObject, URLSessionDataDelegate {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-first-response")
        private var tracker = OpenAICompatTemporaryShim.ResponseDeadlineTracker()
        private var firstResponseDeadlineWorkItem: DispatchWorkItem?
        private var bufferedResponseDeadlineWorkItem: DispatchWorkItem?
        private let startedAt = Date()
        private var firstPayloadAt: Date?

        func installDeadlines(
            firstResponseSeconds: TimeInterval?,
            bufferedResponseSeconds: TimeInterval?,
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
        }

        func finish() {
            stateQueue.sync {
                tracker.finish()
                firstResponseDeadlineWorkItem?.cancel()
                bufferedResponseDeadlineWorkItem?.cancel()
                firstResponseDeadlineWorkItem = nil
                bufferedResponseDeadlineWorkItem = nil
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
        }
    }

    private static let proxiedPoolQueue = DispatchQueue(label: "io.automaze.vibeproxy.proxied-session-pool")
    private static var proxiedSessionPool: [String: (session: URLSession, delegate: MultiplexedSessionDelegate, lastUsed: Date)] = [:]
    private static let proxiedPoolMaxSize = 8
    private static let proxiedPoolIdleEviction: TimeInterval = 300

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

    private static let directPoolQueue = DispatchQueue(label: "io.automaze.vibeproxy.direct-session-pool")
    private static var directSessionPool: [String: (session: URLSession, lastUsed: Date)] = [:]
    private static let directPoolMaxSize = 8
    private static let directPoolIdleEviction: TimeInterval = 300

    static func acquireDirectSession(key: String) -> URLSession? {
        directPoolQueue.sync {
            evictIdleDirectSessionsLocked()

            if let existing = directSessionPool[key] {
                directSessionPool[key] = (existing.session, lastUsed: Date())
                return existing.session
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 300
            let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)

            if directSessionPool.count >= directPoolMaxSize {
                if let oldestKey = directSessionPool.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
                    directSessionPool[oldestKey]?.session.finishTasksAndInvalidate()
                    directSessionPool.removeValue(forKey: oldestKey)
                }
            }

            directSessionPool[key] = (session, lastUsed: Date())
            return session
        }
    }

    /// Remove a session from the pool and invalidate it.  Call this in the
    /// completion handler of a data task that was obtained from
    /// ``acquireDirectSession(key:)`` so that a subsequent request never
    /// picks up an already-invalidated session from the pool.
    static func removeDirectSession(key: String, session: URLSession) {
        directPoolQueue.sync {
            // Only remove if the pooled entry is the exact same session instance.
            if directSessionPool[key]?.session === session {
                directSessionPool.removeValue(forKey: key)
            }
        }
        session.finishTasksAndInvalidate()
    }

    private static func evictIdleDirectSessionsLocked() {
        let now = Date()
        let stale = directSessionPool.filter { now.timeIntervalSince($0.value.lastUsed) > directPoolIdleEviction }
        for (key, entry) in stale {
            entry.session.finishTasksAndInvalidate()
            directSessionPool.removeValue(forKey: key)
        }
    }

    static func clearDirectSessionPoolForTesting() {
        directPoolQueue.sync {
            for (_, entry) in directSessionPool {
                entry.session.finishTasksAndInvalidate()
            }
            directSessionPool = [:]
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
            Self.clearDirectSessionPoolForTesting()
            nvidiaInflightQueue.sync {
                nvidiaRaceWaiters.removeAll()
                inflightCoalescedRequests.removeAll()
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
        NSLog("[ThinkingProxy] Incoming request: \(method) \(path)")

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
                let failoverBody = clientRequestedStream
                    ? (forcingNonStreamChatRequestBody(from: executionPlan.body) ?? executionPlan.body)
                    : executionPlan.body
                let effectiveCandidateModels = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: requestModel,
                    method: method,
                    path: executionPlan.path,
                    jsonString: failoverBody,
                    smartAlias: smartAlias
                )
                let forceProbeCandidateModels = OpenAICompatTemporaryShim.forcedSmartAliasProbeCandidateModels(
                    forPublicAlias: requestModel,
                    method: method,
                    path: executionPlan.path,
                    jsonString: failoverBody,
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
                    if let coalescingKey,
                       !registerOrJoinInflightRequest(key: coalescingKey, connection: connection) {
                        NSLog("[ThinkingProxy] Joined coalesced smart-alias request for %@", publicAlias)
                        return
                    }
                    forwardSmartAliasRequest(
                        method: method,
                        path: executionPlan.path,
                        headers: headers,
                        body: failoverBody,
                        publicAlias: publicAlias,
                        candidateModels: effectiveCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels,
                        originalConnection: connection,
                        coalescingKey: coalescingKey,
                        deliveryMode: executionPlan.deliveryMode
                    )
                    return
                }

                if method == "POST" {
                    forwardSmartAliasRequest(
                        method: method,
                        path: executionPlan.path,
                        headers: headers,
                        body: failoverBody,
                        publicAlias: publicAlias,
                        candidateModels: effectiveCandidateModels,
                        forceProbeCandidateModels: forceProbeCandidateModels,
                        originalConnection: connection,
                        coalescingKey: nil,
                        deliveryMode: executionPlan.deliveryMode
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
                jsonString: modifiedBody
            ) {
                NSLog("[ThinkingProxy] NVIDIA preflight mitigation blocked request for \(rewrittenPath): \(preflightError.message)")
                sendError(to: connection, statusCode: preflightError.statusCode, message: preflightError.message)
                return
            }
        }

        // Direct proxied path for providers with per-provider proxy-url (e.g., opencode via SOCKS5)
        // Must be checked before NVIDIA reasoning path to intercept proxied provider requests
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
                originalConnection: connection
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
            NSLog("[ThinkingProxy] Factory-bound dispatch: model=%@ path=%@ deliveryMode=%@", factoryModelBinding.routeModel, rewrittenPath, String(describing: factoryBoundExecutionPlan.deliveryMode))
            forwardBufferedFactoryBoundRequest(
                method: method,
                path: rewrittenPath,
                headers: headers,
                body: factoryBoundExecutionPlan.body,
                binding: factoryModelBinding,
                deliveryMode: factoryBoundExecutionPlan.deliveryMode,
                originalConnection: connection
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
            if let coalescingKey,
               !registerOrJoinInflightRequest(key: coalescingKey, connection: connection) {
                NSLog("[ThinkingProxy] Joined coalesced NVIDIA request for %@", model)
                return
            }
            forwardNvidiaReasoningRequest(
                method: method,
                path: rewrittenPath,
                headers: headers,
                body: modifiedBody,
                originalConnection: connection,
                state: OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: model,
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
        deliveryMode: SmartAliasDeliveryMode
    ) {
        attemptSmartAliasCandidate(
            method: method,
            path: path,
            headers: headers,
            currentBody: body,
            publicAlias: publicAlias,
            remainingCandidateModels: candidateModels,
            forceProbeCandidateModels: forceProbeCandidateModels,
            primaryProbeRetriesRemaining: forceProbeCandidateModels.isEmpty ? 0 : smartAliasForcedPrimaryRetryLimit,
            failoverDepth: 0,
            deadlineAt: Date().addingTimeInterval(smartAliasTotalTimeout(forRequestJSON: body)),
            originalConnection: originalConnection,
            coalescingKey: coalescingKey,
            terminalFallbackOutcome: nil,
            deliveryMode: deliveryMode,
            loopRetriesRemaining: smartAliasLoopRetryLimitOverrideForTesting ?? smartAliasMaxLoopRetries
        )
    }

    private func forwardBufferedFactoryBoundRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        binding: FactoryModelBinding,
        deliveryMode: FactoryBoundDeliveryMode = .bufferedJSON,
        originalConnection: NWConnection
    ) {
        let resolvedRequestModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: body) ?? binding.routeModel
        let resolutionHeaders = smartAliasResolutionHeaders(
            publicAlias: binding.incomingModelID,
            resolvedRequestModel: resolvedRequestModel
        )
        let effectiveHeaders = headersInjectingRouteSpecific(headers, forCandidateModel: resolvedRequestModel)
        let timeoutInterval = smartAliasCandidateTimeout(forRequestJSON: body)

        let preservesNativeResponsesSurface =
            binding.requestSurface == "responses" && OpenAICompatTemporaryShim.isResponsesPath(path)

        // Only strip reasoning-effort suffixes when bridging onto a chat-completions
        // execution core. Native responses routes own their qualified model IDs.
        let upstreamBody = Self.rewriteModelForUpstream(
            body: body,
            routeModel: binding.routeModel,
            preserveQualifiedRouteModel: preservesNativeResponsesSurface
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

        sendBufferedProxyRequest(
            method: method,
            path: upstreamPath,
            headers: effectiveHeaders,
            body: upstreamBody,
            timeoutInterval: timeoutInterval
        ) { [weak self] bufferedResponse in
            permit?.release()
            guard let self else { return }

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
                // Masquerade billing/quota errors as rate-limit so the Droid client retries
                // without switching models.  402/403 from upstream look like "provider dead"
                // to the Droid, but 429 triggers its built-in retry logic.
                let effectiveStatusCode: Int
                var effectiveHeaders: [AnyHashable: Any] = response.allHeaderFields
                if response.statusCode == 402 || response.statusCode == 403 {
                    NSLog("[ThinkingProxy] Masquerading upstream %d as 429 for factory-bound model %@", response.statusCode, binding.incomingModelID)
                    effectiveStatusCode = 429
                    effectiveHeaders["Retry-After"] = "30"
                } else {
                    effectiveStatusCode = response.statusCode
                }
                self.deliverBufferedHTTPResponse(
                    defaultConnection: originalConnection,
                    statusCode: effectiveStatusCode,
                    headers: effectiveHeaders,
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
                    guard let bufferedBody = forcingNonStreamChatRequestBody(from: body) else {
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
                guard let bufferedBody = forcingNonStreamChatRequestBody(from: chatBody) else {
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

        guard let bufferedBody = forcingNonStreamChatRequestBody(from: body) else {
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
            return (
                path: OpenAICompatTemporaryShim.chatCompletionsPath(matching: path),
                body: chatBody,
                deliveryMode: clientRequestedStream ? .syntheticResponsesSSE : .bufferedResponsesJSON
            )
        }

        guard OpenAICompatTemporaryShim.isChatCompletionsPath(path) else {
            return nil
        }

        return (
            path: path,
            body: body,
            deliveryMode: clientRequestedStream ? .syntheticSSE : .bufferedJSON
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
        deliveryMode: SmartAliasDeliveryMode,
        loopRetriesRemaining: Int = 0
    ) {
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

        // Non-NVIDIA candidates (glm-5.1-zai, mimo-v2-pro-*, minimax-m2.5-opencode) are tried
        // serially. NVIDIA candidates (minimax-m2.5-nvidia, kimi-k2.5-nvidia) are raced against
        // each other for lowest latency. The prefix scan walks candidates until it finds a
        // contiguous run of NVIDIA reasoning models at the front of the remaining list.
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
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining
            )
            return
        }

        guard let transition = OpenAICompatTemporaryShim.nextSmartAliasCandidateTransition(
            method: method,
            path: path,
            currentBody: currentBody,
            candidateModelsRemaining: remainingCandidateModels,
            forceAllowClosedModels: forceProbeCandidateModels
        ) else {
            if let terminalFallbackOutcome {
                deliverSmartAliasTerminalOutcome(
                    terminalFallbackOutcome,
                    publicAlias: publicAlias,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    deliveryMode: deliveryMode
                )
                return
            }

            if loopRetriesRemaining > 0, remainingSmartAliasBudget(until: deadlineAt) > 0 {
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
                    deliveryMode: deliveryMode
                )
                return
            }

            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 503,
                message: "All configured worker backends are currently unavailable.",
                coalescingKey: coalescingKey
            )
            return
        }

        NSLog("[ThinkingProxy] Resolved smart alias %@ to candidate %@ at depth %d", publicAlias, transition.model, failoverDepth)

        if let preflightError = OpenAICompatTemporaryShim.preflightError(
            method: method,
            path: path,
            jsonString: transition.body
        ) {
            if preflightError.statusCode == 503 {
                attemptSmartAliasCandidate(
                    method: method,
                    path: path,
                    headers: headers,
                    currentBody: transition.body,
                    publicAlias: publicAlias,
                    remainingCandidateModels: transition.remainingCandidateModels,
                    forceProbeCandidateModels: forceProbeCandidateModels,
                    primaryProbeRetriesRemaining: primaryProbeRetriesRemaining,
                    failoverDepth: failoverDepth + 1,
                    deadlineAt: deadlineAt,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    terminalFallbackOutcome: terminalFallbackOutcome,
                    deliveryMode: deliveryMode,
                    loopRetriesRemaining: loopRetriesRemaining
                )
                return
            }
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: preflightError.statusCode,
                message: preflightError.message,
                coalescingKey: coalescingKey
            )
            return
        }

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
            coalescingKey: coalescingKey,
            controller: nil
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
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining
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
        deliveryMode: SmartAliasDeliveryMode,
        loopRetriesRemaining: Int = 0
    ) {
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
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining
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

        for (index, transition) in raceTransitions.enumerated() {
            let attemptLane = index + 1
            let controller = SmartAliasCandidateController()
            coordinator.registerAttempt(attemptLane: attemptLane) {
                controller.cancel()
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
                            guard !coordinator.isFinished() else { return }
                            switch outcome {
                            case .success:
                                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
                            case .retryableFailure:
                                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                                remainingAttempts -= 1
                            case .terminalResponse, .terminalError:
                                terminalOutcomesByLane[attemptLane] = outcome
                                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                                remainingAttempts -= 1
                            }
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
                coalescingKey: coalescingKey,
                controller: controller
            ) { [weak self] outcome in
                guard let self else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    completionGate.wait()
                    completionQueue.async {
                        guard !coordinator.isFinished() else { return }

                        switch outcome {
                        case .success(let requestModel, let statusCode, let headers, let body, let telemetryEvent):
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
                                headers: headers,
                                body: body,
                                publicAlias: publicAlias,
                                resolvedRequestModel: requestModel,
                                coalescingKey: coalescingKey,
                                deliveryMode: deliveryMode
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
                        case .terminalError(_, _, _, let telemetryEvent):
                            if let telemetryEvent {
                                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                            }
                            terminalOutcomesByLane[attemptLane] = outcome
                            coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                            remainingAttempts -= 1
                        }

                        let waiters = self.nvidiaInflightQueue.sync { () -> [(SmartAliasCandidateAttemptOutcome) -> Void] in
                            self.nvidiaRaceWaiters.removeValue(forKey: coalescingModelKey) ?? []
                        }
                        if !waiters.isEmpty {
                            NSLog("[ThinkingProxy] Delivering NVIDIA race outcome for %@ to %d coalesced waiter(s)", transition.model, waiters.count)
                            for waiter in waiters {
                                waiter(outcome)
                            }
                        }

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
                                deliveryMode: deliveryMode,
                                loopRetriesRemaining: loopRetriesRemaining
                            )
                            return
                        }

                        if let terminalOutcome = terminalOutcomesByLane.keys.sorted().compactMap({ terminalOutcomesByLane[$0] }).first ?? terminalFallbackOutcome {
                            self.deliverSmartAliasTerminalOutcome(
                                terminalOutcome,
                                publicAlias: publicAlias,
                                originalConnection: originalConnection,
                                coalescingKey: coalescingKey,
                                deliveryMode: deliveryMode
                            )
                            return
                        }

                        // Route through attemptSmartAliasCandidate so loop retry logic applies
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
                            deliveryMode: deliveryMode,
                            loopRetriesRemaining: loopRetriesRemaining
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
        deliveryMode: SmartAliasDeliveryMode,
        loopRetriesRemaining: Int = 0
    ) {
        let healthSensitivity = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias)?.healthSensitivity
        switch outcome {
        case .success(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
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
                deliveryMode: deliveryMode
            )
        case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil)
            where remainingCandidateModels.isEmpty &&
                primaryProbeRetriesRemaining > 0 &&
                forceProbeCandidateModels.contains(requestModel):
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: telemetryEvent.requestModel,
                telemetryEvent: telemetryEvent,
                forcedOpenUntil: cooldownUntil,
                healthSensitivity: healthSensitivity
            )
            let backoffMs = min(500 * (failoverDepth + 1), 2000)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(backoffMs)) { [weak self] in
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
                    deliveryMode: deliveryMode,
                    loopRetriesRemaining: loopRetriesRemaining
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
                guard let self else { return }
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
                    deliveryMode: deliveryMode,
                    loopRetriesRemaining: loopRetriesRemaining
                )
            }
        case .terminalResponse(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
            OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
            deliverBufferedHTTPResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: responseHeaders,
                body: responseBody,
                coalescingKey: coalescingKey,
                overridingHeaders: smartAliasResolutionHeaders(
                    publicAlias: publicAlias,
                    resolvedRequestModel: requestModel
                )
            )
        case .terminalError(_, let statusCode, let message, let telemetryEvent):
            if let telemetryEvent {
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
            }
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                message: message,
                coalescingKey: coalescingKey
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
        deliveryMode: SmartAliasDeliveryMode
    ) {
        guard let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias) else {
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 503,
                message: "All configured worker backends are currently unavailable.",
                coalescingKey: coalescingKey
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
                coalescingKey: coalescingKey
            )
            return
        }
        let attempt = smartAliasMaxLoopRetries - loopRetriesRemaining + 1
        NSLog("[ThinkingProxy] Smart alias %@ loop retry %d/%d", publicAlias, attempt, smartAliasMaxLoopRetries)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            guard let self else { return }
            self.attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: currentBody,
                publicAlias: publicAlias,
                remainingCandidateModels: freshCandidates,
                forceProbeCandidateModels: freshForceProbe,
                primaryProbeRetriesRemaining: freshForceProbe.isEmpty ? 0 : self.smartAliasForcedPrimaryRetryLimit,
                failoverDepth: 0,
                deadlineAt: deadlineAt,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                terminalFallbackOutcome: nil,
                deliveryMode: deliveryMode,
                loopRetriesRemaining: loopRetriesRemaining - 1
            )
        }
    }

    private func deliverSmartAliasTerminalOutcome(
        _ outcome: SmartAliasCandidateAttemptOutcome,
        publicAlias: String,
        originalConnection: NWConnection,
        coalescingKey: String?,
        deliveryMode: SmartAliasDeliveryMode
    ) {
        let healthSensitivity = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: publicAlias)?.healthSensitivity
        switch outcome {
        case .terminalResponse(let requestModel, let statusCode, let responseHeaders, let responseBody, _):
            deliverBufferedHTTPResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: responseHeaders,
                body: responseBody,
                coalescingKey: coalescingKey,
                overridingHeaders: smartAliasResolutionHeaders(
                    publicAlias: publicAlias,
                    resolvedRequestModel: requestModel
                )
            )
        case .terminalError(_, let statusCode, let message, _):
            deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                message: message,
                coalescingKey: coalescingKey
            )
        case .success(let requestModel, let statusCode, let responseHeaders, let responseBody, let telemetryEvent):
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
                deliveryMode: deliveryMode
            )
        case .retryableFailure(let requestModel, let telemetryEvent, let cooldownUntil):
            OpenAICompatTemporaryShim.recordRouteFailure(
                forRequestModel: requestModel,
                telemetryEvent: telemetryEvent,
                forcedOpenUntil: cooldownUntil,
                healthSensitivity: healthSensitivity
            )
            // Masquerade billing/quota exhaustion as rate-limit so the Droid client
            // retries without switching models.  402 from upstream looks like
            // "provider billing exhausted" → Droid switches to bare built-in model.
            // 429 tells Droid "temporary rate limit" → retry with same model.
            if let upstreamStatus = telemetryEvent.upstreamHTTPStatus,
               upstreamStatus == 402 || upstreamStatus == 403 {
                NSLog("[ThinkingProxy] Masquerading upstream %d as 429 for smart alias %@", upstreamStatus, publicAlias)
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 429,
                    message: "Rate limit exceeded. Please retry after 30 seconds.",
                    coalescingKey: coalescingKey
                )
            } else {
                deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: 503,
                    message: "All configured worker backends are currently unavailable.",
                    coalescingKey: coalescingKey
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
        deliveryMode: SmartAliasDeliveryMode
    ) {
        let overridingHeaders = smartAliasResolutionHeaders(
            publicAlias: publicAlias,
            resolvedRequestModel: resolvedRequestModel
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

    private func forcingNonStreamChatRequestBody(from jsonString: String) -> String? {
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
                return nil
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
        coalescingKey: String?,
        controller: SmartAliasCandidateController?,
        completion: @escaping (SmartAliasCandidateAttemptOutcome) -> Void
    ) {
        let remainingBudget = remainingSmartAliasBudget(until: deadlineAt)
        guard remainingBudget > 0 else {
            completion(
                .terminalError(
                    requestModel: candidateModel,
                    statusCode: 504,
                    message: "Worker failover budget exhausted before any backend returned a valid response.",
                    telemetryEvent: nil
                )
            )
            return
        }

        let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel)
        let concurrencyLimitedTelemetry = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: "retry",
                attemptLane: attemptLane,
                failoverDepth: failoverDepth,
                failureClass: "classified_429",
                timeoutStage: .none,
                upstreamHTTPStatus: 429,
                retryCount: 0,
                source: "smart_alias",
                firstByteLatencyMilliseconds: nil,
                totalLatencyMilliseconds: nil
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
                controller: controller,
                state: OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: candidateModel,
                    initialTransportRetries: retryBudget?.transport ?? Config.nvidiaReasoningTransportRetries,
                    initialSemanticRetries: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    transportRetriesRemaining: retryBudget?.transport ?? Config.nvidiaReasoningTransportRetries,
                    semanticRetriesRemaining: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    retryBackoffMilliseconds: retryBudget?.backoffMilliseconds ?? 0,
                    salvagesBestEffortRepair: retryBudget?.salvagesBestEffortRepair ?? false,
                    bestEffortRepairedBodyData: nil,
                    coalescingKey: coalescingKey
                ),
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
                    cooldownUntil: nil
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
                body: body,
                candidateModel: candidateModel,
                timeoutInterval: timeoutInterval,
                endpoint: endpoint,
                firstResponseDeadlineSeconds: OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: body),
                bufferedResponseDeadlineSeconds: OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: body)
            ) { [weak self] bufferedResponse in
                permit.release()
                guard let self, controller?.isCancelled() != true else { return }
                controller?.clearCurrentCancel()
                self.handleSmartAliasBufferedCandidateResult(
                    bufferedResponse,
                    path: path,
                    publicAlias: publicAlias,
                    candidateModel: candidateModel,
                    failoverDepth: failoverDepth,
                    attemptLane: attemptLane,
                    inflightAtRequest: permit.inflightAtRequest,
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
            body: body,
            timeoutInterval: timeoutInterval,
            firstResponseDeadlineSeconds: OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: body),
            bufferedResponseDeadlineSeconds: OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: body)
        ) { [weak self] bufferedResponse in
            permit.release()
            guard let self, controller?.isCancelled() != true else { return }
            controller?.clearCurrentCancel()
            self.handleSmartAliasBufferedCandidateResult(
                bufferedResponse,
                path: path,
                publicAlias: publicAlias,
                candidateModel: candidateModel,
                failoverDepth: failoverDepth,
                attemptLane: attemptLane,
                inflightAtRequest: permit.inflightAtRequest,
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
        controller: SmartAliasCandidateController?,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        completion: @escaping (SmartAliasCandidateAttemptOutcome) -> Void
    ) {
        let remainingBudget = remainingSmartAliasBudget(until: deadlineAt)
        guard remainingBudget > 0 else {
            completion(
                .terminalError(
                    requestModel: candidateModel,
                    statusCode: 504,
                    message: "Worker failover budget exhausted before any backend returned a valid response.",
                    telemetryEvent: nil
                )
            )
            return
        }

        let timeoutInterval = min(
            smartAliasCandidateTimeout(forRequestJSON: body, publicAlias: publicAlias, candidateModel: candidateModel),
            remainingBudget
        )
        let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel)
        let concurrencyLimitedTelemetry = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: "retry",
                attemptLane: attemptLane,
                failoverDepth: failoverDepth,
                failureClass: "classified_429",
                timeoutStage: .none,
                upstreamHTTPStatus: 429,
                retryCount: 0,
                source: "smart_alias",
                firstByteLatencyMilliseconds: nil,
                totalLatencyMilliseconds: nil
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
                    cooldownUntil: nil
                )
            )
            return
        }
        let cancel = sendBufferedProxyRequest(
            method: method,
            path: path,
            headers: headers,
            body: body,
            timeoutInterval: timeoutInterval,
            firstResponseDeadlineSeconds: OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: body),
            bufferedResponseDeadlineSeconds: OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: body)
        ) { [weak self] bufferedResponse in
            permit.release()
            guard let self, controller?.isCancelled() != true else { return }
            controller?.clearCurrentCancel()

            let attempt = OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                data: bufferedResponse.data,
                response: bufferedResponse.response,
                error: bufferedResponse.error,
                deadlineStage: .none,
                firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds
            )
            let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                path: path,
                state: state,
                attempt: attempt
            )
            let telemetryEvent = self.annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.telemetryEvent(
                    path: path,
                    state: state,
                    attempt: attempt,
                    outcome: outcome,
                    source: "smart_alias",
                    attemptLane: attemptLane
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )

            switch outcome {
            case .retry(let nextState):
                if attempt.response?.statusCode == 429 {
                    OpenAICompatTemporaryShim.recordConcurrency429(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest
                    )
                }
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                let delay = DispatchTimeInterval.milliseconds(max(0, nextState.retryBackoffMilliseconds))
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
                        controller: controller,
                        state: nextState,
                        completion: completion
                    )
                }
                if nextState.retryBackoffMilliseconds > 0 {
                    controller?.scheduleRetry(after: delay, block: retryBlock)
                } else {
                    retryBlock()
                }
            case .sendResponse(let statusCode, let responseHeaders, let responseBody):
                if self.classifySmartAliasCandidateFailure(
                    statusCode: statusCode,
                    bodyData: responseBody,
                    path: path
                ).shouldFailover {
                    if statusCode == 429 {
                        OpenAICompatTemporaryShim.recordConcurrency429(
                            routeHealthKey: permit.routeHealthKey,
                            inflightAtRequest: permit.inflightAtRequest
                        )
                    }
                    let cooldownUntil = OpenAICompatTemporaryShim.providerCooldownUntil(
                        statusCode: statusCode,
                        headers: responseHeaders,
                        bodyData: responseBody
                    )
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
                if self.classifySmartAliasCandidateFailure(
                    statusCode: statusCode,
                    bodyData: nil,
                    path: path
                ).shouldFailover {
                    let cooldownUntil = attempt.response.map {
                        OpenAICompatTemporaryShim.providerCooldownUntil(
                            statusCode: statusCode,
                            headers: $0.allHeaderFields
                        )
                    } ?? nil
                    completion(
                        .retryableFailure(
                            requestModel: candidateModel,
                            telemetryEvent: telemetryEvent,
                            cooldownUntil: cooldownUntil
                        )
                    )
                    return
                }

                completion(
                    .terminalError(
                        requestModel: candidateModel,
                        statusCode: statusCode,
                        message: message,
                        telemetryEvent: telemetryEvent
                    )
                )
            }
        }
        controller?.registerCurrentCancel {
            permit.release()
            cancel()
        }
    }

    private func handleSmartAliasBufferedCandidateResult(
        _ bufferedResponse: BufferedProxyResponse,
        path: String,
        publicAlias: String,
        candidateModel: String,
        failoverDepth: Int,
        attemptLane: Int,
        inflightAtRequest: Int? = nil,
        completion: @escaping (SmartAliasCandidateAttemptOutcome) -> Void
    ) {
        let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel)

        if let error = bufferedResponse.error {
            let telemetryEvent = annotatedSmartAliasTelemetryEvent(
                OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: Date(),
                    requestModel: candidateModel,
                    requestedAlias: publicAlias,
                    canonicalModelID: route?.canonicalModelID ?? candidateModel,
                    transportOutcome: "send_error",
                    attemptLane: attemptLane,
                    failoverDepth: failoverDepth,
                    failureClass: transportFailureClass(error),
                    timeoutStage: .none,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "smart_alias",
                    firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                    totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds
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
                    transportOutcome: "send_error",
                    attemptLane: attemptLane,
                    failoverDepth: failoverDepth,
                    failureClass: "missing_response_material",
                    timeoutStage: .none,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "smart_alias",
                    firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                    totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds
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
            bodyData: responseData,
            path: path
        )
        let shouldFailover = failureClassification.shouldFailover
        let failureClass = failureClassification.failureClass
        let telemetryEvent = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: statusCode >= 200 && statusCode < 300 ? "send_response" : "send_error",
                attemptLane: attemptLane,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: (!shouldFailover && statusCode >= 200 && statusCode < 300) ? candidateModel : nil,
                failureClass: failureClass,
                timeoutStage: .none,
                upstreamHTTPStatus: statusCode,
                retryCount: 0,
                source: "smart_alias",
                firstByteLatencyMilliseconds: bufferedResponse.firstByteLatencyMilliseconds,
                totalLatencyMilliseconds: bufferedResponse.totalLatencyMilliseconds
            ),
            requestedAlias: publicAlias,
            failoverDepth: failoverDepth,
            finalWinnerRequestModel: (!shouldFailover && statusCode >= 200 && statusCode < 300) ? candidateModel : nil
        )

        if shouldFailover {
            // Record 429 in concurrency registry for auto-discovery of provider limits
            if statusCode == 429, let routeHealthKey = route?.routeHealthKey {
                OpenAICompatTemporaryShim.recordConcurrency429(
                    routeHealthKey: routeHealthKey,
                    inflightAtRequest: inflightAtRequest
                )
            }
            let cooldownUntil = OpenAICompatTemporaryShim.providerCooldownUntil(
                statusCode: statusCode,
                headers: response.allHeaderFields,
                bodyData: responseData
            )
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
        bodyData: Data?,
        path: String
    ) -> (shouldFailover: Bool, failureClass: String?) {
        if let bodyData,
           let failureClass = classifyRetryableSmartAliasErrorBody(statusCode: statusCode, path: path, bodyData: bodyData) {
            return (true, failureClass)
        }
        if statusCode >= 200 && statusCode < 300,
           let bodyData,
           let failureClass = classifySmartAliasSuccessBodyFailure(path: path, bodyData: bodyData) {
            return (true, failureClass)
        }
        switch statusCode {
        case 402, 408, 429, 403, 404:
            return (true, "classified_\(statusCode)")
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
        return looksLikeRetryableNetworkMask ? "classified_retryable_400_network_error" : nil
    }

    private func classifySmartAliasSuccessBodyFailure(path: String, bodyData: Data) -> String? {
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
        switch OpenAICompatTemporaryShim.validateToolCalls(in: message) {
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
            totalLatencyMilliseconds: event.totalLatencyMilliseconds
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

        let responseProgress = ResponseProgressDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: responseProgress, delegateQueue: nil)
        let (task, exception) = SafeDataTask.create(on: session, with: request) { data, response, error in
            responseProgress.finish()
            completion(
                BufferedProxyResponse(
                    data: data,
                    response: response as? HTTPURLResponse,
                    error: error,
                    firstByteLatencyMilliseconds: responseProgress.firstByteLatencyMilliseconds(),
                    totalLatencyMilliseconds: responseProgress.totalLatencyMilliseconds()
                )
            )
            session.finishTasksAndInvalidate()
        }
        guard let task else {
            NSLog("[SafeDataTask] sendBufferedProxyRequest: session invalidated during dataTask creation — \(exception?.reason ?? "unknown")")
            completion(BufferedProxyResponse(data: nil, response: nil, error: URLError(.cancelled), firstByteLatencyMilliseconds: nil, totalLatencyMilliseconds: nil))
            session.finishTasksAndInvalidate()
            return {}
        }
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
                    totalLatencyMilliseconds: responseProgress.totalLatencyMilliseconds()
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
        originalConnection: NWConnection
    ) {
        let timeoutInterval = OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: body) ?? Config.defaultMitigatedAttemptTimeout
        let effectiveHeaders = headersInjectingRouteSpecific(headers, forCandidateModel: candidateModel)
        guard let permit = acquireRouteConcurrencyPermit(forRequestModel: candidateModel) else {
            var limitHeaders = smartAliasResolutionHeaders(
                publicAlias: candidateModel,
                resolvedRequestModel: candidateModel
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
        _ = sendDirectProxiedRequest(
            method: method,
            path: path,
            headers: effectiveHeaders,
            body: body,
            candidateModel: candidateModel,
            timeoutInterval: timeoutInterval,
            endpoint: endpoint
        ) { [weak self] bufferedResponse in
            permit.release()
            guard let self else { return }
            if let error = bufferedResponse.error {
                let nsError = error as NSError
                let statusCode = (nsError.domain == NSURLErrorDomain && nsError.code == URLError.timedOut.rawValue) ? 504 : 502
                self.sendError(
                    to: originalConnection,
                    statusCode: statusCode,
                    message: statusCode == 504 ? "Gateway Timeout" : "Bad Gateway"
                )
                return
            }
            guard let response = bufferedResponse.response,
                  let data = bufferedResponse.data else {
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
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
                overridingModel: overridingModel
            )
        }
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
        return min(smartAliasCandidateTimeout(forRequestJSON: jsonString) + 60, 360)
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

        if let requestedModelAlias,
           OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: requestedModelAlias) != nil,
           OpenAICompatTemporaryShim.isSafePlainChatRequest(
                method: method,
                path: path,
                jsonString: coalescingSourceBody
           ) {
            return "\(identityPartition)\n\(method) \(path)\n\(coalescingSourceBody)"
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
        return "\(identityPartition)\n\(method) \(path)\n\(body)"
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
            if inflightCoalescedRequests[key] != nil {
                inflightCoalescedRequests[key, default: []].append(connection)
                return false
            }
            inflightCoalescedRequests[key] = [connection]
            return true
        }
    }

    func registerOrJoinInflightRequestForTesting(key: String, connection: NWConnection) -> Bool {
        registerOrJoinInflightRequest(key: key, connection: connection)
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
        resolvedRequestModel: String
    ) -> [String: String] {
        var headers: [String: String] = [
            "X-Public-Model": publicAlias,
            "X-Resolved-Model": resolvedRequestModel
        ]
        if let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: resolvedRequestModel) {
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

    private func deliverBufferedError(
        defaultConnection: NWConnection,
        statusCode: Int,
        message: String,
        coalescingKey: String?
    ) {
        let connections = takeInflightRequestConnections(for: coalescingKey) ?? [defaultConnection]
        for connection in connections {
            sendError(
                to: connection,
                statusCode: statusCode,
                message: message
            )
        }
    }

    private func headerTuples(from headers: [AnyHashable: Any]) -> [(String, String)] {
        headers.map { key, value in
            ("\(key)", "\(value)")
        }
    }

    // Injects provider-specific headers required by certain free-tier upstream services.
    // Currently adds HTTP-Referer for opencode and kilocode candidate routes.
    private func headersInjectingRouteSpecific(
        _ headers: [(String, String)],
        forCandidateModel candidateModel: String
    ) -> [(String, String)] {
        guard let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: candidateModel),
              (route.providerID == "opencode" || route.providerID == "kilocode") else {
            return headers
        }
        let alreadyHasReferer = headers.contains { $0.0.lowercased() == "http-referer" }
        guard !alreadyHasReferer else { return headers }
        return headers + [("HTTP-Referer", "https://openclaw.ai")]
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

    private func forwardNvidiaReasoningRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: OpenAICompatTemporaryShim.NVIDIARetryState
    ) {
        let coordinator = NVIDIAAttemptCoordinator()
        let routeHealthStatus = OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: state.model)
        let hedgeEligible = OpenAICompatTemporaryShim.allowsHedgedNVIDIARequest(
            method: method,
            path: path,
            jsonString: body,
            routeHealthStatus: routeHealthStatus
        )
        forwardNvidiaReasoningRequestWithRetry(
            method: method,
            path: path,
            headers: headers,
            body: body,
            originalConnection: originalConnection,
            state: state,
            coordinator: coordinator,
            attemptLane: 1,
            hedgeEligible: hedgeEligible
        )
    }

    private func forwardNvidiaReasoningRequestWithRetry(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        coordinator: NVIDIAAttemptCoordinator,
        attemptLane: Int,
        hedgeEligible: Bool
    ) {
        guard !coordinator.isFinished() else { return }
        guard let url = URL(string: "http://\(targetHost):\(targetPort)\(path)") else {
            if coordinator.tryFinish(attemptLane: attemptLane) {
                sendError(to: originalConnection, statusCode: 500, message: "Internal Server Error")
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: body) ?? Config.defaultMitigatedAttemptTimeout
        guard let permit = acquireRouteConcurrencyPermit(forRequestModel: state.model) else {
            guard attemptLane == 1 else { return }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
                guard let self, !coordinator.isFinished() else { return }
                self.forwardNvidiaReasoningRequestWithRetry(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    originalConnection: originalConnection,
                    state: state,
                    coordinator: coordinator,
                    attemptLane: attemptLane,
                    hedgeEligible: hedgeEligible
                )
            }
            return
        }

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("close", forHTTPHeaderField: "Connection")

        let sessionKey = "direct:127.0.0.1:\(targetPort)"
        let pooledSession = ThinkingProxy.acquireDirectSession(key: sessionKey)
        let responseProgress = ResponseProgressDelegate()
        let session: URLSession = pooledSession ?? URLSession(configuration: .ephemeral, delegate: responseProgress, delegateQueue: nil)
        let (task, dataTaskException) = SafeDataTask.create(on: session, with: request) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
            guard let self else { return }
            defer {
                permit.release()
                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                responseProgress.finish()
                if pooledSession != nil {
                    ThinkingProxy.removeDirectSession(key: sessionKey, session: session)
                } else {
                    session.finishTasksAndInvalidate()
                }
            }
            let attempt = OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                data: data,
                response: response as? HTTPURLResponse,
                error: error,
                deadlineStage: responseProgress.currentDeadlineStage(),
                firstByteLatencyMilliseconds: responseProgress.firstByteLatencyMilliseconds(),
                totalLatencyMilliseconds: responseProgress.totalLatencyMilliseconds()
            )
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
                attemptLane: attemptLane
            )

            switch outcome {
            case .retry(let nextState):
                if attempt.response?.statusCode == 429 {
                    OpenAICompatTemporaryShim.recordConcurrency429(
                        routeHealthKey: permit.routeHealthKey,
                        inflightAtRequest: permit.inflightAtRequest
                    )
                }
                guard !coordinator.isFinished() else { return }
                if attemptLane == 1,
                   hedgeEligible,
                   coordinator.shouldStartHedge() {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                    self.forwardNvidiaReasoningRequestWithRetry(
                        method: method,
                        path: path,
                        headers: headers,
                        body: body,
                        originalConnection: originalConnection,
                        state: nextState,
                        coordinator: coordinator,
                        attemptLane: 2,
                        hedgeEligible: false
                    )
                    return
                }
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                self.scheduleNvidiaReasoningRetry(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    originalConnection: originalConnection,
                    state: nextState,
                    coordinator: coordinator,
                    attemptLane: attemptLane,
                    hedgeEligible: hedgeEligible
                )
            case .sendResponse(let statusCode, let headers, let bodyData):
                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
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
                    if statusCode == 429 {
                        OpenAICompatTemporaryShim.recordConcurrency429(
                            routeHealthKey: permit.routeHealthKey,
                            inflightAtRequest: permit.inflightAtRequest
                        )
                    }
                    OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
                } else {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(winningTelemetryEvent)
                }
                self.deliverBufferedHTTPResponse(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    headers: headers,
                    body: bodyData,
                    coalescingKey: state.coalescingKey
                )
            case .sendError(let statusCode, let message):
                guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
                let winningTelemetryEvent = OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                    telemetryEvent,
                    winnerAttemptLane: attemptLane
                )
                if statusCode == 429 || statusCode == 403 || statusCode == 404 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
                    if statusCode == 429 {
                        OpenAICompatTemporaryShim.recordConcurrency429(
                            routeHealthKey: permit.routeHealthKey,
                            inflightAtRequest: permit.inflightAtRequest
                        )
                    }
                    OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
                } else {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(winningTelemetryEvent)
                }
                self.deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    message: message,
                    coalescingKey: state.coalescingKey
                )
            }
        }
        guard let task else {
            NSLog("[SafeDataTask] forwardNvidiaReasoningRequestWithRetry: session invalidated — evicting direct pool. \(dataTaskException?.reason ?? "unknown")")
            if pooledSession != nil {
                ThinkingProxy.removeDirectSession(key: sessionKey, session: session)
            } else {
                session.finishTasksAndInvalidate()
            }
            permit.release()
            coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
            guard coordinator.tryFinish(attemptLane: attemptLane) else { return }
            self.deliverBufferedError(
                defaultConnection: originalConnection,
                statusCode: 502,
                message: "upstream session invalidated",
                coalescingKey: state.coalescingKey
            )
            return
        }
        coordinator.registerAttempt(attemptLane: attemptLane) {
            permit.release()
            task.cancel()
        }
        if attemptLane == 1, hedgeEligible {
            let hedgeDelay = OpenAICompatTemporaryShim.recommendedNVIDIAHedgeDelay(forRequestModel: state.model)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + hedgeDelay) { [weak self, weak responseProgress] in
                guard let self,
                      let responseProgress,
                      !coordinator.isFinished(),
                      !responseProgress.hasReceivedPayload(),
                      coordinator.shouldStartHedge() else { return }
                NSLog("[ThinkingProxy] Starting hedged NVIDIA attempt for suspect route %@ after %.2fs without first byte", state.model, hedgeDelay)
                self.forwardNvidiaReasoningRequestWithRetry(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    originalConnection: originalConnection,
                    state: state,
                    coordinator: coordinator,
                    attemptLane: 2,
                    hedgeEligible: false
                )
            }
        }
        responseProgress.installDeadlines(
            firstResponseSeconds: OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                forRequestJSON: body,
                routeHealthStatus: OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: state.model)
            ),
            bufferedResponseSeconds: OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: body),
            for: task
        )
        task.resume()
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

        let requestModels = OpenAICompatTemporaryShim.quarantinedRequestModels()
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
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: requestModel,
                        telemetryEvent: telemetryEvent
                    )
                }
            case .retry, .sendError:
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: requestModel,
                    telemetryEvent: telemetryEvent
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

    private func scheduleNvidiaReasoningRetry(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: OpenAICompatTemporaryShim.NVIDIARetryState,
        coordinator: NVIDIAAttemptCoordinator,
        attemptLane: Int,
        hedgeEligible: Bool
    ) {
        let delay = DispatchTimeInterval.milliseconds(max(0, state.retryBackoffMilliseconds))
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !coordinator.isFinished() else { return }
            self.forwardNvidiaReasoningRequestWithRetry(
                method: method,
                path: path,
                headers: headers,
                body: body,
                originalConnection: originalConnection,
                state: state,
                coordinator: coordinator,
                attemptLane: attemptLane,
                hedgeEligible: hedgeEligible
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
     */
    private func forwardRequest(method: String, path: String, version: String, headers: [(String, String)], body: String, thinkingEnabled: Bool = false, originalConnection: NWConnection, retryWithApiPrefix: Bool = false) {
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
                                self.receiveResponse(from: targetConnection, originalConnection: originalConnection)
                            }
                        }
                    }))
                }
                
            case .failed(let error):
                NSLog("[ThinkingProxy] Target connection failed: \(error)")
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
            let factoryRoute = factoryWorkerContract.effectiveRouteModel
            let inPool = workerCandidates.contains(factoryRoute)
            let severity: String
            let warning: String?
            if inPool {
                severity = "none"
                warning = nil
            } else if factoryWorkerContract.routeModel == factoryRoute {
                severity = "critical"
                warning = "Factory route model '\(factoryRoute)' is not in proxy worker pool. Direct requests will bypass smart failover."
            } else {
                severity = "warning"
                warning = "Factory effective route '\(factoryRoute)' (resolved from '\(factoryWorkerContract.routeModel)') is not in proxy worker pool. Failover will use fallback candidates."
            }
            var drift: [String: Any] = [
                "factory_route_model": factoryRoute,
                "proxy_worker_candidates": workerCandidates,
                "route_in_pool": inPool,
                "severity": severity
            ]
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

        let routeHealthSnapshot = OpenAICompatTemporaryShim.routeHealthSnapshot()
        if !routeHealthSnapshot.isEmpty {
            let routes = routeHealthSnapshot.keys.sorted().reduce(into: [String: [String: Any]]()) { result, requestModel in
                guard let state = routeHealthSnapshot[requestModel] else { return }
                var routePayload: [String: Any] = [
                    "status": state.status.rawValue,
                    "failure_score": state.failureScore,
                    "recovery_successes": state.recoverySuccesses
                ]
                if let route = OpenAICompatTemporaryShim.resolveRouteIdentityForAnyProvider(forRequestModel: requestModel) {
                    routePayload["concurrency_limit"] = OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: route.routeHealthKey)
                    routePayload["inflight"] = OpenAICompatTemporaryShim.currentInflightConcurrency(routeHealthKey: route.routeHealthKey)
                }
                result[requestModel] = routePayload
            }
            payload["route_health"] = [
                "routes": routes,
                "quarantined_models": OpenAICompatTemporaryShim.quarantinedNVIDIAHostedRequestModels()
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
            "snapshot_sync_ok": contract.snapshotDriftPaths.isEmpty,
            "snapshot_drift_count": contract.snapshotDriftPaths.count,
            "snapshot_blocking_sync_ok": contract.blockingSnapshotDriftPaths.isEmpty,
            "snapshot_blocking_drift_count": contract.blockingSnapshotDriftPaths.count,
            "ready": backendReachable && contract.ready
        ]
        dict["effective_route_model"] = contract.effectiveRouteModel
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
        if let bindings = Self.factoryModelBindings()?.bindingsByIncomingModelID.values {
            let workerBindings = bindings.filter {
                $0.authoritativeModelID == contract.workerModelID &&
                $0.routeModel == contract.routeModel &&
                $0.routeProvider == contract.routeProvider
            }
            let acceptedRequestModelIDs = Array(Set(workerBindings.map(\.incomingModelID))).sorted()
            let rescuedRequestModelIDs = Array(Set(workerBindings.compactMap { binding in
                binding.source == "retired_worker_alias_rescue" ? binding.incomingModelID : nil
            })).sorted()

            if !acceptedRequestModelIDs.isEmpty {
                dict["accepted_request_model_ids"] = acceptedRequestModelIDs
            }
            if !rescuedRequestModelIDs.isEmpty {
                dict["rescued_request_model_ids"] = rescuedRequestModelIDs
            }
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
            "ready": backendReachable && contract.ready
        ]
        if let reasoningEffort = contract.reasoningEffort {
            dict["reasoning_effort"] = reasoningEffort
        }
        if let effectiveRouteProvider = contract.effectiveRouteProvider {
            dict["effective_route_provider"] = effectiveRouteProvider
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
        requestSurface: String
    ) -> [String] {
        guard requestSurface == "chat_completions",
              let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) else {
            return [routeModel]
        }

        let syntheticWorkerRequest = """
        {
          "model": "\(routeModel)",
          "messages": [
            {
              "role": "user",
              "content": "Return exactly: OK"
            }
          ],
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
        }
        """

        return OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
            forPublicAlias: routeModel,
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: syntheticWorkerRequest,
            smartAlias: smartAlias
        )
    }

    private static func effectiveFactoryResponsesFallbackCandidateModels(
        routeModel: String
    ) -> [String] {
        guard let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) else {
            return [routeModel]
        }

        let syntheticPlainChatRequest = """
        {
          "model": "\(routeModel)",
          "messages": [
            {
              "role": "user",
              "content": "Return exactly: OK"
            }
          ],
          "max_tokens": 32
        }
        """

        return OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
            forPublicAlias: routeModel,
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: syntheticPlainChatRequest,
            smartAlias: smartAlias
        )
    }

    private static func effectiveFactoryContractHealthStatus(
        routeModel: String,
        requestSurface: String,
        effectiveRouteModel: String
    ) -> String? {
        let workerPrimaryCandidate = OpenAICompatTemporaryShim.workerPrimaryCandidateModel()
        guard requestSurface == "chat_completions",
              OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) != nil,
              OpenAICompatTemporaryShim.routeHealthStatus(
                forRequestModel: workerPrimaryCandidate
              ) == .open,
              effectiveRouteModel != workerPrimaryCandidate else {
            return OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: effectiveRouteModel)?.rawValue
        }

        return nil
    }

    private static func effectiveFactoryCandidateModels(
        routeModel: String,
        routeProvider: String,
        requestSurface: String
    ) -> [String] {
        if OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: routeModel) != nil {
            return effectiveFactoryWorkerCandidateModels(
                routeModel: routeModel,
                requestSurface: requestSurface
            )
        }
        return [routeModel]
    }

    private static func effectiveFactoryRouteModel(
        routeModel: String,
        routeProvider: String,
        requestSurface: String
    ) -> String {
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
            OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: directEffectiveRouteModel)?.providerID
        let directRouteHealthStatus =
            OpenAICompatTemporaryShim.routeHealthStatus(forRequestModel: directEffectiveRouteModel)?.rawValue

        return FactoryRoleContract(
            modelID: modelID,
            reasoningEffort: reasoningEffort,
            routeModel: routeModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface,
            effectiveRouteModel: directEffectiveRouteModel,
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
        guard let settingsPath = ThinkingProxy.factorySettingsPath(),
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let missionModelSettings = root["missionModelSettings"] as? [String: Any],
              let sessionDefaultSettings = root["sessionDefaultSettings"] as? [String: Any],
              let workerModelID = missionModelSettings["workerModel"] as? String,
              let customModels = root["customModels"] as? [[String: Any]],
              let workerModel = customModels.first(where: { ($0["id"] as? String) == workerModelID }),
              let routeModel = workerModel["model"] as? String,
              let routeProvider = workerModel["provider"] as? String else {
            return nil
        }

        let requestSurface = factoryWorkerRequestSurface(forProvider: routeProvider)
        let effectiveRouteModel = ThinkingProxy.effectiveFactoryRouteModel(
            routeModel: routeModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface
        )
        let effectiveRouteProvider =
            OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: effectiveRouteModel)?.providerID

        let snapshotDriftPaths = factoryWorkerSnapshotDriftPaths(
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

        return FactoryWorkerContract(
            workerModelID: workerModelID,
            validationWorkerModelID: missionModelSettings["validationWorkerModel"] as? String,
            workerReasoningEffort: missionModelSettings["workerReasoningEffort"] as? String,
            validationWorkerReasoningEffort: missionModelSettings["validationWorkerReasoningEffort"] as? String,
            routeModel: routeModel,
            routeProvider: routeProvider,
            requestSurface: requestSurface,
            effectiveRouteModel: effectiveRouteModel,
            effectiveRouteProvider: effectiveRouteProvider,
            displayName: workerModel["displayName"] as? String,
            baseURL: workerModel["baseUrl"] as? String,
            routeHealthStatus: effectiveFactoryContractHealthStatus(
                routeModel: routeModel,
                requestSurface: requestSurface,
                effectiveRouteModel: effectiveRouteModel
            ),
            authoritativeSettingsPath: settingsPath,
            snapshotDriftPaths: snapshotDriftPaths
        )
    }

    private static func retiredFactoryWorkerModelIDs(excluding currentWorkerModelID: String) -> Set<String> {
        let retiredIDs: Set<String> = [
            "custom:Proxy-WorkerPool-8",
            "custom:Factory-Worker-GPT-5.4-High-8",
            "custom:Proxy-Worker-Smart-Router-8"
        ]
        return retiredIDs.subtracting([currentWorkerModelID])
    }

    fileprivate static func factoryResolvedRouteModel(forIncomingModelID incomingModelID: String) -> String? {
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

        guard retiredWorkerModelIDs.contains(incomingModelID) else {
            return nil
        }

        if let contract = factoryWorkerContract() {
            return "Factory sent retired worker model \(incomingModelID), but VibeProxy could not bind it onto the authoritative worker model \(contract.workerModelID). Check /healthz factory_worker snapshot drift and resync Factory settings."
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

    private static func factoryModelBinding(forIncomingModelID incomingModelID: String) -> FactoryModelBinding? {
        factoryModelBindings()?.bindingsByIncomingModelID[incomingModelID]
    }

    fileprivate static func factoryModelBindingByRouteModel(forRouteModel routeModel: String) -> FactoryModelBinding? {
        factoryModelBindings()?.bindingsByIncomingModelID.values.first { $0.routeModel == routeModel }
    }

    fileprivate static func factoryModelBindings() -> CachedFactoryModelBindings? {
        guard let settingsPath = ThinkingProxy.factorySettingsPath() else {
            return nil
        }

        let settingsFingerprint = ThinkingProxy.fileFingerprint(at: settingsPath)
        if let cached = factoryBindingsCacheQueue.sync(execute: { cachedFactoryModelBindings }),
           cached.settingsPath == settingsPath,
           cached.settingsFingerprint == settingsFingerprint {
            return cached
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            factoryBindingsCacheQueue.sync {
                cachedFactoryModelBindings = nil
            }
            return nil
        }

        let customModels = root["customModels"] as? [[String: Any]] ?? []
        var bindingsByIncomingModelID: [String: FactoryModelBinding] = [:]

        for customModel in customModels {
            guard let incomingModelID = customModel["id"] as? String,
                  let routeModel = customModel["model"] as? String,
                  let routeProvider = customModel["provider"] as? String else {
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

        if let missionModelSettings = root["missionModelSettings"] as? [String: Any],
           let workerModelID = missionModelSettings["workerModel"] as? String,
           let workerModel = customModels.first(where: { ($0["id"] as? String) == workerModelID }),
           let routeModel = workerModel["model"] as? String,
           let routeProvider = workerModel["provider"] as? String {
            for retiredModelID in retiredFactoryWorkerModelIDs(excluding: workerModelID) {
                bindingsByIncomingModelID[retiredModelID] = FactoryModelBinding(
                    incomingModelID: retiredModelID,
                    authoritativeModelID: workerModelID,
                    routeModel: routeModel,
                    routeProvider: routeProvider,
                    requestSurface: factoryWorkerRequestSurface(forProvider: routeProvider),
                    displayName: workerModel["displayName"] as? String,
                    baseURL: workerModel["baseUrl"] as? String,
                    authoritativeSettingsPath: settingsPath,
                    source: "retired_worker_alias_rescue"
                )
            }
        }

        let cached = CachedFactoryModelBindings(
            settingsPath: settingsPath,
            settingsFingerprint: settingsFingerprint,
            bindingsByIncomingModelID: bindingsByIncomingModelID,
            authoritativeWorkerModelID: (root["missionModelSettings"] as? [String: Any])?["workerModel"] as? String
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
           !overridePath.isEmpty,
           FileManager.default.fileExists(atPath: overridePath) {
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
