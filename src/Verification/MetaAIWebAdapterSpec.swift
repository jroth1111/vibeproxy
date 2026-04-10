import Darwin
import Foundation

@main
struct MetaAIWebAdapterSpec {
    static func main() {
        let recorder = FailureRecorder()
        let authSnapshot = MetaAIWebAdapter.HARAuthSnapshot(
            cookieHeader: "session=abc123",
            userAgent: "MetaAdapterSpec/1.0",
            acceptLanguage: "en-US,en;q=0.9",
            clientTimezone: "Australia/Melbourne",
            userLocale: "en-US",
            devicePixelRatio: 1.25
        )

        run("meta web adapter builds the observed GraphQL request sequence with browser-aligned headers", recorder: recorder) {
            let conversationID = "58631193-7b41-408b-8441-06f6de9e7cf7"

            do {
                let requests = try MetaAIWebAdapter.buildExecutionRequests(
                    authSnapshot: authSnapshot,
                    conversationID: conversationID,
                    prompt: "Hello"
                )

                expectEqual(
                    requests.map(\.kind),
                    [
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.updateLastSelectedMode,
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.warmupConversation,
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.updateConversationMode,
                        MetaAIWebAdapter.PlannedGraphQLRequest.Kind.sendMessage
                    ],
                    "request planner should preserve the GraphQL sequence",
                    recorder: recorder
                )
                expectEqual(
                    requests.map(\.isBestEffort),
                    [true, false, false, false],
                    "mode selection should be best-effort while the rest stay required",
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

                expectEqual(requests[0].request.value(forHTTPHeaderField: "Accept"), MetaAIWebAdapter.setupGraphQLAcceptHeader, "mode selection should request multipart/mixed JSON", recorder: recorder)
                expectEqual(requests[1].request.value(forHTTPHeaderField: "Accept"), MetaAIWebAdapter.setupGraphQLAcceptHeader, "warmup should request multipart/mixed JSON", recorder: recorder)
                expectEqual(requests[2].request.value(forHTTPHeaderField: "Accept"), MetaAIWebAdapter.setupGraphQLAcceptHeader, "mode update should request multipart/mixed JSON", recorder: recorder)
                expectEqual(requests[3].request.value(forHTTPHeaderField: "Accept"), "text/event-stream", "sendMessage should request an event stream", recorder: recorder)

                expectEqual(requests[0].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/", "mode selection should use the root referer like the HAR", recorder: recorder)
                expectEqual(requests[1].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/", "warmup should use the root referer like the HAR", recorder: recorder)
                expectEqual(requests[2].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/", "mode update should use the root referer like the HAR", recorder: recorder)
                expectEqual(requests[3].request.value(forHTTPHeaderField: "Referer"), "https://www.meta.ai/prompt/\(conversationID)", "sendMessage should use the prompt-page referer", recorder: recorder)
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
                    prompt: "Summarize this."
                )

                let modeSelectionBody = try graphQLBody(from: requests[0].request)
                expectEqual(modeSelectionBody["doc_id"] as? String, "98081c3f48eddb05c71cb79d46fc337b", "mode selection should use the observed doc id", recorder: recorder)
                let modeSelectionInput = (modeSelectionBody["variables"] as? [String: Any])?["input"] as? [String: Any]
                expectEqual(modeSelectionInput?["mode"] as? String, "think_hard", "mode selection should pin think_hard", recorder: recorder)

                let warmupBody = try graphQLBody(from: requests[1].request)
                expectEqual(warmupBody["doc_id"] as? String, "e7f802582dbfed8e181b012e010993eb", "warmup should use the observed doc id", recorder: recorder)
                expectEqual((warmupBody["variables"] as? [String: Any])?["conversationId"] as? String, conversationID, "warmup should carry the conversation id", recorder: recorder)

                let updateBody = try graphQLBody(from: requests[2].request)
                expectEqual(updateBody["doc_id"] as? String, "c32bbe999c48e64e855dc63177d5153f", "mode update should use the observed doc id", recorder: recorder)
                let updateInput = (updateBody["variables"] as? [String: Any])?["input"] as? [String: Any]
                expectEqual(updateInput?["conversationId"] as? String, conversationID, "mode update should carry the conversation id", recorder: recorder)
                expectEqual(updateInput?["mode"] as? String, "think_hard", "mode update should pin think_hard", recorder: recorder)

                let sendBody = try graphQLBody(from: requests[3].request)
                expectEqual(sendBody["doc_id"] as? String, "af4c07d1fb42eb351dba31b5a299a819", "sendMessage should use the observed doc id", recorder: recorder)
                let variables = sendBody["variables"] as? [String: Any]
                expectEqual(variables?["conversationId"] as? String, conversationID, "sendMessage should carry the conversation id", recorder: recorder)
                expectEqual(variables?["content"] as? String, "Summarize this.", "sendMessage should carry the prompt content", recorder: recorder)
                expectEqual(variables?["mode"] as? String, "think_hard", "sendMessage should pin think_hard mode", recorder: recorder)
                expectEqual(variables?["currentBranchPath"] as? String, "1", "stateless requests should start from branch 1", recorder: recorder)
                expectEqual(variables?["isNewConversation"] as? Bool, true, "stateless follow-up prompts should still start a fresh Meta conversation", recorder: recorder)
                expectEqual(variables?["promptEditType"] as? String, "new_message", "sendMessage should use the new_message prompt edit type", recorder: recorder)
                expectEqual(variables?["entryPoint"] as? String, "KADABRA__UNKNOWN", "sendMessage should preserve the expected entry point", recorder: recorder)
                expectEqual(variables?["userAgent"] as? String, authSnapshot.userAgent, "sendMessage should forward the HAR user-agent in variables", recorder: recorder)
                expectEqual(variables?["clientTimezone"] as? String, authSnapshot.clientTimezone, "sendMessage should reuse the browser timezone captured in the HAR when available", recorder: recorder)
                expectEqual(variables?["userLocale"] as? String, authSnapshot.userLocale, "sendMessage should reuse the locale derived from the HAR session", recorder: recorder)
                expectEqual(variables?["devicePixelRatio"] as? Double, authSnapshot.devicePixelRatio, "sendMessage should reuse the browser dpr captured in the HAR when available", recorder: recorder)
                expectTrue(variables?["attachments"] is NSNull, "sendMessage should leave attachments null", recorder: recorder)
                expectTrue(variables?["imagineOperationRequest"] is NSNull, "text chat should leave imagineOperationRequest null", recorder: recorder)
                expectTrue(variables?["requestedToolCall"] is NSNull, "text chat should leave requestedToolCall null", recorder: recorder)
                expectTrue(variables?["userEventId"] is NSNull, "text chat should leave userEventId null", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should encode stable GraphQL bodies: \(error)")
            }
        }

        run("meta web adapter extracts required cookies and browser fingerprint from HAR GraphQL traffic", recorder: recorder) {
            let har = """
            {
              "log": {
                "entries": [
                  {
                    "request": {
                      "url": "https://www.meta.ai/api/graphql",
                      "headers": [
                        {"name": "Cookie", "value": "datr=device123; ecto_1_sess=session456; dpr=1.5"},
                        {"name": "User-Agent", "value": "Browser/1.0"},
                        {"name": "Accept-Language", "value": "fr-FR,fr;q=0.9"}
                      ],
                      "postData": {
                        "text": "{\\"variables\\":{\\"clientTimezone\\":\\"Australia/Melbourne\\",\\"userLocale\\":\\"en-US\\",\\"devicePixelRatio\\":2.0}}"
                      }
                    }
                  }
                ]
              }
            }
            """

            do {
                let url = try writeTempFile(named: "meta-auth-\(UUID().uuidString).har", contents: har)
                defer { try? FileManager.default.removeItem(at: url) }

                try withTemporaryEnvironment("VIBEPROXY_META_AI_HAR_PATH", value: url.path) {
                    let snapshot = try MetaAIWebAdapter.loadHARAuthSnapshot(fileManager: .default)
                    expectEqual(snapshot.cookieHeader, "datr=device123; ecto_1_sess=session456; dpr=1.5", "HAR loading should preserve the cookie header", recorder: recorder)
                    expectEqual(snapshot.userAgent, "Browser/1.0", "HAR loading should preserve the user-agent", recorder: recorder)
                    expectEqual(snapshot.acceptLanguage, "fr-FR,fr;q=0.9", "HAR loading should preserve accept-language", recorder: recorder)
                    expectEqual(snapshot.clientTimezone, "Australia/Melbourne", "HAR loading should reuse the browser timezone captured in GraphQL variables", recorder: recorder)
                    expectEqual(snapshot.userLocale, "en-US", "HAR loading should prefer request-level userLocale over accept-language derivation", recorder: recorder)
                    expectEqual(snapshot.devicePixelRatio, 2.0, "HAR loading should prefer request-level devicePixelRatio over cookie dpr", recorder: recorder)
                }
            } catch {
                recorder.recordFailure("meta web adapter should load a modern HAR auth snapshot: \(error)")
            }
        }

        run("meta web adapter falls back to UTC when HAR traffic omits a browser timezone", recorder: recorder) {
            let har = """
            {
              "log": {
                "entries": [
                  {
                    "request": {
                      "url": "https://www.meta.ai/api/graphql",
                      "headers": [
                        {"name": "Cookie", "value": "datr=device123; ecto_1_sess=session456; dpr=1.5"},
                        {"name": "User-Agent", "value": "Browser/1.0"},
                        {"name": "Accept-Language", "value": "fr-FR,fr;q=0.9"}
                      ]
                    }
                  }
                ]
              }
            }
            """

            do {
                let url = try writeTempFile(named: "meta-auth-utc-\(UUID().uuidString).har", contents: har)
                defer { try? FileManager.default.removeItem(at: url) }

                try withTemporaryEnvironment("VIBEPROXY_META_AI_HAR_PATH", value: url.path) {
                    let snapshot = try MetaAIWebAdapter.loadHARAuthSnapshot(fileManager: .default)
                    expectEqual(snapshot.clientTimezone, "UTC", "HAR loading should fall back to a stable timezone instead of the proxy host timezone", recorder: recorder)
                    expectEqual(snapshot.userLocale, "fr-FR", "HAR loading should derive locale from accept-language", recorder: recorder)
                    expectEqual(snapshot.devicePixelRatio, 1.5, "HAR loading should parse dpr from cookies", recorder: recorder)
                }
            } catch {
                recorder.recordFailure("meta web adapter should fall back to UTC when timezone hints are absent: \(error)")
            }
        }

        run("meta web adapter rejects HARs missing the minimum modern cookies", recorder: recorder) {
            let har = """
            {
              "log": {
                "entries": [
                  {
                    "request": {
                      "url": "https://www.meta.ai/api/graphql",
                      "headers": [
                        {"name": "Cookie", "value": "datr=device123"},
                        {"name": "User-Agent", "value": "Browser/1.0"}
                      ]
                    }
                  }
                ]
              }
            }
            """

            do {
                let url = try writeTempFile(named: "meta-auth-missing-\(UUID().uuidString).har", contents: har)
                defer { try? FileManager.default.removeItem(at: url) }

                try withTemporaryEnvironment("VIBEPROXY_META_AI_HAR_PATH", value: url.path) {
                    _ = try MetaAIWebAdapter.loadHARAuthSnapshot(fileManager: .default)
                    recorder.recordFailure("meta web adapter should reject HARs missing ecto_1_sess")
                }
            } catch let failure as MetaAIWebAdapter.Failure {
                expectEqual(failure.statusCode, 500, "missing auth cookies should fail as server-side adapter misconfiguration", recorder: recorder)
                expectContains(failure.message, "datr and ecto_1_sess", "missing-cookie failures should name the minimum modern cookie set", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should throw a typed failure for incomplete HAR cookies: \(error)")
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

        run("meta web adapter accepts tool-bearing chat requests for synthetic single-tool mode", recorder: recorder) {
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
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.toolDefinitions.map(\.name), ["x"], "tool-bearing chat requests should preserve the declared function tools", recorder: recorder)
                expectEqual(parsed.toolChoice, .required, "tool-bearing chat requests should preserve required tool_choice", recorder: recorder)
                expectContains(parsed.executionPrompt, #"{"name":"tool_name","arguments":{"key":"value"}}"#, "synthetic tool mode should require the exact JSON directive shape", recorder: recorder)
                expectContains(parsed.executionPrompt, "- x", "synthetic tool mode should enumerate the available tools", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should parse tool-bearing chat requests into synthetic tool mode: \(error)")
            }
        }

        run("meta web adapter repairs parallel_tool_calls by degrading to single-tool mode", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "hi"}
              ],
              "tools": [
                {"type": "function", "function": {"name": "x", "parameters": {"type": "object"}}}
              ],
              "tool_choice": "required",
              "parallel_tool_calls": true
            }
            """

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.toolDefinitions.map(\.name), ["x"], "parallel_tool_calls should be downgraded instead of rejected", recorder: recorder)
                expectEqual(parsed.toolChoice, .required, "required tool choice should survive the downgrade to single-call mode", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should repair parallel_tool_calls instead of rejecting the request: \(error)")
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

        run("meta web adapter repairs text-bearing wrapper objects into transcript context", recorder: recorder) {
            let request = #"""
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "Find the weather"},
                {"role": "assistant", "content": {"type": "tool_result", "text": "Already read the repo."}},
                {"role": "tool", "content": {"type": "tool_result", "content": [{"type": "output_text", "text": "72F and sunny"}]}},
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

                    Assistant: Already read the repo.

                    Tool result: 72F and sunny

                    User: Answer briefly
                    """,
                    "text-bearing wrapper objects should be flattened instead of rejected",
                    recorder: recorder
                )
                expectEqual(parsed.isNewThread, false, "wrapper-based assistant and tool context should keep the request in follow-up mode", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should repair text-bearing wrapper objects into transcript context: \(error)")
            }
        }

        run("meta web adapter stringifies structured JSON tool-result wrappers into transcript context", recorder: recorder) {
            let request = #"""
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "Check the weather"},
                {
                  "role": "tool",
                  "content": {
                    "type": "tool_result",
                    "content": [
                      {
                        "type": "output_json",
                        "value": {
                          "city": "Boston",
                          "temp_f": 72
                        }
                      }
                    ]
                  }
                },
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
                    User: Check the weather

                    Tool result: {"city":"Boston","temp_f":72}

                    User: Answer briefly
                    """,
                    "structured JSON tool results should be serialized into stable transcript text instead of excluding muse-spark",
                    recorder: recorder
                )
                expectEqual(parsed.isNewThread, false, "structured tool-result context should keep the request in follow-up mode", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should serialize structured JSON tool-result wrappers into transcript context: \(error)")
            }
        }

        run("meta web adapter ignores unknown non-media typed segments while preserving text summary content", recorder: recorder) {
            let request = #"""
            {
              "model": "muse-spark",
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"type": "input_text", "text": "Checked "},
                    {"type": "summary_text", "text": "repo"},
                    {"type": "reasoning", "text": "hidden chain of thought"},
                    {"type": "metadata_marker", "value": {"step": 1}}
                  ]
                },
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
                    Assistant: Checked repo

                    User: Answer briefly
                    """,
                    "unknown non-media typed segments should be skipped while preserving summary text",
                    recorder: recorder
                )
                expectEqual(parsed.isNewThread, false, "summary-bearing assistant context should keep the request in follow-up mode", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should skip unknown non-media typed segments while preserving text: \(error)")
            }
        }

        run("meta web adapter ignores metadata-only typed transcript content instead of rejecting the request", recorder: recorder) {
            let request = #"""
            {
              "model": "muse-spark",
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"type": "reasoning", "text": "hidden chain of thought"},
                    {"type": "metadata_marker", "value": {"step": 1}}
                  ]
                },
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
                    "Answer briefly",
                    "metadata-only typed transcript content should be ignored instead of excluding the Meta bridge",
                    recorder: recorder
                )
                expectEqual(parsed.isNewThread, true, "ignorable metadata-only assistant context should not force follow-up mode", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should ignore metadata-only typed transcript content instead of rejecting the request: \(error)")
            }
        }

        run("meta web adapter ignores opaque untyped structured transcript segments instead of rejecting the request", recorder: recorder) {
            let request = #"""
            {
              "model": "muse-spark",
              "messages": [
                {
                  "role": "assistant",
                  "content": [
                    {"text": "I'll inspect the repo."},
                    {"id": "call_1", "name": "Read", "input": {"file_path": "Cargo.toml"}}
                  ]
                },
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
                    Assistant: I'll inspect the repo.

                    User: Answer briefly
                    """,
                    "opaque untyped non-media transcript segments should be ignored while preserving readable text context",
                    recorder: recorder
                )
                expectEqual(parsed.isNewThread, false, "opaque untyped assistant context should keep the request in follow-up mode", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should ignore opaque untyped structured transcript segments instead of rejecting the request: \(error)")
            }
        }

        run("meta web adapter preserves synthetic-tool preflight while still rejecting typed-content requests", recorder: recorder) {
            let toolRequest = """
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
            let typedRequest = """
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

            let toolFailure = MetaAIWebAdapter.preflightFailure(
                path: "/v1/chat/completions",
                body: toolRequest,
                publicModel: "muse-spark"
            )
            expectEqual(toolFailure, nil, "tool-bearing requests should pass preflight under synthetic tool mode", recorder: recorder)

            let typedFailure = MetaAIWebAdapter.preflightFailure(
                path: "/v1/chat/completions",
                body: typedRequest,
                publicModel: "muse-spark"
            )
            expectEqual(typedFailure?.statusCode, 400, "typed content should fail during preflight", recorder: recorder)
            expectContains(typedFailure?.message ?? "", "only supports text message content", "typed-content preflight should preserve the text-only failure", recorder: recorder)
        }

        run("meta web adapter parses a strict synthetic tool directive", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Find weather",
                executionPrompt: "Find weather",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "search",
                        description: "Look up information",
                        parametersJSONString: #"{"type":"object","properties":{"q":{"type":"string"}}}"#
                    )
                ],
                toolChoice: .required,
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"{"name":"search","arguments":{"q":"weather Boston"}}"#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "search", "synthetic tool mode should accept declared tool names", recorder: recorder)
                expectEqual(directive?.argumentsJSONString, #"{"q":"weather Boston"}"#, "synthetic tool mode should normalize arguments to stable JSON", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should parse a valid synthetic tool directive: \(error)")
            }
        }

        run("meta web adapter repairs undeclared synthetic tool directives when the required tool is clear", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Find weather",
                executionPrompt: "Find weather",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "search",
                        description: "Look up information",
                        parametersJSONString: #"{"type":"object","properties":{"q":{"type":"string"}}}"#
                    )
                ],
                toolChoice: .required,
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"{"name":"browser.search","arguments":{"q":"weather Boston"}}"#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "search", "repair-first mode should map undeclared near-miss tool names back to the required tool", recorder: recorder)
                expectEqual(directive?.argumentsJSONString, #"{"q":"weather Boston"}"#, "repaired near-miss tools should preserve arguments", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should repair undeclared near-miss tool names when the required tool is clear: \(error)")
            }
        }

        run("meta web adapter extracts a valid tool directive from prose-wrapped output", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Find weather",
                executionPrompt: "Find weather",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "search",
                        description: "Look up information",
                        parametersJSONString: #"{"type":"object","properties":{"q":{"type":"string"}}}"#
                    )
                ],
                toolChoice: .required,
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"I will use the search tool now. {"name":"search","arguments":{"q":"weather Boston"}} Done."#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "search", "balanced JSON extraction should recover directives embedded in prose", recorder: recorder)
                expectEqual(directive?.argumentsJSONString, #"{"q":"weather Boston"}"#, "prose-wrapped directives should preserve arguments", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should recover prose-wrapped directives: \(error)")
            }
        }

        run("meta web adapter recovers a specific tool call from a bare arguments object", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Read Cargo.toml",
                executionPrompt: "Read Cargo.toml",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Read",
                        description: "Read a file from disk",
                        parametersJSONString: #"{"type":"object","properties":{"file_path":{"type":"string"}},"required":["file_path"]}"#
                    ),
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Grep",
                        description: "Search file contents",
                        parametersJSONString: #"{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"}},"required":["pattern","path"]}"#
                    )
                ],
                toolChoice: .specific("Read"),
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"{"file_path":"Cargo.toml"}"#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "Read", "specific tool choice should recover bare argument objects as the required tool", recorder: recorder)
                expectEqual(directive?.argumentsJSONString, #"{"file_path":"Cargo.toml"}"#, "bare arguments should be normalized for the required tool", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should recover a specific tool call from a bare arguments object: \(error)")
            }
        }

        run("meta web adapter recovers a tool call from a top-level tool-name wrapper", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Read Cargo.toml",
                executionPrompt: "Read Cargo.toml",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Read",
                        description: "Read a file from disk",
                        parametersJSONString: #"{"type":"object","properties":{"file_path":{"type":"string"}},"required":["file_path"]}"#
                    ),
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Grep",
                        description: "Search file contents",
                        parametersJSONString: #"{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"}},"required":["pattern","path"]}"#
                    )
                ],
                toolChoice: .required,
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"{"Read":{"file_path":"Cargo.toml"}}"#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "Read", "top-level tool-name wrappers should be accepted", recorder: recorder)
                expectEqual(directive?.argumentsJSONString, #"{"file_path":"Cargo.toml"}"#, "wrapped arguments should be normalized", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should recover a tool call from a top-level tool-name wrapper: \(error)")
            }
        }

        run("meta web adapter recovers explicit tool names with top-level parameter fields", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Search for TODO",
                executionPrompt: "Search for TODO",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Grep",
                        description: "Search file contents",
                        parametersJSONString: #"{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"}},"required":["pattern","path"]}"#
                    )
                ],
                toolChoice: .required,
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"{"name":"Grep","pattern":"TODO","path":"."}"#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "Grep", "explicit tool names with top-level parameter fields should be accepted", recorder: recorder)
                expectEqual(directive?.argumentsJSONString, #"{"path":".","pattern":"TODO"}"#, "top-level parameter fields should be normalized into arguments", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should recover explicit tool names with top-level parameter fields: \(error)")
            }
        }

        run("meta web adapter repairs near-miss tool names for specific tool choice", recorder: recorder) {
            let parsedRequest = MetaAIWebAdapter.ParsedRequest(
                surface: .chatCompletions,
                prompt: "Update todos",
                executionPrompt: "Update todos",
                stream: false,
                publicModel: "muse-spark",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "TodoWrite",
                        description: "Update a todo list",
                        parametersJSONString: #"{"type":"object","properties":{"todos":{"type":"array"}},"required":["todos"]}"#
                    ),
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Read",
                        description: "Read a file",
                        parametersJSONString: #"{"type":"object","properties":{"file_path":{"type":"string"}},"required":["file_path"]}"#
                    )
                ],
                toolChoice: .specific("TodoWrite"),
                isNewThread: true
            )

            do {
                let directive = try MetaAIWebAdapter.syntheticToolDirective(
                    from: #"{"tool":"todo_write","todos":[{"content":"verify shim","status":"in_progress","priority":"high"}]}"#,
                    parsedRequest: parsedRequest
                )
                expectEqual(directive?.name, "TodoWrite", "near-miss tool names should normalize to the required tool", recorder: recorder)
                expectContains(directive?.argumentsJSONString ?? "", "\"todos\"", "near-miss repairs should preserve nested todo arguments", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should repair near-miss tool names: \(error)")
            }
        }

        run("meta web adapter repairs near-miss tool_choice function names", recorder: recorder) {
            let request = """
            {
              "model": "muse-spark",
              "messages": [
                {"role": "user", "content": "use TodoWrite"}
              ],
              "tools": [
                {"function": {"name": "TodoWrite", "parameters": {"type": "object"}}},
                {"type": "function", "function": {"name": "Read", "parameters": {"type": "object"}}}
              ],
              "tool_choice": {
                "type": "function",
                "function": {"name": "todo_write"}
              }
            }
            """

            do {
                let parsed = try MetaAIWebAdapter.parseRequest(
                    path: "/v1/chat/completions",
                    body: request,
                    publicModel: "muse-spark"
                )
                expectEqual(parsed.toolDefinitions.map(\.name), ["TodoWrite", "Read"], "tool repair should infer function type and keep valid tool definitions", recorder: recorder)
                expectEqual(parsed.toolChoice, .specific("TodoWrite"), "near-miss tool_choice names should resolve onto the declared tool", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should repair near-miss tool_choice function names: \(error)")
            }
        }

        run("meta web adapter builds a repair prompt for malformed tool output", recorder: recorder) {
            let repairPrompt = MetaAIWebAdapter.buildSyntheticToolRepairPrompt(
                basePrompt: "User: Read Cargo.toml",
                assistantText: "Here is the JSON: {\"name\":\"Read\",\"arguments\":{\"file_path\":\"Cargo.toml\"}}",
                toolDefinitions: [
                    MetaAIWebAdapter.ToolDefinition(
                        name: "Read",
                        description: "Read a file from disk",
                        parametersJSONString: #"{"type":"object","properties":{"file_path":{"type":"string"}},"required":["file_path"]}"#
                    )
                ],
                toolChoice: .specific("Read")
            )
            expectContains(repairPrompt, "Your previous reply was malformed for tool-use mode:", "repair prompt should explain why the retry exists", recorder: recorder)
            expectContains(repairPrompt, "Preserve the same intent and arguments", "repair prompt should ask Meta to normalize instead of changing semantics", recorder: recorder)
            expectContains(repairPrompt, #"{"name":"Read","arguments":{}}"#, "repair prompt should restate the exact raw JSON directive format", recorder: recorder)
        }

        run("meta web adapter extracts assistant text and sources from the GraphQL event stream", recorder: recorder) {
            let stream = """
            :
            event: next
            data: {"data":{"sendMessageStream":{"__typename":"AssistantMessage","content":"OK","error":null,"contentRenderer":{"message":{"sources":[{"source_url":"https://example.com/a","source_display_name":"Example A","source_subtitle":"First source"},{"source_url":"https://example.com/b","source_display_name":"Example B","source_subtitle":"Second source"}]}}}}}
            event: next
            data: {"data":{"sendMessageStream":{"__typename":"Conversation","title":"Simple Confirmation"}}}
            event: complete
            data:

            """

            let parsed = MetaAIWebAdapter.parseEventStream(Data(stream.utf8))
            expectEqual(parsed.assistantText, "OK", "assistant text should come from assistant message events", recorder: recorder)
            expectEqual(parsed.errorMessage, nil, "successful assistant events should not surface an error", recorder: recorder)
            expectEqual(parsed.sources.count, 2, "assistant events should expose extracted sources", recorder: recorder)
            expectEqual(parsed.sources.first?.url, "https://example.com/a", "source URLs should be preserved", recorder: recorder)
            expectEqual(parsed.sources.first?.title, "Example A", "source titles should be preserved", recorder: recorder)
            expectEqual(parsed.sources.first?.subtitle, "First source", "source subtitles should be preserved", recorder: recorder)
        }

        run("meta web adapter extracts top-level SSE errors from the GraphQL event stream", recorder: recorder) {
            let errorStream = #"""
            event: next
            data: {"errors":[{"message":"Variable \"$requestedToolCall\" got invalid value"}]}
            """#

            let parsed = MetaAIWebAdapter.parseEventStream(Data(errorStream.utf8))
            expectEqual(parsed.assistantText, nil, "top-level SSE error frames should not invent assistant text", recorder: recorder)
            expectContains(parsed.errorMessage ?? "", #"Variable "$requestedToolCall" got invalid value"#, "top-level SSE error frames should be surfaced directly", recorder: recorder)
        }

        run("meta web adapter translates GraphQL event-stream errors into a clean upstream failure", recorder: recorder) {
            let errorStream = #"""
            event: next
            data: {"errors":[{"message":"Variable \"$requestedToolCall\" got invalid value \"browser.search\"; Expected type \"RequestedToolCallInput\" to be an object."}]}
            """#

            let message = MetaAIWebAdapter.formattedUpstreamErrorMessage(
                statusCode: 400,
                responseData: Data(errorStream.utf8)
            )
            expectContains(message, #"Variable "$requestedToolCall" got invalid value "browser.search""#, "GraphQL variable validation errors should be extracted from event streams", recorder: recorder)
            expectContains(message, "RequestedToolCallInput", "GraphQL error formatting should preserve the schema detail", recorder: recorder)
        }

        run("meta web adapter classifies challenge pages and expired sessions cleanly", recorder: recorder) {
            let challengeHTML = """
            <!doctype html><html><head><title>Just a moment...</title></head><body>Cloudflare challenge-platform</body></html>
            """
            let authJSON = """
            {"message":"Access token required"}
            """

            let challengeMessage = MetaAIWebAdapter.formattedUpstreamErrorMessage(
                statusCode: 503,
                responseData: Data(challengeHTML.utf8)
            )
            expectContains(challengeMessage, "challenge page", "challenge HTML should map to a clean anti-bot failure", recorder: recorder)

            let authMessage = MetaAIWebAdapter.formattedUpstreamErrorMessage(
                statusCode: 403,
                responseData: Data(authJSON.utf8)
            )
            expectContains(authMessage, "session is no longer authorized", "auth failures should instruct the user to refresh the HAR session", recorder: recorder)
            expectContains(authMessage, "ecto_1_sess", "auth failures should mention the critical session cookie", recorder: recorder)
        }

        run("meta web adapter classifies temporary Meta error pages cleanly", recorder: recorder) {
            let serviceHTML = """
            <!doctype html><html lang="en" id="facebook"><head><title>Facebook | Error</title></head><body>No server is available for the request</body></html>
            """

            let serviceMessage = MetaAIWebAdapter.formattedUpstreamErrorMessage(
                statusCode: 503,
                responseData: Data(serviceHTML.utf8)
            )
            expectContains(serviceMessage, "temporary Meta error page", "raw Meta service error HTML should map to a clean retryable failure", recorder: recorder)
            expectContains(serviceMessage, "retry later", "temporary Meta service failures should encourage retry", recorder: recorder)
        }

        run("meta web adapter surfaces Meta sources on responses outputs", recorder: recorder) {
            let sources = [
                MetaAIWebAdapter.Source(url: "https://example.com/a", title: "Example A", subtitle: "First"),
                MetaAIWebAdapter.Source(url: "https://example.com/b", title: "Example B", subtitle: nil)
            ]

            let body = MetaAIWebAdapter.buildResponsesResponseBody(
                text: "Grounded answer",
                publicModel: "muse-spark",
                sources: sources
            )

            do {
                let response = try jsonObject(from: body)
                let output = response["output"] as? [[String: Any]]
                let content = output?.first?["content"] as? [[String: Any]]
                let annotations = content?.first?["annotations"] as? [[String: Any]]
                expectEqual(annotations?.count, 2, "responses output should expose one annotation per Meta source", recorder: recorder)
                expectEqual(annotations?.first?["type"] as? String, "url_citation", "Meta sources should map to url citations", recorder: recorder)
                expectEqual(annotations?.first?["url"] as? String, "https://example.com/a", "annotation URLs should preserve Meta source URLs", recorder: recorder)
                expectEqual(annotations?.first?["title"] as? String, "Example A", "annotation titles should preserve Meta display names", recorder: recorder)
                expectEqual(annotations?.first?["subtitle"] as? String, "First", "annotation subtitles should preserve Meta source subtitles when present", recorder: recorder)
            } catch {
                recorder.recordFailure("meta web adapter should serialize responses annotations: \(error)")
            }
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
    return try jsonObject(from: body)
}

private func jsonObject(from body: Data) throws -> [String: Any] {
    guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        throw SpecFailure.message("GraphQL body was not a JSON object")
    }
    return json
}

private func writeTempFile(named name: String, contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func withTemporaryEnvironment(_ key: String, value: String, _ body: () throws -> Void) throws {
    let original = getenv(key).map { String(cString: $0) }
    setenv(key, value, 1)
    defer {
        if let original {
            setenv(key, original, 1)
        } else {
            unsetenv(key)
        }
    }
    try body()
}

private enum SpecFailure: Error {
    case message(String)
}
