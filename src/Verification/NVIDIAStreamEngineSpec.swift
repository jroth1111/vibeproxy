import Foundation

@main
struct NVIDIAStreamEngineSpec {
    static func main() {
        let recorder = NVIDIAStreamFailureRecorder()

        runNVIDIAStreamSpec("engine tracks first byte and meaningful text output", recorder: recorder) {
            var engine = NVIDIAStreamEngine()
            let receivedAt = Date(timeIntervalSince1970: 1_700_000_000)
            let outputs = try engine.ingest(
                Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\n".utf8),
                receivedAt: receivedAt
            )
            expectNVIDIAEqual(outputs.count, 1, "engine should emit parsed frames", recorder: recorder)
            expectNVIDIAEqual(engine.state.firstByteReceivedAt, receivedAt, "engine should latch the first byte timestamp", recorder: recorder)
            expectNVIDIAEqual(engine.state.lastChunkReceivedAt, receivedAt, "engine should track the latest chunk timestamp", recorder: recorder)
            expectNVIDIATrue(engine.state.meaningfulOutputEmitted, "visible text should mark the stream as meaningful", recorder: recorder)
            expectNVIDIATrue(engine.state.toolCallStarted == false, "plain text should not start tool-call state", recorder: recorder)
        }

        runNVIDIAStreamSpec("engine marks tool-call output as meaningful and sticky", recorder: recorder) {
            var engine = NVIDIAStreamEngine()
            _ = try engine.ingest(
                Data("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\"}]}}]}\n\n".utf8),
                receivedAt: Date(timeIntervalSince1970: 10)
            )
            expectNVIDIATrue(engine.state.toolCallStarted, "tool-call deltas should latch tool-call state", recorder: recorder)
            expectNVIDIATrue(engine.state.meaningfulOutputEmitted, "tool-call deltas should count as meaningful output", recorder: recorder)

            _ = try engine.ingest(Data("data: {\"choices\":[{\"delta\":{}}]}\n\n".utf8), receivedAt: Date(timeIntervalSince1970: 11))
            expectNVIDIATrue(engine.state.toolCallStarted, "tool-call state should stay sticky once started", recorder: recorder)
        }

        runNVIDIAStreamSpec("engine marks upstream error frames without treating them as meaningful output", recorder: recorder) {
            var engine = NVIDIAStreamEngine()
            _ = try engine.ingest(Data("data: {\"error\":{\"message\":\"rate limited\"}}\n\n".utf8))
            expectNVIDIATrue(engine.state.upstreamErrorSeen, "error payloads should latch upstream error state", recorder: recorder)
            expectNVIDIATrue(engine.state.meaningfulOutputEmitted == false, "error payloads alone should not count as meaningful output", recorder: recorder)
        }

        runNVIDIAStreamSpec("engine marks terminal receipt on the done sentinel", recorder: recorder) {
            var engine = NVIDIAStreamEngine()
            _ = try engine.ingest(Data("data: [DONE]\n\n".utf8))
            expectNVIDIATrue(engine.state.terminalReceived, "done sentinel should mark terminal receipt", recorder: recorder)
        }

        runNVIDIAStreamSpec("buffered and event-stream sinks consume the same parser outputs", recorder: recorder) {
            let outputs: [NVIDIAStreamParserOutput] = [
                .comment("keepalive"),
                .message(NVIDIAStreamMessage(event: "message", identifier: "abc", retryMilliseconds: 500, dataLines: ["{\"delta\":\"OK\"}"])),
                .done
            ]
            var buffered = NVIDIABufferedAccumulatorSink()
            var stream = NVIDIAEventStreamSink()

            for output in outputs {
                try buffered.consume(output)
                try stream.consume(output)
            }

            expectNVIDIAEqual(buffered.comments, ["keepalive"], "buffered sink should preserve comments", recorder: recorder)
            expectNVIDIAEqual(buffered.messages.count, 1, "buffered sink should preserve messages", recorder: recorder)
            expectNVIDIATrue(buffered.terminalReceived, "buffered sink should record terminal receipt", recorder: recorder)
            expectNVIDIAEqual(
                stream.emittedFrames,
                [
                    ":keepalive\n\n",
                    "event: message\nid: abc\nretry: 500\ndata: {\"delta\":\"OK\"}\n\n",
                    "data: [DONE]\n\n"
                ],
                "event-stream sink should render SSE wire frames deterministically",
                recorder: recorder
            )
        }

        for surface in [NVIDIAExecutionSurface.direct, .smartAlias] {
            runNVIDIAStreamSpec("engine locks request ownership after meaningful \(surface.rawValue) text output", recorder: recorder) {
                var engine = NVIDIAStreamEngine()
                let openPolicy = engine.executionPolicy(surface: surface, attemptLane: 1)
                expectNVIDIATrue(openPolicy.retryAllowed, "retries should be allowed before meaningful output", recorder: recorder)
                expectNVIDIATrue(openPolicy.hedgeAllowed, "hedges should be allowed before meaningful output", recorder: recorder)

                _ = try engine.ingest(
                    Data("data: {\"choices\":[{\"delta\":{\"content\":\"OK\"}}]}\n\n".utf8),
                    surface: surface,
                    attemptLane: 2
                )

                let lockedPolicy = engine.executionPolicy(surface: surface, attemptLane: 2)
                expectNVIDIATrue(lockedPolicy.retryAllowed == false, "retries should stop after meaningful output", recorder: recorder)
                expectNVIDIATrue(lockedPolicy.hedgeAllowed == false, "hedges should stop after meaningful output", recorder: recorder)
                expectNVIDIAEqual(
                    lockedPolicy.owner,
                    NVIDIAStreamOwner(surface: surface, attemptLane: 2),
                    "the first meaningful lane should own the request",
                    recorder: recorder
                )
                expectNVIDIATrue(
                    engine.ownsMeaningfulOutput(surface: surface, attemptLane: 2),
                    "the winning lane should stay recorded as the request owner",
                    recorder: recorder
                )
            }

            runNVIDIAStreamSpec("engine locks request ownership after meaningful \(surface.rawValue) tool-call output", recorder: recorder) {
                var engine = NVIDIAStreamEngine()
                _ = try engine.ingest(
                    Data("data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\"}]}}]}\n\n".utf8),
                    surface: surface,
                    attemptLane: 3
                )

                let lockedPolicy = engine.executionPolicy(surface: surface, attemptLane: 1)
                expectNVIDIATrue(lockedPolicy.retryAllowed == false, "tool calls should also lock retries", recorder: recorder)
                expectNVIDIATrue(lockedPolicy.hedgeAllowed == false, "tool calls should also lock hedges", recorder: recorder)
                expectNVIDIAEqual(
                    lockedPolicy.owner,
                    NVIDIAStreamOwner(surface: surface, attemptLane: 3),
                    "tool-call output should claim ownership for the emitting lane",
                    recorder: recorder
                )
            }

            runNVIDIAStreamSpec("engine locks request ownership after meaningful \(surface.rawValue) responses output", recorder: recorder) {
                var engine = NVIDIAStreamEngine()
                _ = try engine.ingest(
                    Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"hello\"}\n\n".utf8),
                    surface: surface,
                    attemptLane: 4
                )
                _ = try engine.ingest(
                    Data("data: {\"choices\":[{\"delta\":{\"content\":\"ignored by losing lane\"}}]}\n\n".utf8),
                    surface: surface,
                    attemptLane: 5
                )

                expectNVIDIAEqual(
                    engine.state.meaningfulOutputOwner,
                    NVIDIAStreamOwner(surface: surface, attemptLane: 4),
                    "later lanes should not override the first meaningful owner",
                    recorder: recorder
                )
                expectNVIDIATrue(
                    engine.executionPolicy(surface: surface, attemptLane: 5).retryAllowed == false,
                    "later lanes should still see retries suppressed once ownership is locked",
                    recorder: recorder
                )
            }
        }

        recorder.finish()
    }
}
