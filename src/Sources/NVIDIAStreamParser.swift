import Foundation

enum NVIDIAStreamParserError: Error, Equatable, CustomStringConvertible {
    case frameTooLarge(limitBytes: Int, actualBytes: Int)
    case invalidUTF8Frame

    var description: String {
        switch self {
        case .frameTooLarge(let limitBytes, let actualBytes):
            return "frame_too_large(limitBytes: \(limitBytes), actualBytes: \(actualBytes))"
        case .invalidUTF8Frame:
            return "invalid_utf8_frame"
        }
    }
}

struct NVIDIAStreamMessage: Equatable {
    var event: String?
    var identifier: String?
    var retryMilliseconds: Int?
    var dataLines: [String]

    var joinedData: String {
        dataLines.joined(separator: "\n")
    }
}

enum NVIDIAStreamParserOutput: Equatable {
    case comment(String)
    case message(NVIDIAStreamMessage)
    case done
}

struct NVIDIAStreamParser {
    private let maximumFrameBytes: Int
    private var pendingBytes = Data()

    init(maximumFrameBytes: Int = 256 * 1024) {
        self.maximumFrameBytes = maximumFrameBytes
    }

    var pendingFrameBytes: Int {
        pendingBytes.count
    }

    mutating func ingest(_ chunk: Data) throws -> [NVIDIAStreamParserOutput] {
        guard !chunk.isEmpty else { return [] }
        pendingBytes.append(chunk)
        try validatePendingFrameBudget()

        var outputs: [NVIDIAStreamParserOutput] = []
        while let boundary = nextFrameBoundary(in: pendingBytes) {
            let frameData = pendingBytes.subdata(in: 0..<boundary.frameEnd)
            pendingBytes.removeSubrange(0..<boundary.consumeEnd)
            outputs.append(contentsOf: try parseFrame(frameData))
        }

        return outputs
    }

    mutating func finish() throws -> [NVIDIAStreamParserOutput] {
        guard !pendingBytes.isEmpty else { return [] }
        let trailingFrame = pendingBytes
        pendingBytes.removeAll(keepingCapacity: false)
        return try parseFrame(trailingFrame)
    }

    private mutating func validatePendingFrameBudget() throws {
        guard pendingBytes.count > maximumFrameBytes else { return }
        throw NVIDIAStreamParserError.frameTooLarge(
            limitBytes: maximumFrameBytes,
            actualBytes: pendingBytes.count
        )
    }

    private func parseFrame(_ frameData: Data) throws -> [NVIDIAStreamParserOutput] {
        guard !frameData.isEmpty else { return [] }
        guard frameData.count <= maximumFrameBytes else {
            throw NVIDIAStreamParserError.frameTooLarge(
                limitBytes: maximumFrameBytes,
                actualBytes: frameData.count
            )
        }
        guard let frameText = String(data: frameData, encoding: .utf8) else {
            throw NVIDIAStreamParserError.invalidUTF8Frame
        }

        let normalized = frameText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var outputs: [NVIDIAStreamParserOutput] = []
        var message = NVIDIAStreamMessage(event: nil, identifier: nil, retryMilliseconds: nil, dataLines: [])
        var sawMessageField = false

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(line)
            if rawLine.hasPrefix(":") {
                outputs.append(.comment(Self.stripOptionalLeadingSpace(from: String(rawLine.dropFirst()))))
                continue
            }

            let field: String
            let value: String
            if let separator = rawLine.firstIndex(of: ":") {
                field = String(rawLine[..<separator])
                value = Self.stripOptionalLeadingSpace(from: String(rawLine[rawLine.index(after: separator)...]))
            } else {
                field = rawLine
                value = ""
            }

            switch field {
            case "event":
                message.event = value
                sawMessageField = true
            case "id":
                message.identifier = value
                sawMessageField = true
            case "retry":
                if let parsed = Int(value) {
                    message.retryMilliseconds = parsed
                }
                sawMessageField = true
            case "data":
                message.dataLines.append(value)
                sawMessageField = true
            default:
                continue
            }
        }

        guard sawMessageField else { return outputs }
        if message.joinedData == "[DONE]" {
            outputs.append(.done)
        } else {
            outputs.append(.message(message))
        }
        return outputs
    }

    private static func stripOptionalLeadingSpace(from value: String) -> String {
        guard value.first == " " else { return value }
        return String(value.dropFirst())
    }

    private func nextFrameBoundary(in data: Data) -> (frameEnd: Int, consumeEnd: Int)? {
        let bytes = Array(data)
        var index = 0

        while index < bytes.count {
            if index + 3 < bytes.count,
               bytes[index] == 0x0D,
               bytes[index + 1] == 0x0A,
               bytes[index + 2] == 0x0D,
               bytes[index + 3] == 0x0A {
                return (frameEnd: index, consumeEnd: index + 4)
            }

            if index + 1 < bytes.count,
               bytes[index] == 0x0A,
               bytes[index + 1] == 0x0A {
                return (frameEnd: index, consumeEnd: index + 2)
            }

            if index + 1 < bytes.count,
               bytes[index] == 0x0D,
               bytes[index + 1] == 0x0D {
                return (frameEnd: index, consumeEnd: index + 2)
            }

            if index + 2 < bytes.count,
               bytes[index] == 0x0D,
               bytes[index + 1] == 0x0A,
               bytes[index + 2] == 0x0A {
                return (frameEnd: index, consumeEnd: index + 3)
            }

            if index + 2 < bytes.count,
               bytes[index] == 0x0A,
               bytes[index + 1] == 0x0D,
               bytes[index + 2] == 0x0A {
                return (frameEnd: index, consumeEnd: index + 3)
            }

            index += 1
        }

        return nil
    }
}
