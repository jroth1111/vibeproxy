import Foundation

@main
struct ThinkingProxyPolicySpec {
    static func main() {
        let recorder = FailureRecorder()

        run("temporary nvidia minimax shim floors max_tokens and strips unsupported fields", recorder: recorder) {
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

        run("temporary nvidia minimax shim sets max_tokens when absent", recorder: recorder) {
            let request = """
            {
              "model": "minimax-m2.5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ]
            }
            """

            let transformed = OpenAICompatTemporaryShim.transformRequest(
                method: "POST",
                path: "/api/v1/chat/completions",
                jsonString: request
            )

            let json = parseJSONObject(transformed, recorder: recorder)
            expectEqual(json["max_tokens"] as? Int, 128, "minimax requests without max_tokens should default to 128", recorder: recorder)
        }

        run("temporary nvidia reasoning shim strips reasoning_effort for glm5 only", recorder: recorder) {
            let request = """
            {
              "model": "glm5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ],
              "max_tokens": 32,
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
            expectEqual(json["max_tokens"] as? Int, 32, "glm5 requests should preserve caller max_tokens", recorder: recorder)
            expectNil(json["reasoning_effort"], "glm5 requests should strip reasoning_effort", recorder: recorder)
            expectEqual((json["response_format"] as? [String: String])?["type"], "json_object", "glm5 should not strip unrelated fields", recorder: recorder)
        }

        run("temporary nvidia reasoning shim forces kimi-k2.5 instant mode and floors max_tokens", recorder: recorder) {
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
            expectNil(json["reasoning_effort"], "kimi-k2.5 requests should strip reasoning_effort", recorder: recorder)
            expectNil(json["stop"], "kimi-k2.5 should strip stop for the temporary mitigation", recorder: recorder)
            expectEqual(json["max_tokens"] as? Int, 384, "kimi-k2.5 should floor max_tokens to 384", recorder: recorder)
            expectEqual((json["chat_template_kwargs"] as? [String: Bool])?["thinking"], false, "kimi-k2.5 should force instant mode", recorder: recorder)
            expectEqual(json["include_reasoning"] as? Bool, false, "kimi-k2.5 should request no reasoning field in non-streaming mode", recorder: recorder)
        }

        run("temporary nvidia mitigation disables streaming tool calls for NVIDIA models", recorder: recorder) {
            let request = """
            {
              "model": "kimi-k2.5",
              "messages": [
                {"role": "user", "content": "Use the tool."}
              ],
              "stream": true,
              "tool_choice": {
                "type": "function",
                "function": {"name": "lookup"}
              },
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
            expectEqual(json["stream"] as? Bool, false, "NVIDIA tool calls should be forced to non-streaming mode", recorder: recorder)
            expectEqual(json["tool_choice"] as? String, "auto", "function-style tool_choice should be rewritten to auto", recorder: recorder)
        }

        run("temporary nvidia reasoning shim leaves unrelated models untouched", recorder: recorder) {
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

            expectNil(transformed, "non-NVIDIA temporary models should not be rewritten", recorder: recorder)
        }

        run("temporary provider mitigation routes glm-5 through response sanity checks without rewriting the request", recorder: recorder) {
            let request = """
            {
              "model": "glm-5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ],
              "max_tokens": 32
            }
            """

            let transformed = OpenAICompatTemporaryShim.transformRequest(
                method: "POST",
                path: "/v1/chat/completions",
                jsonString: request
            )
            let isMitigated = OpenAICompatTemporaryShim.isNvidiaReasoningChatRequest(
                method: "POST",
                path: "/v1/chat/completions",
                jsonString: request
            )

            expectNil(transformed, "glm-5 should not be rewritten when no request shaping is required", recorder: recorder)
            expectEqual(isMitigated, true, "glm-5 should still enter the mitigation retry/repair path", recorder: recorder)
        }

        run("temporary nvidia model timeout overrides are model-specific", recorder: recorder) {
            let glm5Request = """
            {
              "model": "glm5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ]
            }
            """
            let minimaxRequest = """
            {
              "model": "minimax-m2.5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ]
            }
            """
            let zaiRequest = """
            {
              "model": "glm-5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ]
            }
            """

            expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: glm5Request), 200, "glm5 should use the 200 second timeout override", recorder: recorder)
            expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: minimaxRequest), 200, "minimax should use the 200 second timeout override", recorder: recorder)
            expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: zaiRequest), 200, "Z.AI mitigation should keep the long-running timeout override", recorder: recorder)

            let glm5Budget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: glm5Request)
            let minimaxBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: minimaxRequest)
            expectEqual(glm5Budget?.transport, 2, "glm5 should keep transport retries only", recorder: recorder)
            expectEqual(glm5Budget?.semantic, 0, "glm5 should not spend semantic retries on transport-only failures", recorder: recorder)
            expectEqual(minimaxBudget?.transport, 2, "minimax should retain transport retries", recorder: recorder)
            expectEqual(minimaxBudget?.semantic, 2, "minimax should retain semantic retries", recorder: recorder)
            expectEqual(minimaxBudget?.backoffMilliseconds, 250, "minimax should use retry backoff", recorder: recorder)
            expectEqual(minimaxBudget?.salvagesBestEffortRepair, true, "minimax should preserve best-effort repaired responses across retries", recorder: recorder)
        }

        run("temporary nvidia reasoning shim ignores non-chat endpoints", recorder: recorder) {
            let request = """
            {
              "model": "minimax-m2.5",
              "messages": [
                {"role": "user", "content": "Return exactly: OK"}
              ],
              "max_tokens": 32
            }
            """

            let transformed = OpenAICompatTemporaryShim.transformRequest(
                method: "POST",
                path: "/v1/models",
                jsonString: request
            )

            expectNil(transformed, "non-chat endpoints should not be rewritten", recorder: recorder)
        }

        run("temporary nvidia reasoning shim retries leaked reasoning responses", recorder: recorder) {
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

        run("temporary nvidia reasoning shim can repair closed think blocks with trailing answers", recorder: recorder) {
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

            expectEqual(evaluation.retryReason, "reasoning_leak_length", "closed think blocks should still be retryable first", recorder: recorder)

            guard let repairedBodyData = evaluation.repairedBodyData,
                  let repairedJSON = try? JSONSerialization.jsonObject(with: repairedBodyData) as? [String: Any],
                  let repairedChoices = repairedJSON["choices"] as? [[String: Any]],
                  let repairedMessage = repairedChoices.first?["message"] as? [String: Any] else {
                recorder.recordFailure("expected repaired minimax response body to be generated")
                return
            }

            expectEqual(repairedMessage["content"] as? String, "OK", "repaired minimax responses should drop the think block and keep the trailing answer", recorder: recorder)
            expectNil(repairedMessage["reasoning"], "repaired minimax responses should strip provider-specific reasoning fields", recorder: recorder)
        }

        run("temporary nvidia reasoning shim retries empty content without attempting repair", recorder: recorder) {
            let response = """
            {
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {
                    "content": "   "
                  }
                }
              ]
            }
            """

            let evaluation = OpenAICompatTemporaryShim.evaluateNvidiaReasoningResponse(
                model: "glm-5",
                statusCode: 200,
                bodyData: Data(response.utf8)
            )

            expectEqual(evaluation.retryReason, "empty_content", "empty content should be retryable", recorder: recorder)
            expectNil(evaluation.repairedBodyData, "empty content should not generate a repaired body", recorder: recorder)
        }

        run("temporary nvidia reasoning shim retries kimi reasoning-only responses with missing content", recorder: recorder) {
            let response = """
            {
              "choices": [
                {
                  "finish_reason": "length",
                  "message": {
                    "content": null,
                    "reasoning": "The user wants exactly OK."
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

            expectEqual(
                evaluation.retryReason,
                "reasoning_only_content_missing",
                "reasoning-only kimi responses should be classified as invalid and retryable",
                recorder: recorder
            )
            expectNil(evaluation.repairedBodyData, "reasoning-only kimi responses should not be repaired into synthetic output", recorder: recorder)
        }

        run("temporary nvidia reasoning shim retries kimi reasoning_content-only responses with missing content", recorder: recorder) {
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

            expectEqual(
                evaluation.retryReason,
                "reasoning_only_content_missing",
                "reasoning_content-only kimi responses should be classified as invalid and retryable",
                recorder: recorder
            )
            expectNil(evaluation.repairedBodyData, "reasoning_content-only kimi responses should not be repaired into synthetic output", recorder: recorder)
        }

        run("temporary nvidia reasoning shim strips provider-specific reasoning on successful kimi responses", recorder: recorder) {
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
            expectNil(normalizedMessage?["reasoning"], "normalized kimi responses should strip provider-specific reasoning", recorder: recorder)
            expectNil(normalizedMessage?["reasoning_content"], "normalized kimi responses should strip provider-specific reasoning_content", recorder: recorder)
        }

        run("temporary nvidia reasoning shim treats retryable transport failures as retryable", recorder: recorder) {
            let timeoutError = URLError(.timedOut)
            let retryableStatusCodes = [408, 429, 500, 502, 503, 504]

            expectEqual(
                OpenAICompatTemporaryShim.shouldRetryNvidiaReasoningTransport(error: timeoutError),
                true,
                "timed out NVIDIA transport failures should be retried",
                recorder: recorder
            )

            for statusCode in retryableStatusCodes {
                expectEqual(
                    OpenAICompatTemporaryShim.shouldRetryNvidiaReasoningTransport(statusCode: statusCode),
                    true,
                    "HTTP \(statusCode) should be retried for temporary NVIDIA reasoning mitigation",
                    recorder: recorder
                )
            }
        }

        run("temporary nvidia reasoning shim ignores non-retryable transport states", recorder: recorder) {
            expectEqual(
                OpenAICompatTemporaryShim.shouldRetryNvidiaReasoningTransport(error: URLError(.badURL)),
                false,
                "non-retryable URL errors should not be retried",
                recorder: recorder
            )
            expectEqual(
                OpenAICompatTemporaryShim.shouldRetryNvidiaReasoningTransport(statusCode: 401),
                false,
                "HTTP 401 should not be retried by the temporary NVIDIA mitigation",
                recorder: recorder
            )
        }

        run("temporary nvidia minimax shim does not claim a repair when only think text remains", recorder: recorder) {
            let response = """
            {
              "choices": [
                {
                  "finish_reason": "stop",
                  "message": {
                    "content": "<think>draft reasoning</think>"
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

            expectEqual(evaluation.retryReason, "reasoning_leak_length", "think-only minimax responses should still be retried", recorder: recorder)
            expectNil(evaluation.repairedBodyData, "think-only minimax responses should not invent a repaired answer", recorder: recorder)
        }

        run("temporary nvidia reasoning shim accepts normal responses unchanged", recorder: recorder) {
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
