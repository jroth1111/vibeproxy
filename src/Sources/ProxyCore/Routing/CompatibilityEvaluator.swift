import Foundation

public final class CompatibilityEvaluator {
    public enum CompatibilityResult: Equatable {
        case compatible
        case incompatible(reason: String)
    }

    public init() {}

    // MARK: - NVIDIA Route Compatibility

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

    // MARK: - Path Utilities

    public static func isChatCompletionsPath(_ path: String) -> Bool {
        path == "/v1/chat/completions" || path == "/api/v1/chat/completions"
    }

    public static func isResponsesPath(_ path: String) -> Bool {
        path == "/v1/responses" || path == "/api/v1/responses"
    }

    public static func chatCompletionsPath(matching path: String) -> String {
        path.hasPrefix("/api/") ? "/api/v1/chat/completions" : "/v1/chat/completions"
    }

    // MARK: - Tool Choice

    public static func hasStrictToolChoice(in json: [String: Any]) -> Bool {
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

    // MARK: - Streaming Detection

    public static func requestedStream(forRequestJSON jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["stream"] as? Bool == true
    }

    // MARK: - Media Content

    private static let unsupportedMediaTypes: Set<String> = [
        "input_image", "image", "image_url",
        "input_audio", "audio", "audio_url",
        "file", "input_file",
        "video", "input_video"
    ]

    private static let unsupportedMediaKeys: Set<String> = [
        "image", "image_url",
        "audio", "audio_url",
        "file", "file_data", "file_url",
        "video", "video_url"
    ]

    public static func containsUnsupportedMediaContent(_ dictionary: [String: Any]) -> Bool {
        if let type = (dictionary["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           unsupportedMediaTypes.contains(type) {
            return true
        }
        return dictionary.keys.contains(where: { unsupportedMediaKeys.contains($0) })
    }

    public static func containsUnsupportedMediaPayload(_ value: Any) -> Bool {
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

    public static func containsUnsupportedMediaMessageContent(in json: [String: Any]) -> Bool {
        guard let messages = json["messages"] as? [[String: Any]] else {
            return false
        }
        for message in messages {
            if let content = message["content"],
               containsUnsupportedMediaPayload(content) {
                return true
            }
        }
        return false
    }

    // MARK: - JSON Parsing Utilities

    public static func rawModelName(forRequestJSON jsonString: String) -> String? {
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let model = json["model"] as? String else {
            return nil
        }
        return model
    }

    public static func requiredToolParametersIndex(forRequestJSON jsonString: String) -> [String: [String]]? {
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
}
