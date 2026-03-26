import Foundation

@main
struct ThinkingProxyPolicySpec {
    static func main() {
        let recorder = FailureRecorder()

        run("temporary nvidia minimax shim floors max_tokens and strips unsupported fields", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "minimax-m2.5",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ],
                  "max_tokens": 32,
                  "reasoning_effort": "high",
                  "response_format": {"type": "json_object"},
                  "stop": ["END"]
                }
                """

                let transformed = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )

                let json = parseJSONObject(transformed, recorder: recorder)
                expectEqual(json["max_tokens"] as? Int, 128, "minimax requests should be floored to max_tokens 128", recorder: recorder)
                expectNil(json["reasoning_effort"], "reasoning_effort should be stripped for minimax", recorder: recorder)
                expectNil(json["response_format"], "response_format should be stripped for minimax", recorder: recorder)
                expectNil(json["stop"], "stop should be stripped for minimax", recorder: recorder)
            }
        }

        run("temporary nvidia kimi shim forces instant mode and floors max_tokens", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "kimi-k2.5",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ],
                  "reasoning_effort": "medium",
                  "stop": ["END"]
                }
                """

                let transformed = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )

                let json = parseJSONObject(transformed, recorder: recorder)
                let chatTemplate = json["chat_template_kwargs"] as? [String: Bool]
                expectEqual(json["max_tokens"] as? Int, 384, "kimi should floor max_tokens to 384", recorder: recorder)
                expectNil(json["reasoning_effort"], "kimi should strip reasoning_effort", recorder: recorder)
                expectNil(json["stop"], "kimi should strip stop", recorder: recorder)
                expectEqual(chatTemplate?["thinking"], false, "kimi should force chat_template_kwargs.thinking=false", recorder: recorder)
                expectEqual(chatTemplate?["enable_thinking"], false, "kimi should force chat_template_kwargs.enable_thinking=false", recorder: recorder)
                expectEqual(json["include_reasoning"] as? Bool, false, "kimi should request no reasoning field in buffered mode", recorder: recorder)
            }
        }

        run("canonical nvidia route identity preserves mitigation when aliases are renamed", recorder: recorder) {
            withMergedConfig(renamedAliasMergedConfigYAML()) {
                let request = """
                {
                  "model": "glm-five-custom",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ],
                  "reasoning_effort": "high",
                  "response_format": {"type": "json_object"}
                }
                """

                let transformed = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )
                let json = parseJSONObject(transformed, recorder: recorder)
                let isMitigated = OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: transformed ?? request
                )

                expectEqual(isMitigated, true, "renamed aliases should still resolve to the canonical NVIDIA mitigation policy", recorder: recorder)
                expectNil(json["reasoning_effort"], "glm5 mitigation should still strip reasoning_effort after alias renames", recorder: recorder)
                expectNil(json["response_format"], "glm5 mitigation should still strip response_format after alias renames", recorder: recorder)
            }
        }

        run("temporary nvidia preflight rejects streaming for buffered mitigation routes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "glm5",
                  "stream": true,
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ]
                }
                """

                let transformed = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )
                let preflightError = OpenAICompatTemporaryShim.preflightError(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )

                expectNil(transformed, "stream-only requests should not be silently rewritten just to hide buffering", recorder: recorder)
                expectEqual(preflightError?.statusCode ?? 0, 501, "buffered NVIDIA mitigations should reject client streaming explicitly", recorder: recorder)
            }
        }

        run("temporary nvidia preflight rejects strict tool choice instead of silently weakening semantics", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "kimi-k2.5",
                  "messages": [
                    {"role": "user", "content": "Use the tool."}
                  ],
                  "tool_choice": {
                    "type": "required",
                    "function": {"name": "lookup"}
                  },
                  "response_format": {"type": "json_object"},
                  "tools": [
                    {
                      "type": "function",
                      "function": {
                        "name": "lookup",
                        "parameters": {"type": "object"}
                      }
                    }
                  ]
                }
                """

                let transformed = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )
                let json = parseJSONObject(transformed, recorder: recorder)
                let preflightError = OpenAICompatTemporaryShim.preflightError(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: transformed ?? request
                )
                let toolChoice = json["tool_choice"] as? [String: Any]

                expectEqual(toolChoice?["type"] as? String, "required", "strict tool choice should not be rewritten to auto", recorder: recorder)
                expectNil(json["response_format"], "response_format should still be stripped for NVIDIA tool requests", recorder: recorder)
                expectEqual(preflightError?.statusCode ?? 0, 501, "strict NVIDIA tool-choice requests should fail closed", recorder: recorder)
            }
        }

        run("temporary nvidia shim flattens text-only typed content arrays", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "glm5",
                  "messages": [
                    {
                      "role": "user",
                      "content": [
                        {"type": "text", "text": "Hello "},
                        {"type": "input_text", "text": "world"}
                      ]
                    }
                  ]
                }
                """

                let transformed = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )

                let json = parseJSONObject(transformed, recorder: recorder)
                let messages = json["messages"] as? [[String: Any]]
                expectEqual(messages?.first?["content"] as? String, "Hello world", "text-only typed content arrays should be flattened into a single string", recorder: recorder)
            }
        }

        run("temporary nvidia preflight rejects unsupported typed content arrays", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "glm5",
                  "messages": [
                    {
                      "role": "user",
                      "content": [
                        {
                          "type": "image_url",
                          "image_url": {"url": "https://example.com/cat.png"}
                        }
                      ]
                    }
                  ]
                }
                """

                let preflightError = OpenAICompatTemporaryShim.preflightError(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )

                expectEqual(preflightError?.statusCode ?? 0, 400, "unsupported typed content should be rejected before the NVIDIA backend sees it", recorder: recorder)
            }
        }

        run("temporary nvidia preflight rejects /v1/responses for NVIDIA-hosted routes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "glm5",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ]
                }
                """

                let preflightError = OpenAICompatTemporaryShim.preflightError(
                    method: "POST",
                    path: "/v1/responses",
                    jsonString: request
                )

                expectEqual(preflightError?.statusCode ?? 0, 501, "NVIDIA-hosted routes should fail fast on /v1/responses", recorder: recorder)
            }
        }

        run("temporary nvidia timeout and retry budgets are route-specific", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let glm5Request = """
                {
                  "model": "glm5",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """
                let minimaxRequest = """
                {
                  "model": "minimax-m2.5",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: glm5Request), 200, "glm5 should keep the long per-attempt timeout", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: minimaxRequest), 200, "minimax should keep the long per-attempt timeout", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: glm5Request), 25, "glm5 should fail closed on first-byte stalls", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: minimaxRequest), 25, "minimax should also guard first-byte stalls", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: glm5Request), 28, "glm5 should bound the full buffered response time", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: minimaxRequest), 28, "minimax should also bound the full buffered response time", recorder: recorder)

                let glm5Budget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: glm5Request)
                let minimaxBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: minimaxRequest)
                expectEqual(glm5Budget?.transport, 0, "glm5 should not spend extra proxy transport retries", recorder: recorder)
                expectEqual(glm5Budget?.semantic, 1, "glm5 should reserve one semantic retry for malformed tool-call payloads", recorder: recorder)
                expectEqual(minimaxBudget?.transport, 0, "minimax should leave transport failover to the backend manager", recorder: recorder)
                expectEqual(minimaxBudget?.semantic, 2, "minimax should keep semantic retries", recorder: recorder)
                expectEqual(minimaxBudget?.backoffMilliseconds, 250, "minimax should use retry backoff", recorder: recorder)
                expectEqual(minimaxBudget?.salvagesBestEffortRepair, true, "minimax should preserve a best-effort repaired body across retries", recorder: recorder)
            }
        }

        run("temporary nvidia deadline tracker fires first-byte timeout before payload and buffered timeout after payload", recorder: recorder) {
            var tracker = OpenAICompatTemporaryShim.ResponseDeadlineTracker()

            expectEqual(tracker.firstResponseDeadlineDidFire(), true, "first-response deadline should fire before any payload arrives", recorder: recorder)
            expectEqual(tracker.deadlineExceeded, true, "first-response deadline should mark the tracker as exceeded", recorder: recorder)

            tracker = OpenAICompatTemporaryShim.ResponseDeadlineTracker()
            tracker.payloadReceived()
            expectEqual(tracker.firstResponseDeadlineDidFire(), false, "first-response deadline should be suppressed after payload arrives", recorder: recorder)
            expectEqual(tracker.bufferedResponseDeadlineDidFire(), true, "buffered deadline should still fire until the response finishes", recorder: recorder)
        }

        run("temporary nvidia deadline tracker finish suppresses later cancellations", recorder: recorder) {
            var tracker = OpenAICompatTemporaryShim.ResponseDeadlineTracker()
            tracker.finish()

            expectEqual(tracker.firstResponseDeadlineDidFire(), false, "finished responses should not be cancelled by the first-response deadline", recorder: recorder)
            expectEqual(tracker.bufferedResponseDeadlineDidFire(), false, "finished responses should not be cancelled by the buffered deadline", recorder: recorder)
            expectEqual(tracker.deadlineExceeded, false, "finishing before deadlines fire should keep the tracker clean", recorder: recorder)
        }

        run("temporary nvidia semantic retry disposition preserves repaired bodies and returns them after retry exhaustion", recorder: recorder) {
            let repaired = Data("{\"choices\":[{\"message\":{\"content\":\"OK\"}}]}".utf8)
            let evaluation = OpenAICompatTemporaryShim.NvidiaReasoningEvaluation(
                failureClass: .reasoningLeakLength,
                repairedBodyData: repaired,
                normalizedBodyData: repaired
            )

            let retryDisposition = OpenAICompatTemporaryShim.semanticFailureDisposition(
                evaluation: evaluation,
                semanticRetriesRemaining: 1,
                preservedBestEffortRepair: nil,
                salvagesBestEffortRepair: true
            )

            switch retryDisposition {
            case .retry(let nextRemaining, let preserved):
                expectEqual(nextRemaining, 0, "semantic retries should decrement exactly once", recorder: recorder)
                expectEqual(preserved, repaired, "semantic retries should preserve repaired bodies for later fallback", recorder: recorder)
            default:
                recorder.recordFailure("expected semantic failure disposition to retry while retries remain")
            }

            let fallbackEvaluation = OpenAICompatTemporaryShim.NvidiaReasoningEvaluation(
                failureClass: .reasoningLeakLength,
                repairedBodyData: nil,
                normalizedBodyData: nil
            )
            let fallbackDisposition = OpenAICompatTemporaryShim.semanticFailureDisposition(
                evaluation: fallbackEvaluation,
                semanticRetriesRemaining: 0,
                preservedBestEffortRepair: repaired,
                salvagesBestEffortRepair: true
            )

            switch fallbackDisposition {
            case .returnRepaired(let body):
                expectEqual(body, repaired, "exhausted semantic retries should return the preserved repaired body", recorder: recorder)
            default:
                recorder.recordFailure("expected exhausted semantic retries to return the preserved repaired body")
            }
        }

        run("temporary nvidia semantic retry disposition fails closed when no repaired body exists", recorder: recorder) {
            let evaluation = OpenAICompatTemporaryShim.NvidiaReasoningEvaluation(
                failureClass: .emptyContent,
                repairedBodyData: nil,
                normalizedBodyData: nil
            )

            let disposition = OpenAICompatTemporaryShim.semanticFailureDisposition(
                evaluation: evaluation,
                semanticRetriesRemaining: 0,
                preservedBestEffortRepair: nil,
                salvagesBestEffortRepair: true
            )

            switch disposition {
            case .returnGatewayError:
                break
            default:
                recorder.recordFailure("expected exhausted semantic failures without repaired output to fail closed")
            }
        }

        run("temporary nvidia transport retry disposition returns preserved repaired bodies after retry exhaustion", recorder: recorder) {
            let repaired = Data("{\"choices\":[{\"message\":{\"content\":\"OK\"}}]}".utf8)
            let disposition = OpenAICompatTemporaryShim.transportFailureDisposition(
                error: URLError(.timedOut),
                transportRetriesRemaining: 0,
                salvagesBestEffortRepair: true,
                preservedBestEffortRepair: repaired
            )

            switch disposition {
            case .returnRepaired(let body):
                expectEqual(body, repaired, "transport exhaustion should return preserved repaired output when available", recorder: recorder)
            default:
                recorder.recordFailure("expected transport exhaustion with preserved repair to return the repaired body")
            }
        }

        run("temporary nvidia transport retry disposition fails with 504 for deadline-driven timeouts", recorder: recorder) {
            let disposition = OpenAICompatTemporaryShim.transportFailureDisposition(
                error: URLError(.timedOut),
                transportRetriesRemaining: 0,
                salvagesBestEffortRepair: false,
                preservedBestEffortRepair: nil
            )

            switch disposition {
            case .returnGatewayError(let statusCode, let message):
                expectEqual(statusCode, 504, "timed-out NVIDIA transport failures should surface as 504", recorder: recorder)
                expectEqual(message, "Gateway Timeout", "timed-out NVIDIA transport failures should keep the gateway-timeout message", recorder: recorder)
            default:
                recorder.recordFailure("expected timed-out transport exhaustion to return a gateway-timeout error")
            }
        }

        run("temporary nvidia failure classification normalizes function-not-found outages", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let problem = """
                {
                  "status": 404,
                  "title": "Not Found",
                  "detail": "Function 'abc': Not found for account 'acct'"
                }
                """

                let classification = OpenAICompatTemporaryShim.classifyUpstreamFailure(
                    model: "glm5",
                    path: "/v1/chat/completions",
                    statusCode: 404,
                    bodyData: Data(problem.utf8)
                )

                expectEqual(classification?.statusCode ?? 0, 503, "function-not-found outages should surface as provider unavailability", recorder: recorder)
            }
        }

        run("temporary nvidia failure classification normalizes responses endpoint 404s", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = "404 page not found"

                let classification = OpenAICompatTemporaryShim.classifyUpstreamFailure(
                    model: "glm5",
                    path: "/v1/responses",
                    statusCode: 404,
                    bodyData: Data(body.utf8)
                )

                expectEqual(classification?.statusCode ?? 0, 501, "responses 404s should surface as unsupported NVIDIA hosted behavior", recorder: recorder)
            }
        }

        run("temporary nvidia failure classification preserves upstream overload as 429", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = """
                {
                  "error": {
                    "message": "Too Many Requests"
                  }
                }
                """

                let classification = OpenAICompatTemporaryShim.classifyUpstreamFailure(
                    model: "kimi-k2.5",
                    path: "/v1/chat/completions",
                    statusCode: 429,
                    bodyData: Data(body.utf8)
                )

                expectEqual(classification?.statusCode ?? 0, 429, "NVIDIA overload/rate-limit responses should remain explicit 429s", recorder: recorder)
            }
        }

        run("temporary nvidia failure classification normalizes typed-content schema mismatch", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = """
                {
                  "detail": [
                    {
                      "loc": ["body", "messages", 0, "content"],
                      "msg": "Input should be a valid string"
                    }
                  ]
                }
                """

                let classification = OpenAICompatTemporaryShim.classifyUpstreamFailure(
                    model: "glm5",
                    path: "/v1/chat/completions",
                    statusCode: 400,
                    bodyData: Data(body.utf8)
                )

                expectEqual(classification?.statusCode ?? 0, 400, "typed-content schema mismatches should surface as explicit 400s", recorder: recorder)
            }
        }

        run("temporary nvidia failure classification normalizes EngineCore upstream faults", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = """
                {
                  "error": {
                    "message": "EngineCore encountered an issue"
                  }
                }
                """

                let classification = OpenAICompatTemporaryShim.classifyUpstreamFailure(
                    model: "glm5",
                    path: "/v1/chat/completions",
                    statusCode: 500,
                    bodyData: Data(body.utf8)
                )

                expectEqual(classification?.statusCode ?? 0, 502, "EngineCore faults should be normalized into upstream bad-gateway failures", recorder: recorder)
            }
        }

        run("temporary nvidia shim retries empty-body successes instead of forwarding them", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "kimi-k2.5",
                    statusCode: 200,
                    bodyData: Data()
                )

                expectEqual(evaluation.retryReason, "empty_body", "empty 200 bodies should be treated as retryable invalid-success responses", recorder: recorder)
                expectNil(evaluation.repairedBodyData, "empty-body successes should not be auto-repaired", recorder: recorder)
            }
        }

        run("temporary nvidia glm5 shim retries empty-content successes instead of forwarding them", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "stop",
                      "message": {
                        "content": null
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "glm5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectEqual(evaluation.retryReason, "empty_content", "glm5 should fail closed on blank 200 responses instead of forwarding them", recorder: recorder)
                expectNil(evaluation.repairedBodyData, "blank glm5 successes should not be auto-repaired", recorder: recorder)
            }
        }

        run("temporary nvidia minimax shim retries leaked reasoning responses", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "length",
                      "message": {
                        "content": "<think>The user wants the answer OK."
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "minimax-m2.5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectEqual(evaluation.retryReason, "reasoning_leak_length", "leaked reasoning should be marked retryable", recorder: recorder)
                expectNil(evaluation.repairedBodyData, "unclosed leaked reasoning should not claim a safe repaired body", recorder: recorder)
            }
        }

        run("temporary nvidia minimax shim can repair closed think blocks with trailing answers", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "stop",
                      "message": {
                        "content": "<think>draft reasoning</think>\\n\\nOK"
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "minimax-m2.5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectEqual(evaluation.retryReason, "reasoning_leak_length", "closed think blocks should still be retried first", recorder: recorder)
                guard let repairedBodyData = evaluation.repairedBodyData,
                      let repairedJSON = try? JSONSerialization.jsonObject(with: repairedBodyData) as? [String: Any],
                      let repairedChoices = repairedJSON["choices"] as? [[String: Any]],
                      let repairedMessage = repairedChoices.first?["message"] as? [String: Any] else {
                    recorder.recordFailure("expected repaired minimax response body to be generated")
                    return
                }

                expectEqual(repairedMessage["content"] as? String, "OK", "repaired minimax responses should keep the trailing answer", recorder: recorder)
                expectNil(repairedMessage["reasoning"], "repaired minimax responses should strip provider reasoning fields", recorder: recorder)
            }
        }

        run("temporary nvidia kimi shim retries reasoning-only responses with missing content", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "length",
                      "message": {
                        "content": null,
                        "reasoning_content": "The user wants exactly OK."
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "kimi-k2.5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectEqual(evaluation.retryReason, "reasoning_only_content_missing", "reasoning-only kimi responses should be classified as invalid and retryable", recorder: recorder)
                expectNil(evaluation.repairedBodyData, "reasoning-only kimi responses should not be repaired into synthetic output", recorder: recorder)
            }
        }

        run("temporary nvidia shim strips provider-specific reasoning from successful kimi responses", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "stop",
                      "message": {
                        "content": " OK",
                        "reasoning": "hidden chain of thought",
                        "reasoning_content": "duplicate hidden chain of thought"
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "kimi-k2.5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectNil(evaluation.retryReason, "successful kimi responses should not be retried", recorder: recorder)
                guard let normalizedBodyData = evaluation.normalizedBodyData else {
                    recorder.recordFailure("expected normalized kimi response body to be generated")
                    return
                }

                let normalizedJSON = parseDataJSONObject(normalizedBodyData, recorder: recorder)
                let normalizedChoices = normalizedJSON["choices"] as? [[String: Any]]
                let normalizedMessage = normalizedChoices?.first?["message"] as? [String: Any]
                expectEqual(normalizedMessage?["content"] as? String, " OK", "normalized kimi responses should preserve visible content", recorder: recorder)
                expectNil(normalizedMessage?["reasoning"], "normalized kimi responses should strip provider reasoning", recorder: recorder)
                expectNil(normalizedMessage?["reasoning_content"], "normalized kimi responses should strip provider reasoning_content", recorder: recorder)
            }
        }

        run("temporary nvidia shim accepts valid tool-call responses without visible content", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "tool_calls",
                      "message": {
                        "content": null,
                        "tool_calls": [
                          {
                            "id": "call_123",
                            "type": "function",
                            "function": {
                              "name": "lookup",
                              "arguments": "{\\"query\\":\\"OK\\"}"
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "glm5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectNil(evaluation.retryReason, "valid tool-call responses should not be misclassified as empty content", recorder: recorder)
            }
        }

        run("temporary nvidia shim retries malformed tool-call argument payloads", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "tool_calls",
                      "message": {
                        "content": null,
                        "tool_calls": [
                          {
                            "id": "call_123",
                            "type": "function",
                            "function": {
                              "name": "lookup",
                              "arguments": "{\\"query\\":\\"OK\\""
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "glm5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectEqual(evaluation.retryReason, "malformed_tool_arguments", "malformed tool-call payloads should be retried", recorder: recorder)
                expectNil(evaluation.repairedBodyData, "malformed tool-call payloads should not be auto-repaired", recorder: recorder)
            }
        }

        run("temporary nvidia shim accepts clean responses unchanged", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let response = """
                {
                  "choices": [
                    {
                      "finish_reason": "stop",
                      "message": {
                        "content": "\\n\\nOK"
                      }
                    }
                  ]
                }
                """

                let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                    model: "minimax-m2.5",
                    statusCode: 200,
                    bodyData: Data(response.utf8)
                )

                expectNil(evaluation.retryReason, "clean minimax responses should not be retried", recorder: recorder)
                expectNil(evaluation.repairedBodyData, "clean minimax responses should not be rewritten", recorder: recorder)
            }
        }

        run("temporary nvidia shim leaves unrelated models untouched", recorder: recorder) {
            let request = """
            {
              "model": "gpt-5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ],
              "reasoning_effort": "high"
            }
            """

            let transformed = OpenAICompatTemporaryShim.transformRequest(
                method: "POST",
                path: "/v1/chat/completions",
                jsonString: request
            )

            expectNil(transformed, "unrelated models should not be rewritten", recorder: recorder)
        }

        if recorder.failures == 0 {
            print("ThinkingProxyPolicySpec: all checks passed")
            Foundation.exit(EXIT_SUCCESS)
        }

        fputs("ThinkingProxyPolicySpec: \(recorder.failures) check(s) failed\n", stderr)
        Foundation.exit(EXIT_FAILURE)
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

private func expectNil(
    _ value: @autoclosure () -> Any?,
    _ message: String,
    recorder: FailureRecorder
) {
    guard value() == nil else {
        recorder.recordFailure("\(message): expected nil")
        return
    }
}

private func parseJSONObject(_ jsonString: String?, recorder: FailureRecorder) -> [String: Any] {
    guard let jsonString,
          let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        recorder.recordFailure("failed to parse transformed JSON")
        return [:]
    }
    return json
}

private func parseDataJSONObject(_ data: Data, recorder: FailureRecorder) -> [String: Any] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        recorder.recordFailure("failed to parse transformed JSON data")
        return [:]
    }
    return json
}

private func withMergedConfig(_ yaml: String, body: () -> Void) {
    let key = "VIBEPROXY_MERGED_CONFIG_PATH"
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configPath = temporaryDirectory.appendingPathComponent("merged-config.yaml")
    let previousValue = ProcessInfo.processInfo.environment[key]

    try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try? yaml.write(to: configPath, atomically: true, encoding: .utf8)
    setenv(key, configPath.path, 1)
    defer {
        if let previousValue {
            setenv(key, previousValue, 1)
        } else {
            unsetenv(key)
        }
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    body()
}

private func defaultMergedConfigYAML() -> String {
    [
        "openai-compatibility:",
        "- name: nvidia",
        "  base-url: https://integrate.api.nvidia.com/v1",
        "  models:",
        "  - alias: glm5",
        "    name: z-ai/glm5",
        "  - alias: kimi-k2.5",
        "    name: moonshotai/kimi-k2.5",
        "- name: nvidia-minimax",
        "  base-url: https://integrate.api.nvidia.com/v1",
        "  models:",
        "  - alias: minimax-m2.5",
        "    name: minimaxai/minimax-m2.5"
    ].joined(separator: "\n")
}

private func renamedAliasMergedConfigYAML() -> String {
    [
        "openai-compatibility:",
        "- name: nvidia",
        "  base-url: https://integrate.api.nvidia.com/v1",
        "  models:",
        "  - alias: glm-five-custom",
        "    name: z-ai/glm5",
        "  - alias: kimi-custom",
        "    name: moonshotai/kimi-k2.5",
        "- name: nvidia-minimax",
        "  base-url: https://integrate.api.nvidia.com/v1",
        "  models:",
        "  - alias: minimax-custom",
        "    name: minimaxai/minimax-m2.5"
    ].joined(separator: "\n")
}
