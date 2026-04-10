import Foundation

enum NVIDIAExecutionSurface: String, Equatable {
    case direct
    case smartAlias
}

struct NVIDIAStreamOwner: Equatable {
    let surface: NVIDIAExecutionSurface
    let attemptLane: Int
}

struct NVIDIAStreamExecutionPolicy: Equatable {
    let retryAllowed: Bool
    let hedgeAllowed: Bool
    let owner: NVIDIAStreamOwner?
}

struct NVIDIAStreamState: Equatable {
    var firstByteReceivedAt: Date?
    var lastChunkReceivedAt: Date?
    var meaningfulOutputEmitted = false
    var meaningfulOutputOwner: NVIDIAStreamOwner?
    var toolCallStarted = false
    var terminalReceived = false
    var upstreamErrorSeen = false
}

struct NVIDIAStreamSemanticFlags: Equatable {
    var meaningfulOutput = false
    var toolCallStarted = false
    var upstreamErrorSeen = false

    mutating func formUnion(_ other: NVIDIAStreamSemanticFlags) {
        meaningfulOutput = meaningfulOutput || other.meaningfulOutput
        toolCallStarted = toolCallStarted || other.toolCallStarted
        upstreamErrorSeen = upstreamErrorSeen || other.upstreamErrorSeen
    }
}

struct NVIDIAStreamEngine {
    private var parser: NVIDIAStreamParser
    private(set) var state = NVIDIAStreamState()

    init(parser: NVIDIAStreamParser = NVIDIAStreamParser()) {
        self.parser = parser
    }

    mutating func ingest(
        _ chunk: Data,
        receivedAt: Date = Date(),
        surface: NVIDIAExecutionSurface = .direct,
        attemptLane: Int = 1
    ) throws -> [NVIDIAStreamParserOutput] {
        guard !chunk.isEmpty else { return [] }
        if state.firstByteReceivedAt == nil {
            state.firstByteReceivedAt = receivedAt
        }
        state.lastChunkReceivedAt = receivedAt

        let outputs = try parser.ingest(chunk)
        apply(outputs, surface: surface, attemptLane: attemptLane)
        return outputs
    }

    mutating func finish(
        receivedAt: Date = Date(),
        surface: NVIDIAExecutionSurface = .direct,
        attemptLane: Int = 1
    ) throws -> [NVIDIAStreamParserOutput] {
        let outputs = try parser.finish()
        if !outputs.isEmpty {
            if state.firstByteReceivedAt == nil {
                state.firstByteReceivedAt = receivedAt
            }
            state.lastChunkReceivedAt = receivedAt
        }
        apply(outputs, surface: surface, attemptLane: attemptLane)
        return outputs
    }

    func executionPolicy(
        surface: NVIDIAExecutionSurface,
        attemptLane: Int
    ) -> NVIDIAStreamExecutionPolicy {
        let owner = state.meaningfulOutputOwner
        let allowsFurtherExecution = owner == nil && !state.terminalReceived
        return NVIDIAStreamExecutionPolicy(
            retryAllowed: allowsFurtherExecution,
            hedgeAllowed: allowsFurtherExecution,
            owner: owner
        )
    }

    func ownsMeaningfulOutput(
        surface: NVIDIAExecutionSurface,
        attemptLane: Int
    ) -> Bool {
        state.meaningfulOutputOwner == NVIDIAStreamOwner(surface: surface, attemptLane: attemptLane)
    }

    private mutating func apply(
        _ outputs: [NVIDIAStreamParserOutput],
        surface: NVIDIAExecutionSurface,
        attemptLane: Int
    ) {
        for output in outputs {
            switch output {
            case .comment:
                continue
            case .done:
                state.terminalReceived = true
            case .message(let message):
                let flags = Self.semanticFlags(for: message)
                if flags.meaningfulOutput {
                    state.meaningfulOutputEmitted = true
                    if state.meaningfulOutputOwner == nil {
                        state.meaningfulOutputOwner = NVIDIAStreamOwner(surface: surface, attemptLane: attemptLane)
                    }
                }
                if flags.toolCallStarted {
                    state.toolCallStarted = true
                }
                if flags.upstreamErrorSeen {
                    state.upstreamErrorSeen = true
                }
            }
        }
    }

    static func semanticFlags(for message: NVIDIAStreamMessage) -> NVIDIAStreamSemanticFlags {
        let payload = message.joinedData.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return NVIDIAStreamSemanticFlags() }

        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NVIDIAStreamSemanticFlags(meaningfulOutput: true)
        }

        return semanticFlags(forJSONObject: object)
    }

    private static func semanticFlags(forJSONObject object: Any) -> NVIDIAStreamSemanticFlags {
        if let dictionary = object as? [String: Any] {
            if dictionary["error"] != nil {
                return NVIDIAStreamSemanticFlags(upstreamErrorSeen: true)
            }

            var flags = NVIDIAStreamSemanticFlags()
            let type = dictionary["type"] as? String
            if type == "error" {
                flags.upstreamErrorSeen = true
            }
            if type == "response.output_text.delta",
               hasVisibleText(dictionary["delta"]) {
                flags.meaningfulOutput = true
            }
            if let type, type.contains("tool_call") {
                flags.toolCallStarted = true
                flags.meaningfulOutput = true
            }

            if let choices = dictionary["choices"] as? [Any] {
                for choice in choices {
                    flags.formUnion(semanticFlags(fromChoice: choice))
                }
            }

            if let output = dictionary["output"] as? [Any] {
                for item in output {
                    flags.formUnion(semanticFlags(fromOutputItem: item))
                }
            }

            if flags.meaningfulOutput == false,
               hasVisibleText(dictionary["text"]) || hasVisibleText(dictionary["delta"]) || hasVisibleText(dictionary["content"]) {
                flags.meaningfulOutput = true
            }

            if flags.toolCallStarted == false,
               let toolCalls = dictionary["tool_calls"] as? [Any],
               !toolCalls.isEmpty {
                flags.toolCallStarted = true
                flags.meaningfulOutput = true
            }

            return flags
        }

        if let array = object as? [Any] {
            return array.reduce(into: NVIDIAStreamSemanticFlags()) { partial, element in
                partial.formUnion(semanticFlags(forJSONObject: element))
            }
        }

        if let text = object as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NVIDIAStreamSemanticFlags(meaningfulOutput: true)
        }

        return NVIDIAStreamSemanticFlags()
    }

    private static func semanticFlags(fromChoice choice: Any) -> NVIDIAStreamSemanticFlags {
        guard let dictionary = choice as? [String: Any] else { return NVIDIAStreamSemanticFlags() }
        var flags = NVIDIAStreamSemanticFlags()

        if let delta = dictionary["delta"] as? [String: Any] {
            if hasVisibleText(delta["content"]) {
                flags.meaningfulOutput = true
            }
            if let toolCalls = delta["tool_calls"] as? [Any], !toolCalls.isEmpty {
                flags.toolCallStarted = true
                flags.meaningfulOutput = true
            }
        }

        if let message = dictionary["message"] as? [String: Any],
           hasVisibleText(message["content"]) {
            flags.meaningfulOutput = true
        }

        return flags
    }

    private static func semanticFlags(fromOutputItem item: Any) -> NVIDIAStreamSemanticFlags {
        guard let dictionary = item as? [String: Any] else { return NVIDIAStreamSemanticFlags() }
        var flags = NVIDIAStreamSemanticFlags()

        if let type = dictionary["type"] as? String, type.contains("tool_call") {
            flags.toolCallStarted = true
            flags.meaningfulOutput = true
        }

        if let content = dictionary["content"] as? [Any] {
            for element in content {
                if hasVisibleText(element) {
                    flags.meaningfulOutput = true
                }
            }
        }

        if hasVisibleText(dictionary["text"]) {
            flags.meaningfulOutput = true
        }

        return flags
    }

    private static func hasVisibleText(_ value: Any?) -> Bool {
        switch value {
        case let text as String:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case let elements as [Any]:
            return elements.contains { element in
                if let dictionary = element as? [String: Any] {
                    return hasVisibleText(dictionary["text"]) || hasVisibleText(dictionary["content"])
                }
                return hasVisibleText(element)
            }
        case let dictionary as [String: Any]:
            return hasVisibleText(dictionary["text"]) ||
                hasVisibleText(dictionary["content"]) ||
                hasVisibleText(dictionary["delta"])
        default:
            return false
        }
    }
}
