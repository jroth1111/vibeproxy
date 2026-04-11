import Foundation

@main
struct NVIDIAStreamTransportSpec {
    static func main() {
        let recorder = NVIDIAStreamFailureRecorder()

        runNVIDIAStreamSpec("direct transport policy prefers http/1.1 semantics", recorder: recorder) {
            let policy = NVIDIATransportPolicy.direct
            expectNVIDIAEqual(
                policy.protocolPreference,
                .http1Only,
                "nvidia transport should require the dedicated http/1.1 path",
                recorder: recorder
            )
            expectNVIDIAEqual(
                Int(policy.interChunkReadTimeoutSeconds),
                300,
                "nvidia transport should tolerate long inter-chunk silence",
                recorder: recorder
            )
            expectNVIDIATrue(
                policy.waitsForConnectivity,
                "nvidia transport should wait briefly for connectivity",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("direct transport timeout budgets inherit the scaled slow-success budget", recorder: recorder) {
            let budget = NVIDIATransportPolicy.direct.scaledTimeoutBudget(scaleTimeout: { $0 * 3 })
            expectNVIDIAEqual(
                Int(budget.request),
                900,
                "request timeout should scale from the direct transport policy",
                recorder: recorder
            )
            expectNVIDIAEqual(
                Int(budget.resource),
                1080,
                "resource timeout should scale from the direct transport policy",
                recorder: recorder
            )
            expectNVIDIATrue(
                NVIDIATransportPolicy.direct.waitsForConnectivity,
                "scaled transport budgets should preserve waitsForConnectivity policy",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("event stream sink emits keepalives only after the idle window", recorder: recorder) {
            var sink = NVIDIAEventStreamSink(policy: .streamed)
            let start = Date(timeIntervalSince1970: 100)
            try sink.consume(
                .message(NVIDIAStreamMessage(event: nil, identifier: nil, retryMilliseconds: nil, dataLines: ["{\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}"])),
                receivedAt: start
            )
            expectNVIDIAEqual(
                sink.emitKeepaliveIfIdle(now: start.addingTimeInterval(7)),
                nil,
                "keepalive should not fire before the idle interval elapses",
                recorder: recorder
            )
            expectNVIDIAEqual(
                sink.emitKeepaliveIfIdle(now: start.addingTimeInterval(8)),
                ": keepalive\n\n",
                "keepalive should fire once the idle interval elapses",
                recorder: recorder
            )
            expectNVIDIAEqual(
                sink.keepaliveCount,
                1,
                "sink should track emitted keepalives",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("event stream sink stops keepalives after terminal done", recorder: recorder) {
            var sink = NVIDIAEventStreamSink(policy: .streamed)
            let start = Date(timeIntervalSince1970: 200)
            try sink.consume(.done, receivedAt: start)
            expectNVIDIAEqual(
                sink.emitKeepaliveIfIdle(now: start.addingTimeInterval(20)),
                nil,
                "terminal streams must not emit downstream keepalives",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("buffered sink policy disables keepalives", recorder: recorder) {
            var sink = NVIDIAEventStreamSink(policy: .buffered)
            let start = Date(timeIntervalSince1970: 300)
            try sink.consume(
                .message(NVIDIAStreamMessage(event: nil, identifier: nil, retryMilliseconds: nil, dataLines: ["{}"])),
                receivedAt: start
            )
            expectNVIDIAEqual(
                sink.emitKeepaliveIfIdle(now: start.addingTimeInterval(60)),
                nil,
                "buffered transport should never emit keepalives",
                recorder: recorder
            )
        }

        recorder.finish()
    }
}
