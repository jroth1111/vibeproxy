import Foundation

@main
struct MetaAIWebAdapterSpec {
    static func main() {
        let recorder = FailureRecorder()

        run("meta web adapter flattens text-only chat requests into a prompt transcript", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {"role": "system", "content": "Be terse."},
                {"role": "user", "content": [{"type": "input_text", "text": "Say hi"}]}
              ]
            }
            """

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.surface, .chatCompletions, "chat requests should keep the chat-completions surface", recorder: recorder)
                expectEqual(parsed.stream, false, "chat requests should default stream=false", recorder: recorder)
                expectEqual(parsed.prompt, "System: Be terse.\n\nUser: Say hi", "chat requests should flatten into a stable transcript", recorder: recorder)
                expectEqual(parsed.isNewThread, false, "multi-turn with system message is a follow-up", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should parse text-only chat requests: \(error)")
            }
        }

        run("meta web adapter detects single user message as new thread", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "Hello"}
              ]
            }
            """

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.prompt, "Hello", "single user message should strip User: prefix", recorder: recorder)
                expectEqual(parsed.isNewThread, true, "single user message should be detected as new thread", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should parse single user message: \(error)")
            }
        }

        run("meta web adapter detects multi-turn as follow-up", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "Hi"},
                {"role": "assistant", "content": "Hello"},
                {"role": "user", "content": "How are you?"}
              ]
            }
            """

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.prompt, "User: Hi\n\nAssistant: Hello\n\nUser: How are you?", "multi-turn should flatten into transcript", recorder: recorder)
                expectEqual(parsed.isNewThread, false, "multi-turn with assistant messages is a follow-up", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should parse multi-turn messages: \(error)")
            }
        }

        run("meta web adapter converts responses input onto the chat transcript path", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "stream": true,
              "instructions": "Be terse.",
              "input": [
                {"role": "user", "content": [{"type": "input_text", "text": "Return exactly OK"}]}
              ]
            }
            """

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/responses",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.surface, .responses, "responses requests should keep the responses surface", recorder: recorder)
                expectEqual(parsed.stream, true, "responses requests should preserve stream=true", recorder: recorder)
                expectEqual(parsed.prompt, "System: Be terse.\n\nUser: Return exactly OK", "responses requests should reuse the same prompt flattening logic", recorder: recorder)
                expectEqual(parsed.isNewThread, false, "responses with instructions have system context = follow-up", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should parse text-only responses requests: \(error)")
            }
        }

        run("meta web adapter rejects tool-bearing chat requests", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "hi"}
              ],
              "tools": [
                {"type": "function", "function": {"name": "x", "parameters": {"type": "object"}}}
              ]
            }
            """

            do {
                _ = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                recorder.recordFailure("meta web adapter should reject tool-bearing chat requests")
            } catch let failure as MetaAIWebAdapter.Failure {
                expectEqual(failure.statusCode, 501, "tool-bearing requests should fail closed", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should throw a typed failure for tool-bearing requests: \(error)")
            }
        }

        run("meta web adapter extracts assistant text from the GraphQL event stream", recorder: recorder) {
            let stream = """
            :
            event: next
            data: {"data":{"sendMessageStream":{"__typename":"AssistantMessage","content":"OK","error":null}}}
            event: next
            data: {"data":{"sendMessageStream":{"__typename":"Conversation","title":"Simple Confirmation"}}}
            event: complete
            data:

            """

            let parsed = MetaAIWebAdapter.parseEventStream(Data(stream.utf8))
            expectEqual(parsed.assistantText, "OK", "assistant text should come from assistant message events", recorder: recorder)
            expectEqual(parsed.errorMessage, nil, "successful assistant events should not surface an error", recorder: recorder)
        }
    }
}

private final class FailureRecorder {
    var failures = 0

    func recordFailure(_ message: String) {
        failures += 1
        fputs("  - \(message)\n", stderr)
    }
}

private func run(_ name: String, recorder: FailureRecorder, _ body: () -> Void) {
    let startingFailures = recorder.failures
    body()
    let status = recorder.failures == startingFailures ? "PASS" : "FAIL"
    print("[\(status)] \(name)")
}

private func expectEqual<T: Equatable>(
    _ actual: @autoclosure () -> T,
    _ expected: T,
    _ message: String,
    recorder: FailureRecorder
) {
    let value = actual()
    guard value == expected else {
        recorder.recordFailure("\(message): expected \(expected), got \(value)")
        return
    }
}
