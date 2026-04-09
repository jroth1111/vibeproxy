import Darwin
import Foundation

@main
struct MetaAIWebAdapterSpec {
    static func main() {
        let recorder = FailureRecorder()
        let authSnapshot = MetaAIWebAdapter.HARAuthSnapshot(
            cookieHeader: "session=abc123",
            userAgent: "MetaAdapterSpec/1.0",
            acceptLanguage: "en-US,en;q=0.9"
        )

        run("meta web adapter builds the observed GraphQL request sequence with browser-aligned headers", recorder: recorder) {
            let conversationID = "58631193-7b41-408b-8441-06f6de9e7cf7"

            do {
                let requests = try MetaAIWebAdapter.buildExecutionRequests(
                    authSnapshot: authSnapshot,
                    conversationID: conversationID,
                    prompt: "Hello",
                    isNewThread: true
                )

                expectEqual(
                    requests.map(\.kind),
                    [
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.warmupConversation,
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.updateConversationMode,
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.sendMessage
                    ],
                    "request planner should preserve the GraphQL sequence",
                    recorder: recorder
                )
                expectEqual(
                    requests.map(\.isBestEffort),
                    [false, false, false],
                    "all setup and send requests are required",
                    recorder: recorder
                )

                for request in requests.map(\.request) {
                    expectEqual(request.url?.absoluteString, "https://www.meta.ai/api/graphql", "GraphQL requests should target the www.meta.ai endpoint", recorder: recorder)
                    expectEqual(request.httpMethod, "POST", "GraphQL requests should be POSTs", recorder: recorder)
                    expectEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json", "GraphQL requests should send JSON bodies", recorder: recorder)
                    expectEqual(request.value(forHTTPHeaderField: "Origin"), "https://www.meta.ai", "GraphQL requests should send the browser origin", recorder: recorder)
                    expectEqual(request.value(forHTTPHeaderField: "User-Agent"), authSnapshot.userAgent, "GraphQL requests should forward the HAR user-agent", recorder: recorder)
                    expectEqual(request.value(forHTTPHeaderField: "Accept-Language"), authSnapshot.acceptLanguage, "GraphQL requests should forward the HAR language header", recorder: recorder)
                    expectEqual(request.value(forHTTPHeaderField: "Cookie"), authSnapshot.cookieHeader, "GraphQL requests should forward the HAR cookie header", recorder: recorder)
                }

                expectEqual(requests[0].request.value(forHTTPHeaderField: "Accept"), MetaAIWebAdapter.setupGraphQLAcceptHeader, "warmup should request multipart/mixed JSON", recorder: recorder)
                expectEqual(requests[1].request.value(forHTTPHeaderField: "Accept"), MetaAIWebAdapter.setupGraphQLAcceptHeader, "mode update should request multipart/mixed JSON", recorder: recorder)
                expectEqual(requests[2].request.value(forHTTPHeaderField: "Accept"), "text/event-stream", "sendMessage should request an event stream", recorder: recorder)

                expectEqual(requests[0].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/", "warmup should use the root referer like the HAR", recorder: recorder)
                expectEqual(requests[1].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/", "mode update should use the root referer like the HAR", recorder: recorder)
                expectEqual(requests[2].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/prompt/\(conversationID)", "sendMessage should use the prompt-page referer", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should build browser-aligned request headers: \(error)")
            }
        }

        run("meta web adapter encodes the expected GraphQL request bodies", recorder: recorder) {
            let conversationID = "58631193-7b41-408b-8441-06f6de9e7cf7"

            do {
                let requests = try MetaAIWebAdapter.buildExecutionRequests(
                    authSnapshot: authSnapshot,
                    conversationID: conversationID,
                    prompt: "Summarize this.",
                    isNewThread: false
                )

                let warmupBody = try graphQLBody(from: requests[0].request)
                expectEqual(warmupBody["doc_id"] as? String, "e7f802582dbfed8e181b012e010993eb", "warmup should use the observed doc id", recorder: recorder)
                expectEqual((warmupBody["variables"] as? [String: Any])?["conversationId"] as? String, conversationID, "warmup should carry the conversation id", recorder: recorder)

                let updateBody = try graphQLBody(from: requests[1].request)
                expectEqual(updateBody["doc_id"] as? String, "c32bbe999c48e64e855dc63177d5153f", "mode update should use the observed doc id", recorder: recorder)
                let updateInput = (updateBody["variables"] as? [String: Any])?["input"] as? [String: Any]
                expectEqual(updateInput?["conversationId"] as? String, conversationID, "mode update should carry the conversation id", recorder: recorder)
                expectEqual(updateInput?["mode"] as? String, "think_hard", "mode update should pin think_hard", recorder: recorder)

                let sendBody = try graphQLBody(from: requests[2].request)
                expectEqual(sendBody["doc_id"] as? String, "af4c07d1fb42eb351dba31b5a299a819", "sendMessage should use the observed doc id", recorder: recorder)
                let variables = sendBody["variables"] as? [String: Any]
                expectEqual(variables?["conversationId"] as? String, conversationID, "sendMessage should carry the conversation id", recorder: recorder)
                expectEqual(variables?["content"] as? String, "Summarize this.", "sendMessage should carry the prompt content", recorder: recorder)
                expectEqual(variables?["mode"] as? String, "think_hard", "sendMessage should pin think_hard mode", recorder: recorder)
                expectEqual(variables?["currentBranchPath"] as? String, "1", "stateless requests should start from branch 1", recorder: recorder)
                expectEqual(variables?["isNewConversation"] as? Bool, false, "follow-up prompts should set isNewConversation=false", recorder: recorder)
                expectEqual(variables?["promptEditType"] as? String, "new_message", "sendMessage should use the new_message prompt edit type", recorder: recorder)
                expectEqual(variables?["entryPoint"] as? String, "KADABRA__UNKNOWN", "sendMessage should preserve the expected entry point", recorder: recorder)
                expectEqual(variables?["userAgent"] as? String, authSnapshot.userAgent, "sendMessage should forward the HAR user-agent in variables", recorder: recorder)
                expectTrue(variables?["attachments"] is NSNull, "sendMessage should leave attachments null", recorder: recorder)
                expectTrue(variables?["imagineOperationRequest"] is NSNull, "text chat should leave imagineOperationRequest null", recorder: recorder)
                expectTrue(variables?["requestedToolCall"] is NSNull, "text chat should leave requestedToolCall null", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should encode stable GraphQL bodies: \(error)")
            }
        }

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
              ],
              "tool_choice": "required"
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
                expectContains(failure.message, "does not support live tool execution", "tool-bearing requests should explain the unsupported live-tool path", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should throw a typed failure for tool-bearing requests: \(error)")
            }
        }

        run("meta web adapter rejects unsupported typed message content instead of dropping it", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {"type": "input_text", "text": "Describe this"},
                    {"type": "input_image", "image_url": "https://example.com/cat.png"}
                  ]
                }
              ]
            }
            """

            do {
                _ = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                recorder.recordFailure("meta web adapter should reject unsupported typed message content")
            } catch let failure as MetaAIWebAdapter.Failure {
                expectEqual(failure.statusCode, 400, "unsupported typed content should fail with a client error", recorder: recorder)
                expectContains(failure.message, "only supports text message content", "unsupported typed content should fail with a clear text-only message", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should throw a typed failure for unsupported typed content: \(error)")
            }
        }

        run("meta web adapter flattens completed tool history into plain transcript context", recorder: recorder) {
            let request = #"""
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "Find the weather"},
                {
                  "role": "assistant",
                  "content": "",
                  "tool_calls": [
                    {
                      "id": "call_1",
                      "type": "function",
                      "function": {
                        "name": "search",
                        "arguments": "{\"q\":\"weather Boston\"}"
                      }
                    }
                  ]
                },
                {"role": "tool", "content": "72F and sunny"},
                {"role": "user", "content": "Answer briefly"}
              ]
            }
            """#

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(
                    parsed.prompt,
                    """
                    User: Find the weather

                    Assistant: [Called search({\"q\":\"weather Boston\"})]

                    Tool result: 72F and sunny

                    User: Answer briefly
                    """,
                    "completed tool history should be inlined as plain transcript context",
                    recorder: recorder
                )
                expectEqual(parsed.isNewThread, false, "tool-history follow-ups should be treated as existing threads", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should flatten completed tool history into transcript context: \(error)")
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

        exit(recorder.failures == 0 ? 0 : 1)
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

private func expectTrue(
    _ actual: @autoclosure () -> Bool,
    _ message: String,
    recorder: FailureRecorder
) {
    guard actual() else {
        recorder.recordFailure(message)
        return
    }
}

private func expectContains(
    _ actual: @autoclosure () -> String,
    _ needle: String,
    _ message: String,
    recorder: FailureRecorder
) {
    let value = actual()
    guard value.contains(needle) else {
        recorder.recordFailure("\(message): expected '\(value)' to contain '\(needle)'")
        return
    }
}

private func graphQLBody(from request: URLRequest) throws -> [String: Any] {
    guard let body = request.httpBody else {
        throw SpecFailure.message("missing HTTP body")
    }
    guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw SpecFailure.message("GraphQL body was not a JSON object")
    }
    return json
}

private enum SpecFailure: Error {
    case message(String)
}
