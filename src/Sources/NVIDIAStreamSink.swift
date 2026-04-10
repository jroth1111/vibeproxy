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
    let policy: NVIDIAStreamSinkPolicy
    private(set) var emittedFrames: [String] = []
    private(set) var lastUpstreamActivityAt: Date?
    private(set) var lastDownstreamActivityAt: Date?
    private(set) var keepaliveCount = 0
    private(set) var terminalReceived = false

    init(policy: NVIDIAStreamSinkPolicy = .streamed) {
        self.policy = policy
    }

    mutating func consume(_ output: NVIDIAStreamParserOutput) throws {
        try consume(output, receivedAt: Date())
    }

    mutating func consume(
        _ output: NVIDIAStreamParserOutput,
        receivedAt: Date
    ) throws {
        lastUpstreamActivityAt = receivedAt
        switch output {
        case .comment(let comment):
            emittedFrames.append(":\(comment)\n\n")
        case .done:
            emittedFrames.append("data: [DONE]\n\n")
            terminalReceived = true
        case .message(let message):
            emittedFrames.append(render(message))
        }
        lastDownstreamActivityAt = receivedAt
    }

    mutating func emitKeepaliveIfIdle(now: Date = Date()) -> String? {
        guard policy.emitsDownstreamKeepalives, !terminalReceived else { return nil }
        let lastActivityAt = lastDownstreamActivityAt ?? lastUpstreamActivityAt
        guard let lastActivityAt,
              now.timeIntervalSince(lastActivityAt) >= policy.keepaliveIntervalSeconds else {
            return nil
        }
        let frame = ":\(policy.keepaliveComment)\n\n"
        emittedFrames.append(frame)
        lastDownstreamActivityAt = now
        keepaliveCount += 1
        return frame
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
