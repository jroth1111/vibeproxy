import Foundation
import Network

enum OpenAICompatTemporaryShim {
    struct ClientFacingNVIDIAFailure {
        let statusCode: Int
        let message: String
    }

    private struct CachedNVIDIAAliasMap {
        let configPath: String?
        let modificationDate: Date?
        let aliasesByModel: [String: String]
    }

    private static let genericNvidiaFallbackPolicy = RequestPolicy(
        responseProfile: .genericSanity,
        minimumMaxTokens: nil,
        strippedFields: ["reasoning_effort", "frequency_penalty", "presence_penalty", "ignore_eos"],
        attemptTimeout: 200,
        firstResponseDeadline: 25,
        transportRetries: 0,
        semanticRetries: 2,
        retryBackoffMilliseconds: 250,
        stripsReasoningFieldFromSuccess: true,
        salvagesBestEffortRepair: true
    )
    private static let nvidiaReasoningModelPolicies: [String: RequestPolicy] = [
        "glm5": RequestPolicy(
            responseProfile: .transportOnly,
            minimumMaxTokens: nil,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 200,
            firstResponseDeadline: 25,
            transportRetries: 0,
            semanticRetries: 0,
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            salvagesBestEffortRepair: false
        ),
        "kimi-k2.5": RequestPolicy(
            responseProfile: .kimiReasoningOnly,
            minimumMaxTokens: 384,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 200,
            firstResponseDeadline: 25,
            transportRetries: 0,
            semanticRetries: 2,
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            salvagesBestEffortRepair: false
        ),
        "minimax-m2.5": RequestPolicy(
            responseProfile: .minimaxThinkLeak,
            minimumMaxTokens: 128,
            strippedFields: ["reasoning_effort", "response_format", "stop", "frequency_penalty", "presence_penalty", "ignore_eos"],
            attemptTimeout: 200,
            firstResponseDeadline: 25,
            transportRetries: 0,
            semanticRetries: 2,
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: true,
            salvagesBestEffortRepair: true
        ),
        "glm-4.7": RequestPolicy(
            responseProfile: .genericSanity,
            minimumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            salvagesBestEffortRepair: false
        ),
        "glm-5": RequestPolicy(
            responseProfile: .genericSanity,
            minimumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            salvagesBestEffortRepair: false
        ),
        "glm-5-turbo": RequestPolicy(
            responseProfile: .genericSanity,
            minimumMaxTokens: nil,
            strippedFields: [],
            attemptTimeout: 200,
            firstResponseDeadline: nil,
            transportRetries: 2,
            semanticRetries: 2,
            retryBackoffMilliseconds: 250,
            stripsReasoningFieldFromSuccess: false,
            salvagesBestEffortRepair: false
        )
    ]

    private enum ResponseProfile {
        case transportOnly
        case kimiReasoningOnly
        case minimaxThinkLeak
        case genericSanity
    }

    private struct RequestPolicy {
        let responseProfile: ResponseProfile
        let minimumMaxTokens: Int?
        let strippedFields: Set<String>
        let attemptTimeout: TimeInterval?
        let firstResponseDeadline: TimeInterval?
        let transportRetries: Int
        let semanticRetries: Int
        let retryBackoffMilliseconds: Int
        let stripsReasoningFieldFromSuccess: Bool
        let salvagesBestEffortRepair: Bool
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
    private static let nvidiaAliasCacheQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-alias-cache")
    private static var cachedNVIDIAAliasMap: CachedNVIDIAAliasMap?

    struct NvidiaReasoningEvaluation {
        let retryReason: String?
        let repairedBodyData: Data?
        let normalizedBodyData: Data?

        var shouldRetry: Bool {
            retryReason != nil
        }
    }

    private enum ToolCallValidation {
        case none
        case valid
        case invalid(reason: String)
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

        if (json["stream"] as? Bool) == true {
            json["stream"] = false
            modified = true
        }
        if json["stream_options"] != nil {
            json.removeValue(forKey: "stream_options")
            modified = true
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
            if let toolChoice = json["tool_choice"] as? String, ["function", "required"].contains(toolChoice) {
                json["tool_choice"] = "auto"
                modified = true
            } else if let toolChoice = json["tool_choice"] as? [String: Any],
                      let type = toolChoice["type"] as? String,
                      ["function", "required"].contains(type) {
                json["tool_choice"] = "auto"
                modified = true
            }
        }

        if model == "kimi-k2.5" {
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
            if (json["stream"] as? Bool) != true,
               (json["include_reasoning"] as? Bool) != false {
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

    static func preflightError(method: String, path: String, jsonString: String) -> ClientFacingNVIDIAFailure? {
        guard method == "POST",
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String,
              isNVIDIAHostedModel(model) else {
            return nil
        }

        if isResponsesPath(path) {
            return ClientFacingNVIDIAFailure(
                statusCode: 501,
                message: "NVIDIA hosted inference does not reliably support /v1/responses via this proxy; use /v1/chat/completions."
            )
        }

        if isChatCompletionsPath(path),
           containsUnsupportedTypedMessageContent(in: json) {
            return ClientFacingNVIDIAFailure(
                statusCode: 400,
                message: "NVIDIA hosted chat completions currently require string message content; typed content arrays are not supported on this route."
            )
        }

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

        return policy(forModel: model) != nil
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

    static func synthesizeEventStreamBody(fromChatCompletionBody bodyData: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first else {
            return nil
        }

        let message = choice["message"] as? [String: Any] ?? [:]
        let role = (message["role"] as? String) ?? "assistant"
        let content = message["content"] as? String
        let toolCalls = message["tool_calls"] as? [[String: Any]]
        let finishReason = (choice["finish_reason"] as? String) ?? "stop"
        let identifier = (json["id"] as? String) ?? UUID().uuidString

        var events: [String] = []

        if let roleChunk = encodeStreamChunk(
            id: identifier,
            delta: ["role": role],
            finishReason: nil
        ) {
            events.append(roleChunk)
        }

        if let content,
           !content.isEmpty,
           let contentChunk = encodeStreamChunk(
            id: identifier,
            delta: ["content": content],
            finishReason: nil
           ) {
            events.append(contentChunk)
        }

        if let toolCalls,
           !toolCalls.isEmpty,
           let toolCallChunk = encodeStreamChunk(
            id: identifier,
            delta: ["tool_calls": toolCalls],
            finishReason: nil
           ) {
            events.append(toolCallChunk)
        }

        if let finalChunk = encodeStreamChunk(
            id: identifier,
            delta: [:],
            finishReason: finishReason
        ) {
            events.append(finalChunk)
        }

        events.append("data: [DONE]\n\n")
        return events.joined().data(using: .utf8)
    }

    static func attemptTimeout(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.attemptTimeout
    }

    static func firstResponseDeadline(forRequestJSON jsonString: String) -> TimeInterval? {
        policy(forRequestJSON: jsonString)?.firstResponseDeadline
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

    static func modelName(forRequestJSON jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return nil
        }
        return model
    }

    static func evaluateNvidiaReasoningResponse(model: String, statusCode: Int, bodyData: Data) -> NvidiaReasoningEvaluation {
        guard let policy = policy(forModel: model) else {
            return NvidiaReasoningEvaluation(retryReason: nil, repairedBodyData: nil, normalizedBodyData: nil)
        }

        if statusCode == 200, bodyData.isEmpty {
            return NvidiaReasoningEvaluation(retryReason: "empty_content", repairedBodyData: nil, normalizedBodyData: nil)
        }

        guard statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              !choices.isEmpty else {
            return NvidiaReasoningEvaluation(retryReason: nil, repairedBodyData: nil, normalizedBodyData: nil)
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
        case .invalid(let reason):
            return NvidiaReasoningEvaluation(
                retryReason: reason,
                repairedBodyData: nil,
                normalizedBodyData: nil
            )
        case .valid:
            return NvidiaReasoningEvaluation(
                retryReason: nil,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        case .none:
            break
        }

        switch policy.responseProfile {
        case .transportOnly:
            return NvidiaReasoningEvaluation(
                retryReason: nil,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        case .kimiReasoningOnly:
            if trimmedContent.isEmpty,
               !reasoning.isEmpty,
               finishReason == "length" {
                return NvidiaReasoningEvaluation(
                    retryReason: "reasoning_only_content_missing",
                    repairedBodyData: nil,
                    normalizedBodyData: nil
                )
            }
            if trimmedContent.isEmpty {
                return NvidiaReasoningEvaluation(
                    retryReason: "empty_content",
                    repairedBodyData: nil,
                    normalizedBodyData: nil
                )
            }
            return NvidiaReasoningEvaluation(
                retryReason: nil,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        case .minimaxThinkLeak:
            if trimmedContent.isEmpty {
                return NvidiaReasoningEvaluation(
                    retryReason: "empty_content",
                    repairedBodyData: nil,
                    normalizedBodyData: nil
                )
            }
            guard startsWithThinkTag(trimmedContent) else {
                return NvidiaReasoningEvaluation(
                    retryReason: nil,
                    repairedBodyData: nil,
                    normalizedBodyData: normalizedBodyData
                )
            }
            let repairedBodyData = normalizedResponseBody(
                json: json,
                contentOverride: stripLeadingThinkBlock(from: content),
                stripsReasoningField: policy.stripsReasoningFieldFromSuccess
            )
            return NvidiaReasoningEvaluation(
                retryReason: "reasoning_leak_length",
                repairedBodyData: repairedBodyData,
                normalizedBodyData: nil
            )
        case .genericSanity:
            if trimmedContent.isEmpty,
               !reasoning.isEmpty,
               finishReason == "length" {
                return NvidiaReasoningEvaluation(
                    retryReason: "reasoning_only_content_missing",
                    repairedBodyData: nil,
                    normalizedBodyData: nil
                )
            }
            if trimmedContent.isEmpty {
                return NvidiaReasoningEvaluation(
                    retryReason: "empty_content",
                    repairedBodyData: nil,
                    normalizedBodyData: nil
                )
            }
            if startsWithThinkTag(trimmedContent) {
                let repairedBodyData = normalizedResponseBody(
                    json: json,
                    contentOverride: stripLeadingThinkBlock(from: content),
                    stripsReasoningField: policy.stripsReasoningFieldFromSuccess
                )
                return NvidiaReasoningEvaluation(
                    retryReason: "reasoning_leak_length",
                    repairedBodyData: repairedBodyData,
                    normalizedBodyData: nil
                )
            }
            return NvidiaReasoningEvaluation(
                retryReason: nil,
                repairedBodyData: nil,
                normalizedBodyData: normalizedBodyData
            )
        }
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

    private static func encodeStreamChunk(
        id: String,
        delta: [String: Any],
        finishReason: String?
    ) -> String? {
        let encodedFinishReason: Any = finishReason ?? NSNull()
        let chunk: [String: Any] = [
            "id": id,
            "choices": [[
                "index": 0,
                "delta": delta,
                "finish_reason": encodedFinishReason
            ]]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: chunk),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return "data: \(string)\n\n"
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
                return .invalid(reason: "malformed_tool_arguments")
            }

            let trimmedArguments = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedArguments.isEmpty else {
                return .invalid(reason: "malformed_tool_arguments")
            }
            guard let argumentsData = trimmedArguments.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: argumentsData),
                  jsonObject is [String: Any] else {
                return .invalid(reason: "malformed_tool_arguments")
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
        if let policy = nvidiaReasoningModelPolicies[model] {
            return policy
        }
        if configuredNVIDIAProviderIDsByModelAlias()[model] != nil {
            return genericNvidiaFallbackPolicy
        }
        return nil
    }

    private static func isNVIDIAHostedModel(_ model: String) -> Bool {
        if ["glm5", "kimi-k2.5", "minimax-m2.5"].contains(model) {
            return true
        }
        return configuredNVIDIAProviderIDsByModelAlias()[model] != nil
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

    private static func configuredNVIDIAProviderIDsByModelAlias() -> [String: String] {
        let path = mergedConfigPath()
        let modificationDate = path.flatMap { configPath in
            (try? FileManager.default.attributesOfItem(atPath: configPath)[.modificationDate]) as? Date
        }

        return nvidiaAliasCacheQueue.sync {
            if let cachedNVIDIAAliasMap,
               cachedNVIDIAAliasMap.configPath == path,
               cachedNVIDIAAliasMap.modificationDate == modificationDate {
                return cachedNVIDIAAliasMap.aliasesByModel
            }

            let aliasesByModel = loadConfiguredNVIDIAProviderIDsByModelAlias(from: path)
            cachedNVIDIAAliasMap = CachedNVIDIAAliasMap(
                configPath: path,
                modificationDate: modificationDate,
                aliasesByModel: aliasesByModel
            )
            return aliasesByModel
        }
    }

    private static func loadConfiguredNVIDIAProviderIDsByModelAlias(from path: String?) -> [String: String] {
        guard let path,
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        struct ParsedProvider {
            var name = ""
            var baseURL = ""
            var modelAliases: [String] = []
        }

        var aliasesByModel: [String: String] = [:]
        var insideOpenAICompatibility = false
        var currentProvider: ParsedProvider?
        var insideModels = false
        var currentModelAlias: String?

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
            guard let providerValue = currentProvider,
                  let aliasValue = currentModelAlias?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !aliasValue.isEmpty else {
                currentModelAlias = nil
                return
            }
            var provider = providerValue
            provider.modelAliases.append(aliasValue)
            currentProvider = provider
            currentModelAlias = nil
        }

        func finalizeCurrentProvider() {
            finalizeCurrentModel()
            guard let provider = currentProvider else {
                return
            }
            let trimmedName = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBaseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isNVIDIAProvider = trimmedName.hasPrefix("nvidia") || trimmedBaseURL.contains("integrate.api.nvidia.com")
            if isNVIDIAProvider {
                let providerID = trimmedName.isEmpty ? "nvidia" : trimmedName
                for alias in provider.modelAliases {
                    aliasesByModel[alias] = providerID
                }
            }
            currentProvider = nil
            insideModels = false
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if !insideOpenAICompatibility {
                if trimmed == "openai-compatibility:" {
                    insideOpenAICompatibility = true
                }
                continue
            }

            let indent = indentation(of: line)
            if indent == 0 && !trimmed.hasPrefix("- ") {
                finalizeCurrentProvider()
                break
            }

            if indent == 0 && trimmed.hasPrefix("- ") {
                finalizeCurrentProvider()
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
                if trimmed.hasPrefix("- alias: ") || trimmed.hasPrefix("- name: ") {
                    currentModelAlias = scalarValue(from: trimmed)
                }
                continue
            }

            if indent >= 4, trimmed.hasPrefix("alias: "), let value = scalarValue(from: trimmed) {
                currentModelAlias = value
                continue
            }

            if indent >= 4,
               trimmed.hasPrefix("name: "),
               currentModelAlias == nil,
               let value = scalarValue(from: trimmed) {
                currentModelAlias = value
            }
        }

        finalizeCurrentProvider()
        return aliasesByModel
    }

    private static func mergedConfigPath() -> String? {
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
    private var listener: NWListener?
    let proxyPort: UInt16 = 8317
    private let targetPort: UInt16 = 8318
    private let targetHost = "127.0.0.1"
    private(set) var isRunning = false
    private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.thinking-proxy-state")

    var vercelConfig = VercelGatewayConfig(enabled: false, apiKey: "")
    
    private enum Config {
        static let hardTokenCap = 32000
        static let minimumHeadroom = 1024
        static let headroomRatio = 0.1
        static let vercelGatewayHost = "ai-gateway.vercel.sh"
        static let anthropicVersion = "2023-06-01"
        static let nvidiaReasoningSemanticRetries = 2
        static let defaultMitigatedAttemptTimeout: TimeInterval = 30
    }

    private struct NvidiaReasoningRetryState {
        let model: String
        let originalStreamRequested: Bool
        var transportRetriesRemaining: Int
        var semanticRetriesRemaining: Int
        let retryBackoffMilliseconds: Int
        let salvagesBestEffortRepair: Bool
        var bestEffortRepairedBodyData: Data?
    }

    private final class ResponseProgressDelegate: NSObject, URLSessionDataDelegate {
        private let stateQueue = DispatchQueue(label: "io.automaze.vibeproxy.nvidia-first-response")
        private var hasReceivedPayload = false
        private var deadlineExceeded = false
        private var deadlineWorkItem: DispatchWorkItem?

        func installFirstResponseDeadline(
            seconds: TimeInterval?,
            for task: URLSessionTask
        ) {
            guard let seconds, seconds > 0 else {
                return
            }

            let workItem = DispatchWorkItem { [weak self, weak task] in
                guard let self else { return }
                let shouldCancel = self.stateQueue.sync { () -> Bool in
                    guard !self.hasReceivedPayload else {
                        return false
                    }
                    self.deadlineExceeded = true
                    return true
                }
                if shouldCancel {
                    task?.cancel()
                }
            }

            stateQueue.sync {
                deadlineWorkItem = workItem
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds, execute: workItem)
        }

        func finish() {
            stateQueue.sync {
                hasReceivedPayload = true
                deadlineWorkItem?.cancel()
                deadlineWorkItem = nil
            }
        }

        func didExceedDeadline() -> Bool {
            stateQueue.sync { deadlineExceeded }
        }

        private func markPayloadReceived() {
            stateQueue.sync {
                hasReceivedPayload = true
                deadlineWorkItem?.cancel()
                deadlineWorkItem = nil
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
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
            NSLog("[ThinkingProxy] Stopped")
        }
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
        
        // Try to parse and modify JSON body for POST requests
        var modifiedBody = bodyString
        var thinkingEnabled = false
        var nvidiaOriginalStreamRequested = false
        
        if method == "POST" && !bodyString.isEmpty {
            if let result = processThinkingParameter(jsonString: bodyString) {
                modifiedBody = result.0
                thinkingEnabled = result.1
            }
            // Strip cache_control fields that cause 400 errors via the OAuth route
            if let stripped = stripCacheControl(from: modifiedBody) {
                modifiedBody = stripped
            }
            nvidiaOriginalStreamRequested = OpenAICompatTemporaryShim.requestedStream(forRequestJSON: modifiedBody)
            if let shimmed = OpenAICompatTemporaryShim.transformRequest(
                method: method,
                path: rewrittenPath,
                jsonString: modifiedBody
            ) {
                modifiedBody = shimmed
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
            forwardNvidiaReasoningRequestWithRetry(
                method: method,
                path: rewrittenPath,
                headers: headers,
                body: modifiedBody,
                originalConnection: connection,
                state: NvidiaReasoningRetryState(
                    model: model,
                    originalStreamRequested: nvidiaOriginalStreamRequested,
                    transportRetriesRemaining: retryBudget?.transport ?? Config.nvidiaReasoningSemanticRetries,
                    semanticRetriesRemaining: retryBudget?.semantic ?? Config.nvidiaReasoningSemanticRetries,
                    retryBackoffMilliseconds: retryBudget?.backoffMilliseconds ?? 0,
                    salvagesBestEffortRepair: retryBudget?.salvagesBestEffortRepair ?? false,
                    bestEffortRepairedBodyData: nil
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

    private func forwardNvidiaReasoningRequestWithRetry(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: NvidiaReasoningRetryState
    ) {
        guard let url = URL(string: "http://\(targetHost):\(targetPort)\(path)") else {
            sendError(to: originalConnection, statusCode: 500, message: "Internal Server Error")
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
                responseProgress.finish()
                session.finishTasksAndInvalidate()
            }

            if let error {
                let effectiveError: Error
                if responseProgress.didExceedDeadline() {
                    effectiveError = URLError(.timedOut)
                } else {
                    effectiveError = error
                }
                if state.transportRetriesRemaining > 0,
                   OpenAICompatTemporaryShim.shouldRetryNvidiaReasoningTransport(error: effectiveError) {
                    NSLog(
                        "[ThinkingProxy] Retrying temporary NVIDIA reasoning-model shim request due to transport error %@ (%d retries left)",
                        effectiveError.localizedDescription,
                        state.transportRetriesRemaining
                    )
                    self.scheduleNvidiaReasoningRetry(
                        method: method,
                        path: path,
                        headers: headers,
                        body: body,
                        originalConnection: originalConnection,
                        state: NvidiaReasoningRetryState(
                            model: state.model,
                            originalStreamRequested: state.originalStreamRequested,
                            transportRetriesRemaining: state.transportRetriesRemaining - 1,
                            semanticRetriesRemaining: state.semanticRetriesRemaining,
                            retryBackoffMilliseconds: state.retryBackoffMilliseconds,
                            salvagesBestEffortRepair: state.salvagesBestEffortRepair,
                            bestEffortRepairedBodyData: state.bestEffortRepairedBodyData
                        )
                    )
                    return
                }

                if state.salvagesBestEffortRepair,
                   let repairedBodyData = state.bestEffortRepairedBodyData {
                    NSLog("[ThinkingProxy] Returning preserved best-effort repaired response after transport exhaustion")
                    let synthesizedStreamBody = state.originalStreamRequested
                        ? OpenAICompatTemporaryShim.synthesizeEventStreamBody(fromChatCompletionBody: repairedBodyData)
                        : nil
                    let bodyToSend = synthesizedStreamBody ?? repairedBodyData
                    self.sendHTTPResponse(
                        to: originalConnection,
                        statusCode: 200,
                        headers: ["Content-Type": "application/json; charset=utf-8"],
                        body: bodyToSend,
                        overridingHeaders: synthesizedStreamBody != nil
                            ? ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                            : [:]
                    )
                    return
                }

                NSLog("[ThinkingProxy] NVIDIA reasoning-model shim backend request failed: \(effectiveError)")
                let nsError = effectiveError as NSError
                let statusCode = nsError.domain == NSURLErrorDomain &&
                    nsError.code == URLError.Code.timedOut.rawValue ? 504 : 502
                self.sendError(
                    to: originalConnection,
                    statusCode: statusCode,
                    message: statusCode == 504 ? "Gateway Timeout" : "Bad Gateway"
                )
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let bodyData = data else {
                self.sendError(to: originalConnection, statusCode: 502, message: "Bad Gateway")
                return
            }

            if let classifiedFailure = OpenAICompatTemporaryShim.classifyUpstreamFailure(
                model: state.model,
                path: path,
                statusCode: httpResponse.statusCode,
                bodyData: bodyData
            ) {
                NSLog(
                    "[ThinkingProxy] Classified NVIDIA upstream failure for %@ on %@ as HTTP %d: %@",
                    state.model,
                    path,
                    httpResponse.statusCode,
                    classifiedFailure.message
                )
                self.sendError(
                    to: originalConnection,
                    statusCode: classifiedFailure.statusCode,
                    message: classifiedFailure.message
                )
                return
            }

            if state.transportRetriesRemaining > 0,
               OpenAICompatTemporaryShim.shouldRetryNvidiaReasoningTransport(statusCode: httpResponse.statusCode) {
                NSLog(
                    "[ThinkingProxy] Retrying temporary NVIDIA reasoning-model shim request due to HTTP %d (%d retries left)",
                    httpResponse.statusCode,
                    state.transportRetriesRemaining
                )
                    self.scheduleNvidiaReasoningRetry(
                        method: method,
                        path: path,
                        headers: headers,
                        body: body,
                        originalConnection: originalConnection,
                        state: NvidiaReasoningRetryState(
                            model: state.model,
                            originalStreamRequested: state.originalStreamRequested,
                            transportRetriesRemaining: state.transportRetriesRemaining - 1,
                            semanticRetriesRemaining: state.semanticRetriesRemaining,
                            retryBackoffMilliseconds: state.retryBackoffMilliseconds,
                            salvagesBestEffortRepair: state.salvagesBestEffortRepair,
                            bestEffortRepairedBodyData: state.bestEffortRepairedBodyData
                    )
                )
                return
            }

            let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                model: state.model,
                statusCode: httpResponse.statusCode,
                bodyData: bodyData
            )

            if evaluation.shouldRetry {
                let bestEffortRepairedBodyData = evaluation.repairedBodyData ?? state.bestEffortRepairedBodyData
                if state.semanticRetriesRemaining > 0 {
                    NSLog(
                        "[ThinkingProxy] Retrying temporary provider mitigation request due to %@ (%d retries left)",
                        evaluation.retryReason ?? "unknown",
                        state.semanticRetriesRemaining
                    )
                    self.scheduleNvidiaReasoningRetry(
                        method: method,
                        path: path,
                        headers: headers,
                        body: body,
                        originalConnection: originalConnection,
                        state: NvidiaReasoningRetryState(
                            model: state.model,
                            originalStreamRequested: state.originalStreamRequested,
                            transportRetriesRemaining: state.transportRetriesRemaining,
                            semanticRetriesRemaining: state.semanticRetriesRemaining - 1,
                            retryBackoffMilliseconds: state.retryBackoffMilliseconds,
                            salvagesBestEffortRepair: state.salvagesBestEffortRepair,
                            bestEffortRepairedBodyData: bestEffortRepairedBodyData
                        )
                    )
                    return
                }

                if let repairedBodyData = bestEffortRepairedBodyData {
                    NSLog("[ThinkingProxy] Applied response repair for temporary provider mitigation shim")
                    let synthesizedStreamBody = state.originalStreamRequested
                        ? OpenAICompatTemporaryShim.synthesizeEventStreamBody(fromChatCompletionBody: repairedBodyData)
                        : nil
                    let bodyToSend = synthesizedStreamBody ?? repairedBodyData
                    self.sendHTTPResponse(
                        to: originalConnection,
                        statusCode: 200,
                        headers: httpResponse.allHeaderFields,
                        body: bodyToSend,
                        overridingHeaders: synthesizedStreamBody != nil
                            ? ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                            : [:]
                    )
                    return
                }

                NSLog(
                    "[ThinkingProxy] Exhausted temporary provider mitigation retries after %@; returning gateway error instead of invalid upstream success",
                    evaluation.retryReason ?? "unknown"
                )
                self.sendError(
                    to: originalConnection,
                    statusCode: 502,
                    message: "Bad Gateway - Upstream provider returned an unusable response"
                )
                return
            }

            let responseBodyData = evaluation.normalizedBodyData ?? bodyData
            let synthesizedStreamBody = state.originalStreamRequested && httpResponse.statusCode == 200
                ? OpenAICompatTemporaryShim.synthesizeEventStreamBody(fromChatCompletionBody: responseBodyData)
                : nil
            let bodyToSend = synthesizedStreamBody ?? responseBodyData
            self.sendHTTPResponse(
                to: originalConnection,
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields,
                body: bodyToSend,
                overridingHeaders: synthesizedStreamBody != nil
                    ? ["Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-cache"]
                    : [:]
            )
        }
        responseProgress.installFirstResponseDeadline(
            seconds: OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: body),
            for: task
        )
        task.resume()
    }

    private func scheduleNvidiaReasoningRetry(
        method: String,
        path: String,
        headers: [(String, String)],
        body: String,
        originalConnection: NWConnection,
        state: NvidiaReasoningRetryState
    ) {
        let delay = DispatchTimeInterval.milliseconds(max(0, state.retryBackoffMilliseconds))
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.forwardNvidiaReasoningRequestWithRetry(
                method: method,
                path: path,
                headers: headers,
                body: body,
                originalConnection: originalConnection,
                state: state
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
