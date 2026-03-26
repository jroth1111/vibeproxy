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
            totalLatencyMilliseconds: Int? = nil
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

    struct SmartAliasDefinition: Equatable {
        let alias: String
        let requestClass: String
        let failover: String
        let candidates: [String]
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
            guard requestCount > 0 else { return 0 }
            return Double(timeoutCount) / Double(requestCount)
        }

        var invalidSuccessRate: Double {
            guard requestCount > 0 else { return 0 }
            return Double(invalidSuccessCount) / Double(requestCount)
        }

        var averageFirstByteLatencyMilliseconds: Int? {
            guard !recentFirstByteLatencyMilliseconds.isEmpty else { return nil }
            let total = recentFirstByteLatencyMilliseconds.reduce(0, +)
            return total / recentFirstByteLatencyMilliseconds.count
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

        func isUnavailable(at now: Date) -> Bool {
            switch status {
            case .closed, .suspect:
                return false
            case .open, .halfOpen:
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
        let smartAliasesByAlias: [String: SmartAliasDefinition]
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

    enum FailureClass: String, Hashable {
        case emptyBody = "empty_body"
        case emptyContent = "empty_content"
        case reasoningOnlyContentMissing = "reasoning_only_content_missing"
        case reasoningLeakLength = "reasoning_leak_length"
        case malformedToolArguments = "malformed_tool_arguments"
    }

    private static let knownNVIDIARoutePoliciesByCanonicalModelID: [String: RequestPolicy] = [
        "z-ai/glm5": RequestPolicy(
            minimumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 200,
            firstResponseDeadline: 25,
            bufferedResponseDeadline: 28,
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
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 200,
            firstResponseDeadline: 25,
            bufferedResponseDeadline: 28,
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
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 200,
            firstResponseDeadline: 25,
            bufferedResponseDeadline: 28,
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
    private static let nonNVIDIAMitigationPoliciesByRequestModel: [String: RequestPolicy] = [
        "glm-4.7": RequestPolicy(
            minimumMaxTokens: nil,
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
        "glm-5-turbo": RequestPolicy(
            minimumMaxTokens: nil,
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
        )
    ]

    private struct RequestPolicy {
        let minimumMaxTokens: Int?
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
    private static let nvidiaRouteHealthQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-route-health")
    private static var routeCircuitStatesByRouteHealthKey: [String: RouteCircuitState] = [:]
    private static var hasLoadedPersistedRouteHealth = false
    static var routeTelemetryHookForTesting: ((RouteTelemetryEvent) -> Void)?
    private static let routeCircuitBreakerPolicy = RouteCircuitBreakerPolicy(
        failureThreshold: 2,
        cooldown: 300,
        recoverySuccessThreshold: 2
    )
    private static let routeRollingWindow = 8
    private static let fastCanaryInterval: TimeInterval = 30
    private static let defaultCanaryInterval: TimeInterval = 60
    private static let defaultSuspectHedgeDelay: TimeInterval = 6
    private static let suspectFirstResponseDeadline: TimeInterval = 8
    private static let routeFailureScoreDecayInterval: TimeInterval = 180

    private enum ToolCallValidation {
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
              let model = json["model"] as? String,
              let policy = policy(forModel: model) else {
            return nil
        }
        var modified = false

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

    static func smartAliasDefinition(forRequestModel requestModel: String) -> SmartAliasDefinition? {
        configuredRouteConfiguration().smartAliasesByAlias[requestModel]
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
        publicAlias: String,
        method: String,
        path: String,
        currentBody: String,
        candidateModelsRemaining: [String]
    ) -> (body: String, model: String, remainingCandidateModels: [String])? {
        var remainingCandidateModels = candidateModelsRemaining
        while !remainingCandidateModels.isEmpty {
            let nextCandidateModel = remainingCandidateModels.removeFirst()
            guard resolveConfiguredRoute(forRequestModel: nextCandidateModel) != nil else {
                continue
            }
            guard let candidateBody = rewrittenRequestJSON(
                method: method,
                path: path,
                replacingRequestModelIn: currentBody,
                with: nextCandidateModel
            ) else {
                continue
            }
            if isConfiguredRouteOpen(forRequestModel: nextCandidateModel) {
                continue
            }
            return (candidateBody, nextCandidateModel, remainingCandidateModels)
        }
        _ = publicAlias
        return nil
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

    static func isNvidiaReasoningChatRequest(method: String, path: String, jsonString: String) -> Bool {
        guard method == "POST",
              isChatCompletionsPath(path),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
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

        return nil
    }

    static func attemptTimeout(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.attemptTimeout
    }

    static func firstResponseDeadline(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.firstResponseDeadline
    }

    static func effectiveFirstResponseDeadline(
        forRequestJSON jsonString: String,
        routeHealthStatus: RouteHealthStatus?
    ) -> TimeInterval? {
        let baseline = firstResponseDeadline(forRequestJSON: jsonString)
        guard routeHealthStatus == .suspect,
              let baseline else {
            return baseline
        }
        return min(baseline, suspectFirstResponseDeadline)
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
        if evaluation.shouldRetry, semanticRetriesRemaining > 0 {
            return .retry(
                nextSemanticRetriesRemaining: semanticRetriesRemaining - 1,
                preservedBestEffortRepair: bestEffortRepairedBodyData
            )
        }

        if evaluation.shouldRetry,
           salvagesBestEffortRepair,
           let repairedBodyData = bestEffortRepairedBodyData {
            return .returnRepaired(repairedBodyData)
        }

        return evaluation.shouldRetry ? .returnGatewayError : .retry(
            nextSemanticRetriesRemaining: semanticRetriesRemaining,
            preservedBestEffortRepair: bestEffortRepairedBodyData
        )
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

    static func modelName(forRequestJSON jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return nil
        }
        return model
    }

    static func filteredModelListBodyRemovingOpenNVIDIARoutes(_ bodyData: Data, now: Date = Date()) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let data = json["data"] as? [[String: Any]] else {
            return nil
        }

        let unavailableModelIDs = unavailableRequestModelIDs(at: now)
        var changed = false
        var filteredData = data.filter { entry in
            guard let id = entry["id"] as? String else {
                return true
            }
            let keep = !unavailableModelIDs.contains(id)
            if !keep {
                changed = true
            }
            return keep
        }

        let existingIDs = Set(filteredData.compactMap { $0["id"] as? String })
        for smartAlias in configuredRouteConfiguration().smartAliasesByAlias.values.sorted(by: { $0.alias < $1.alias }) {
            guard !existingIDs.contains(smartAlias.alias),
                  smartAlias.candidates.contains(where: {
                      resolveConfiguredRoute(forRequestModel: $0) != nil &&
                      !isConfiguredRouteOpen(forRequestModel: $0, at: now)
                  }) else {
                continue
            }
            filteredData.append([
                "id": smartAlias.alias,
                "object": "model",
                "owned_by": "smart-alias"
            ])
            changed = true
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
        return nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let routesByHealthKey = configuredRouteConfiguration().routesByRequestModel.values.reduce(into: [String: OpenAICompatTemporaryShim.RouteIdentity]()) { routesByHealthKey, route in
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

    static func routeHealthStatus(forRequestModel requestModel: String, at now: Date = Date()) -> RouteHealthStatus? {
        _ = now
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
            return nil
        }
        return nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.status
        }
    }

    static func recommendedNVIDIAHedgeDelay(forRequestModel requestModel: String) -> TimeInterval {
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
            return defaultSuspectHedgeDelay
        }
        return nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return recommendedNVIDIAHedgeDelay(
                metrics: routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.rollingMetrics
            )
        }
    }

    static func recommendedNVIDIACanaryInterval() -> TimeInterval {
        return nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let metrics = routeCircuitStatesByRouteHealthKey.values
                .filter { $0.isUnavailable(at: Date()) }
                .map(\.rollingMetrics)
            return recommendedNVIDIACanaryInterval(metrics: metrics)
        }
    }

    static func isConfiguredRouteOpen(forRequestModel requestModel: String, at now: Date = Date()) -> Bool {
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
            return false
        }
        return nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.isUnavailable(at: now) ?? false
        }
    }

    static func isNVIDIAHostedRouteOpen(forRequestModel requestModel: String, at now: Date = Date()) -> Bool {
        guard let route = resolveNVIDIAHostedRoute(forRequestModel: requestModel) else {
            return false
        }
        return nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            return routeCircuitStatesByRouteHealthKey[route.routeHealthKey]?.isUnavailable(at: now) ?? false
        }
    }

    static func recordNVIDIAHostedRouteFailure(
        forRequestModel requestModel: String,
        telemetryEvent: RouteTelemetryEvent? = nil,
        at now: Date = Date()
    ) {
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
            return
        }
        nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let current = routeCircuitStatesByRouteHealthKey[route.routeHealthKey]
            var nextState = nextRouteCircuitState(
                current: current,
                afterFailureAt: now,
                telemetryEvent: telemetryEvent,
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
            persistRouteHealthLocked()
            if let enrichedTelemetryEvent {
                logNVIDIARouteTelemetry(enrichedTelemetryEvent)
            }
        }
    }

    static func recordNVIDIAHostedRouteSuccess(
        forRequestModel requestModel: String,
        telemetryEvent: RouteTelemetryEvent? = nil,
        at now: Date = Date()
    ) {
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
            return
        }
        nvidiaRouteHealthQueue.sync {
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
            persistRouteHealthLocked()
            if let enrichedTelemetryEvent {
                logNVIDIARouteTelemetry(enrichedTelemetryEvent)
            }
        }
    }

    static func clearNVIDIAHostedRouteHealthForTesting() {
        nvidiaRouteHealthQueue.sync {
            routeCircuitStatesByRouteHealthKey = [:]
            hasLoadedPersistedRouteHealth = true
            persistRouteHealthLocked()
        }
    }

    static func forceOpenNVIDIAHostedRouteForTesting(requestModel: String, until: Date) {
        guard let route = resolveConfiguredRoute(forRequestModel: requestModel) else {
            return
        }
        nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            routeCircuitStatesByRouteHealthKey[route.routeHealthKey] = RouteCircuitState(
                status: .open,
                failureScore: routeCircuitBreakerPolicy.failureThreshold,
                recoverySuccesses: 0,
                openUntil: until,
                lastScoreUpdatedAt: until,
                lastTelemetryEvent: nil,
                rollingMetrics: .empty
            )
            persistRouteHealthLocked()
        }
    }

    static func routeHealthSnapshotForTesting() -> [String: RouteCircuitState] {
        nvidiaRouteHealthQueue.sync {
            loadPersistedRouteHealthIfNeededLocked()
            let routesByHealthKey = configuredRouteConfiguration().routesByRequestModel.values.reduce(into: [String: OpenAICompatTemporaryShim.RouteIdentity]()) { routesByHealthKey, route in
                routesByHealthKey[route.routeHealthKey] = route
            }
            return routeCircuitStatesByRouteHealthKey.reduce(into: [String: RouteCircuitState]()) { snapshot, entry in
                let canonicalModelID = routesByHealthKey[entry.key]?.canonicalModelID ?? entry.key
                snapshot[canonicalModelID] = entry.value
            }
        }
    }

    static func reloadPersistedRouteHealthForTesting() {
        nvidiaRouteHealthQueue.sync {
            hasLoadedPersistedRouteHealth = false
            routeCircuitStatesByRouteHealthKey = [:]
            loadPersistedRouteHealthIfNeededLocked()
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

    private static func isChatCompletionsPath(_ path: String) -> Bool {
        path == "/v1/chat/completions" || path == "/api/v1/chat/completions"
    }

    private static func isResponsesPath(_ path: String) -> Bool {
        path == "/v1/responses" || path == "/api/v1/responses"
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    private static func nextRouteCircuitState(
        current: RouteCircuitState?,
        afterFailureAt now: Date,
        telemetryEvent: RouteTelemetryEvent?,
        policy: RouteCircuitBreakerPolicy? = nil
    ) -> RouteCircuitState {
        let effectivePolicy = policy ?? routeCircuitBreakerPolicy
        let failurePenalty = failurePenalty(for: telemetryEvent)
        let lastTelemetryEvent = telemetryEvent ?? current?.lastTelemetryEvent
        let nextRollingMetrics = updatedRollingMetrics(
            current: current?.rollingMetrics,
            telemetryEvent: telemetryEvent
        )
        let decayedFailureScore = decayedFailureScore(
            current?.failureScore ?? 0,
            lastUpdatedAt: current?.lastScoreUpdatedAt,
            now: now
        )
        let failureThreshold = effectiveFailureThreshold(
            policy: effectivePolicy,
            metrics: nextRollingMetrics
        )

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
                    rollingMetrics: nextRollingMetrics
                )
            }
            return RouteCircuitState(
                status: .suspect,
                failureScore: nextFailureScore,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics
            )
        case .open, .halfOpen:
            return RouteCircuitState(
                status: .open,
                failureScore: failureThreshold,
                recoverySuccesses: 0,
                openUntil: now.addingTimeInterval(effectivePolicy.cooldown),
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics
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
                rollingMetrics: nextRollingMetrics
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
                    rollingMetrics: nextRollingMetrics
                )
            }
            return RouteCircuitState(
                status: .closed,
                failureScore: 0,
                recoverySuccesses: 0,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics
            )
        case .open:
            return RouteCircuitState(
                status: .halfOpen,
                failureScore: 0,
                recoverySuccesses: 1,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics
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
                    rollingMetrics: nextRollingMetrics
                )
            }
            return RouteCircuitState(
                status: .halfOpen,
                failureScore: 0,
                recoverySuccesses: nextRecoverySuccesses,
                openUntil: nil,
                lastScoreUpdatedAt: now,
                lastTelemetryEvent: lastTelemetryEvent,
                rollingMetrics: nextRollingMetrics
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
            rollingMetrics: state.rollingMetrics
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
        metrics: RouteRollingMetrics
    ) -> Int {
        guard metrics.requestCount >= 3 else {
            return policy.failureThreshold
        }
        if metrics.timeoutRate >= 0.5 || metrics.invalidSuccessRate >= 0.5 {
            return max(1, policy.failureThreshold - 1)
        }
        return policy.failureThreshold
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
        if metrics.timeoutRate >= 0.5 {
            return 3
        }
        if metrics.invalidSuccessRate >= 0.5 {
            return 2
        }
        if let averageFirstByteLatencyMilliseconds = metrics.averageFirstByteLatencyMilliseconds,
           averageFirstByteLatencyMilliseconds >= 4_000 {
            return 4
        }
        return defaultSuspectHedgeDelay
    }

    private static func recommendedNVIDIACanaryInterval(metrics: [RouteRollingMetrics]) -> TimeInterval {
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

    private static func loadPersistedRouteHealthIfNeededLocked() {
        guard !hasLoadedPersistedRouteHealth else { return }
        hasLoadedPersistedRouteHealth = true
        guard let path = routeHealthStatePath(),
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = json["routes"] as? [String: [String: Any]] else {
            routeCircuitStatesByRouteHealthKey = [:]
            return
        }

        var loaded: [String: RouteCircuitState] = [:]
        for (routeHealthKey, entry) in routes {
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
                rollingMetrics: rollingMetrics
            )
        }
        routeCircuitStatesByRouteHealthKey = loaded
    }

    private static func persistRouteHealthLocked() {
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
            routes[routeHealthKey] = entry
        }

        let payload: [String: Any] = [
            "version": 1,
            "routes": routes
        ]
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

    private static func validateToolCalls(in message: [String: Any]) -> ToolCallValidation {
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

    static func resolveConfiguredRoute(forRequestModel model: String) -> RouteIdentity? {
        configuredRouteConfiguration().routesByRequestModel[model]
    }

    private static func resolveNVIDIAHostedRoute(forRequestModel model: String) -> RouteIdentity? {
        guard let route = resolveConfiguredRoute(forRequestModel: model),
              route.providerID.hasPrefix("nvidia") else {
            return nil
        }
        return route
    }

    private static func unavailableRequestModelIDs(at now: Date) -> Set<String> {
        let routes = configuredRouteConfiguration().routesByRequestModel
        let openRouteHealthKeys: Set<String> = nvidiaRouteHealthQueue.sync {
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
                smartAliasesByAlias: loadedConfiguration.smartAliasesByAlias
            )
            cachedRouteConfiguration = cachedMap
            return cachedMap
        }
    }

    private static func loadConfiguredRouteConfiguration(from path: String?) -> (
        routesByRequestModel: [String: RouteIdentity],
        nvidiaRoutesByRequestModel: [String: RouteIdentity],
        smartAliasesByAlias: [String: SmartAliasDefinition]
    ) {
        guard let path,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ([:], [:], [:])
        }

        struct ParsedModel {
            var alias: String?
            var name: String?
        }

        struct ParsedProvider {
            var name = ""
            var baseURL = ""
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
        var smartAliasesByAlias: [String: SmartAliasDefinition] = [:]
        var currentSection: ParsedSection = .none
        var currentProvider: ParsedProvider?
        var insideModels = false
        var currentModel = ParsedModel()
        var currentSmartAliasName: String?
        var currentSmartAliasRequestClass: String?
        var currentSmartAliasFailover: String?
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
                }
                routesByRequestModel[canonicalModelID] = routeIdentity
                if isNVIDIAProvider {
                    nvidiaRoutesByRequestModel[canonicalModelID] = routeIdentity
                }
            }
            currentProvider = nil
            insideModels = false
        }

        func finalizeCurrentSmartAlias() {
            guard let smartAliasName = currentSmartAliasName else {
                currentSmartAliasRequestClass = nil
                currentSmartAliasFailover = nil
                currentSmartAliasCandidates = []
                return
            }
            let requestClass = currentSmartAliasRequestClass?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let failover = currentSmartAliasFailover?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let candidates = currentSmartAliasCandidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !requestClass.isEmpty, !failover.isEmpty, !candidates.isEmpty {
                smartAliasesByAlias[smartAliasName] = SmartAliasDefinition(
                    alias: smartAliasName,
                    requestClass: requestClass,
                    failover: failover,
                    candidates: candidates
                )
            }
            currentSmartAliasName = nil
            currentSmartAliasRequestClass = nil
            currentSmartAliasFailover = nil
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
            smartAliasesByAlias.filter { !$0.key.isEmpty }
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

    private static func mergedConfigPath() -> String? {
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
    struct BufferedProxyResponse {
        let data: Data?
        let response: HTTPURLResponse?
        let error: Error?
    }

    private var listener: NWListener?
    let proxyPort: UInt16 = 8317
    private let targetPort: UInt16 = 8318
    private let targetHost = "127.0.0.1"
    private(set) var isRunning = false
    private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.thinking-proxy-state")
    private let nvidiaInflightQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-inflight")
    private var nvidiaCanaryTimer: DispatchSourceTimer?
    private let nvidiaCanaryQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-canary")
    private var nvidiaCanarySweepInFlight = false
    private var inflightNVIDIARequests: [String: [NWConnection]] = [:]
    var nvidiaCanaryTransportForTesting: ((String, String, @escaping (Data?, HTTPURLResponse?, Error?) -> Void) -> Void)?
    var bufferedProxyTransportForTesting: ((String, String, [(String, String)], String, TimeInterval, @escaping (BufferedProxyResponse) -> Void) -> Void)?
    var deliveredHTTPResponseForTesting: ((Int, [AnyHashable: Any], Data) -> Void)?
    var deliveredErrorForTesting: ((Int, String) -> Void)?

    var vercelConfig = VercelGatewayConfig(enabled: false, apiKey: "")
    
    private enum Config {
        static let hardTokenCap = 32000
        static let minimumHeadroom = 1024
        static let headroomRatio = 0.1
        static let vercelGatewayHost = "ai-gateway.vercel.sh"
        static let anthropicVersion = "2023-06-01"
        static let nvidiaReasoningSemanticRetries = 2
        static let defaultMitigatedAttemptTimeout: TimeInterval = 30
        static let nvidiaCanaryTimeout: TimeInterval = 20
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
            startNVIDIACanaryLoop()
            
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
            stopNVIDIACanaryLoop()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
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
        
        if method == "POST" && !bodyString.isEmpty {
            if let result = processThinkingParameter(jsonString: bodyString) {
                modifiedBody = result.0
                thinkingEnabled = result.1
            }
            // Strip cache_control fields that cause 400 errors via the OAuth route
            if let stripped = stripCacheControl(from: modifiedBody) {
                modifiedBody = stripped
            }
            if let shimmed = OpenAICompatTemporaryShim.transformRequest(
                method: method,
                path: rewrittenPath,
                jsonString: modifiedBody
            ) {
                modifiedBody = shimmed
            }

            coalescingSourceBody = modifiedBody

            if let requestModel = OpenAICompatTemporaryShim.modelName(forRequestJSON: modifiedBody),
               let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: requestModel) {
                guard smartAlias.requestClass == "plain-chat",
                      smartAlias.failover == "silent",
                      OpenAICompatTemporaryShim.isSafePlainChatRequest(
                        method: method,
                        path: rewrittenPath,
                        jsonString: modifiedBody
                      ) else {
                    sendError(
                        to: connection,
                        statusCode: 501,
                        message: "The worker smart alias only supports non-streaming plain chat in this proxy; pin a specific model for streaming, tools, or structured output."
                    )
                    return
                }
                let coalescingKey = nvidiaCoalescingKey(
                    method: method,
                    path: rewrittenPath,
                    body: modifiedBody,
                    coalescingSourceBody: coalescingSourceBody,
                    requestedModelAlias: requestModel
                )
                if let coalescingKey,
                   !registerOrJoinNVIDIAInflightRequest(key: coalescingKey, connection: connection) {
                    NSLog("[ThinkingProxy] Joined coalesced smart-alias request for %@", requestModel)
                    return
                }
                forwardSmartAliasRequest(
                    method: method,
                    path: rewrittenPath,
                    headers: headers,
                    body: modifiedBody,
                    publicAlias: requestModel,
                    candidateModels: smartAlias.candidates,
                    originalConnection: connection,
                    coalescingKey: coalescingKey
                )
                return
            }

            if let preflightError = OpenAICompatTemporaryShim.preflightError(
                method: method,
                path: rewrittenPath,
                jsonString: modifiedBody
            ) {
                NSLog("[ThinkingProxy] NVIDIA preflight mitigation blocked request for \(rewrittenPath): \(preflightError.message)")
                sendError(to: connection, statusCode: preflightError.statusCode, message: preflightError.message)
                return
            }
        }

        if OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
            method: method,
            path: rewrittenPath,
            jsonString: modifiedBody
        ) {
            let retryBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: modifiedBody)
            let model = OpenAICompatTemporaryShim.modelName(forRequestJSON: modifiedBody) ?? "unknown"
            let coalescingKey = nvidiaCoalescingKey(
                method: method,
                path: rewrittenPath,
                body: modifiedBody,
                coalescingSourceBody: coalescingSourceBody,
                requestedModelAlias: nil
            )
            if let coalescingKey,
               !registerOrJoinNVIDIAInflightRequest(key: coalescingKey, connection: connection) {
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
                    initialTransportRetries: retryBudget?.transport ?? Config.nvidiaReasoningSemanticRetries,
                    initialSemanticRetries: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    transportRetriesRemaining: retryBudget?.transport ?? Config.nvidiaReasoningSemanticRetries,
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
        originalConnection: NWConnection,
        coalescingKey: String?
    ) {
        attemptSmartAliasCandidate(
            method: method,
            path: path,
            headers: headers,
            currentBody: body,
            publicAlias: publicAlias,
            remainingCandidateModels: candidateModels,
            failoverDepth: 0,
            originalConnection: originalConnection,
            coalescingKey: coalescingKey
        )
    }

    private func attemptSmartAliasCandidate(
        method: String,
        path: String,
        headers: [(String, String)],
        currentBody: String,
        publicAlias: String,
        remainingCandidateModels: [String],
        failoverDepth: Int,
        originalConnection: NWConnection,
        coalescingKey: String?
    ) {
        guard let transition = OpenAICompatTemporaryShim.nextSmartAliasCandidateTransition(
            publicAlias: publicAlias,
            method: method,
            path: path,
            currentBody: currentBody,
            candidateModelsRemaining: remainingCandidateModels
        ) else {
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
                    failoverDepth: failoverDepth + 1,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey
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

        if let candidateRoute = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: transition.model),
           candidateRoute.providerID.hasPrefix("nvidia"),
           OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
            method: method,
            path: path,
            jsonString: transition.body
           ) {
            let retryBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: transition.body)
            attemptSmartAliasMitigatedCandidate(
                method: method,
                path: path,
                headers: headers,
                body: transition.body,
                publicAlias: publicAlias,
                currentCandidateModel: transition.model,
                remainingCandidateModels: transition.remainingCandidateModels,
                failoverDepth: failoverDepth,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey,
                state: OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: transition.model,
                    initialTransportRetries: retryBudget?.transport ?? Config.nvidiaReasoningSemanticRetries,
                    initialSemanticRetries: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    transportRetriesRemaining: retryBudget?.transport ?? Config.nvidiaReasoningSemanticRetries,
                    semanticRetriesRemaining: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    retryBackoffMilliseconds: retryBudget?.backoffMilliseconds ?? 0,
                    salvagesBestEffortRepair: retryBudget?.salvagesBestEffortRepair ?? false,
                    bestEffortRepairedBodyData: nil,
                    coalescingKey: coalescingKey
                )
            )
            return
        }

        let timeoutInterval = smartAliasCandidateTimeout(forRequestJSON: transition.body)
        sendBufferedProxyRequest(
            method: method,
            path: path,
            headers: headers,
            body: transition.body,
            timeoutInterval: timeoutInterval
        ) { [weak self] bufferedResponse in
            guard let self else { return }
            self.handleSmartAliasBufferedCandidateResult(
                bufferedResponse,
                method: method,
                path: path,
                headers: headers,
                candidateBody: transition.body,
                publicAlias: publicAlias,
                candidateModel: transition.model,
                remainingCandidateModels: transition.remainingCandidateModels,
                failoverDepth: failoverDepth,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey
            )
        }
    }

    private func attemptSmartAliasMitigatedCandidate(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        publicAlias: String,
        currentCandidateModel: String,
        remainingCandidateModels: [String],
        failoverDepth: Int,
        originalConnection: NWConnection,
        coalescingKey: String?,
        state: OpenAICompatTemporaryShim.NVIDIARetryState
    ) {
        let timeoutInterval = smartAliasCandidateTimeout(forRequestJSON: body)
        sendBufferedProxyRequest(
            method: method,
            path: path,
            headers: headers,
            body: body,
            timeoutInterval: timeoutInterval
        ) { [weak self] bufferedResponse in
            guard let self else { return }

            let attempt = OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                data: bufferedResponse.data,
                response: bufferedResponse.response,
                error: bufferedResponse.error,
                deadlineStage: .none
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
                    attemptLane: 1
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )

            switch outcome {
            case .retry(let nextState):
                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
                self.attemptSmartAliasMitigatedCandidate(
                    method: method,
                    path: path,
                    headers: headers,
                    body: body,
                    publicAlias: publicAlias,
                    currentCandidateModel: currentCandidateModel,
                    remainingCandidateModels: remainingCandidateModels,
                    failoverDepth: failoverDepth,
                    originalConnection: originalConnection,
                    coalescingKey: coalescingKey,
                    state: nextState
                )
            case .sendResponse(let statusCode, let responseHeaders, let responseBody):
                let winningTelemetry = self.annotatedSmartAliasTelemetryEvent(
                    OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                        telemetryEvent,
                        winnerAttemptLane: 1
                    ),
                    requestedAlias: publicAlias,
                    failoverDepth: failoverDepth,
                    finalWinnerRequestModel: statusCode >= 200 && statusCode < 300 ? currentCandidateModel : nil
                )
                if self.shouldFailoverSmartAliasCandidate(onHTTPStatus: statusCode) {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                        forRequestModel: currentCandidateModel,
                        telemetryEvent: winningTelemetry
                    )
                    self.attemptSmartAliasCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: body,
                        publicAlias: publicAlias,
                        remainingCandidateModels: remainingCandidateModels,
                        failoverDepth: failoverDepth + 1,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey
                    )
                    return
                }

                if statusCode >= 200 && statusCode < 300 {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(
                        forRequestModel: currentCandidateModel,
                        telemetryEvent: winningTelemetry
                    )
                    self.deliverBufferedHTTPResponse(
                        defaultConnection: originalConnection,
                        statusCode: statusCode,
                        headers: responseHeaders,
                        body: responseBody,
                        coalescingKey: coalescingKey,
                        overridingModel: publicAlias
                    )
                    return
                }

                OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(winningTelemetry)
                self.deliverBufferedHTTPResponse(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    headers: responseHeaders,
                    body: responseBody,
                    coalescingKey: coalescingKey
                )
            case .sendError(let statusCode, let message):
                let winningTelemetry = self.annotatedSmartAliasTelemetryEvent(
                    OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                        telemetryEvent,
                        winnerAttemptLane: 1
                    ),
                    requestedAlias: publicAlias,
                    failoverDepth: failoverDepth,
                    finalWinnerRequestModel: nil
                )
                if self.shouldFailoverSmartAliasCandidate(onHTTPStatus: statusCode) {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                        forRequestModel: currentCandidateModel,
                        telemetryEvent: winningTelemetry
                    )
                    self.attemptSmartAliasCandidate(
                        method: method,
                        path: path,
                        headers: headers,
                        currentBody: body,
                        publicAlias: publicAlias,
                        remainingCandidateModels: remainingCandidateModels,
                        failoverDepth: failoverDepth + 1,
                        originalConnection: originalConnection,
                        coalescingKey: coalescingKey
                    )
                    return
                }

                if statusCode == 429 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                        forRequestModel: currentCandidateModel,
                        telemetryEvent: winningTelemetry
                    )
                } else {
                    OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(winningTelemetry)
                }
                self.deliverBufferedError(
                    defaultConnection: originalConnection,
                    statusCode: statusCode,
                    message: message,
                    coalescingKey: coalescingKey
                )
            }
        }
    }

    private func handleSmartAliasBufferedCandidateResult(
        _ bufferedResponse: BufferedProxyResponse,
        method: String,
        path: String,
        headers: [(String, String)],
        candidateBody: String,
        publicAlias: String,
        candidateModel: String,
        remainingCandidateModels: [String],
        failoverDepth: Int,
        originalConnection: NWConnection,
        coalescingKey: String?
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
                    failoverDepth: failoverDepth,
                    failureClass: transportFailureClass(error),
                    timeoutStage: .none,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "smart_alias"
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )
            OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                forRequestModel: candidateModel,
                telemetryEvent: telemetryEvent
            )
            attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: candidateBody,
                publicAlias: publicAlias,
                remainingCandidateModels: remainingCandidateModels,
                failoverDepth: failoverDepth + 1,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey
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
                    failoverDepth: failoverDepth,
                    failureClass: "missing_response_material",
                    timeoutStage: .none,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "smart_alias"
                ),
                requestedAlias: publicAlias,
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: nil
            )
            OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                forRequestModel: candidateModel,
                telemetryEvent: telemetryEvent
            )
            attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: candidateBody,
                publicAlias: publicAlias,
                remainingCandidateModels: remainingCandidateModels,
                failoverDepth: failoverDepth + 1,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey
            )
            return
        }

        let statusCode = response.statusCode
        let shouldFailover = shouldFailoverSmartAliasCandidate(onHTTPStatus: statusCode)
        let failureClass = shouldFailover ? "classified_\(statusCode)" : nil
        let telemetryEvent = annotatedSmartAliasTelemetryEvent(
            OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(),
                requestModel: candidateModel,
                requestedAlias: publicAlias,
                canonicalModelID: route?.canonicalModelID ?? candidateModel,
                transportOutcome: statusCode >= 200 && statusCode < 300 ? "send_response" : "send_error",
                failoverDepth: failoverDepth,
                finalWinnerRequestModel: (!shouldFailover && statusCode >= 200 && statusCode < 300) ? candidateModel : nil,
                failureClass: failureClass,
                timeoutStage: .none,
                upstreamHTTPStatus: statusCode,
                retryCount: 0,
                source: "smart_alias"
            ),
            requestedAlias: publicAlias,
            failoverDepth: failoverDepth,
            finalWinnerRequestModel: (!shouldFailover && statusCode >= 200 && statusCode < 300) ? candidateModel : nil
        )

        if shouldFailover {
            OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                forRequestModel: candidateModel,
                telemetryEvent: telemetryEvent
            )
            attemptSmartAliasCandidate(
                method: method,
                path: path,
                headers: headers,
                currentBody: candidateBody,
                publicAlias: publicAlias,
                remainingCandidateModels: remainingCandidateModels,
                failoverDepth: failoverDepth + 1,
                originalConnection: originalConnection,
                coalescingKey: coalescingKey
            )
            return
        }

        if statusCode >= 200 && statusCode < 300 {
            OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(
                forRequestModel: candidateModel,
                telemetryEvent: telemetryEvent
            )
            deliverBufferedHTTPResponse(
                defaultConnection: originalConnection,
                statusCode: statusCode,
                headers: response.allHeaderFields,
                body: responseData,
                coalescingKey: coalescingKey,
                overridingModel: publicAlias
            )
            return
        }

        OpenAICompatTemporaryShim.logNVIDIARouteTelemetry(telemetryEvent)
        deliverBufferedHTTPResponse(
            defaultConnection: originalConnection,
            statusCode: statusCode,
            headers: response.allHeaderFields,
            body: responseData,
            coalescingKey: coalescingKey
        )
    }

    private func shouldFailoverSmartAliasCandidate(onHTTPStatus statusCode: Int) -> Bool {
        statusCode == 429 || statusCode >= 500
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

    private func sendBufferedProxyRequest(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        timeoutInterval: TimeInterval,
        completion: @escaping (BufferedProxyResponse) -> Void
    ) {
        if let bufferedProxyTransportForTesting {
            bufferedProxyTransportForTesting(method, path, headers, body, timeoutInterval, completion)
            return
        }

        guard let url = URL(string: "http://\(targetHost):\(targetPort)\(path)") else {
            completion(BufferedProxyResponse(data: nil, response: nil, error: URLError(.badURL)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = timeoutInterval

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("close", forHTTPHeaderField: "Connection")

        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { data, response, error in
            completion(
                BufferedProxyResponse(
                    data: data,
                    response: response as? HTTPURLResponse,
                    error: error
                )
            )
            session.finishTasksAndInvalidate()
        }.resume()
    }

    private func smartAliasCandidateTimeout(forRequestJSON jsonString: String) -> TimeInterval {
        min(
            OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: jsonString) ?? Config.defaultMitigatedAttemptTimeout,
            Config.defaultMitigatedAttemptTimeout
        )
    }

    private func nvidiaCoalescingKey(
        method: String,
        path: String,
        body: String,
        coalescingSourceBody: String,
        requestedModelAlias: String?
    ) -> String? {
        if let requestedModelAlias,
           OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: requestedModelAlias) != nil,
           OpenAICompatTemporaryShim.isSafePlainChatRequest(
                method: method,
                path: path,
                jsonString: coalescingSourceBody
           ) {
            return "\(method) \(path)\n\(coalescingSourceBody)"
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
        return "\(method) \(path)\n\(body)"
    }

    private func registerOrJoinNVIDIAInflightRequest(
        key: String,
        connection: NWConnection
    ) -> Bool {
        nvidiaInflightQueue.sync {
            if inflightNVIDIARequests[key] != nil {
                inflightNVIDIARequests[key, default: []].append(connection)
                return false
            }
            inflightNVIDIARequests[key] = [connection]
            return true
        }
    }

    func registerOrJoinNVIDIAInflightRequestForTesting(key: String, connection: NWConnection) -> Bool {
        registerOrJoinNVIDIAInflightRequest(key: key, connection: connection)
    }

    func inflightNVIDIAWaiterCount(for key: String) -> Int {
        nvidiaInflightQueue.sync {
            inflightNVIDIARequests[key]?.count ?? 0
        }
    }

    func takeInflightNVIDIAConnectionsForTesting(for key: String) -> [NWConnection]? {
        takeInflightNVIDIAConnections(for: key)
    }

    private func takeInflightNVIDIAConnections(for key: String?) -> [NWConnection]? {
        guard let key else { return nil }
        return nvidiaInflightQueue.sync {
            let connections = inflightNVIDIARequests.removeValue(forKey: key)
            return connections
        }
    }

    private func deliverBufferedHTTPResponse(
        defaultConnection: NWConnection,
        statusCode: Int,
        headers: [AnyHashable: Any],
        body: Data,
        coalescingKey: String?,
        overridingModel: String? = nil
    ) {
        let deliveredBody = rewrittenResponseBody(
            body,
            overridingModelWith: overridingModel,
            statusCode: statusCode
        ) ?? body
        let connections = takeInflightNVIDIAConnections(for: coalescingKey) ?? [defaultConnection]
        for connection in connections {
            sendHTTPResponse(
                to: connection,
                statusCode: statusCode,
                headers: headers,
                body: deliveredBody
            )
        }
    }

    private func deliverBufferedError(
        defaultConnection: NWConnection,
        statusCode: Int,
        message: String,
        coalescingKey: String?
    ) {
        let connections = takeInflightNVIDIAConnections(for: coalescingKey) ?? [defaultConnection]
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

        let excludedHeaders: Set<String> = ["content-length", "host", "connection", "transfer-encoding"]
        for (name, value) in headers where !excludedHeaders.contains(name.lowercased()) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue("close", forHTTPHeaderField: "Connection")

        let responseProgress = ResponseProgressDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: responseProgress, delegateQueue: nil)
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            defer {
                coordinator.finishAttemptWithoutWinning(attemptLane: attemptLane)
                responseProgress.finish()
                session.finishTasksAndInvalidate()
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
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
                } else if statusCode == 429 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
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
                if statusCode == 429 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: state.model, telemetryEvent: winningTelemetryEvent)
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
        coordinator.registerAttempt(attemptLane: attemptLane) {
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

    private func startNVIDIACanaryLoop() {
        stateQueue.sync {
            guard nvidiaCanaryTimer == nil else { return }
            scheduleNextNVIDIACanaryLocked(after: OpenAICompatTemporaryShim.recommendedNVIDIACanaryInterval())
        }
    }

    private func scheduleNextNVIDIACanaryLocked(after interval: TimeInterval) {
        nvidiaCanaryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: nvidiaCanaryQueue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler { [weak self] in
            self?.performNVIDIACanariesOnce { [weak self] in
                guard let self else { return }
                self.stateQueue.sync {
                    guard self.isRunning else { return }
                    self.scheduleNextNVIDIACanaryLocked(after: OpenAICompatTemporaryShim.recommendedNVIDIACanaryInterval())
                }
            }
        }
        nvidiaCanaryTimer = timer
        timer.resume()
    }

    private func stopNVIDIACanaryLoop() {
        stateQueue.sync {
            nvidiaCanaryTimer?.cancel()
            nvidiaCanaryTimer = nil
            nvidiaCanarySweepInFlight = false
        }
    }

    func performNVIDIACanariesOnce(completion: (() -> Void)? = nil) {
        let shouldStart = stateQueue.sync { () -> Bool in
            guard !nvidiaCanarySweepInFlight else { return false }
            nvidiaCanarySweepInFlight = true
            return true
        }
        guard shouldStart else {
            completion?()
            return
        }

        let requestModels = OpenAICompatTemporaryShim.quarantinedNVIDIAHostedRequestModels()
        guard !requestModels.isEmpty else {
            stateQueue.sync { nvidiaCanarySweepInFlight = false }
            completion?()
            return
        }

        runNVIDIACanary(at: 0, requestModels: requestModels) { [weak self] in
            self?.stateQueue.sync { self?.nvidiaCanarySweepInFlight = false }
            completion?()
        }
    }

    private func runNVIDIACanary(at index: Int, requestModels: [String], completion: @escaping () -> Void) {
        guard index < requestModels.count else {
            completion()
            return
        }

        let requestModel = requestModels[index]
        let requestJSON = nvidiaCanaryRequestJSON(forRequestModel: requestModel)
        let transformedJSON = OpenAICompatTemporaryShim.transformRequest(
            method: "POST",
            path: "/v1/chat/completions",
            jsonString: requestJSON
        ) ?? requestJSON

        sendNVIDIACanaryRequest(requestModel: requestModel, requestJSON: transformedJSON) { [weak self] data, response, error in
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
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(
                        forRequestModel: requestModel,
                        telemetryEvent: telemetryEvent
                    )
                } else {
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                        forRequestModel: requestModel,
                        telemetryEvent: telemetryEvent
                    )
                }
            case .retry, .sendError:
                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                    forRequestModel: requestModel,
                    telemetryEvent: telemetryEvent
                )
            }

            self.runNVIDIACanary(at: index + 1, requestModels: requestModels, completion: completion)
        }
    }

    private func sendNVIDIACanaryRequest(
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
        request.timeoutInterval = Config.nvidiaCanaryTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("close", forHTTPHeaderField: "Connection")

        URLSession.shared.dataTask(with: request) { data, response, error in
            completion(data, response as? HTTPURLResponse, error)
        }.resume()
    }

    private func nvidiaCanaryRequestJSON(forRequestModel requestModel: String) -> String {
        """
        {
          "model": "\(requestModel)",
          "messages": [
            {"role": "user", "content": "Return exactly: OK"}
          ],
          "max_tokens": 32,
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
    private func sendError(to connection: NWConnection, statusCode: Int, message: String) {
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
        
        let headers = "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)\r\n" +
                     "Content-Type: text/plain\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
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
        if let deliveredHTTPResponseForTesting {
            deliveredHTTPResponseForTesting(statusCode, headers, body)
            connection.cancel()
            return
        }
        var response = "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)\r\n"
        var excludedHeaders: Set<String> = ["content-length", "connection", "transfer-encoding"]
        excludedHeaders.formUnion(overridingHeaders.keys.map { $0.lowercased() })

        for (rawName, rawValue) in headers {
            guard let name = rawName as? String,
                  !excludedHeaders.contains(name.lowercased()) else {
                continue
            }
            response += "\(name): \(String(describing: rawValue))\r\n"
        }

        for (name, value) in overridingHeaders {
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
}
