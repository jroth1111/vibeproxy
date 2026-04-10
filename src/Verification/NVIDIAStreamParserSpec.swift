import Foundation

@main
struct NVIDIAStreamParserSpec {
    static func main() {
        let recorder = NVIDIAStreamFailureRecorder()

        runNVIDIAStreamSpec("parser assembles partial SSE frames across chunk boundaries", recorder: recorder) {
            var parser = NVIDIAStreamParser()
            let first = try parser.ingest(Data("event: message\ndata: {\"delta\":\"he".utf8))
            expectNVIDIAEqual(first.count, 0, "partial chunks should not dispatch early", recorder: recorder)

            let second = try parser.ingest(Data("llo\"}\n\n".utf8))
            expectNVIDIAEqual(
                second,
                [
                    .message(
                        NVIDIAStreamMessage(
                            event: "message",
                            identifier: nil,
                            retryMilliseconds: nil,
                            dataLines: ["{\"delta\":\"hello\"}"]
                        )
                    )
                ],
                "parser should join partial frame bytes before dispatch",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("parser emits comments and done sentinel separately", recorder: recorder) {
            var parser = NVIDIAStreamParser()
            let outputs = try parser.ingest(Data(": keepalive\ndata: [DONE]\n\n".utf8))
            expectNVIDIAEqual(
                outputs,
                [.comment("keepalive"), .done],
                "parser should surface comments and the terminal done sentinel",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("parser accepts CRLF framed SSE messages", recorder: recorder) {
            var parser = NVIDIAStreamParser()
            let outputs = try parser.ingest(Data("id: abc\r\ndata: {\"ok\":true}\r\n\r\n".utf8))
            expectNVIDIAEqual(
                outputs,
                [
                    .message(
                        NVIDIAStreamMessage(
                            event: nil,
                            identifier: "abc",
                            retryMilliseconds: nil,
                            dataLines: ["{\"ok\":true}"]
                        )
                    )
                ],
                "parser should dispatch CRLF-delimited frames",
                recorder: recorder
            )
        }

        runNVIDIAStreamSpec("parser rejects oversized frames before dispatch", recorder: recorder) {
            var parser = NVIDIAStreamParser(maximumFrameBytes: 32)
            let oversized = Data(("data: " + String(repeating: "x", count: 40)).utf8)
            do {
                _ = try parser.ingest(oversized)
                recorder.recordFailure("oversized frames should fail before dispatch")
            } catch let error as NVIDIAStreamParserError {
                expectNVIDIAEqual(
                    error,
                    .frameTooLarge(limitBytes: 32, actualBytes: oversized.count),
                    "oversized frames should surface a bounded parser error",
                    recorder: recorder
                )
            }
        }

        runNVIDIAStreamSpec("parser rejects invalid UTF-8 frames", recorder: recorder) {
            var parser = NVIDIAStreamParser()
            do {
                _ = try parser.ingest(Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0x20, 0xC3, 0x28, 0x0A, 0x0A]))
                recorder.recordFailure("invalid UTF-8 frames should fail closed")
            } catch let error as NVIDIAStreamParserError {
                expectNVIDIAEqual(
                    error,
                    .invalidUTF8Frame,
                    "invalid UTF-8 should be classified explicitly",
                    recorder: recorder
                )
            }
        }

        recorder.finish()
    }
}
