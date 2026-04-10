import Foundation

protocol NVIDIAStreamSink {
    mutating func consume(_ output: NVIDIAStreamParserOutput) throws
}

struct NVIDIABufferedAccumulatorSink: NVIDIAStreamSink, Equatable {
    private(set) var comments: [String] = []
    private(set) var messages: [NVIDIAStreamMessage] = []
    private(set) var terminalReceived = false

    mutating func consume(_ output: NVIDIAStreamParserOutput) throws {
        switch output {
        case .comment(let comment):
            comments.append(comment)
        case .message(let message):
            messages.append(message)
        case .done:
            terminalReceived = true
        }
    }
}

struct NVIDIAEventStreamSink: NVIDIAStreamSink, Equatable {
    private(set) var emittedFrames: [String] = []

    mutating func consume(_ output: NVIDIAStreamParserOutput) throws {
        switch output {
        case .comment(let comment):
            emittedFrames.append(":\(comment)\n\n")
        case .done:
            emittedFrames.append("data: [DONE]\n\n")
        case .message(let message):
            emittedFrames.append(render(message))
        }
    }

    private func render(_ message: NVIDIAStreamMessage) -> String {
        var lines: [String] = []
        if let event = message.event {
            lines.append("event: \(event)")
        }
        if let identifier = message.identifier {
            lines.append("id: \(identifier)")
        }
        if let retryMilliseconds = message.retryMilliseconds {
            lines.append("retry: \(retryMilliseconds)")
        }
        for dataLine in message.dataLines {
            lines.append("data: \(dataLine)")
        }
        return lines.joined(separator: "\n") + "\n\n"
    }
}
