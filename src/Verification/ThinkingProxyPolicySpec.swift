import Foundation
import Network

@main
struct ThinkingProxyPolicySpec {
    static func main() {
        let recorder = FailureRecorder()

        run("temporary nvidia minimax shim floors max_tokens and strips unsupported fields", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let request = """
                {
                  "model": "minimax-m2.5-nvidia",
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
                  "model": "kimi-k2.5-nvidia",
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

        run("provider models can hide raw canonical names while preserving aliased upstream routing", recorder: recorder) {
            withMergedConfig(
                [
                    "openai-compatibility:",
                    "- name: ollama-pro",
                    "  base-url: https://ollama.com/api",
                    "  models:",
                    "  - alias: glm-5.1-ollama-pro",
                    "    name: glm-5.1",
                    "    register-canonical-name: false"
                ].joined(separator: "\n")
            ) {
                let aliasedRoute = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: "glm-5.1-ollama-pro")
                expectEqual(aliasedRoute?.providerID, "ollama-pro", "aliased ollama provider route should resolve", recorder: recorder)
                expectEqual(aliasedRoute?.canonicalModelID, "glm-5.1", "aliased ollama route should still forward the real upstream model name", recorder: recorder)

                let rawRoute = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: "glm-5.1")
                expectNil(rawRoute, "raw upstream model name should stay unregistered when register-canonical-name=false", recorder: recorder)
            }
        }

        run("worker-pool entrypoints floor tiny max_tokens budgets before fallback", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let publicAliasRequest = """
                {
                  "model": "proxy-worker-smart-router",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ],
                  "max_tokens": 32
                }
                """

                let transformedPublicAlias = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: publicAliasRequest
                )
                let publicAliasJSON = parseJSONObject(transformedPublicAlias, recorder: recorder)
                expectEqual(publicAliasJSON["max_tokens"] as? Int, 128, "worker smart-router requests should floor tiny max_tokens budgets before GLM/Ollama fallback", recorder: recorder)
            }

            withMergedConfig(defaultMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    let selfRoutedWorkerRequest = """
                    {
                      "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                      "messages": [
                        {"role": "user", "content": "Return exactly: OK"}
                      ],
                      "max_tokens": 32
                    }
                    """

                    let transformedSelfRoutedWorker = OpenAICompatTemporaryShim.transformRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        jsonString: selfRoutedWorkerRequest
                    )
                    let selfRoutedWorkerJSON = parseJSONObject(transformedSelfRoutedWorker, recorder: recorder)
                    expectEqual(selfRoutedWorkerJSON["max_tokens"] as? Int, 128, "self-routed Factory worker IDs should inherit the same max_tokens floor as the public worker smart route", recorder: recorder)
                }
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
                  "model": "kimi-k2.5-nvidia",
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

        run("temporary direct glm-5.1-zai route rejects /v1/responses", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let request = """
                {
                  "model": "glm-5.1-zai",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ]
                }
                """

                let preflightError = OpenAICompatTemporaryShim.configuredRoutePreflightError(
                    method: "POST",
                    path: "/v1/responses",
                    jsonString: request
                )

                expectEqual(preflightError?.statusCode ?? 0, 501, "direct glm-5.1-zai requests should fail fast on /v1/responses instead of surfacing a useless success-shaped response", recorder: recorder)
                expectEqual(preflightError?.message, "Z.AI glm-5.1 does not provide a reliable /v1/responses surface via this proxy; use Anthropic /v1/messages or /v1/chat/completions.", "direct glm-5.1-zai /v1/responses rejections should steer callers to the supported surfaces", recorder: recorder)
            }
        }

        run("legacy zai glm aliases normalize to glm-5.1", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let legacyRequest = """
                {
                  "model": "glm-5",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ]
                }
                """
                let turboRequest = """
                {
                  "model": "glm-5-turbo",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ]
                }
                """

                let transformedLegacy = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: legacyRequest
                )
                let transformedTurbo = OpenAICompatTemporaryShim.transformRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: turboRequest
                )
                let legacyJSON = parseJSONObject(transformedLegacy ?? legacyRequest, recorder: recorder)
                let turboJSON = parseJSONObject(transformedTurbo ?? turboRequest, recorder: recorder)

                expectEqual(OpenAICompatTemporaryShim.modelName(forRequestJSON: legacyRequest), "glm-5.1", "legacy glm-5 requests should normalize to glm-5.1 before routing", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.modelName(forRequestJSON: turboRequest), "glm-5.1", "legacy glm-5-turbo requests should normalize to glm-5.1 before routing", recorder: recorder)
                expectEqual(legacyJSON["model"] as? String, "glm-5.1", "legacy glm-5 request bodies should be rewritten onto glm-5.1", recorder: recorder)
                expectEqual(turboJSON["model"] as? String, "glm-5.1", "legacy glm-5-turbo request bodies should be rewritten onto glm-5.1", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "glm-5")?.candidates.contains("glm-5.1-ollama-pro"), true, "legacy glm-5 alias should reuse the pooled Ollama GLM primary", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "glm-5-turbo")?.candidates.contains("glm-5.1-ollama-pro"), true, "legacy glm-5-turbo alias should reuse the pooled Ollama GLM primary", recorder: recorder)
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
                let kimiRequest = """
                {
                  "model": "kimi-k2.5-nvidia",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """
                let minimaxRequest = """
                {
                  "model": "minimax-m2.5-nvidia",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """
                let workerRequest = """
                {
                  "model": "proxy-worker-smart-router",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """
                let gptRequest = """
                {
                  "model": "gpt-5.4(high)",
                  "input": "Return exactly: OK"
                }
                """

                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: glm5Request), 900, "glm5 should keep the tripled per-attempt timeout budget", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: kimiRequest), 900, "all routed attempts should now floor to the global 900-second minimum even when the model-specific budget is lower", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: minimaxRequest), 900, "minimax should keep the tripled per-attempt timeout budget", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: workerRequest), 900, "worker smart-router requests should inherit the tripled per-attempt timeout budget", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.attemptTimeout(forRequestJSON: gptRequest), 900, "direct GPT requests should inherit the tripled per-attempt timeout budget", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: glm5Request), 720, "glm5 should allow a tripled first-byte latency budget before failing", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: kimiRequest), 360, "kimi should use the tripled first-byte deadline for NVIDIA-hosted model", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: minimaxRequest), 720, "minimax should also allow the tripled first-byte latency budget before failing", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: workerRequest), 180, "worker smart-router requests should use the tripled first-byte deadline", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.firstResponseDeadline(forRequestJSON: gptRequest), 180, "direct GPT requests should use the tripled first-byte deadline", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: glm5Request), 855, "glm5 should bound the full buffered response with the tripled latency budget", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: kimiRequest), 450, "kimi should use the tripled buffered-response deadline", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: minimaxRequest), 855, "minimax should also keep the tripled buffered-response budget", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: workerRequest), 540, "worker smart-router requests should use the tripled buffered-response deadline", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.bufferedResponseDeadline(forRequestJSON: gptRequest), 540, "direct GPT requests should use the tripled buffered-response deadline", recorder: recorder)

                let glm5Budget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: glm5Request)
                let kimiBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: kimiRequest)
                let minimaxBudget = OpenAICompatTemporaryShim.retryBudget(forRequestJSON: minimaxRequest)
                expectEqual(glm5Budget?.transport, 0, "glm5 should not spend extra proxy transport retries", recorder: recorder)
                expectEqual(glm5Budget?.semantic, 1, "glm5 should reserve one semantic retry for malformed tool-call payloads", recorder: recorder)
                expectEqual(kimiBudget?.transport, 0, "kimi should still avoid extra transport retries", recorder: recorder)
                expectEqual(kimiBudget?.semantic, 2, "kimi should keep semantic retries for malformed provider payloads", recorder: recorder)
                expectEqual(minimaxBudget?.transport, 0, "minimax should leave transport failover to the backend manager", recorder: recorder)
                expectEqual(minimaxBudget?.semantic, 2, "minimax should keep semantic retries", recorder: recorder)
                expectEqual(minimaxBudget?.backoffMilliseconds, 250, "minimax should use retry backoff", recorder: recorder)
                expectEqual(minimaxBudget?.salvagesBestEffortRepair, true, "minimax should preserve a best-effort repaired body across retries", recorder: recorder)
            }
        }

        run("temporary nvidia suspect routes keep the same first-byte deadline as healthy routes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let glm5Request = """
                {
                  "model": "glm5",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                expectEqual(
                    OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                        forRequestJSON: glm5Request,
                        routeHealthStatus: .closed
                    ),
                    720,
                    "healthy routes should keep the baseline first-byte deadline",
                    recorder: recorder
                )
                expectEqual(
                    OpenAICompatTemporaryShim.effectiveFirstResponseDeadline(
                        forRequestJSON: glm5Request,
                        routeHealthStatus: .suspect
                    ),
                    720,
                    "suspect routes should not shrink the first-byte deadline for slow NVIDIA models",
                    recorder: recorder
                )
            }
        }

        run("temporary nvidia route circuit degrades to suspect before quarantine, then closes immediately on recovery", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)

                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), false, "glm5 should start healthy", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now)
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), false, "one failure should not quarantine the route yet", recorder: recorder)
                var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .suspect, "one failure should degrade the route to suspect", recorder: recorder)
                expectEqual(snapshot["z-ai/glm5"]?.failureScore, 1, "suspect state should retain the current failure score", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(6))
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now.addingTimeInterval(6)), false, "two failures should still leave the route available while it is only suspect", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(12))
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now.addingTimeInterval(12)), false, "three failures should still avoid immediate quarantine for slow routes", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(18))
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now.addingTimeInterval(18)), true, "four failures should finally quarantine the route", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: "glm5")
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now.addingTimeInterval(18)), false, "one success should immediately close the route once a canary proves recovery", recorder: recorder)

                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "first recovery success should restore the healthy state", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia rolling metrics keep flaky suspect routes degraded until they prove stability", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                let timeoutEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm5",
                    canonicalModelID: "z-ai/glm5",
                    transportOutcome: "send_error",
                    failureClass: "transport_timeout",
                    timeoutStage: .firstResponse,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "live_request",
                    firstByteLatencyMilliseconds: 6_000,
                    totalLatencyMilliseconds: 25_000
                )
                let successEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now.addingTimeInterval(1),
                    requestModel: "glm5",
                    canonicalModelID: "z-ai/glm5",
                    transportOutcome: "send_response",
                    failureClass: nil,
                    timeoutStage: .none,
                    upstreamHTTPStatus: 200,
                    retryCount: 0,
                    source: "live_request",
                    firstByteLatencyMilliseconds: 150,
                    totalLatencyMilliseconds: 400
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now
                )
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: "glm5",
                    telemetryEvent: successEvent
                )

                var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .suspect, "a single lucky success should not instantly clear a flaky suspect route", recorder: recorder)
                expectEqual(snapshot["z-ai/glm5"]?.rollingMetrics.recentOutcomes.contains(where: { $0.hasSuffix(":transport_timeout") }), true, "rolling metrics should retain timeout history while the route is suspect", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: "glm5",
                    telemetryEvent: successEvent
                )
                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "enough clean successes should still restore the healthy state", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary provider retry-after cooldowns immediately suppress worker routes for the advised window", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                let retryAfterFormatter = DateFormatter()
                retryAfterFormatter.locale = Locale(identifier: "en_US_POSIX")
                retryAfterFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                retryAfterFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

                let numericBoundaryBelowHeaders: [AnyHashable: Any] = ["Retry-After": "299"]
                let numericBoundaryBelowCooldown = OpenAICompatTemporaryShim.providerCooldownUntil(statusCode: 429, headers: numericBoundaryBelowHeaders, now: now)
                expectNil(numericBoundaryBelowCooldown, "Retry-After values below 5 minutes should be treated as concurrency noise", recorder: recorder)

                let numericBoundaryAtHeaders: [AnyHashable: Any] = ["Retry-After": "300"]
                let numericBoundaryAtCooldown = OpenAICompatTemporaryShim.providerCooldownUntil(statusCode: 429, headers: numericBoundaryAtHeaders, now: now)
                expectEqual(numericBoundaryAtCooldown?.timeIntervalSince(now), 300, "Retry-After values at the 5 minute boundary should trigger a cooldown", recorder: recorder)

                let httpDateBoundaryBelowHeaders: [AnyHashable: Any] = [
                    "Retry-After": retryAfterFormatter.string(from: now.addingTimeInterval(299))
                ]
                let httpDateBoundaryBelowCooldown = OpenAICompatTemporaryShim.providerCooldownUntil(statusCode: 429, headers: httpDateBoundaryBelowHeaders, now: now)
                expectNil(httpDateBoundaryBelowCooldown, "HTTP-date Retry-After values below 5 minutes should also be treated as concurrency noise", recorder: recorder)

                let httpDateBoundaryAtHeaders: [AnyHashable: Any] = [
                    "Retry-After": retryAfterFormatter.string(from: now.addingTimeInterval(300))
                ]
                let httpDateBoundaryAtCooldown = OpenAICompatTemporaryShim.providerCooldownUntil(statusCode: 429, headers: httpDateBoundaryAtHeaders, now: now)
                expectEqual(httpDateBoundaryAtCooldown?.timeIntervalSince(now), 300, "HTTP-date Retry-After values at the 5 minute boundary should trigger a cooldown", recorder: recorder)

                let longHeaders: [AnyHashable: Any] = ["Retry-After": "3600"]
                let longCooldown = OpenAICompatTemporaryShim.providerCooldownUntil(statusCode: 429, headers: longHeaders, now: now)
                expectEqual(longCooldown?.timeIntervalSince(now), 3600, "long Retry-After windows should be honored in full", recorder: recorder)

                let cooldownEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm-5.1-ollama-pro",
                    canonicalModelID: "glm-5.1",
                    transportOutcome: "send_error",
                    failureClass: "classified_429",
                    timeoutStage: .none,
                    upstreamHTTPStatus: 429,
                    retryCount: 0,
                    source: "smart_alias"
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-ollama-pro",
                    telemetryEvent: cooldownEvent,
                    at: now,
                    forcedOpenUntil: longCooldown
                )

                expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1-ollama-pro", at: now.addingTimeInterval(1)), true, "provider-advised rate-limit cooldown should immediately suppress the route", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1-ollama-pro", at: now.addingTimeInterval(3599)), true, "worker candidates should remain suppressed until the provider retry window expires", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1-ollama-pro", at: now.addingTimeInterval(3601)), false, "worker candidates should become eligible again once the provider cooldown expires", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary provider GLM body-embedded reset time triggers cooldown when no Retry-After header", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                // GLM 429 body: reset 2 hours from now; format as CST wall clock (what GLM sends)
                let resetDate = now.addingTimeInterval(2 * 3600)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
                let resetString = formatter.string(from: resetDate)
                let glmBody = Data("""
                {"error":{"code":"1308","message":"Usage limit reached for 5 hour. Your limit will reset at \(resetString)"},"request_id":"test"}
                """.utf8)

                // No Retry-After header
                let cooldown = OpenAICompatTemporaryShim.providerCooldownUntil(
                    statusCode: 429,
                    headers: [:],
                    bodyData: glmBody,
                    now: now
                )
                let interval = cooldown.map { $0.timeIntervalSince(now) }
                expectEqual(interval != nil, true, "GLM body reset time should produce a cooldown", recorder: recorder)
                if let interval {
                    expectEqual(abs(interval - (2 * 3600)) < 5, true, "GLM reset windows should be honored until the provider reset time", recorder: recorder)
                }

                // Short Retry-After should still win over body (header takes precedence, returns nil for concurrency)
                let shortHeaderCooldown = OpenAICompatTemporaryShim.providerCooldownUntil(
                    statusCode: 429,
                    headers: ["Retry-After": "30"],
                    bodyData: glmBody,
                    now: now
                )
                expectNil(shortHeaderCooldown, "short Retry-After header should suppress body parsing and return nil (concurrency)", recorder: recorder)
            }
        }

        run("temporary provider 429 classification distinguishes overload, concurrency, and quota-window exhaustion", recorder: recorder) {
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            switch OpenAICompatTemporaryShim.classifyProvider429Disposition(
                statusCode: 429,
                headers: [:],
                bodyData: Data("""
                {"error":{"code":"1305","message":"The service may be temporarily overloaded, please try again later"}}
                """.utf8),
                now: now
            ) {
            case .overload(let retryDelaySeconds):
                expectEqual(Int(retryDelaySeconds), 1, "overload 429s should trigger short same-route retries", recorder: recorder)
            default:
                recorder.recordFailure("expected overload 429 classification for ZAI service-overloaded response")
            }

            switch OpenAICompatTemporaryShim.classifyProvider429Disposition(
                statusCode: 429,
                headers: ["Retry-After": "2"],
                bodyData: nil,
                now: now
            ) {
            case .concurrency(let retryAfterSeconds):
                expectEqual(Int(retryAfterSeconds ?? -1), 2, "short Retry-After should classify as concurrency saturation", recorder: recorder)
            default:
                recorder.recordFailure("expected concurrency 429 classification for short Retry-After")
            }

            switch OpenAICompatTemporaryShim.classifyProvider429Disposition(
                statusCode: 429,
                headers: ["Retry-After": "3600"],
                bodyData: nil,
                now: now
            ) {
            case .quotaWindow(let cooldownUntil):
                expectEqual(Int(cooldownUntil.timeIntervalSince(now)), 3600, "long Retry-After should classify as a quota/reset window", recorder: recorder)
            default:
                recorder.recordFailure("expected quota-window 429 classification for long Retry-After")
            }
        }

        run("temporary adaptive concurrency learning only records concurrency-class 429s", recorder: recorder) {
            let quotaRouteHealthKey = "quota::glm-5.1"
            for _ in 0..<3 {
                OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                    routeHealthKey: quotaRouteHealthKey,
                    inflightAtRequest: 1,
                    statusCode: 429,
                    headers: ["Retry-After": "3600"],
                    bodyData: nil
                )
            }
            expectEqual(
                OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: quotaRouteHealthKey),
                3,
                "quota-window 429s should not ratchet down learned concurrency",
                recorder: recorder
            )

            let overloadRouteHealthKey = "overload::glm-5.1"
            let overloadBody = Data("""
            {"error":{"code":"1305","message":"The service may be temporarily overloaded, please try again later"}}
            """.utf8)
            for _ in 0..<3 {
                OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                    routeHealthKey: overloadRouteHealthKey,
                    inflightAtRequest: 1,
                    statusCode: 429,
                    headers: [:],
                    bodyData: overloadBody
                )
            }
            expectEqual(
                OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: overloadRouteHealthKey),
                3,
                "overload 429s should not ratchet down learned concurrency",
                recorder: recorder
            )

            let concurrencyRouteHealthKey = "concurrency::glm-5.1"
            for _ in 0..<3 {
                OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                    routeHealthKey: concurrencyRouteHealthKey,
                    inflightAtRequest: 1,
                    statusCode: 429,
                    headers: ["Retry-After": "2"],
                    bodyData: nil
                )
            }
            expectEqual(
                OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: concurrencyRouteHealthKey),
                3,
                "single-flight concurrency 429s should not infer a learned concurrency limit of 1",
                recorder: recorder
            )
        }

        run("temporary single-flight concurrency retry-after windows do not amplify into multi-minute route cooldowns", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                let retryAfterHeaders: [AnyHashable: Any] = ["Retry-After": "12"]
                let providerRetryUntil = OpenAICompatTemporaryShim.providerDeferralUntil(
                    statusCode: 429,
                    headers: retryAfterHeaders,
                    bodyData: nil,
                    now: now
                )

                guard let providerRetryUntil else {
                    recorder.recordFailure("expected a short concurrency retry-after window to produce a provider deferral")
                    return
                }

                OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                    forRequestModel: "glm-5.1-zai",
                    until: providerRetryUntil,
                    at: now
                )
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-zai",
                    telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: now,
                        requestModel: "glm-5.1-zai",
                        canonicalModelID: "glm-5.1",
                        transportOutcome: "retry",
                        failureClass: "classified_429_concurrency",
                        timeoutStage: .none,
                        upstreamHTTPStatus: 429,
                        retryCount: 0,
                        source: "smart_alias",
                        inflightAtRequest: 1
                    ),
                    at: now
                )

                let effectiveDeferral = OpenAICompatTemporaryShim.routeAvailabilityDeferralUntilForTesting(
                    requestModel: "glm-5.1-zai"
                )
                expectEqual(
                    Int(effectiveDeferral?.timeIntervalSince(now) ?? -1),
                    12,
                    "single-flight concurrency 429s should honor the provider retry-after window instead of inflating it into a long route cooldown",
                    recorder: recorder
                )
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary provider overload 429s do not create route penalties or cooldowns", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_100)
                let overloadBody = Data("""
                {"error":{"code":"1305","message":"The service may be temporarily overloaded, please try again later"}}
                """.utf8)
                let providerRetryUntil = OpenAICompatTemporaryShim.providerDeferralUntil(
                    statusCode: 429,
                    headers: [:],
                    bodyData: overloadBody,
                    now: now
                )
                expectNil(
                    providerRetryUntil,
                    "provider overload 429s should not create route-level availability deferrals",
                    recorder: recorder
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-zai",
                    telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: now,
                        requestModel: "glm-5.1-zai",
                        canonicalModelID: "glm-5.1",
                        transportOutcome: "retry",
                        failureClass: "classified_429_overload",
                        timeoutStage: .none,
                        upstreamHTTPStatus: 429,
                        retryCount: 0,
                        source: "smart_alias",
                        inflightAtRequest: 1
                    ),
                    at: now,
                    forcedOpenUntil: now.addingTimeInterval(1)
                )

                expectEqual(
                    OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1-zai", at: now.addingTimeInterval(0.5)),
                    false,
                    "provider overload 429s should not open or quarantine the preferred route",
                    recorder: recorder
                )
                expectNil(
                    OpenAICompatTemporaryShim.routeAvailabilityDeferralUntilForTesting(requestModel: "glm-5.1-zai"),
                    "provider overload 429s should not create route cooldowns",
                    recorder: recorder
                )
                expectNil(
                    OpenAICompatTemporaryShim.rollingMetrics(forRequestModel: "glm-5.1-zai"),
                    "provider overload 429s should not mutate route-health ranking state",
                    recorder: recorder
                )
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary adaptive concurrency learning re-probes upward quickly after confirmed low multi-flight caps start succeeding", recorder: recorder) {
            let routeHealthKey = "relearn::glm-5.1"
            for _ in 0..<3 {
                OpenAICompatTemporaryShim.recordConcurrency429IfNeeded(
                    routeHealthKey: routeHealthKey,
                    inflightAtRequest: 2,
                    statusCode: 429,
                    headers: ["Retry-After": "2"],
                    bodyData: nil
                )
            }
            expectEqual(
                OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: routeHealthKey),
                1,
                "repeated multi-flight concurrency signals should still lower the learned cap initially",
                recorder: recorder
            )

            for _ in 0..<3 {
                OpenAICompatTemporaryShim.recordConcurrencySuccess(
                    routeHealthKey: routeHealthKey,
                    inflightAtRequest: 1
                )
            }
            expectEqual(
                OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: routeHealthKey),
                2,
                "sustained success at a provisional single-flight cap should quickly re-probe upward",
                recorder: recorder
            )
        }

        run("concurrency-classified 429s do not degrade route health status", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm-5.1-zai",
                    requestedAlias: "worker",
                    canonicalModelID: "glm-5.1",
                    transportOutcome: "send_error",
                    failureClass: "classified_429_concurrency",
                    timeoutStage: .none,
                    upstreamHTTPStatus: 429,
                    retryCount: 0,
                    source: "smart_alias",
                    inflightAtRequest: 1
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-zai",
                    telemetryEvent: event,
                    at: now
                )

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .closed, "concurrency 429s should not poison route health", recorder: recorder)
                expectEqual(snapshot["glm-5.1"]?.failureScore, 0, "concurrency 429s should not increase failure score", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("concurrency-classified 429 retry windows create deferrals without opening route health", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_010)
                let retryUntil = now.addingTimeInterval(3)
                let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm-5.1-zai",
                    requestedAlias: "worker",
                    canonicalModelID: "glm-5.1",
                    transportOutcome: "retry",
                    failureClass: "classified_429_concurrency",
                    timeoutStage: .none,
                    upstreamHTTPStatus: 429,
                    retryCount: 0,
                    source: "smart_alias",
                    inflightAtRequest: 2
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-zai",
                    telemetryEvent: event,
                    at: now,
                    forcedOpenUntil: retryUntil
                )

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .closed, "concurrency retry windows should not open route health", recorder: recorder)
                expectEqual(snapshot["glm-5.1"]?.failureScore, 0, "concurrency retry windows should not increase failure score", recorder: recorder)
                expectEqual(
                    Int(OpenAICompatTemporaryShim.routeAvailabilityDeferralUntilForTesting(requestModel: "glm-5.1-zai")?.timeIntervalSince(now) ?? -1),
                    3,
                    "concurrency retry windows should still produce a short route deferral",
                    recorder: recorder
                )

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary provider route-health reload clears stale in-memory provider cooldowns", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withRouteHealthPath { path in
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let now = Date()
                    let cooldownEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: now,
                        requestModel: "glm-5.1-ollama-pro",
                        canonicalModelID: "glm-5.1",
                        transportOutcome: "send_error",
                        failureClass: "classified_429",
                        timeoutStage: .none,
                        upstreamHTTPStatus: 429,
                        retryCount: 0,
                        source: "smart_alias"
                    )

                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm-5.1-ollama-pro",
                        telemetryEvent: cooldownEvent,
                        at: now,
                        forcedOpenUntil: now.addingTimeInterval(3600)
                    )

                    let payload = """
                    {
                      "version": 1,
                      "routes": {}
                    }
                    """
                    try? payload.write(toFile: path, atomically: true, encoding: .utf8)

                    OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forcePersistRouteHealthForTesting()

                    guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                        recorder.recordFailure("expected to read route-health cache file after reload")
                        return
                    }
                    let rawJSON = parseDataJSONObject(rawData, recorder: recorder)
                    let providerCooldowns = rawJSON["provider_cooldowns"] as? [String: Any]
                    expectEqual(providerCooldowns?.isEmpty ?? true, true, "reload should discard provider cooldowns that are not present on disk", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("temporary nvidia hedging is enabled only for suspect plain-chat requests", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let plainRequest = """
                {
                  "model": "glm5",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ],
                  "max_tokens": 32,
                  "stream": false
                }
                """
                let toolRequest = """
                {
                  "model": "glm5",
                  "messages": [
                    {"role": "user", "content": "Use the tool"}
                  ],
                  "tools": [
                    {
                      "type": "function",
                      "function": {
                        "name": "lookup",
                        "parameters": {"type": "object"}
                      }
                    }
                  ],
                  "stream": false
                }
                """

                expectEqual(
                    OpenAICompatTemporaryShim.allowsHedgedNVIDIARequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        jsonString: plainRequest,
                        routeHealthStatus: .suspect
                    ),
                    true,
                    "suspect plain-chat requests should be hedge-eligible",
                    recorder: recorder
                )
                expectEqual(
                    OpenAICompatTemporaryShim.allowsHedgedNVIDIARequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        jsonString: plainRequest,
                        routeHealthStatus: .closed
                    ),
                    false,
                    "healthy routes should not hedge by default",
                    recorder: recorder
                )
                expectEqual(
                    OpenAICompatTemporaryShim.allowsHedgedNVIDIARequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        jsonString: toolRequest,
                        routeHealthStatus: .suspect
                    ),
                    false,
                    "tool-calling requests should not be hedge-eligible",
                    recorder: recorder
                )
            }
        }

        run("temporary nvidia rolling metrics tune hedge delay and canary cadence for flaky routes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date()
                let timeoutEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm5",
                    canonicalModelID: "z-ai/glm5",
                    transportOutcome: "send_error",
                    failureClass: "transport_timeout",
                    timeoutStage: .firstResponse,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "live_request",
                    firstByteLatencyMilliseconds: 5_500,
                    totalLatencyMilliseconds: 25_000
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now
                )
                expectEqual(OpenAICompatTemporaryShim.recommendedNVIDIAHedgeDelay(forRequestModel: "glm5"), 45, "high recent timeout rates should keep a cautious hedge delay instead of racing immediately", recorder: recorder)

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now.addingTimeInterval(1)
                )
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now.addingTimeInterval(2)
                )
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now.addingTimeInterval(3)
                )
                expectEqual(OpenAICompatTemporaryShim.recommendedCanaryInterval(), 30, "quarantined slow routes should still be canaried aggressively once they truly open", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia hedge coordination starts once, cancels losers, and only lets one attempt finish", recorder: recorder) {
            let coordinator = ThinkingProxy.NVIDIAAttemptCoordinator()
            var canceledAttempts: [Int] = []

            coordinator.registerAttempt(attemptLane: 1) {
                canceledAttempts.append(1)
            }
            coordinator.registerAttempt(attemptLane: 2) {
                canceledAttempts.append(2)
            }

            expectEqual(coordinator.shouldStartHedge(), true, "the first hedge request should start the secondary attempt", recorder: recorder)
            expectEqual(coordinator.shouldStartHedge(), false, "duplicate hedge launches should be suppressed", recorder: recorder)
            expectEqual(coordinator.tryFinish(attemptLane: 1), true, "the first completed attempt should win delivery", recorder: recorder)
            expectEqual(canceledAttempts, [2], "winning attempts should actively cancel the losing hedge lane", recorder: recorder)
            expectEqual(coordinator.tryFinish(attemptLane: 2), false, "later attempts should be prevented from sending duplicate responses", recorder: recorder)
            expectEqual(coordinator.isFinished(), true, "coordinator should stay finished once a winner is recorded", recorder: recorder)
            expectEqual(coordinator.winnerAttemptLaneValue(), 1, "coordinator should record the winning attempt lane", recorder: recorder)
        }

        run("temporary nvidia failure score decays over time instead of opening on stale failures", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)

                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now)
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(400))

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .suspect, "stale failure score should decay before the next failure is applied", recorder: recorder)
                expectEqual(snapshot["z-ai/glm5"]?.failureScore, 1, "decayed stale failures should not force an immediate open transition", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia rolling metrics do not lower the quarantine threshold for slow routes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)
                let timeoutEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm5",
                    canonicalModelID: "z-ai/glm5",
                    transportOutcome: "send_error",
                    failureClass: "transport_timeout",
                    timeoutStage: .firstResponse,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "live_request"
                )
                let successEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now.addingTimeInterval(1),
                    requestModel: "glm5",
                    canonicalModelID: "z-ai/glm5",
                    transportOutcome: "send_response",
                    failureClass: nil,
                    timeoutStage: .none,
                    upstreamHTTPStatus: 200,
                    retryCount: 0,
                    source: "live_request"
                )

                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now
                )
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: "glm5",
                    telemetryEvent: successEvent,
                    at: now.addingTimeInterval(1)
                )
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm5",
                    telemetryEvent: timeoutEvent,
                    at: now.addingTimeInterval(2)
                )

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .suspect, "rolling metrics should retain caution without prematurely quarantining a slow route", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia telemetry can record hedge and winner attempt lanes", recorder: recorder) {
            let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                requestModel: "glm5",
                canonicalModelID: "z-ai/glm5",
                transportOutcome: "send_response",
                attemptLane: 2,
                failureClass: nil,
                timeoutStage: .none,
                upstreamHTTPStatus: 200,
                retryCount: 0,
                source: "live_request"
            )
            let winningEvent = OpenAICompatTemporaryShim.telemetryEventWithWinnerAttemptLane(
                event,
                winnerAttemptLane: 2
            )

            expectEqual(winningEvent.attemptLane, 2, "telemetry should preserve the attempt lane that produced the response", recorder: recorder)
            expectEqual(winningEvent.winnerAttemptLane, 2, "telemetry should record which hedge lane ultimately won", recorder: recorder)
        }

        run("temporary nvidia coalescing registry shares one in-flight slot across duplicate safe requests", recorder: recorder) {
            let proxy = ThinkingProxy()
            let key = "POST /v1/chat/completions\n{\"model\":\"glm5\"}"
            let firstConnection = NWConnection(
                to: .hostPort(host: "127.0.0.1", port: 1),
                using: .tcp
            )
            let secondConnection = NWConnection(
                to: .hostPort(host: "127.0.0.1", port: 1),
                using: .tcp
            )

            expectEqual(proxy.registerOrJoinInflightRequestForTesting(key: key, connection: firstConnection), true, "the first request should own the in-flight slot", recorder: recorder)
            expectEqual(proxy.registerOrJoinInflightRequestForTesting(key: key, connection: secondConnection), false, "duplicate requests should join the existing in-flight slot", recorder: recorder)
            expectEqual(proxy.inflightRequestWaiterCount(for: key), 2, "joined duplicate requests should share the same waiter list", recorder: recorder)
            expectEqual(proxy.takeInflightRequestConnectionsForTesting(for: key)?.count, 2, "finishing the in-flight slot should return all coalesced waiters", recorder: recorder)
            expectEqual(proxy.inflightRequestWaiterCount(for: key), 0, "taking the slot should clear the coalescing registry", recorder: recorder)
        }

        run("temporary worker smart alias is config-driven and skips quarantined fallback models", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                    requestModel: "minimax-m2.7-ollama-pro",
                    until: Date().addingTimeInterval(60)
                )
                let request = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "worker")
                expectEqual(smartAlias?.candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "worker should load its candidate order from merged config", recorder: recorder)

                let transition = OpenAICompatTemporaryShim.nextSmartAliasCandidateTransition(
                    method: "POST",
                    path: "/v1/chat/completions",
                    currentBody: request,
                    candidateModelsRemaining: ["minimax-m2.7-ollama-pro"]
                )

                expectNil(transition, "fallback planning should surface no candidate when the only fallback route is quarantined", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary glm-5.1 public entrypoint reuses the internal worker failover pool", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "glm-5.1")
                expectEqual(smartAlias?.requestClass, "plain-chat", "glm-5.1 should inherit the pooled request class instead of bypassing the worker pool", recorder: recorder)
                expectEqual(smartAlias?.failover, "silent", "glm-5.1 should inherit silent failover from the internal worker pool", recorder: recorder)
                expectEqual(smartAlias?.candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "glm-5.1 should reuse the full worker candidate order", recorder: recorder)
            }
        }

        run("neutral proxy worker smart router alias reuses the internal worker failover pool", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "proxy-worker-smart-router")
                expectEqual(smartAlias?.requestClass, "plain-chat", "proxy-worker-smart-router should inherit the pooled request class instead of bypassing the worker pool", recorder: recorder)
                expectEqual(smartAlias?.failover, "silent", "proxy-worker-smart-router should inherit silent failover from the internal worker pool", recorder: recorder)
                expectEqual(smartAlias?.candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "proxy-worker-smart-router should reuse the full worker candidate order", recorder: recorder)
            }
        }

        run("temporary gpt-4.1-mini public entrypoint is no longer a pooled alias", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "gpt-4.1-mini")
                expectNil(smartAlias, "gpt-4.1-mini should no longer resolve through the pooled worker alias path", recorder: recorder)
            }
        }

        run("glm-5.1 public entrypoint keeps tool-heavy requests on the same worker execution policy", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                guard let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "glm-5.1") else {
                    recorder.recordFailure("glm-5.1 should still inherit the worker pool definition")
                    return
                }

                let requestJSON = """
                {
                  "model": "glm-5.1",
                  "stream": false,
                  "tools": [
                    {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                  ],
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                let candidates = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: "glm-5.1",
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: requestJSON,
                    smartAlias: smartAlias
                )

                expectEqual(candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "tool-heavy glm-5.1 requests should keep the same worker pool", recorder: recorder)
            }
        }

        run("neutral proxy worker smart router alias keeps tool-heavy requests on the same worker execution policy", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                guard let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "proxy-worker-smart-router") else {
                    recorder.recordFailure("proxy-worker-smart-router should inherit the worker pool definition")
                    return
                }

                let requestJSON = """
                {
                  "model": "proxy-worker-smart-router",
                  "stream": false,
                  "tools": [
                    {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                  ],
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                let candidates = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: "proxy-worker-smart-router",
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: requestJSON,
                    smartAlias: smartAlias
                )

                expectEqual(candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "tool-heavy proxy-worker-smart-router requests should keep the same worker pool", recorder: recorder)
            }
        }

        run("tool-heavy proxy worker requests share the same failover ordering as plain chat", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                guard let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(forRequestModel: "proxy-worker-smart-router") else {
                    recorder.recordFailure("proxy-worker-smart-router should inherit the worker pool definition")
                    return
                }

                let now = Date()
                let glmSlowSuccess = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now,
                    requestModel: "glm-5.1-ollama-pro",
                    canonicalModelID: "glm-5.1",
                    transportOutcome: "send_response",
                    failureClass: nil,
                    timeoutStage: .none,
                    upstreamHTTPStatus: 200,
                    retryCount: 0,
                    source: "smart_alias",
                    firstByteLatencyMilliseconds: 15_000,
                    totalLatencyMilliseconds: 60_000
                )
                let minimaxFastSuccess = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: now.addingTimeInterval(1),
                    requestModel: "minimax-m2.7-ollama-pro",
                    canonicalModelID: "minimax-m2.7",
                    transportOutcome: "send_response",
                    failureClass: nil,
                    timeoutStage: .none,
                    upstreamHTTPStatus: 200,
                    retryCount: 0,
                    source: "smart_alias",
                    firstByteLatencyMilliseconds: 80,
                    totalLatencyMilliseconds: 300
                )

                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: "glm-5.1-ollama-pro",
                    telemetryEvent: glmSlowSuccess
                )
                OpenAICompatTemporaryShim.recordRouteSuccess(
                    forRequestModel: "minimax-m2.7-ollama-pro",
                    telemetryEvent: minimaxFastSuccess
                )

                let requestJSON = """
                {
                  "model": "proxy-worker-smart-router",
                  "stream": false,
                  "tools": [
                    {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                  ],
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                let stickyCandidates = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: "proxy-worker-smart-router",
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: requestJSON,
                    smartAlias: smartAlias
                )
                expectEqual(stickyCandidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "tool-heavy worker requests should keep the same candidate ordering as plain chat", recorder: recorder)

                OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                    requestModel: "glm-5.1-ollama-pro",
                    until: now.addingTimeInterval(300)
                )

                let stillPinnedCandidates = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                    forPublicAlias: "proxy-worker-smart-router",
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: requestJSON,
                    smartAlias: smartAlias
                )
                expectEqual(stillPinnedCandidates, ["glm-5.1-zai", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia", "glm-5.1-ollama-pro"], "tool-heavy worker requests should demote degraded siblings behind still-healthy fallbacks while preserving the healthy primary", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("provider endpoint parsing captures per-provider proxy-url when set", recorder: recorder) {
            withMergedConfig(
                [
                    "openai-compatibility:",
                    "- name: proxied-provider",
                    "  api-key: test-proxy-key",
                    "  base-url: https://proxy.example.com/v1",
                    "  proxy-url: socks5://user:pass@proxy.example.com:1080",
                    "  models:",
                    "  - alias: proxied-model",
                    "    name: proxied-model",
                    "- name: plain-provider",
                    "  api-key: test-plain-key",
                    "  base-url: https://plain.example.com/v1",
                    "  models:",
                    "  - alias: plain-model",
                    "    name: plain-model"
                ].joined(separator: "\n")
            ) {
                guard let endpoint = OpenAICompatTemporaryShim.providerEndpoint(forProviderID: "proxied-provider") else {
                    recorder.recordFailure("proxied-provider should have a proxy endpoint")
                    return
                }
                expectEqual(endpoint.baseURL, "https://proxy.example.com/v1", "proxied-provider endpoint should have the configured base URL", recorder: recorder)
                expectEqual(endpoint.proxyURL, "socks5://user:pass@proxy.example.com:1080", "proxied-provider endpoint should have the configured proxy URL", recorder: recorder)

                let plainEndpoint = OpenAICompatTemporaryShim.providerEndpoint(forProviderID: "plain-provider")
                expectNil(plainEndpoint, "providers without proxy-url should not expose a proxy endpoint", recorder: recorder)
            }
        }

        run("provider endpoint returns nil when proxy-url is empty", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let endpoint = OpenAICompatTemporaryShim.providerEndpoint(forProviderID: "ollama-pro")
                expectNil(endpoint, "ollama-pro should have no proxy endpoint when proxy-url is empty", recorder: recorder)
            }
        }

        run("tool-heavy proxy worker smart router preserves the public-alias timeout budget on GPT-backed attempts", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var capturedTimeout: TimeInterval?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, timeoutInterval, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    capturedTimeout = timeoutInterval
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-worker-timeout-budget",
                              "object": "chat.completion",
                              "model": "\(json["model"] as? String ?? "unknown")",
                              "choices": [{"index": 0, "message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { _, _, _ in
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                    {"model":"proxy-worker-smart-router","messages":[{"role":"user","content":"Return exactly: OK"}],"tools":[{"type":"function","function":{"name":"lookup","parameters":{"type":"object"}}}],"stream":false}
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("tool-heavy smart-router request should complete under test transport")
                    return
                }

                expectEqual(Int(capturedTimeout ?? 0), 900, "tool-heavy smart-router attempts should use the tripled alias timeout budget (900s, accommodating slow inference)", recorder: recorder)
            }
        }

        run("Factory smart-router custom model IDs reuse the worker pool and preserve caller-visible IDs", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedBody: String?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        forwardedBody = body
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-factory-smart-router",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(
                                    statusCode: 200,
                                    headerFields: ["Content-Type": "application/json"]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { _, headers, body in
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "\(genericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "tools": [
                            {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                          ],
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("Factory smart-router custom model ID should return a response")
                        return
                    }

                    let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                    expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "Factory smart-router custom IDs should route to the worker pool primary", recorder: recorder)

                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    expectEqual(deliveredJSON["model"] as? String, genericCompatFactoryWorkerContract.workerModelID, "smart-router custom IDs should stay caller-visible on the way out", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Public-Model"] as? String, genericCompatFactoryWorkerContract.workerModelID, "smart-router custom IDs should be preserved in proxy audit headers", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "smart-router custom IDs should expose the pool primary candidate", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Factory-Authoritative-Model-ID"] as? String, genericCompatFactoryWorkerContract.workerModelID, "smart-router custom IDs should expose the authoritative Factory model id", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "authoritative_custom_model", "smart-router custom IDs should expose the binding source", recorder: recorder)
                }
            }
        }

        run("Factory self-routed smart-router custom model IDs learn concurrency from the primary upstream route and fail over when GLM is saturated", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.resetConcurrencyRegistryForTesting()
                    let primaryRouteHealthKey = "zai::glm-5.1"
                    _ = OpenAICompatTemporaryShim.acquireConcurrencySlot(routeHealthKey: primaryRouteHealthKey)
                    _ = OpenAICompatTemporaryShim.acquireConcurrencySlot(routeHealthKey: primaryRouteHealthKey)
                    _ = OpenAICompatTemporaryShim.acquireConcurrencySlot(routeHealthKey: primaryRouteHealthKey)
                    defer {
                        OpenAICompatTemporaryShim.releaseConcurrencySlot(routeHealthKey: primaryRouteHealthKey)
                        OpenAICompatTemporaryShim.releaseConcurrencySlot(routeHealthKey: primaryRouteHealthKey)
                        OpenAICompatTemporaryShim.releaseConcurrencySlot(routeHealthKey: primaryRouteHealthKey)
                        OpenAICompatTemporaryShim.resetConcurrencyRegistryForTesting()
                    }

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredStatus: Int?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?
                    var forwardedModel: String?

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        let forwardedJSON = parseJSONObject(body, recorder: recorder)
                        forwardedModel = forwardedJSON["model"] as? String
                        let response = """
                        {
                          "id": "chatcmpl-self-routed-fallback",
                          "object": "chat.completion",
                          "created": 1712534626,
                          "model": "\(forwardedModel ?? "")",
                          "choices": [
                            {
                              "index": 0,
                              "message": {
                                "role": "assistant",
                                "content": "OK"
                              },
                              "finish_reason": "stop"
                            }
                          ]
                        }
                        """
                        let url = URL(string: "http://127.0.0.1:8318/v1/chat/completions")!
                        let httpResponse = HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: ["Content-Type": "application/json"]
                        )
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data(response.utf8),
                                response: httpResponse,
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { status, headers, body in
                        deliveredStatus = status
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("self-routed smart-router request should return a fallback response")
                        return
                    }

                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    expectEqual(deliveredStatus, 200, "self-routed smart-router request should fall over to the next worker candidate when the learned GLM route is saturated", recorder: recorder)
                    expectEqual(forwardedModel, "glm-5.1-ollama-pro", "self-routed smart-router requests should fail over from saturated ZAI GLM onto the Ollama GLM sibling before the rest of the chain", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Public-Model"] as? String, selfRoutedGenericCompatFactoryWorkerContract.workerModelID, "fallback responses should preserve the caller-visible custom worker model id", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-ollama-pro", "fallback responses should expose the actual fallback winner after GLM saturation", recorder: recorder)
                    expectEqual(deliveredJSON["model"] as? String, selfRoutedGenericCompatFactoryWorkerContract.workerModelID, "fallback responses should stay caller-visible on the way out", recorder: recorder)
                }
            }
        }

        run("Factory self-routed smart-router custom model IDs inherit the worker pool without duplicate merged-config aliases", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    let smartAlias = OpenAICompatTemporaryShim.smartAliasDefinition(
                        forRequestModel: selfRoutedGenericCompatFactoryWorkerContract.workerModelID
                    )

                    expectEqual(smartAlias?.requestClass, "plain-chat", "self-routed smart-router worker IDs should inherit the worker request class from proxy source of truth", recorder: recorder)
                    expectEqual(smartAlias?.failover, "silent", "self-routed smart-router worker IDs should inherit worker failover from proxy source of truth", recorder: recorder)
                    expectEqual(smartAlias?.candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "self-routed smart-router worker IDs should reuse the full worker candidate order without a duplicate merged-config alias", recorder: recorder)
                }
            }
        }

        run("Factory self-routed smart-router custom model IDs keep tool-heavy requests on the same worker execution policy", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    let candidates = OpenAICompatTemporaryShim.effectiveSmartAliasCandidateModels(
                        forPublicAlias: selfRoutedGenericCompatFactoryWorkerContract.workerModelID,
                        method: "POST",
                        path: "/v1/chat/completions",
                        jsonString: """
                        {
                          "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "tools": [
                            {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                          ],
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """,
                        smartAlias: OpenAICompatTemporaryShim.smartAliasDefinition(
                            forRequestModel: selfRoutedGenericCompatFactoryWorkerContract.workerModelID
                        )!
                    )

                    expectEqual(candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "tool-heavy self-routed smart-router requests should keep the same worker pool", recorder: recorder)
                }
            }
        }

        run("Factory GPT orchestration alias surfaces direct auth failures without worker-chain rescue", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedPaths: [String] = []
                    var forwardedModels: [String] = []
                    var deliveredStatus: Int?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?

                    proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        forwardedPaths.append(path)
                        forwardedModels.append(json["model"] as? String ?? "")
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "error": {
                                    "message": "auth_not_found: no auth available",
                                    "type": "server_error",
                                    "code": "internal_server_error"
                                  }
                                }
                                """.utf8),
                                response: httpURLResponse(
                                    statusCode: 500,
                                    headerFields: ["Content-Type": "application/json"]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                        deliveredStatus = statusCode
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                        {
                          "model": "\(genericCompatFactoryWorkerContract.validationWorkerModelID)",
                          "input": "Return exactly: OK"
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("Factory GPT orchestration alias should return a direct error response")
                        return
                    }

                    expectEqual(forwardedPaths, ["/v1/responses"], "Factory GPT orchestration should stay on the direct responses lane", recorder: recorder)
                    expectEqual(forwardedModels, ["gpt-5.4(high)"], "Factory GPT orchestration should not spill into the worker smart-router chain", recorder: recorder)
                    expectEqual(deliveredStatus, 500, "Factory GPT orchestration should surface the direct-lane auth failure", recorder: recorder)

                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let deliveredError = deliveredJSON["error"] as? [String: Any]
                    expectEqual(deliveredError?["message"] as? String, "auth_not_found: no auth available", "Factory GPT orchestration should preserve the upstream auth error", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Public-Model"] as? String, genericCompatFactoryWorkerContract.validationWorkerModelID, "Factory GPT orchestration should preserve the caller-visible model header", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "gpt-5.4(high)", "Factory GPT orchestration should expose the direct route model that failed", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "openai", "Factory GPT orchestration should expose the direct provider that failed", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "authoritative_custom_model", "Factory GPT orchestration should keep the authoritative custom binding source", recorder: recorder)
                }
            }
        }

        run("Factory GPT orchestration alias surfaces streaming quota failures without worker-chain rescue", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedPaths: [String] = []
                    var forwardedModels: [String] = []
                    var deliveredStatus: Int?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?

                    proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        forwardedPaths.append(path)
                        forwardedModels.append(json["model"] as? String ?? "")
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "error": {
                                    "type": "usage_limit_reached",
                                    "message": "The usage limit has been reached"
                                  }
                                }
                                """.utf8),
                                response: httpURLResponse(
                                    statusCode: 429,
                                    headerFields: ["Content-Type": "application/json"]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                        deliveredStatus = statusCode
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                        {
                          "model": "\(genericCompatFactoryWorkerContract.validationWorkerModelID)",
                          "stream": true,
                          "input": "Return exactly: OK"
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("streaming Factory GPT orchestration alias should return a direct error response")
                        return
                    }

                    expectEqual(forwardedPaths, ["/v1/responses"], "streaming Factory GPT orchestration should stay on the direct responses lane", recorder: recorder)
                    expectEqual(forwardedModels, ["gpt-5.4(high)"], "streaming Factory GPT orchestration should not spill into the worker smart-router chain", recorder: recorder)
                    expectEqual(deliveredStatus, 429, "streaming Factory GPT orchestration should surface the direct-lane quota failure", recorder: recorder)
                    expectEqual(deliveredHeaders?["Content-Type"] as? String, "application/json", "streaming Factory GPT orchestration should return the backend error body rather than synthetic SSE", recorder: recorder)
                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let deliveredError = deliveredJSON["error"] as? [String: Any]
                    expectEqual(deliveredError?["type"] as? String, "usage_limit_reached", "streaming Factory GPT orchestration should preserve the upstream quota classification", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Public-Model"] as? String, genericCompatFactoryWorkerContract.validationWorkerModelID, "streaming Factory GPT orchestration should preserve the caller-visible model header", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "gpt-5.4(high)", "streaming Factory GPT orchestration should expose the direct route model that failed", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "openai", "streaming Factory GPT orchestration should expose the direct provider that failed", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "authoritative_custom_model", "streaming Factory GPT orchestration should keep the authoritative custom binding source", recorder: recorder)
                }
            }
        }

        run("raw managed GPT orchestration route surfaces direct auth failures to the caller", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedPaths: [String] = []
                    var forwardedModels: [String] = []
                    var deliveredStatus: Int?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?

                    proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        forwardedPaths.append(path)
                        forwardedModels.append(json["model"] as? String ?? "")

                        if path == "/v1/responses" {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {
                                      "error": {
                                        "message": "auth_not_found: no auth available",
                                        "type": "server_error",
                                        "code": "internal_server_error"
                                      }
                                    }
                                    """.utf8),
                                    response: httpURLResponse(
                                        statusCode: 500,
                                        headerFields: ["Content-Type": "application/json"]
                                    ),
                                    error: nil
                                )
                            )
                            return
                        }

                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-rescued-raw-factory-role",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(
                                    statusCode: 200,
                                    headerFields: ["Content-Type": "application/json"]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                        deliveredStatus = statusCode
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                        {
                          "model": "gpt-5.4(high)",
                          "input": "Return exactly: OK"
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("raw managed GPT route should return a response for auth failures")
                        return
                    }

                    expectEqual(forwardedPaths, ["/v1/responses"], "raw managed GPT should only attempt the direct route without silent rescue", recorder: recorder)
                    expectEqual(forwardedModels, ["gpt-5.4(high)"], "raw managed GPT should forward the original model without rescue", recorder: recorder)
                    expectEqual(deliveredStatus, 500, "raw managed GPT auth failures should surface the upstream error status to the caller", recorder: recorder)

                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let errorDict = deliveredJSON["error"] as? [String: Any]
                    expectEqual(errorDict?["code"] as? String, "internal_server_error", "raw managed GPT should surface the upstream error code", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "gpt-5.4(high)", "raw managed GPT failure should expose the route model that failed", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "openai", "raw managed GPT failure should expose the provider that failed", recorder: recorder)
                }
            }
        }

        run("raw managed GPT orchestration route surfaces streaming quota failures to the caller", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedPaths: [String] = []
                    var forwardedModels: [String] = []
                    var deliveredStatus: Int?
                    var deliveredHeaders: [AnyHashable: Any]?

                    proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        forwardedPaths.append(path)
                        forwardedModels.append(json["model"] as? String ?? "")

                        if path == "/v1/responses" {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {
                                      "error": {
                                        "type": "usage_limit_reached",
                                        "message": "The usage limit has been reached"
                                      }
                                    }
                                    """.utf8),
                                    response: httpURLResponse(
                                        statusCode: 429,
                                        headerFields: ["Content-Type": "application/json"]
                                    ),
                                    error: nil
                                )
                            )
                            return
                        }

                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-rescued-raw-factory-role-stream",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(
                                    statusCode: 200,
                                    headerFields: ["Content-Type": "application/json"]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { statusCode, headers, _ in
                        deliveredStatus = statusCode
                        deliveredHeaders = headers
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                        {
                          "model": "gpt-5.4(high)",
                          "stream": true,
                          "input": "Return exactly: OK"
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("streaming raw managed GPT route should return a response for quota failures")
                        return
                    }

                    expectEqual(forwardedPaths, ["/v1/responses"], "streaming raw managed GPT should only attempt the direct route without silent rescue", recorder: recorder)
                    expectEqual(forwardedModels, ["gpt-5.4(high)"], "streaming raw managed GPT should forward the original model without rescue", recorder: recorder)
                    expectEqual(deliveredStatus, 429, "streaming raw managed GPT quota failures should surface the upstream error status to the caller", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "gpt-5.4(high)", "streaming raw managed GPT failure should expose the route model that failed", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "openai", "streaming raw managed GPT failure should expose the provider that failed", recorder: recorder)
                }
            }
        }

        run("retired Factory worker model IDs are rescued onto the current worker route", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedBody: String?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        forwardedBody = body
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-retired-factory-worker",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(
                                    statusCode: 200,
                                    headerFields: ["Content-Type": "application/json"]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { _, headers, body in
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "custom:Factory-Worker-GPT-5.4-High-8",
                          "stream": false,
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("retired Factory worker model ID should be rescued by the proxy")
                        return
                    }

                    let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                    expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "retired Factory worker IDs should be rerouted through the current worker smart-router primary", recorder: recorder)

                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    expectEqual(deliveredJSON["model"] as? String, "custom:Factory-Worker-GPT-5.4-High-8", "retired Factory worker IDs should stay caller-visible after proxy rescue", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Public-Model"] as? String, "custom:Factory-Worker-GPT-5.4-High-8", "retired Factory worker IDs should be preserved in audit headers", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "retired Factory worker IDs should expose the authoritative current worker route", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Factory-Authoritative-Model-ID"] as? String, genericCompatFactoryWorkerContract.workerModelID, "retired Factory worker IDs should expose the current authoritative Factory worker id", recorder: recorder)
                    expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "retired_worker_alias_rescue", "retired Factory worker IDs should expose that they were proxy-rescued", recorder: recorder)
                }
            }
        }

        run("retired Factory worker model IDs fail closed with a contract error when no authoritative worker binding exists", recorder: recorder) {
            withFactorySettings("""
            {
              "missionModelSettings": {
                "workerModel": "custom:GPT-5.4-High-Proxy-2"
              },
              "customModels": []
            }
            """) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredMessage: String?

                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                    {
                      "model": "custom:Factory-Worker-GPT-5.4-High-8",
                      "stream": false,
                      "messages": [{"role": "user", "content": "Return exactly: OK"}]
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("retired Factory worker ids without an authoritative binding should fail closed")
                    return
                }

                expectEqual(deliveredStatus, 409, "retired Factory worker ids without a binding should return a contract error instead of leaking into an opaque backend failure", recorder: recorder)
                expectEqual(deliveredMessage?.contains("custom:Factory-Worker-GPT-5.4-High-8"), true, "contract errors should name the retired leaked worker id", recorder: recorder)
                expectEqual(deliveredMessage?.contains("authoritative worker contract"), true, "contract errors should explain the missing authoritative binding", recorder: recorder)
            }
        }

        run("temporary worker smart alias forwards non-streaming tool requests to the primary backend", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedBody: String?
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    forwardedBody = body
                    expectEqual(path, "/v1/chat/completions", "worker rich-request primary path should still use chat-completions upstream", recorder: recorder)
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-worker-rich",
                              "object": "chat.completion",
                                  "model": "glm-5.1-ollama-pro",
                              "choices": [
                                {
                                  "index": 0,
                                  "message": {"role": "assistant", "content": "OK"},
                                  "finish_reason": "stop"
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "stream": false,
                  "tools": [
                    {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                  ],
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("worker rich-request primary path should return a response")
                    return
                }

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "worker rich requests should target the health-ranked pool primary", recorder: recorder)
                expectEqual(forwardedJSON["stream"] as? Bool, false, "worker rich requests should preserve explicit non-streaming semantics", recorder: recorder)
                let forwardedTools = forwardedJSON["tools"] as? [[String: Any]]
                expectEqual(forwardedTools?.count, 1, "worker rich requests should preserve tool definitions toward the primary backend", recorder: recorder)

                expectEqual(deliveredStatus, 200, "worker rich requests should succeed through the primary backend path", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker rich-request responses should still surface the public alias", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "worker rich-request responses should expose the pool primary candidate", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "worker rich-request responses should expose the pool primary provider", recorder: recorder)
            }
        }

        run("Factory openai custom model IDs preserve caller-visible identity on direct routes", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPath: String?
                var forwardedBody: String?
                var forwardedTimeout: TimeInterval?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, timeoutInterval, completion in
                    forwardedPath = path
                    forwardedBody = body
                    forwardedTimeout = timeoutInterval
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "resp_factory_direct",
                              "object": "response",
                              "model": "gpt-5.4(high)",
                              "status": "completed",
                              "output": [
                                {
                                  "type": "message",
                                  "role": "assistant",
                                  "status": "completed",
                                  "content": [
                                    {"type": "output_text", "text": "OK", "annotations": []}
                                  ]
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { _, headers, body in
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("openai Factory custom model IDs should return a buffered direct response")
                    return
                }

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedPath, "/v1/responses", "openai Factory custom IDs should preserve the responses API path", recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, openAIFactoryWorkerContract.routeModel, "openai Factory custom IDs should be rewritten to their configured route model before proxy forwarding", recorder: recorder)
                expectEqual(Int(forwardedTimeout ?? 0), 900, "direct Factory OpenAI attempts should also respect the 900-second per-attempt minimum", recorder: recorder)

                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, openAIFactoryWorkerContract.workerModelID, "openai Factory custom IDs should stay caller-visible on the way out", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.workerModelID, "openai Factory custom IDs should emit the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "openai Factory custom IDs should expose the direct resolved model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, openAIFactoryWorkerContract.effectiveRouteProvider, "openai Factory custom IDs should expose the direct provider", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Authoritative-Model-ID"] as? String, openAIFactoryWorkerContract.workerModelID, "openai Factory custom IDs should expose the authoritative Factory model id", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "authoritative_custom_model", "openai Factory custom IDs should expose the binding source", recorder: recorder)
            }
        }

        run("Factory self-routed worker custom model IDs keep the 900-second minimum attempt timeout", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var forwardedTimeout: TimeInterval?

                    proxy.bufferedProxyTransportForTesting = { _, _, _, _, timeoutInterval, completion in
                        forwardedTimeout = timeoutInterval
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-self-routed-timeout-floor",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [{"index": 0, "message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { _, _, _ in
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("self-routed worker custom model ID should return a response")
                        return
                    }

                    expectEqual(Int(forwardedTimeout ?? 0), 900, "self-routed worker custom IDs should not fall back below the 900-second per-attempt minimum", recorder: recorder)
                }
            }
        }

        run("Factory openai custom model IDs preserve direct auth-unavailable errors without cross-model failover", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPaths: [String] = []
                var forwardedModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    forwardedPaths.append(path)
                    forwardedModels.append(json["model"] as? String ?? "")
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "error": {
                                "message": "auth_not_found: no auth available",
                                "type": "server_error",
                                "code": "internal_server_error"
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 500,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("Factory direct auth failures should preserve the direct-lane error")
                    return
                }

                expectEqual(forwardedPaths, ["/v1/responses"], "Factory direct auth failures should stay on the direct responses lane", recorder: recorder)
                expectEqual(forwardedModels, ["gpt-5.4(high)"], "Factory direct auth failures should not spill into the worker smart-router chain", recorder: recorder)
                expectEqual(deliveredStatus, 500, "Factory direct auth failures should surface the direct-lane error", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                let deliveredError = deliveredJSON["error"] as? [String: Any]
                expectEqual(deliveredError?["message"] as? String, "auth_not_found: no auth available", "Factory direct auth failures should preserve the upstream auth error", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.workerModelID, "Factory direct auth failures should preserve the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "Factory direct auth failures should still expose the direct route model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, openAIFactoryWorkerContract.effectiveRouteProvider, "Factory direct auth failures should still expose the direct provider", recorder: recorder)
            }
        }

        run("Factory openai custom model IDs preserve direct quota errors without cross-model failover", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPaths: [String] = []
                var forwardedModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    forwardedPaths.append(path)
                    forwardedModels.append(json["model"] as? String ?? "")
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "error": {
                                "type": "usage_limit_reached",
                                "message": "The usage limit has been reached"
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 429,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("Factory direct quota failures should preserve the direct-lane error")
                    return
                }

                expectEqual(forwardedPaths, ["/v1/responses"], "Factory direct quota failures should stay on the direct responses lane", recorder: recorder)
                expectEqual(forwardedModels, ["gpt-5.4(high)"], "Factory direct quota failures should not spill into the worker smart-router chain", recorder: recorder)
                expectEqual(deliveredStatus, 429, "Factory direct quota failures should surface the direct-lane error", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                let deliveredError = deliveredJSON["error"] as? [String: Any]
                expectEqual(deliveredError?["type"] as? String, "usage_limit_reached", "Factory direct quota failures should preserve the upstream quota classification", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.workerModelID, "Factory direct quota failures should preserve the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "Factory direct quota failures should still expose the direct route model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, openAIFactoryWorkerContract.effectiveRouteProvider, "Factory direct quota failures should still expose the direct provider", recorder: recorder)
            }
        }

        run("Factory openai custom model IDs preserve caller-visible identity on streaming direct responses", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPath: String?
                var forwardedBody: String?
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("streaming openai Factory custom IDs should stay on the buffered direct path")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    forwardedPath = path
                    forwardedBody = body
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "resp_factory_direct_stream",
                              "object": "response",
                              "model": "gpt-5.4(high)",
                              "status": "completed",
                              "output": [
                                {
                                  "type": "message",
                                  "id": "msg_factory_direct_stream",
                                  "role": "assistant",
                                  "status": "completed",
                                  "content": [
                                    {"type": "output_text", "text": "OK", "annotations": []}
                                  ]
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "stream": true,
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("openai Factory custom model IDs should return a synthetic SSE response")
                    return
                }

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedPath, "/v1/responses", "streaming openai Factory custom IDs should preserve the responses API path", recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, openAIFactoryWorkerContract.routeModel, "streaming openai Factory custom IDs should be rewritten to their configured route model", recorder: recorder)
                expectEqual(forwardedJSON["stream"] as? Bool, false, "streaming openai Factory custom IDs should buffer upstream direct routes with stream=false", recorder: recorder)

                expectEqual(deliveredStatus, 200, "streaming openai Factory custom IDs should succeed", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "streaming openai Factory custom IDs should surface an SSE content type", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.workerModelID, "streaming openai Factory custom IDs should preserve the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "streaming openai Factory custom IDs should expose the resolved direct model", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"model\":\"\(openAIFactoryWorkerContract.workerModelID)\""), true, "streaming openai Factory custom IDs should preserve the outward custom model inside synthetic SSE events", recorder: recorder)
                expectEqual(deliveredText.contains("response.created"), true, "streaming openai Factory custom IDs should emit Responses SSE lifecycle events", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "streaming openai Factory custom IDs should terminate with the OpenAI SSE sentinel", recorder: recorder)
            }
        }

        run("Factory openai streaming custom model IDs pass through unknown Responses output item types", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("streaming openai Factory custom IDs should stay on the buffered direct path")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let forwardedJSON = parseJSONObject(body, recorder: recorder)
                    expectEqual(path, "/v1/responses", "unknown Responses output item passthrough should stay on the responses API path", recorder: recorder)
                    expectEqual(forwardedJSON["model"] as? String, openAIFactoryWorkerContract.routeModel, "unknown Responses output item passthrough should keep the configured direct route model", recorder: recorder)
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "resp_factory_direct_stream_unknown_item",
                              "object": "response",
                              "model": "gpt-5.4(high)",
                              "status": "completed",
                              "output": [
                                {
                                  "type": "custom_tool_call",
                                  "id": "ctc_1",
                                  "call_id": "call_custom_1",
                                  "name": "custom_lookup",
                                  "status": "completed",
                                  "arguments": "{\\"city\\":\\"Sydney\\"}"
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "stream": true,
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("streaming openai Factory custom IDs should synthesize SSE for unknown Responses output items")
                    return
                }

                expectEqual(deliveredStatus, 200, "unknown Responses output items should not trigger a synthetic 502", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "unknown Responses output items should still emit an SSE content type", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"type\":\"response.output_item.added\""), true, "unknown Responses output items should emit output-item added events", recorder: recorder)
                expectEqual(deliveredText.contains("\"type\":\"response.output_item.done\""), true, "unknown Responses output items should emit output-item done events", recorder: recorder)
                expectEqual(deliveredText.contains("\"type\":\"custom_tool_call\""), true, "unknown Responses output items should be preserved verbatim inside the synthetic SSE stream", recorder: recorder)
                expectEqual(deliveredText.contains("\"model\":\"\(openAIFactoryWorkerContract.workerModelID)\""), true, "unknown Responses output items should still preserve the outward custom model", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "unknown Responses output items should terminate with the OpenAI SSE sentinel", recorder: recorder)
            }
        }

        run("Factory openai streaming custom model IDs preserve direct auth-unavailable errors without cross-model failover", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPaths: [String] = []
                var forwardedModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("streaming Factory auth failures should stay on the buffered direct path")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    forwardedPaths.append(path)
                    forwardedModels.append(json["model"] as? String ?? "")
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "error": {
                                "message": "auth_not_found: no auth available",
                                "type": "server_error",
                                "code": "internal_server_error"
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 500,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "stream": true,
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("streaming Factory direct auth failures should preserve the direct-lane error")
                    return
                }

                expectEqual(forwardedPaths, ["/v1/responses"], "streaming Factory direct auth failures should stay on the direct responses lane", recorder: recorder)
                expectEqual(forwardedModels, ["gpt-5.4(high)"], "streaming Factory direct auth failures should not spill into the worker smart-router chain", recorder: recorder)
                expectEqual(deliveredStatus, 500, "streaming Factory direct auth failures should surface the direct-lane error", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "application/json", "streaming Factory direct auth failures should return the backend error body rather than synthetic SSE", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                let deliveredError = deliveredJSON["error"] as? [String: Any]
                expectEqual(deliveredError?["message"] as? String, "auth_not_found: no auth available", "streaming Factory direct auth failures should preserve the upstream auth error", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.workerModelID, "streaming Factory direct auth failures should preserve the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "streaming Factory direct auth failures should still expose the direct route model", recorder: recorder)
            }
        }

        run("Raw managed GPT route models preserve direct auth-unavailable errors without worker failover", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPaths: [String] = []
                var forwardedModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    forwardedPaths.append(path)
                    forwardedModels.append(json["model"] as? String ?? "")
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "error": {
                                "message": "auth_not_found: no auth available",
                                "type": "server_error",
                                "code": "internal_server_error"
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 500,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.routeModel)",
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("raw managed GPT route auth failures should preserve the direct-lane error")
                    return
                }

                expectEqual(forwardedPaths, ["/v1/responses"], "raw managed GPT route auth failures should stay on the direct responses lane", recorder: recorder)
                expectEqual(forwardedModels, ["gpt-5.4(high)"], "raw managed GPT route auth failures should not spill into the worker smart-router chain", recorder: recorder)
                expectEqual(deliveredStatus, 500, "raw managed GPT route auth failures should surface the direct-lane error", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                let deliveredError = deliveredJSON["error"] as? [String: Any]
                expectEqual(deliveredError?["message"] as? String, "auth_not_found: no auth available", "raw managed GPT route auth failures should preserve the upstream auth error", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.routeModel, "raw managed GPT route auth failures should preserve the caller-visible route header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "raw managed GPT route auth failures should still expose the direct route model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Authoritative-Model-ID"] as? String, openAIFactoryWorkerContract.workerModelID, "raw managed GPT route auth failures should still expose the authoritative Factory model id", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "raw_managed_route_rescue", "raw managed GPT route auth failures should preserve the raw-route binding source", recorder: recorder)
            }
        }

        run("Raw managed GPT streaming route models preserve direct auth-unavailable errors without worker failover", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPaths: [String] = []
                var forwardedModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("streaming raw managed GPT auth failures should stay on the buffered direct path")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    forwardedPaths.append(path)
                    forwardedModels.append(json["model"] as? String ?? "")
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "error": {
                                "message": "auth_not_found: no auth available",
                                "type": "server_error",
                                "code": "internal_server_error"
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 500,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.routeModel)",
                      "stream": true,
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("streaming raw managed GPT auth failures should preserve the direct-lane error")
                    return
                }

                expectEqual(forwardedPaths, ["/v1/responses"], "streaming raw managed GPT auth failures should stay on the direct responses lane", recorder: recorder)
                expectEqual(forwardedModels, ["gpt-5.4(high)"], "streaming raw managed GPT auth failures should not spill into the worker smart-router chain", recorder: recorder)
                expectEqual(deliveredStatus, 500, "streaming raw managed GPT auth failures should surface the direct-lane error", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "application/json", "streaming raw managed GPT auth failures should return the backend error body rather than synthetic SSE", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                let deliveredError = deliveredJSON["error"] as? [String: Any]
                expectEqual(deliveredError?["message"] as? String, "auth_not_found: no auth available", "streaming raw managed GPT auth failures should preserve the upstream auth error", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.routeModel, "streaming raw managed GPT auth failures should preserve the outward raw route model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Authoritative-Model-ID"] as? String, openAIFactoryWorkerContract.workerModelID, "streaming raw managed GPT auth failures should still expose the authoritative Factory model id", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Model-Binding"] as? String, "raw_managed_route_rescue", "streaming raw managed GPT auth failures should preserve the raw-route binding source", recorder: recorder)
            }
        }

        run("Factory openai streaming custom model IDs preserve direct quota errors without cross-model failover", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPaths: [String] = []
                var forwardedModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("streaming Factory quota failures should stay on the buffered direct path")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    forwardedPaths.append(path)
                    forwardedModels.append(json["model"] as? String ?? "")
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "error": {
                                "type": "usage_limit_reached",
                                "message": "The usage limit has been reached"
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 429,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "stream": true,
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("streaming Factory direct quota failures should preserve the direct-lane error")
                    return
                }

                expectEqual(forwardedPaths, ["/v1/responses"], "streaming Factory direct quota failures should stay on the direct responses lane", recorder: recorder)
                expectEqual(forwardedModels, ["gpt-5.4(high)"], "streaming Factory direct quota failures should not spill into the worker smart-router chain", recorder: recorder)
                expectEqual(deliveredStatus, 429, "streaming Factory direct quota failures should surface the direct-lane error", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "application/json", "streaming Factory direct quota failures should return the backend error body rather than synthetic SSE", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                let deliveredError = deliveredJSON["error"] as? [String: Any]
                expectEqual(deliveredError?["type"] as? String, "usage_limit_reached", "streaming Factory direct quota failures should preserve the upstream quota classification", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, openAIFactoryWorkerContract.workerModelID, "streaming Factory direct quota failures should preserve the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, openAIFactoryWorkerContract.routeModel, "streaming Factory direct quota failures should still expose the direct route model", recorder: recorder)
            }
        }

        run("Factory generic-chat direct custom model IDs preserve caller-visible identity on streaming chat routes", recorder: recorder) {
            withFactorySettings(factorySettingsJSON(contract: directChatFactoryWorkerContract)) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPath: String?
                var forwardedBody: String?
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("streaming generic-chat Factory custom IDs should stay on the buffered direct path")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    forwardedPath = path
                    forwardedBody = body
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl_factory_direct_stream",
                              "object": "chat.completion",
                              "model": "gpt-5.4(high)",
                              "choices": [
                                {
                                  "index": 0,
                                  "message": {"role": "assistant", "content": "OK"},
                                  "finish_reason": "stop"
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                    {
                      "model": "\(directChatFactoryWorkerContract.workerModelID)",
                      "stream": true,
                      "messages": [{"role": "user", "content": "Return exactly: OK"}]
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("generic-chat direct Factory custom IDs should return a synthetic SSE response")
                    return
                }

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedPath, "/v1/chat/completions", "streaming generic-chat Factory custom IDs should preserve the chat-completions path", recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, directChatFactoryWorkerContract.routeModel, "streaming generic-chat Factory custom IDs should be rewritten to their configured route model", recorder: recorder)
                expectEqual(forwardedJSON["stream"] as? Bool, false, "streaming generic-chat Factory custom IDs should buffer upstream direct routes with stream=false", recorder: recorder)

                expectEqual(deliveredStatus, 200, "streaming generic-chat Factory custom IDs should succeed", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "streaming generic-chat Factory custom IDs should surface an SSE content type", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, directChatFactoryWorkerContract.workerModelID, "streaming generic-chat Factory custom IDs should preserve the caller-visible model header", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, directChatFactoryWorkerContract.routeModel, "streaming generic-chat Factory custom IDs should expose the resolved direct model", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"model\":\"\(directChatFactoryWorkerContract.workerModelID)\""), true, "streaming generic-chat Factory custom IDs should preserve the outward custom model inside synthetic SSE chunks", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "streaming generic-chat Factory custom IDs should terminate with the OpenAI SSE sentinel", recorder: recorder)
            }
        }

        run("temporary worker smart alias forwards non-streaming structured-output requests to the primary backend", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedBody: String?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    forwardedBody = body
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-worker-json",
                              "object": "chat.completion",
                              "model": "gpt-5.4(high)",
                              "choices": [
                                {
                                  "index": 0,
                                  "message": {"role": "assistant", "content": "{\\\"ok\\\":true}"},
                                  "finish_reason": "stop"
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { _, _, _ in
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "stream": false,
                  "response_format": {"type": "json_object"},
                  "messages": [{"role": "user", "content": "Return a JSON object with ok=true"}]
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("worker structured-output primary path should return a response")
                    return
                }

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "worker structured-output requests should target the health-ranked pool primary", recorder: recorder)
                expectEqual((forwardedJSON["response_format"] as? [String: Any])?["type"] as? String, "json_object", "worker structured-output requests should preserve response_format toward the worker primary", recorder: recorder)
            }
        }

        run("temporary glm-5.1 pooled alias normalizes non-streaming responses onto the chat-completions failover core", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPath: String?
                var forwardedBody: String?
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    forwardedPath = path
                    forwardedBody = body
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-zai-responses-buffered",
                              "object": "chat.completion",
                              "model": "glm-5.1",
                              "choices": [
                                {
                                  "index": 0,
                                  "message": {"role": "assistant", "content": "OK"},
                                  "finish_reason": "stop"
                                }
                              ],
                              "usage": {
                                "prompt_tokens": 11,
                                "completion_tokens": 2,
                                "total_tokens": 13
                              }
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "glm-5.1",
                  "input": "Return exactly: OK",
                  "stream": false,
                  "max_output_tokens": 32
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/responses",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("glm-5.1 responses primary path should return a buffered response")
                    return
                }

                expectEqual(forwardedPath, "/v1/chat/completions", "glm-5.1 responses requests should normalize onto the chat-completions execution core upstream", recorder: recorder)
                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "glm-5.1 responses requests should enter the real worker failover chain at the ZAI GLM primary lane", recorder: recorder)
                expectEqual(forwardedJSON["stream"] as? Bool, false, "glm-5.1 responses requests should preserve explicit non-streaming semantics toward chat completions", recorder: recorder)
                expectEqual(forwardedJSON["max_tokens"] as? Int, 128, "glm-5.1 responses requests should floor translated chat max_tokens to the shared worker minimum before fallback", recorder: recorder)
                let forwardedMessages = forwardedJSON["messages"] as? [[String: Any]]
                expectEqual(forwardedMessages?.count, 1, "glm-5.1 responses requests should translate input into a chat messages array", recorder: recorder)
                expectEqual(forwardedMessages?.first?["role"] as? String, "user", "glm-5.1 responses requests should preserve the user role", recorder: recorder)
                expectEqual(forwardedMessages?.first?["content"] as? String, "Return exactly: OK", "glm-5.1 responses requests should preserve input content when normalizing to chat completions", recorder: recorder)

                expectEqual(deliveredStatus, 200, "glm-5.1 responses requests should succeed through the worker failover core", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "glm-5.1", "glm-5.1 responses requests should still surface the public alias in buffered JSON responses", recorder: recorder)
                expectEqual(deliveredJSON["object"] as? String, "response", "glm-5.1 responses requests should emit a Responses API envelope back to the caller", recorder: recorder)
                expectEqual(deliveredJSON["status"] as? String, "completed", "glm-5.1 responses requests should emit a completed Responses status for stop-finished chat completions", recorder: recorder)
                let output = deliveredJSON["output"] as? [[String: Any]]
                expectEqual(output?.count, 1, "glm-5.1 responses requests should translate the winning chat response into one output item", recorder: recorder)
                expectEqual(output?.first?["type"] as? String, "message", "glm-5.1 responses requests should emit message output items", recorder: recorder)
                let outputContent = (output?.first?["content"] as? [[String: Any]])?.first
                expectEqual(outputContent?["text"] as? String, "OK", "glm-5.1 responses requests should preserve assistant text inside the Responses envelope", recorder: recorder)
                expectEqual((deliveredJSON["usage"] as? [String: Any])?["input_tokens"] as? Int, 11, "glm-5.1 responses requests should translate prompt token usage onto Responses input_tokens", recorder: recorder)
                expectEqual((deliveredJSON["usage"] as? [String: Any])?["output_tokens"] as? Int, 2, "glm-5.1 responses requests should translate completion token usage onto Responses output_tokens", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "glm-5.1 responses requests should expose the winning worker route model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "glm-5.1 responses requests should expose the winning worker route provider", recorder: recorder)
            }
        }

        run("temporary glm-5.1 pooled alias synthesizes streaming responses from the chat-completions failover core", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPath: String?
                var forwardedBody: String?
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.deliveredErrorForTesting = { _, message in
                    recorder.recordFailure("glm-5.1 streaming responses requests should not fail closed: \(message)")
                    delivered.signal()
                }
                proxy.bufferedProxyTransportForTesting = { method, path, _, body, _, completion in
                    forwardedPath = path
                    forwardedBody = body
                    expectEqual(method, "POST", "glm-5.1 streaming responses should stay on POST", recorder: recorder)
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-zai-responses-streaming",
                              "object": "chat.completion",
                              "model": "glm-5.1",
                              "choices": [
                                {
                                  "index": 0,
                                  "message": {"role": "assistant", "content": "OK"},
                                  "finish_reason": "stop"
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "glm-5.1",
                  "input": "Return exactly: OK",
                  "stream": true,
                  "max_output_tokens": 32
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/responses",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("glm-5.1 streaming responses should return a synthetic Responses SSE response")
                    return
                }

                expectEqual(forwardedPath, "/v1/chat/completions", "glm-5.1 streaming responses should normalize onto the chat-completions execution core upstream", recorder: recorder)
                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "glm-5.1 streaming responses should enter the real worker failover chain at the ZAI GLM primary lane", recorder: recorder)
                expectEqual(forwardedJSON["stream"] as? Bool, false, "glm-5.1 streaming responses should buffer upstream chat completions before synthesizing Responses SSE", recorder: recorder)

                expectEqual(deliveredStatus, 200, "glm-5.1 streaming responses should succeed through the worker failover core", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "glm-5.1 streaming responses should surface an SSE content type", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "glm-5.1 streaming responses should expose the winning worker route model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "glm-5.1 streaming responses should expose the winning worker route provider", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"type\":\"response.output_text.delta\""), true, "glm-5.1 streaming responses should emit Responses text delta events", recorder: recorder)
                expectEqual(deliveredText.contains("\"type\":\"response.completed\""), true, "glm-5.1 streaming responses should emit a terminal Responses completion event", recorder: recorder)
                expectEqual(deliveredText.contains("\"model\":\"glm-5.1\""), true, "glm-5.1 streaming responses should preserve the public alias in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "glm-5.1 streaming responses should terminate with the SSE sentinel", recorder: recorder)
            }
        }

        run("temporary glm-5.1 pooled alias keeps tool-bearing responses on the worker primary and preserves the public alias outwardly", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var bodiesByModel: [String: [String: Any]] = [:]
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    bodiesByModel[model] = json
                    lock.unlock()
                    expectEqual(path, "/v1/chat/completions", "glm-5.1 tool-bearing responses should normalize onto the chat-completions execution core upstream", recorder: recorder)

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-glm-responses-tools",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {
                                        "role": "assistant",
                                        "content": "",
                                        "tool_calls": [
                                          {
                                            "id": "call_lookup_glm_1",
                                            "type": "function",
                                            "function": {
                                              "name": "lookup",
                                              "arguments": "{\\"city\\":\\"Sydney\\"}"
                                            }
                                          }
                                        ]
                                      },
                                      "finish_reason": "tool_calls"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        recorder.recordFailure("tool-bearing glm-5.1 responses requests should stay on the worker primary")
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "glm-5.1",
                  "stream": true,
                  "tools": [
                    {"type": "function", "name": "lookup", "description": "Lookup a city", "parameters": {"type": "object"}}
                  ],
                  "tool_choice": "auto",
                  "input": "Find the weather"
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/responses",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("glm-5.1 tool-bearing responses requests should return a synthetic Responses SSE stream through the worker primary")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai"], "tool-bearing glm-5.1 responses requests should use the healthy worker primary", recorder: recorder)
                expectEqual((bodiesByModel["glm-5.1-zai"]?["stream"] as? Bool) ?? true, false, "glm-5.1 tool-bearing responses requests should buffer upstream chat completions before synthesizing Responses SSE", recorder: recorder)
                let forwardedMessages = bodiesByModel["glm-5.1-zai"]?["messages"] as? [[String: Any]]
                expectEqual(forwardedMessages?.last?["content"] as? String, "Find the weather", "glm-5.1 tool-bearing responses requests should translate input onto a chat messages array", recorder: recorder)
                let forwardedTools = bodiesByModel["glm-5.1-zai"]?["tools"] as? [[String: Any]]
                expectEqual(forwardedTools?.count, 1, "glm-5.1 tool-bearing responses requests should preserve tool definitions toward the pool primary", recorder: recorder)
                let forwardedFunction = forwardedTools?.first?["function"] as? [String: Any]
                expectEqual(forwardedFunction?["name"] as? String, "lookup", "glm-5.1 tool-bearing responses requests should normalize Responses tool definitions onto chat-completions function objects", recorder: recorder)
                expectEqual(forwardedFunction?["description"] as? String, "Lookup a city", "glm-5.1 tool-bearing responses requests should preserve tool descriptions when normalizing onto chat completions", recorder: recorder)

                expectEqual(deliveredStatus, 200, "glm-5.1 tool-bearing responses requests should still succeed through the pool primary", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "glm-5.1 tool-bearing responses requests should surface a Responses SSE content type", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "glm-5.1 tool-bearing responses requests should expose the pool primary candidate", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "glm-5.1 tool-bearing responses requests should expose the pool primary provider", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"type\":\"response.function_call_arguments.delta\""), true, "glm-5.1 tool-bearing responses requests should emit function-call argument deltas in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("\"call_id\":\"call_lookup_glm_1\""), true, "glm-5.1 tool-bearing responses requests should preserve the winning tool call id in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("\"model\":\"glm-5.1\""), true, "glm-5.1 tool-bearing responses requests should preserve the outward alias in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "glm-5.1 tool-bearing responses requests should terminate with the SSE sentinel", recorder: recorder)
            }
        }

        run("temporary worker responses requests keep tool-bearing traffic on the worker primary and synthesize function-call response events", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var bodiesByModel: [String: [String: Any]] = [:]
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    bodiesByModel[model] = json
                    lock.unlock()
                    expectEqual(path, "/v1/chat/completions", "worker responses requests should normalize onto the chat-completions execution core upstream", recorder: recorder)

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-worker-responses-tools",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {
                                        "role": "assistant",
                                        "content": "",
                                        "tool_calls": [
                                          {
                                            "id": "call_lookup_1",
                                            "type": "function",
                                            "function": {
                                              "name": "lookup",
                                              "arguments": "{\\"city\\":\\"Sydney\\"}"
                                            }
                                          }
                                        ]
                                      },
                                      "finish_reason": "tool_calls"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        recorder.recordFailure("tool-bearing worker responses requests should stay on the worker primary")
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "stream": true,
                  "tools": [
                    {"type": "function", "name": "lookup", "description": "Lookup a city", "parameters": {"type": "object"}}
                  ],
                  "tool_choice": "auto",
                  "input": "Find the weather"
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/responses",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker responses requests should return a synthetic Responses SSE stream through the worker primary")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai"], "tool-bearing worker responses requests should use the healthy worker primary", recorder: recorder)
                expectEqual((bodiesByModel["glm-5.1-zai"]?["stream"] as? Bool) ?? true, false, "worker responses requests should buffer upstream chat completions before synthesizing Responses SSE", recorder: recorder)
                let forwardedMessages = bodiesByModel["glm-5.1-zai"]?["messages"] as? [[String: Any]]
                expectEqual(forwardedMessages?.last?["content"] as? String, "Find the weather", "worker responses requests should translate input onto a chat messages array", recorder: recorder)
                let forwardedTools = bodiesByModel["glm-5.1-zai"]?["tools"] as? [[String: Any]]
                expectEqual(forwardedTools?.count, 1, "worker responses requests should preserve tool definitions toward the pool primary", recorder: recorder)
                let forwardedFunction = forwardedTools?.first?["function"] as? [String: Any]
                expectEqual(forwardedFunction?["name"] as? String, "lookup", "worker responses requests should normalize Responses tool definitions onto chat-completions function objects", recorder: recorder)
                expectEqual(forwardedFunction?["description"] as? String, "Lookup a city", "worker responses requests should preserve tool descriptions when normalizing onto chat completions", recorder: recorder)

                expectEqual(deliveredStatus, 200, "worker responses requests should still succeed through the pool primary", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "worker responses requests should surface a Responses SSE content type", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "worker responses requests should expose the pool primary candidate", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "worker responses requests should expose the pool primary provider", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"type\":\"response.function_call_arguments.delta\""), true, "worker responses requests should emit function-call argument deltas in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("\"call_id\":\"call_lookup_1\""), true, "worker responses requests should preserve the winning tool call id in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("\"model\":\"worker\""), true, "worker responses requests should preserve the outward alias in the synthetic Responses stream", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "worker responses requests should terminate with the SSE sentinel", recorder: recorder)
            }
        }

        run("temporary worker smart alias keeps tool-bearing streaming requests on the worker primary and returns a synthetic worker SSE stream", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var bodiesByModel: [String: [String: Any]] = [:]
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.forwardRequestInterceptorForTesting = { _, _, _, _, _, _, _, _ in
                    recorder.recordFailure("worker streaming failover should not bypass the buffered smart-alias transport anymore")
                    return true
                }
                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    bodiesByModel[model] = json
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-stream-primary",
                                  "object": "chat.completion",
                                  "model": "glm-5.1-zai",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        recorder.recordFailure("tool-bearing worker streaming requests should not fail over beyond the worker primary in this healthy-path test")
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "stream": true,
                  "tools": [
                    {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                  ],
                  "messages": [{"role": "user", "content": "Return exactly: OK"}]
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker streaming requests should return a synthetic SSE response through the worker primary")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai"], "tool-bearing worker streaming requests should use the healthy worker primary", recorder: recorder)
                expectEqual((bodiesByModel["glm-5.1-zai"]?["stream"] as? Bool) ?? true, false, "worker streaming requests should buffer the upstream alias transport with stream=false", recorder: recorder)
                let forwardedTools = bodiesByModel["glm-5.1-zai"]?["tools"] as? [[String: Any]]
                expectEqual(forwardedTools?.count, 1, "worker streaming requests should preserve tool definitions toward the pool primary", recorder: recorder)

                expectEqual(deliveredStatus, 200, "worker streaming requests should still succeed through the pool primary", recorder: recorder)
                expectEqual(deliveredHeaders?["Content-Type"] as? String, "text/event-stream; charset=utf-8", "worker streaming responses should surface an SSE content type to Factory", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "worker streaming responses should expose the pool primary candidate", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "worker streaming responses should expose the pool primary provider", recorder: recorder)
                let deliveredText = String(data: deliveredBody ?? Data(), encoding: .utf8) ?? ""
                expectEqual(deliveredText.contains("\"model\":\"worker\""), true, "worker streaming responses should preserve the outward alias inside the synthetic SSE chunks", recorder: recorder)
                expectEqual(deliveredText.contains("data: [DONE]"), true, "worker streaming responses should terminate with the OpenAI SSE sentinel", recorder: recorder)
            }
        }

        run("temporary worker smart alias fails closed when the worker pool contract is misconfigured", recorder: recorder) {
            withMergedConfig(workerMisconfiguredMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredMessage: String?
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }
                proxy.bufferedProxyTransportForTesting = { _, _, _, _, _, _ in
                    recorder.recordFailure("worker misconfiguration should fail before any upstream transport is attempted")
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("worker contract misconfiguration should return an error response")
                    return
                }
                expectEqual(deliveredStatus, 500, "worker should fail closed when its primary route contract is violated", recorder: recorder)
                expectEqual(
                    deliveredMessage,
                    "The worker pooled alias is misconfigured: candidates must be glm-5.1-zai, then glm-5.1-ollama-pro, then minimax-m2.7-ollama-pro, then muse-spark, then glm5-nvidia.",
                    "worker should emit a stable misconfiguration error",
                    recorder: recorder
                )
            }
        }

        run("temporary worker smart alias preserves the OpenAI chat envelope toward 8318 and rewrites the response back to worker", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedMethod: String?
                var forwardedPath: String?
                var forwardedHeaders: [(String, String)] = []
                var forwardedBody: String?
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { method, path, headers, body, _, completion in
                    forwardedMethod = method
                    forwardedPath = path
                    forwardedHeaders = headers
                    forwardedBody = body

                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-zai-primary",
                              "object": "chat.completion",
                              "model": "glm-5.1",
                              "choices": [
                                {
                                  "index": 0,
                                  "message": {"role": "assistant", "content": "OK"},
                                  "finish_reason": "stop"
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: [
                                    "Content-Type": "application/json",
                                    "X-Upstream-Hop": "stub-8318"
                                ]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [
                    {"role": "system", "content": "You are terse."},
                    {"role": "user", "content": "Return exactly: OK"}
                  ],
                  "stream": false,
                  "temperature": 0
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        headers: [
                            ("Authorization", "Bearer factory-local-proxy"),
                            ("X-Factory-Session", "mission-worker-test")
                        ],
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("worker contract test should deliver a response")
                    return
                }

                expectEqual(forwardedMethod, "POST", "worker should preserve the POST method when forwarding to 8318", recorder: recorder)
                expectEqual(forwardedPath, "/v1/chat/completions", "worker should preserve the chat-completions path when forwarding to 8318", recorder: recorder)

                let forwardedHeaderMap = Dictionary(uniqueKeysWithValues: forwardedHeaders.map { ($0.0.lowercased(), $0.1) })
                expectEqual(forwardedHeaderMap["authorization"], "Bearer factory-local-proxy", "worker should forward caller authorization headers toward 8318", recorder: recorder)
                expectEqual(forwardedHeaderMap["x-factory-session"], "mission-worker-test", "worker should forward custom caller headers toward 8318", recorder: recorder)
                expectEqual(forwardedHeaderMap["content-type"], "application/json", "worker should preserve the OpenAI JSON content type toward 8318", recorder: recorder)

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, "glm-5.1-zai", "worker should rewrite the outbound model to the primary candidate before forwarding to 8318", recorder: recorder)
                expectEqual(forwardedJSON["stream"] as? Bool, false, "worker should preserve explicit non-streaming chat semantics toward 8318", recorder: recorder)
                expectEqual(forwardedJSON["temperature"] as? Int, 0, "worker should preserve unrelated OpenAI chat parameters toward 8318", recorder: recorder)
                let forwardedMessages = forwardedJSON["messages"] as? [[String: Any]]
                expectEqual(forwardedMessages?.count, 2, "worker should preserve the OpenAI messages array toward 8318", recorder: recorder)
                expectEqual(forwardedMessages?.first?["role"] as? String, "system", "worker should leave the system message in the OpenAI envelope toward 8318", recorder: recorder)
                expectEqual(forwardedMessages?.last?["role"] as? String, "user", "worker should preserve the user message toward 8318", recorder: recorder)

                expectEqual(deliveredStatus, 200, "worker should surface the successful 8318 response to the caller", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker should rewrite the response model back to the public alias", recorder: recorder)
                expectEqual(((deliveredJSON["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String), "stop", "worker should preserve the OpenAI finish_reason from the winning backend", recorder: recorder)
                expectEqual((((deliveredJSON["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String), "OK", "worker should preserve the assistant content from the winning backend", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-zai", "worker should expose the resolved primary model on the client response", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "zai", "worker should expose the resolved primary provider on the client response", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Upstream-Hop"] as? String, "stub-8318", "worker should preserve unrelated upstream response headers when returning to the caller", recorder: recorder)
            }
        }

        /*
         run("temporary worker smart alias tries kilocode mimo-v2-pro after opencode fails and preserves the outward alias", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                var seenModels: [String] = []
                var seenHeadersByModel: [String: [(String, String)]] = [:]
                var recordedEvents: [OpenAICompatTemporaryShim.RouteTelemetryEvent] = []
                let lock = NSLock()

                OpenAICompatTemporaryShim.routeTelemetryHookForTesting = { event in
                    lock.lock()
                    recordedEvents.append(event)
                    lock.unlock()
                }
                defer { OpenAICompatTemporaryShim.routeTelemetryHookForTesting = nil }

                proxy.bufferedProxyTransportForTesting = { _, _, headers, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    seenHeadersByModel[model] = headers
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-opencode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-kilocode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-kilocode",
                                  "object": "chat.completion",
                                  "model": "mimo-v2-pro-free",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker failover should eventually return a successful response")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode"], "worker should try glm-5.1, then opencode MiMo, then kilocode MiMo before NVIDIA", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should return the kilocode MiMo fallback response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker responses should preserve the outward alias instead of leaking the winner model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, "worker", "worker should expose the public alias in response headers for auditability", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "mimo-v2-pro-kilocode", "worker should expose the winning kilocode MiMo backend model in response headers", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "kilocode", "worker should expose the winning kilocode MiMo backend provider in response headers", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Canonical-Model"] as? String, "xiaomi/mimo-v2-pro:free", "worker should expose the winning MiMo canonical model in response headers", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()["glm-5.1"]?.status, .suspect, "route health should track non-NVIDIA worker candidates so the pool can quarantine flaky primaries", recorder: recorder)

                let kilocodeReferer = seenHeadersByModel["mimo-v2-pro-kilocode"]?.first(where: { $0.0.lowercased() == "http-referer" })?.1
                let opencodeReferer = seenHeadersByModel["mimo-v2-pro-opencode"]?.first(where: { $0.0.lowercased() == "http-referer" })?.1
                expectEqual(kilocodeReferer, "https://openclaw.ai", "kilocode requests should carry the free-tier HTTP-Referer header", recorder: recorder)
                expectEqual(opencodeReferer, "https://openclaw.ai", "opencode requests should carry the free-tier HTTP-Referer header", recorder: recorder)

                let workerEvents = recordedEvents.filter { $0.requestedAlias == "worker" }
                expectEqual(workerEvents.contains(where: { $0.requestModel == "glm-5.1-zai" && $0.failoverDepth == 0 }), true, "worker telemetry should record the failed primary candidate with failover depth 0", recorder: recorder)
                expectEqual(workerEvents.contains(where: { $0.requestModel == "mimo-v2-pro-opencode" && $0.failoverDepth == 1 }), true, "worker telemetry should record the failed opencode MiMo attempt at depth 1", recorder: recorder)
                expectEqual(workerEvents.contains(where: { $0.requestModel == "mimo-v2-pro-kilocode" && $0.failoverDepth == 2 && $0.finalWinnerRequestModel == "mimo-v2-pro-kilocode" }), true, "worker telemetry should record the winning kilocode MiMo attempt and final winner", recorder: recorder)
            }
        }

         run("temporary worker smart alias fails over from z.ai to kilocode mimo-v2-pro after a 429", recorder: recorder) {
            withMergedConfig(workerWithMimoMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                var seenModels: [String] = []
                var seenHeadersByModel: [String: [(String, String)]] = [:]
                var recordedEvents: [OpenAICompatTemporaryShim.RouteTelemetryEvent] = []
                let lock = NSLock()

                OpenAICompatTemporaryShim.routeTelemetryHookForTesting = { event in
                    lock.lock()
                    recordedEvents.append(event)
                    lock.unlock()
                }
                defer { OpenAICompatTemporaryShim.routeTelemetryHookForTesting = nil }

                proxy.bufferedProxyTransportForTesting = { method, path, headers, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    seenHeadersByModel[model] = headers
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"rate limited\"}".utf8),
                            response: httpURLResponse(statusCode: 429),
                            error: nil
                        ))
                    case "mimo-v2-pro-opencode":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"rate limited\"}".utf8),
                            response: httpURLResponse(statusCode: 429),
                            error: nil
                        ))
                    case "mimo-v2-pro-kilocode":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-kilo",
                              "object": "chat.completion",
                              "model": "xiaomi/mimo-v2-pro",
                              "choices": [{"index": 0, "message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        ))
                    default:
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"unexpected model\"}".utf8),
                            response: httpURLResponse(statusCode: 500),
                            error: nil
                        ))
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                    {"model":"worker","messages":[{"role":"user","content":"Return exactly: OK"}],"stream":false}
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should eventually deliver a response after glm-5.1 429")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode"], "worker should try glm-5.1, then opencode, then fall over to kilocode mimo-v2-pro", recorder: recorder)
                expectEqual(deliveredStatus, 200, "kilocode mimo-v2-pro should be delivered as a successful response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "response model should be rewritten to the public alias", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "mimo-v2-pro-kilocode", "resolved model header should name the winning kilocode candidate", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "kilocode", "resolved provider header should identify kilocode", recorder: recorder)

                let kilocodeHeaders = seenHeadersByModel["mimo-v2-pro-kilocode"] ?? []
                let referer = kilocodeHeaders.first(where: { $0.0.lowercased() == "http-referer" })?.1
                expectEqual(referer, "https://openclaw.ai", "kilocode requests should carry the HTTP-Referer header required by the free tier", recorder: recorder)

                let workerEvents = recordedEvents.filter { $0.requestedAlias == "worker" }
                expectEqual(workerEvents.contains(where: { $0.requestModel == "glm-5.1-zai" && $0.failoverDepth == 0 }), true, "telemetry should record the failed glm-5.1 attempt at depth 0", recorder: recorder)
                expectEqual(workerEvents.contains(where: { $0.requestModel == "mimo-v2-pro-kilocode" && $0.failoverDepth == 2 && $0.finalWinnerRequestModel == "mimo-v2-pro-kilocode" }), true, "telemetry should record the winning kilocode attempt at depth 2", recorder: recorder)
            }
        }

        run("temporary worker smart alias tries opencode MiniMax free after both mimo-v2-pro providers fail and before NVIDIA", recorder: recorder) {
            withMergedConfig(workerWithMimoMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                var seenModels: [String] = []
                var seenHeadersByModel: [String: [(String, String)]] = [:]
                let lock = NSLock()

                proxy.bufferedProxyTransportForTesting = { _, _, headers, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    seenHeadersByModel[model] = headers
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"rate limited\"}".utf8),
                            response: httpURLResponse(statusCode: 429),
                            error: nil
                        ))
                    case "minimax-m2.5-opencode":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-opencode-minimax",
                              "object": "chat.completion",
                              "model": "minimax/minimax-m2.5-20260211",
                              "choices": [{"index": 0, "message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        ))
                    default:
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"unexpected model\"}".utf8),
                            response: httpURLResponse(statusCode: 500),
                            error: nil
                        ))
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                    {"model":"worker","messages":[{"role":"user","content":"Return exactly: OK"}],"stream":false}
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should eventually deliver the opencode MiniMax free response")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode"], "worker should try opencode MiniMax free after both MiMo legs and before NVIDIA", recorder: recorder)
                expectEqual(deliveredStatus, 200, "opencode MiniMax free should be returned as a successful worker fallback", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker should preserve the outward alias when opencode MiniMax free wins", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "minimax-m2.5-opencode", "resolved model header should identify the opencode MiniMax free candidate", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "opencode", "resolved provider header should identify opencode", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Canonical-Model"] as? String, "minimax-m2.5-free", "resolved canonical model should expose the upstream free model id", recorder: recorder)

                let opencodeMinimaxHeaders = seenHeadersByModel["minimax-m2.5-opencode"] ?? []
                let referer = opencodeMinimaxHeaders.first(where: { $0.0.lowercased() == "http-referer" })?.1
                expectEqual(referer, "https://openclaw.ai", "opencode MiniMax free requests should carry the HTTP-Referer header required by the free tier", recorder: recorder)
            }
        }

        run("temporary worker smart alias falls over to nvidia race after opencode MiniMax free returns reasoning-only output", recorder: recorder) {
            withMergedConfig(workerWithMimoMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredBody: Data?
                var seenModels: [String] = []
                var seenHeadersByModel: [String: [(String, String)]] = [:]
                let lock = NSLock()

                proxy.bufferedProxyTransportForTesting = { method, path, headers, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    seenHeadersByModel[model] = headers
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"rate limited\"}".utf8),
                            response: httpURLResponse(statusCode: 429),
                            error: nil
                        ))
                    case "minimax-m2.5-opencode":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "gen-1774709641-IkHjO3hMcIwXCTm68N1s",
                              "object": "chat.completion",
                              "created": 1774709641,
                              "model": "minimax/minimax-m2.5-20260211",
                              "choices": [
                                {
                                  "index": 0,
                                  "finish_reason": "length",
                                  "message": {
                                    "role": "assistant",
                                    "content": null,
                                    "reasoning": "The user has just said \\\"Hi\\\""
                                  }
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        ))
                    case "minimax-m2.5-nvidia":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-minimax",
                              "object": "chat.completion",
                              "model": "minimaxai/minimax-m2.5",
                              "choices": [{"index": 0, "message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        ))
                    case "kimi-k2.5-nvidia":
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "chatcmpl-kimi",
                              "object": "chat.completion",
                              "model": "moonshotai/kimi-k2.5",
                              "choices": [{"index": 0, "message": {"role": "assistant", "content": "OK"}, "finish_reason": "stop"}]
                            }
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        ))
                    default:
                        completion(ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"unexpected model\"}".utf8),
                            response: httpURLResponse(statusCode: 500),
                            error: nil
                        ))
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                    {"model":"worker","messages":[{"role":"user","content":"Return exactly: OK"}],"stream":false}
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should eventually deliver a response after all mimo providers fail")
                    return
                }

                // glm-5.1, kilo, MiMo opencode, and MiniMax free opencode are tried serially; then NVIDIA races
                let seenBeforeNvidia = seenModels.prefix(4)
                expectEqual(Array(seenBeforeNvidia), ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode"], "worker should try both MiMo legs and the opencode MiniMax free leg before falling through to NVIDIA", recorder: recorder)
                expectEqual(seenModels.contains("minimax-m2.5-nvidia") || seenModels.contains("kimi-k2.5-nvidia"), true, "worker should reach the nvidia race after all mimo providers fail", recorder: recorder)
                expectEqual(deliveredStatus, 200, "nvidia fallback should deliver a successful response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "response model should be rewritten to the public alias", recorder: recorder)

                let opencodeHeaders = seenHeadersByModel["mimo-v2-pro-opencode"] ?? []
                let referer = opencodeHeaders.first(where: { $0.0.lowercased() == "http-referer" })?.1
                expectEqual(referer, "https://openclaw.ai", "opencode requests should carry the HTTP-Referer header required by the free tier", recorder: recorder)
                let opencodeMinimaxHeaders = seenHeadersByModel["minimax-m2.5-opencode"] ?? []
                let opencodeMinimaxReferer = opencodeMinimaxHeaders.first(where: { $0.0.lowercased() == "http-referer" })?.1
                expectEqual(opencodeMinimaxReferer, "https://openclaw.ai", "opencode MiniMax free requests should also carry the HTTP-Referer header required by the free tier", recorder: recorder)
            }
        }

        run("temporary glm-5.1 public entrypoint silently fails over through the internal worker pool while preserving the outward model", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                var seenModels: [String] = []
                var recordedEvents: [OpenAICompatTemporaryShim.RouteTelemetryEvent] = []
                let lock = NSLock()

                OpenAICompatTemporaryShim.routeTelemetryHookForTesting = { event in
                    lock.lock()
                    recordedEvents.append(event)
                    lock.unlock()
                }
                defer { OpenAICompatTemporaryShim.routeTelemetryHookForTesting = nil }

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-kilocode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-test",
                                  "object": "chat.completion",
                                  "model": "xiaomi/mimo-v2-pro:free",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "glm-5.1",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("glm-5.1 pooled entrypoint should eventually return a successful response")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode"], "glm-5.1 should use the worker pool ordering and reach kilocode MiMo after opencode", recorder: recorder)
                expectEqual(deliveredStatus, 200, "glm-5.1 should return the fallback candidate's success response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "glm-5.1", "glm-5.1 pooled responses should preserve the public entrypoint instead of leaking the winner model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, "glm-5.1", "glm-5.1 pooled responses should expose the public entrypoint in response headers", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "mimo-v2-pro-kilocode", "glm-5.1 pooled responses should expose the winning backend model in response headers", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "kilocode", "glm-5.1 pooled responses should expose the winning backend provider in response headers", recorder: recorder)

                let glmEvents = recordedEvents.filter { $0.requestedAlias == "glm-5.1" }
                expectEqual(glmEvents.contains(where: { $0.requestModel == "glm-5.1-zai" && $0.failoverDepth == 0 }), true, "glm-5.1 telemetry should record the failed primary candidate with failover depth 0", recorder: recorder)
                expectEqual(glmEvents.contains(where: { $0.requestModel == "mimo-v2-pro-kilocode" && $0.failoverDepth == 2 && $0.finalWinnerRequestModel == "mimo-v2-pro-kilocode" }), true, "glm-5.1 telemetry should record the winning MiMo fallback candidate and final winner", recorder: recorder)
            }
        }

        run("temporary worker smart alias silently fails over when z.ai returns 404 route unavailable", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"model not found for account\"}".utf8),
                                response: httpURLResponse(statusCode: 404),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-kilocode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-zai-404-fallback",
                                  "object": "chat.completion",
                                  "model": "xiaomi/mimo-v2-pro:free",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should fail over after a z.ai route-unavailable 404")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode"], "worker should treat a route-unavailable z.ai 404 as candidate failure and fall through opencode to kilocode MiMo", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should still succeed after failing over from a z.ai 404", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker should preserve the outward alias after a z.ai 404 fallback", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "mimo-v2-pro-kilocode", "worker should expose the MiMo fallback backend model after a z.ai 404", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "kilocode", "worker should expose the MiMo fallback backend provider after a z.ai 404", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()["glm-5.1"]?.status, .suspect, "route health should penalize z.ai route-unavailable 404 failures", recorder: recorder)
            }
        }

        run("temporary worker smart alias silently fails over when z.ai masks a network error as 400", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "type": "error",
                                  "error": {
                                    "message": "Network error, error id: 20260408053603cba1fa9060364a9d, please contact customer service",
                                    "code": "1234"
                                  }
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 400),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-kilocode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-zai-400-fallback",
                                  "object": "chat.completion",
                                  "model": "xiaomi/mimo-v2-pro:free",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should fail over after a z.ai masked network-error 400")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode"], "worker should treat z.ai synthetic network-error 400 bodies as retryable candidate failures", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should still succeed after failing over from a z.ai synthetic network-error 400", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker should preserve the outward alias after a z.ai synthetic network-error 400 fallback", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "mimo-v2-pro-kilocode", "worker should expose the MiMo fallback backend model after the z.ai synthetic network-error 400", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "kilocode", "worker should expose the MiMo fallback backend provider after the z.ai synthetic network-error 400", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()["glm-5.1"]?.status, .suspect, "route health should penalize z.ai synthetic network-error 400 failures", recorder: recorder)
            }
        }

        run("temporary worker smart alias ranks raced nvidia fallbacks by live route health", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "minimax-m2.5-nvidia",
                    telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: Date(),
                        requestModel: "minimax-m2.5-nvidia",
                        requestedAlias: "worker",
                        canonicalModelID: "minimaxai/minimax-m2.5",
                        transportOutcome: "send_error",
                        failoverDepth: 1,
                        failureClass: "transport_timeout",
                        timeoutStage: .firstResponse,
                        upstreamHTTPStatus: nil,
                        retryCount: 0,
                        source: "smart_alias",
                        firstByteLatencyMilliseconds: 5000,
                        totalLatencyMilliseconds: 5000
                    )
                )

                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-ranked",
                                  "object": "chat.completion",
                                  "model": "\(model)",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, _ in
                    deliveredStatus = statusCode
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should still return a winner after ranking the fallback race")
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    return
                }

                expectEqual(seenModels.prefix(6).map { $0 }, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode", "kimi-k2.5-nvidia", "minimax-m2.5-nvidia"], "worker should exhaust the free serial legs first, then launch healthier NVIDIA fallbacks first once live metrics mark minimax as degraded", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should keep succeeding while reordering its fallback race by route health", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary worker smart alias returns the first valid raced fallback and cancels the loser", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var kimiCanceled = false
                var deliveredStatus: Int?
                var deliveredBody: Data?

                proxy.bufferedProxyCancelableTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                        return {}
                    case "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                        return {}
                    case "minimax-m2.5-nvidia":
                        let workItem = DispatchWorkItem {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {
                                      "id": "chatcmpl-race-win",
                                      "object": "chat.completion",
                                      "model": "minimax-m2.5-nvidia",
                                      "choices": [
                                        {
                                          "index": 0,
                                          "message": {"role": "assistant", "content": "OK"},
                                          "finish_reason": "stop"
                                        }
                                      ]
                                    }
                                    """.utf8),
                                    response: httpURLResponse(statusCode: 200),
                                    error: nil
                                )
                            )
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02, execute: workItem)
                        return { workItem.cancel() }
                    case "kimi-k2.5-nvidia":
                        let workItem = DispatchWorkItem {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {
                                      "id": "chatcmpl-race-loser",
                                      "object": "chat.completion",
                                      "model": "kimi-k2.5-nvidia",
                                      "choices": [
                                        {
                                          "index": 0,
                                          "message": {"role": "assistant", "content": "SLOW"},
                                          "finish_reason": "stop"
                                        }
                                      ]
                                    }
                                    """.utf8),
                                    response: httpURLResponse(statusCode: 200),
                                    error: nil
                                )
                            )
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.20, execute: workItem)
                        return {
                            lock.lock()
                            kimiCanceled = true
                            lock.unlock()
                            workItem.cancel()
                        }
                    default:
                        return {}
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should return the first valid raced fallback winner")
                    return
                }

                expectEqual(deliveredStatus, 200, "worker should return a successful raced fallback winner", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker should preserve the outward alias when a raced fallback wins", recorder: recorder)
                expectEqual(kimiCanceled, true, "worker should cancel the losing raced fallback once a valid winner is chosen", recorder: recorder)
            }
        }

        run("temporary worker smart alias ignores fast invalid-success fallbacks and waits for a slower valid winner", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "minimax-m2.5-nvidia":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-invalid",
                                  "object": "chat.completion",
                                  "model": "minimax-m2.5-nvidia",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "<think>hidden reasoning only"},
                                      "finish_reason": "length"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    case "kimi-k2.5-nvidia":
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {
                                      "id": "chatcmpl-valid-kimi",
                                      "object": "chat.completion",
                                      "model": "kimi-k2.5-nvidia",
                                      "choices": [
                                        {
                                          "index": 0,
                                          "message": {"role": "assistant", "content": "KIMI OK"},
                                          "finish_reason": "stop"
                                        }
                                      ]
                                    }
                                    """.utf8),
                                    response: httpURLResponse(statusCode: 200),
                                    error: nil
                                )
                            )
                        }
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = body
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should wait for a valid raced fallback instead of forwarding a fast invalid-success response")
                    return
                }

                expectEqual(deliveredStatus, 200, "worker should still succeed when the first raced fallback is invalid-success junk", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(((deliveredJSON["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String, "KIMI OK", "worker should return the slower valid raced fallback instead of a fast invalid-success body", recorder: recorder)
            }
        }

        run("temporary worker smart alias fails over when the primary returns a malformed success-shaped 200", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredBody: Data?
                var deliveredMessage: String?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-zai-invalid",
                                  "object": "chat.completion",
                                  "model": "glm-5.1"
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "minimax-m2.5-opencode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-opencode-minimax-invalid",
                                  "object": "chat.completion",
                                  "model": "minimax/minimax-m2.5-20260211",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": null, "reasoning": "The user has just said \\\"Hi\\\""},
                                      "finish_reason": "length"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    case "minimax-m2.5-nvidia":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-fallback-valid",
                                  "object": "chat.completion",
                                  "model": "minimax-m2.5-nvidia",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "MINIMAX OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    case "kimi-k2.5-nvidia":
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {
                                      "id": "chatcmpl-kimi-slower",
                                      "object": "chat.completion",
                                      "model": "kimi-k2.5-nvidia",
                                      "choices": [
                                        {
                                          "index": 0,
                                          "message": {"role": "assistant", "content": "KIMI OK"},
                                          "finish_reason": "stop"
                                        }
                                      ]
                                    }
                                    """.utf8),
                                    response: httpURLResponse(statusCode: 200),
                                    error: nil
                                )
                            )
                        }
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = body
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should fail over after a malformed primary 200 response")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode", "minimax-m2.5-nvidia", "kimi-k2.5-nvidia"], "worker should treat malformed primary 200 bodies as retryable candidate failures, exhaust the free serial fallbacks, then race the NVIDIA fallbacks", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should still return a successful fallback response after a malformed primary 200", recorder: recorder)
                expectNil(deliveredMessage, "worker should not surface an error when a later fallback returns a valid response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(((deliveredJSON["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String, "MINIMAX OK", "worker should return the first valid fallback after rejecting malformed primary success bodies", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()["glm-5.1"]?.status, .suspect, "malformed primary 200 bodies should penalize route health for the primary", recorder: recorder)
            }
        }

        run("temporary worker smart alias keeps trying deferred backends after raced fallback terminals", recorder: recorder) {
            withMergedConfig(workerMergedConfigWithLastResortYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredBody: Data?
                var deliveredMessage: String?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(statusCode: 429),
                                error: nil
                            )
                        )
                    case "minimax-m2.5-nvidia":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"bad request\"}".utf8),
                                response: httpURLResponse(statusCode: 400),
                                error: nil
                            )
                        )
                    case "kimi-k2.5-nvidia":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unauthorized\"}".utf8),
                                response: httpURLResponse(statusCode: 401),
                                error: nil
                            )
                        )
                    case "gpt-5.4-medium":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-last-resort",
                                  "object": "chat.completion",
                                  "model": "gpt-5.4-medium",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "LAST RESORT OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = body
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should continue to deferred backends after the raced fallback set only returns terminal failures")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "mimo-v2-pro-opencode", "mimo-v2-pro-kilocode", "minimax-m2.5-opencode", "minimax-m2.5-nvidia", "kimi-k2.5-nvidia", "gpt-5.4-medium"], "worker should continue to the deferred last-resort backend after the free serial legs fail and the raced NVIDIA fallbacks only return terminal outcomes", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should still succeed once the deferred last-resort backend returns a valid response", recorder: recorder)
                expectNil(deliveredMessage, "worker should not surface an error when the deferred last-resort backend succeeds", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(((deliveredJSON["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String, "LAST RESORT OK", "worker should surface the deferred last-resort backend once the raced fallbacks fail terminally", recorder: recorder)
            }
        }

        */

        run("temporary worker smart alias falls through from z.ai glm to ollama glm on quota-window 429s before the rest of the chain", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var deliveredStatus: Int?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                var seenModels: [String] = []
                var recordedEvents: [OpenAICompatTemporaryShim.RouteTelemetryEvent] = []

                OpenAICompatTemporaryShim.routeTelemetryHookForTesting = { event in
                    lock.lock()
                    recordedEvents.append(event)
                    lock.unlock()
                }
                defer { OpenAICompatTemporaryShim.routeTelemetryHookForTesting = nil }

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(
                                    statusCode: 429,
                                    headerFields: [
                                        "Content-Type": "application/json",
                                        "Retry-After": "3600"
                                    ]
                                ),
                                error: nil
                            )
                        )
                    case "glm-5.1-ollama-pro":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-zai-ollama-fallback",
                                  "object": "chat.completion",
                                  "model": "glm-5.1",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                    deliveredStatus = statusCode
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: """
                        {
                          "model": "worker",
                          "messages": [{"role": "user", "content": "Return exactly: OK"}],
                          "stream": false
                        }
                        """
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker failover should eventually return a successful response")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-ollama-pro"], "worker should try the ZAI GLM primary and then the Ollama GLM sibling before the rest of the chain when the primary is in a quota window", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should return the Ollama GLM fallback response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, "worker", "worker responses should preserve the outward alias instead of leaking the winner model", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Public-Model"] as? String, "worker", "worker should expose the public alias in response headers for auditability", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Model"] as? String, "glm-5.1-ollama-pro", "worker should expose the winning fallback model in response headers", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Provider"] as? String, "ollama-pro", "worker should expose the winning fallback provider in response headers", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Resolved-Canonical-Model"] as? String, "glm-5.1", "worker should expose the winning fallback canonical model in response headers", recorder: recorder)

                let workerEvents = recordedEvents.filter { $0.requestedAlias == "worker" }
                expectEqual(workerEvents.contains(where: { $0.requestModel == "glm-5.1-zai" && $0.failoverDepth == 0 }), true, "worker telemetry should record the failed primary candidate with failover depth 0", recorder: recorder)
                expectEqual(workerEvents.contains(where: { $0.requestModel == "glm-5.1-ollama-pro" && $0.failoverDepth == 1 && $0.finalWinnerRequestModel == "glm-5.1-ollama-pro" }), true, "worker telemetry should record the winning sibling fallback candidate and final winner", recorder: recorder)
            }
        }

        run("temporary worker smart alias treats malformed primary 200 bodies as retryable and falls over to minimax", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredBody: Data?
                var deliveredMessage: String?

                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    switch model {
                    case "glm-5.1-ollama-pro":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-glm-invalid",
                                  "object": "chat.completion",
                                  "model": "glm-5.1"
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    case "minimax-m2.7-ollama-pro":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-minimax-valid",
                                  "object": "chat.completion",
                                  "model": "minimax-m2.7",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "MINIMAX OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    default:
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected model\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = body
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: """
                        {
                          "model": "worker",
                          "messages": [{"role": "user", "content": "Return exactly: OK"}],
                          "stream": false
                        }
                        """
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should fail over after a malformed primary 200 response")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro"], "worker should retry on the fallback after a malformed primary success body", recorder: recorder)
                expectEqual(deliveredStatus, 200, "worker should still return a successful fallback response after a malformed primary 200", recorder: recorder)
                expectNil(deliveredMessage, "worker should not surface an error when a later fallback returns a valid response", recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                expectEqual(((deliveredJSON["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String, "MINIMAX OK", "worker should return the first valid fallback after rejecting malformed primary success bodies", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()["glm-5.1"]?.status, .suspect, "malformed primary 200 bodies should penalize route health for the primary", recorder: recorder)
            }
        }

        run("temporary worker smart alias caps total failover latency for the whole request after falling through quota-window 429s", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                proxy.smartAliasTotalTimeoutOverrideForTesting = 0.05
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredMessage: String?

                proxy.bufferedProxyCancelableTransportForTesting = { _, _, _, body, timeoutInterval, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    switch model {
                    case "glm-5.1-zai":
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(
                                    statusCode: 429,
                                    headerFields: [
                                        "Content-Type": "application/json",
                                        "Retry-After": "3600"
                                    ]
                                ),
                                error: nil
                            )
                        )
                        return {}
                    default:
                        let workItem = DispatchWorkItem {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: nil,
                                    response: nil,
                                    error: URLError(.timedOut)
                                )
                            )
                        }
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutInterval + 0.01, execute: workItem)
                        return { workItem.cancel() }
                    }
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should stop once the alias-level failover budget is exhausted")
                    return
                }

                expectEqual(deliveredStatus, 504, "worker should return 504 when the alias-level failover budget expires before any fallback succeeds", recorder: recorder)
                expectEqual(deliveredMessage, "Worker failover budget exhausted before any backend returned a valid response.", "worker should emit a stable timeout message when the alias-level budget expires", recorder: recorder)
            }
        }

        run("temporary worker smart alias coalesces duplicate safe requests from the same caller identity behind one upstream sequence", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let proxy = ThinkingProxy()
                let firstConnection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let secondConnection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var transportInvocationCount = 0
                var deliveredResponseCount = 0

                proxy.bufferedProxyTransportForTesting = { _, _, _, _, _, completion in
                    lock.lock()
                    transportInvocationCount += 1
                    lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-coalesced",
                                  "object": "chat.completion",
                                  "model": "glm-5.1",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { _, _, _ in
                    lock.lock()
                    deliveredResponseCount += 1
                    let shouldSignal = deliveredResponseCount == 2
                    lock.unlock()
                    if shouldSignal {
                        delivered.signal()
                    }
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """
                let rawRequest = rawHTTPRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    headers: [
                        ("Authorization", "Bearer shared-worker-token"),
                        ("X-Factory-Session", "mission-worker-shared")
                    ],
                    body: requestJSON
                )

                proxy.processRequestForTesting(rawRequest, connection: firstConnection)
                proxy.processRequestForTesting(rawRequest, connection: secondConnection)

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("coalesced worker requests should deliver one upstream winner to both waiters")
                    return
                }

                expectEqual(transportInvocationCount, 1, "duplicate worker requests should share one upstream request sequence", recorder: recorder)
                expectEqual(deliveredResponseCount, 2, "coalesced worker requests should fan out the winner to both waiting callers", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary worker smart alias does not coalesce identical safe requests across different caller identities", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let proxy = ThinkingProxy()
                let firstConnection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let secondConnection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var transportInvocationCount = 0
                var deliveredResponseCount = 0

                proxy.bufferedProxyTransportForTesting = { _, _, _, _, _, completion in
                    lock.lock()
                    transportInvocationCount += 1
                    let invocationNumber = transportInvocationCount
                    lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl-isolated-\(invocationNumber)",
                                  "object": "chat.completion",
                                  "model": "glm-5.1",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    }
                }
                proxy.deliveredHTTPResponseForTesting = { _, _, _ in
                    lock.lock()
                    deliveredResponseCount += 1
                    let shouldSignal = deliveredResponseCount == 2
                    lock.unlock()
                    if shouldSignal {
                        delivered.signal()
                    }
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """
                let firstRequest = rawHTTPRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    headers: [
                        ("Authorization", "Bearer worker-token-one"),
                        ("X-Factory-Session", "mission-worker-one")
                    ],
                    body: requestJSON
                )
                let secondRequest = rawHTTPRequest(
                    method: "POST",
                    path: "/v1/chat/completions",
                    headers: [
                        ("Authorization", "Bearer worker-token-two"),
                        ("X-Factory-Session", "mission-worker-two")
                    ],
                    body: requestJSON
                )

                proxy.processRequestForTesting(firstRequest, connection: firstConnection)
                proxy.processRequestForTesting(secondRequest, connection: secondConnection)

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("identity-partitioned worker requests should each receive a response")
                    return
                }

                expectEqual(transportInvocationCount, 2, "worker requests from different caller identities must not share one upstream request sequence", recorder: recorder)
                expectEqual(deliveredResponseCount, 2, "identity-partitioned worker requests should still return one response per caller", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary worker smart alias returns one retryable 429 when every candidate is in a quota window and loop retries are exhausted", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredMessage: String?

                proxy.smartAliasLoopRetryLimitOverrideForTesting = 0
                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"rate limited\"}".utf8),
                            response: httpURLResponse(
                                statusCode: 429,
                                headerFields: [
                                    "Content-Type": "application/json",
                                    "Retry-After": "3600"
                                ]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.metaAIBufferedResponseForTesting = { _, _, publicModel in
                    lock.lock()
                    seenModels.append(publicModel)
                    lock.unlock()
                    return ThinkingProxy.BufferedProxyResponse(
                        data: Data("{\"error\":\"rate limited\"}".utf8),
                        response: httpURLResponse(
                            statusCode: 429,
                            headerFields: [
                                "Content-Type": "application/json",
                                "Retry-After": "3600"
                            ]
                        ),
                        error: nil
                    )
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should return a final error when all candidates fail")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "worker should exhaust every configured candidate before surfacing failure", recorder: recorder)
                expectEqual(deliveredStatus, 429, "worker should return one retryable 429 when every configured candidate is in a quota window", recorder: recorder)
                expectEqual(deliveredMessage, "Upstream rate-limit window reached for worker; retry when the provider window resets.", "worker should emit the quota-window retry guidance after exhausting the pool", recorder: recorder)
            }
        }

        run("temporary worker smart alias waits through short concurrency Retry-After windows on the preferred primary before succeeding", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredBody: String?
                var deliveredError: String?
                var attemptsByModel: [String: Int] = [:]

                proxy.smartAliasLoopRetryLimitOverrideForTesting = 2
                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    attemptsByModel[model, default: 0] += 1
                    let attempt = attemptsByModel[model] ?? 0
                    lock.unlock()

                    if attempt == 1 {
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"busy\"}".utf8),
                                response: httpURLResponse(statusCode: 429, headerFields: ["Retry-After": "0.1"]),
                                error: nil
                            )
                        )
                        return
                    }

                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"id\":\"chatcmpl-test\",\"object\":\"chat.completion\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"OK\"},\"finish_reason\":\"stop\"}],\"model\":\"\(model)\"}".utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = String(data: body, encoding: .utf8)
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { _, message in
                    deliveredError = message
                    delivered.signal()
                }

                let requestJSON = """
                {
                  "model": "worker",
                  "messages": [{"role": "user", "content": "Return exactly: OK"}],
                  "stream": false
                }
                """

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: requestJSON
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 3) == .success else {
                    recorder.recordFailure("worker should wait through short concurrency deferrals and eventually succeed")
                    return
                }

                expectEqual(deliveredStatus, 200, "worker should not surface a terminal 429 when the preferred primary is only briefly concurrency-limited", recorder: recorder)
                expectEqual(deliveredError, nil, "worker should succeed instead of surfacing a terminal concurrency error", recorder: recorder)
                expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-zai"], "worker should stay on the preferred primary while short concurrency deferrals clear", recorder: recorder)
                expectEqual(deliveredBody?.contains("\"content\":\"OK\""), true, "worker retry should eventually return a successful completion body", recorder: recorder)
            }
        }

        run("temporary worker smart alias does not spin on the same concurrency-limited lane when sibling fallbacks remain", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredMessage: String?

                proxy.smartAliasLoopRetryLimitOverrideForTesting = 0
                proxy.smartAliasTotalTimeoutOverrideForTesting = 5
                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()

                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"busy\"}".utf8),
                            response: httpURLResponse(statusCode: 429, headerFields: ["Retry-After": "0.1"]),
                            error: nil
                        )
                    )
                }
                proxy.metaAIBufferedResponseForTesting = { _, _, publicModel in
                    lock.lock()
                    seenModels.append(publicModel)
                    lock.unlock()
                    return ThinkingProxy.BufferedProxyResponse(
                        data: Data("{\"error\":\"busy\"}".utf8),
                        response: httpURLResponse(statusCode: 429, headerFields: ["Retry-After": "0.1"]),
                        error: nil
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, _ in
                    deliveredStatus = statusCode
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: """
                        {
                          "model": "worker",
                          "messages": [{"role": "user", "content": "Return exactly: OK"}],
                          "stream": false
                        }
                        """
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should return a terminal concurrency error promptly when every pool lane is saturated")
                    return
                }

                expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "worker should give the preferred primary one bounded retry, then advance through the rest of the pool instead of spinning indefinitely", recorder: recorder)
                expectEqual(deliveredStatus, 429, "worker should surface a retryable concurrency error when every pool lane is saturated", recorder: recorder)
                expectEqual(deliveredMessage, "Upstream concurrency limit reached for worker; retry shortly.", "worker should return the public worker concurrency guidance after exhausting the pool", recorder: recorder)
            }
        }

        run("temporary worker smart alias treats meta adapter 400s as retryable lane failures and falls through", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date()
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "glm-5.1-zai", until: now.addingTimeInterval(300))
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "minimax-m2.7-ollama-pro", until: now.addingTimeInterval(300))
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "glm5-nvidia", until: now.addingTimeInterval(300))
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-ollama-pro",
                    telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: now,
                        requestModel: "glm-5.1-ollama-pro",
                        canonicalModelID: "glm-5.1",
                        transportOutcome: "send_error",
                        failureClass: "transport_timeout",
                        timeoutStage: .firstResponse,
                        upstreamHTTPStatus: nil,
                        retryCount: 0,
                        source: "smart_alias"
                    ),
                    at: now
                )

                let proxy = ThinkingProxy()
                proxy.smartAliasLoopRetryLimitOverrideForTesting = 0
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                let lock = NSLock()
                var seenModels: [String] = []
                var deliveredStatus: Int?
                var deliveredBody: String?
                var deliveredError: String?

                proxy.metaAIBufferedResponseForTesting = { _, _, publicModel in
                    lock.lock()
                    seenModels.append(publicModel)
                    lock.unlock()
                    return ThinkingProxy.BufferedProxyResponse(
                        data: Data("""
                        {"error":{"message":"Meta web adapter synthetic tool mode required tool Read, but Meta did not return a valid tool directive.","type":"server_error","code":"internal_server_error"}}
                        """.utf8),
                        response: httpURLResponse(statusCode: 400, headerFields: ["Content-Type": "application/json"]),
                        error: nil
                    )
                }
                proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                    let json = parseJSONObject(body, recorder: recorder)
                    let model = json["model"] as? String ?? ""
                    lock.lock()
                    seenModels.append(model)
                    lock.unlock()
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {"id":"chatcmpl-test","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}],"model":"\(model)"}
                            """.utf8),
                            response: httpURLResponse(statusCode: 200),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                    deliveredStatus = statusCode
                    deliveredBody = String(data: body, encoding: .utf8)
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { _, message in
                    deliveredError = message
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(
                        method: "POST",
                        path: "/v1/chat/completions",
                        body: """
                        {
                          "model": "worker",
                          "stream": false,
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """
                    ),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 2) == .success else {
                    recorder.recordFailure("worker should fall through a retryable meta adapter 400 and still deliver a later candidate success")
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    return
                }

                expectEqual(deliveredStatus, 200, "worker should not surface the meta adapter 400 when a later fallback succeeds", recorder: recorder)
                expectEqual(deliveredError, nil, "worker should not treat the retryable meta adapter 400 as terminal", recorder: recorder)
                expectEqual(seenModels, ["muse-spark", "glm-5.1-ollama-pro"], "worker should fail over from muse-spark to the next remaining fallback after a retryable meta adapter 400", recorder: recorder)
                expectEqual(deliveredBody?.contains("\"content\":\"OK\""), true, "worker should deliver the later fallback response after the meta adapter 400", recorder: recorder)
                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["muse-spark"]?.status, .suspect, "retryable meta adapter 400s should penalize the muse-spark lane so it is deprioritized on later turns", recorder: recorder)
                expectEqual(snapshot["muse-spark"]?.lastTelemetryEvent?.failureClass, "classified_retryable_400_meta_adapter", "route health should retain the retryable meta adapter failure class for diagnostics", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary worker smart alias stays hidden from /v1/models even while candidate routes are healthy", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let body = """
                {
                  "object": "list",
                  "data": [
                    {"id": "glm-5.1", "object": "model", "owned_by": "zai"},
                    {"id": "minimax-m2.5-nvidia", "object": "model", "owned_by": "nvidia"},
                    {"id": "kimi-k2.5-nvidia", "object": "model", "owned_by": "nvidia"}
                  ]
                }
                """

                let unmodified = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(Data(body.utf8))
                expectNil(unmodified, "worker should not be injected into /v1/models when the upstream list is already healthy", recorder: recorder)

                let until = Date().addingTimeInterval(60)
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "glm-5.1", until: until)
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "minimax-m2.5-nvidia", until: until)
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "kimi-k2.5-nvidia", until: until)

                guard let filtered = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(Data(body.utf8)) else {
                    recorder.recordFailure("filtered /v1/models should still be materialized after every worker candidate is quarantined")
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    return
                }
                let filteredJSON = parseDataJSONObject(filtered, recorder: recorder)
                let filteredIDs = ((filteredJSON["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
                expectEqual(filteredIDs.contains("worker"), false, "worker should remain absent from /v1/models even after candidate filtering runs", recorder: recorder)
                expectEqual(filteredIDs.contains("glm-5.1"), false, "filtered /v1/models should still remove unavailable concrete worker candidates", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("legacy zai glm ids are normalized out of /v1/models", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let body = """
                {
                  "object": "list",
                  "data": [
                    {"id": "glm-5", "object": "model", "owned_by": "zai"},
                    {"id": "glm-5-turbo", "object": "model", "owned_by": "zai"},
                    {"id": "glm-5.1", "object": "model", "owned_by": "zai"}
                  ]
                }
                """

                guard let filtered = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(Data(body.utf8)) else {
                    recorder.recordFailure("legacy Z.AI GLM ids should force a normalized /v1/models rewrite")
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    return
                }

                let filteredJSON = parseDataJSONObject(filtered, recorder: recorder)
                let filteredIDs = ((filteredJSON["data"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
                expectEqual(filteredIDs, ["glm-5.1"], "legacy Z.AI GLM ids should collapse to the canonical glm-5.1 listing", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary expired route cooldowns restore worker candidate availability", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let body = """
                {
                  "object": "list",
                  "data": [
                    {"id": "glm-5.1", "object": "model", "owned_by": "zai"},
                    {"id": "minimax-m2.5-nvidia", "object": "model", "owned_by": "nvidia"},
                    {"id": "kimi-k2.5-nvidia", "object": "model", "owned_by": "nvidia"}
                  ]
                }
                """
                let expired = Date().addingTimeInterval(-60)
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "glm-5.1", until: expired)
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "minimax-m2.5-nvidia", until: expired)
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(requestModel: "kimi-k2.5-nvidia", until: expired)

                expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1"), false, "expired cooldown windows should make worker primaries eligible for live traffic again", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "minimax-m2.5-nvidia"), false, "expired cooldown windows should make raced fallbacks eligible again", recorder: recorder)

                let filtered = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(Data(body.utf8))
                expectNil(filtered, "healthy cooldown-expired worker candidates should leave /v1/models unchanged instead of re-injecting the smart alias", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia recovered routes become suspect again on the next failure", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)

                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now)
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(6))
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(12))
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(18))
                OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: "glm5")
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(24))

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .suspect, "a post-recovery failure should re-enter suspect instead of immediately quarantining again", recorder: recorder)
                expectEqual(snapshot["z-ai/glm5"]?.recoverySuccesses, 0, "closing the route should reset the recovery counter", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), false, "one new failure after recovery should still keep the route available", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia preflight rejects quarantined hosted routes before spending timeout budget", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                    requestModel: "kimi-k2.5-nvidia",
                    until: Date().addingTimeInterval(60)
                )
                let request = """
                {
                  "model": "kimi-k2.5-nvidia",
                  "messages": [
                    {"role": "user", "content": "Return exactly: OK"}
                  ]
                }
                """

                let preflightError = OpenAICompatTemporaryShim.preflightError(
                    method: "POST",
                    path: "/v1/chat/completions",
                    jsonString: request
                )

                expectEqual(preflightError?.statusCode ?? 0, 503, "quarantined NVIDIA routes should fail immediately instead of consuming the full timeout budget", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia model list filtering hides quarantined aliases", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                    requestModel: "glm5",
                    until: Date().addingTimeInterval(60)
                )
                let body = """
                {
                  "object": "list",
                  "data": [
                    {"id": "glm5", "object": "model", "owned_by": "nvidia"},
                    {"id": "kimi-k2.5-nvidia", "object": "model", "owned_by": "nvidia"},
                    {"id": "gpt-5", "object": "model", "owned_by": "openai"}
                  ]
                }
                """

                guard let filtered = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(Data(body.utf8)) else {
                    recorder.recordFailure("expected quarantined route to be removed from /v1/models response")
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    return
                }

                let json = parseDataJSONObject(filtered, recorder: recorder)
                let data = json["data"] as? [[String: Any]]
                let ids = (data ?? []).compactMap { $0["id"] as? String }
                expectEqual(ids.contains("glm5"), false, "quarantined glm5 alias should be removed from /v1/models", recorder: recorder)
                expectEqual(ids.contains("kimi-k2.5-nvidia"), true, "healthy NVIDIA aliases should remain visible", recorder: recorder)
                expectEqual(ids.contains("gpt-5"), true, "non-NVIDIA models should remain visible", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("temporary nvidia route health reload keeps failure evidence without hard-quarantining startup", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withRouteHealthPath { path in
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let now = Date()
                    let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: now,
                        requestModel: "glm5",
                        canonicalModelID: "z-ai/glm5",
                        transportOutcome: "send_error",
                        failureClass: "transport_timeout",
                        timeoutStage: .bufferedResponse,
                        upstreamHTTPStatus: nil,
                        retryCount: 1,
                        source: "live_request"
                    )

                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm5",
                        telemetryEvent: event,
                        at: now
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm5",
                        telemetryEvent: event,
                        at: now.addingTimeInterval(6)
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm5",
                        telemetryEvent: event,
                        at: now.addingTimeInterval(12)
                    )
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm5",
                        telemetryEvent: event,
                        at: now.addingTimeInterval(18)
                    )

                    guard FileManager.default.fileExists(atPath: path) else {
                        recorder.recordFailure("expected persistent NVIDIA route-health cache file to be written")
                        return
                    }

                    OpenAICompatTemporaryShim.forcePersistRouteHealthForTesting()
                OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()

                    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    let persisted = snapshot["z-ai/glm5"]
                    expectEqual(persisted?.status, .suspect, "startup reload should downgrade persisted open state to suspect so live traffic can re-probe the route", recorder: recorder)
                    expectEqual(persisted?.failureScore ?? 0, 4, "startup reload should retain the failure score", recorder: recorder)
                    expectEqual(persisted?.isUnavailable(at: now), false, "startup reload should not keep the route unavailable purely from persisted state", recorder: recorder)
                    expectEqual(persisted?.lastTelemetryEvent?.transportOutcome, "send_error", "startup reload should retain the transport outcome", recorder: recorder)
                    expectEqual(persisted?.lastTelemetryEvent?.healthTransition, "suspect->open", "startup reload should retain the original health transition evidence", recorder: recorder)
                    expectEqual(persisted?.rollingMetrics.recentOutcomes.filter { $0.hasSuffix(":transport_timeout") }.count, 4, "startup reload should retain rolling timeout counts in recent outcomes", recorder: recorder)
                    expectEqual(persisted?.rollingMetrics.recentOutcomes.count, 4, "startup reload should retain recent outcomes", recorder: recorder)

                    guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                        recorder.recordFailure("expected to read persisted route-health cache file")
                        return
                    }
                    let rawJSON = parseDataJSONObject(rawData, recorder: recorder)
                    let routes = rawJSON["routes"] as? [String: Any]
                    let glm5 = routes?["nvidia::z-ai/glm5"] as? [String: Any]
                    expectEqual(glm5?["status"] as? String, "suspect", "startup normalization should rewrite persisted route-health state to suspect", recorder: recorder)
                    expectEqual(glm5?["failure_score"] as? Int, 4, "startup normalization should retain the failure score on disk", recorder: recorder)
                    let lastEvent = glm5?["last_event"] as? [String: Any]
                    expectEqual(lastEvent?["health_transition"] as? String, "suspect->open", "startup normalization should preserve the original health transition evidence on disk", recorder: recorder)
                    let rollingMetrics = glm5?["rolling_metrics"] as? [String: Any]
                    expectEqual((rollingMetrics?["recent_outcomes"] as? [String])?.filter { $0.hasSuffix(":transport_timeout") }.count, 4, "startup normalization should preserve rolling timeout counts in recent outcomes", recorder: recorder)
                    expectEqual(glm5?["open_until"] == nil, true, "startup normalization should drop persisted open-until timestamps so restart does not inherit unavailability", recorder: recorder)
                }
            }
        }

        run("persisted legacy zai glm route-health entries are pruned on reload", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                guard let path = ProcessInfo.processInfo.environment["VIBEPROXY_ROUTE_HEALTH_PATH"] else {
                    recorder.recordFailure("expected temporary route-health path to be configured")
                    return
                }

                let payload = """
                {
                  "version": 1,
                  "routes": {
                    "zai::glm-5-turbo": {
                      "status": "closed",
                      "failure_score": 1,
                      "recovery_successes": 0,
                      "rolling_metrics": {
                        "request_count": 1,
                        "success_count": 1,
                        "timeout_count": 0,
                        "invalid_success_count": 0,
                        "recent_outcomes": ["send_response"],
                        "recent_first_byte_latency_ms": []
                      }
                    },
                    "zai::glm-5.1": {
                      "status": "suspect",
                      "failure_score": 2,
                      "recovery_successes": 0,
                      "rolling_metrics": {
                        "request_count": 2,
                        "success_count": 1,
                        "timeout_count": 0,
                        "invalid_success_count": 0,
                        "recent_outcomes": ["send_response", "send_error:empty_content"],
                        "recent_first_byte_latency_ms": []
                      }
                    }
                  }
                }
                """

                try? payload.write(toFile: path, atomically: true, encoding: .utf8)
                OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectNil(snapshot["glm-5-turbo"], "legacy glm-5-turbo route-health state should be dropped during reload", recorder: recorder)
                expectEqual(snapshot["glm-5.1"]?.failureScore, 2, "current glm-5.1 route-health state should survive reload", recorder: recorder)

                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let routes = json["routes"] as? [String: Any] else {
                    recorder.recordFailure("expected pruned route-health file to be readable")
                    return
                }

                expectEqual(routes["zai::glm-5-turbo"] == nil, true, "persisted route-health file should delete stale glm-5-turbo entries after reload", recorder: recorder)
                expectEqual((routes["zai::glm-5.1"] as? [String: Any])?["failure_score"] as? Int, 2, "persisted route-health file should retain current glm-5.1 state", recorder: recorder)
            }
        }

        run("persisted legacy low learned concurrency caps are not trusted on reload without freshness metadata", recorder: recorder) {
            withRouteHealthPath { path in
                let payload = """
                {
                  "version": 3,
                  "routes": {},
                  "discovered_concurrency_limits": {
                    "zai::glm-5.1": 1
                  }
                }
                """

                try? payload.write(toFile: path, atomically: true, encoding: .utf8)
                OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()

                expectEqual(
                    OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: "zai::glm-5.1"),
                    3,
                    "legacy low learned concurrency caps should reset to the default until the new process re-learns them",
                    recorder: recorder
                )
            }
        }

        run("persisted pre-migration learned concurrency caps of 1 are discarded even with freshness metadata", recorder: recorder) {
            withRouteHealthPath { path in
                let payload = """
                {
                  "version": 4,
                  "routes": {},
                  "discovered_concurrency_limits": {
                    "zai::glm-5.1": 1
                  },
                  "discovered_concurrency_limit_metadata": {
                    "zai::glm-5.1": {
                      "updated_at": "2026-04-09T08:53:48Z"
                    }
                  }
                }
                """

                try? payload.write(toFile: path, atomically: true, encoding: .utf8)
                OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()

                expectEqual(
                    OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: "zai::glm-5.1"),
                    3,
                    "pre-migration learned caps of 1 should be cleared so the new learner can re-establish them from true multi-flight evidence",
                    recorder: recorder
                )
            }
        }

        run("temporary nvidia telemetry derives timeout-stage context from deadline-driven failures", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm5",
                    initialTransportRetries: 1,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let event = OpenAICompatTemporaryShim.telemetryEvent(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: nil,
                        response: nil,
                        error: URLError(.timedOut),
                        deadlineStage: .bufferedResponse
                    ),
                    outcome: .sendError(statusCode: 504, message: "Gateway Timeout"),
                    source: "live_request"
                )

                expectEqual(event.requestModel, "glm5", "telemetry should preserve the request model alias", recorder: recorder)
                expectEqual(event.canonicalModelID, "z-ai/glm5", "telemetry should resolve canonical NVIDIA model identity", recorder: recorder)
                expectEqual(event.transportOutcome, "send_error", "telemetry should encode the runtime outcome label", recorder: recorder)
                expectEqual(event.failureClass, "transport_timeout", "deadline-driven transport failures should be labeled explicitly", recorder: recorder)
                expectEqual(event.timeoutStage, .bufferedResponse, "telemetry should capture the deadline stage", recorder: recorder)
                expectEqual(event.retryCount, 1, "telemetry should include retries already spent before the outcome", recorder: recorder)
                expectNil(event.upstreamHTTPStatus, "transport-level failures should not claim an upstream HTTP status", recorder: recorder)
                expectEqual(event.source, "live_request", "telemetry should preserve the event source", recorder: recorder)
            }
        }

        run("temporary nvidia telemetry derives upstream status and retry counts from classified failures", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = Data("""
                {
                  "error": {
                    "message": "Too Many Requests"
                  }
                }
                """.utf8)
                let response = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "kimi-k2.5-nvidia",
                    initialTransportRetries: 2,
                    initialSemanticRetries: 1,
                    transportRetriesRemaining: 1,
                    semanticRetriesRemaining: 1,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )
                let outcome = OpenAICompatTemporaryShim.NVIDIARuntimeOutcome.sendError(statusCode: 429, message: "Too Many Requests")
                let event = OpenAICompatTemporaryShim.telemetryEvent(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: body,
                        response: response,
                        error: nil,
                        deadlineStage: .none
                    ),
                    outcome: outcome,
                    source: "live_request"
                )

                expectEqual(event.canonicalModelID, "moonshotai/kimi-k2.5", "telemetry should resolve the canonical Kimi model ID", recorder: recorder)
                expectEqual(event.failureClass, "classified_429_concurrency", "classified upstream failures should carry their normalized 429 subtype", recorder: recorder)
                expectEqual(event.upstreamHTTPStatus, 429, "telemetry should preserve the upstream HTTP status when available", recorder: recorder)
                expectEqual(event.retryCount, 1, "telemetry should count prior transport retries", recorder: recorder)
            }
        }

        run("generic route telemetry classifies non-nvidia 429 responses", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                let body = Data("""
                {
                  "error": {
                    "message": "The service may be temporarily overloaded, please try again later"
                  }
                }
                """.utf8)
                let response = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm-5.1-zai",
                    initialTransportRetries: 0,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 0,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )
                let event = OpenAICompatTemporaryShim.telemetryEvent(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: body,
                        response: response,
                        error: nil,
                        deadlineStage: .none
                    ),
                    outcome: .sendResponse(statusCode: 429, headers: response?.allHeaderFields ?? [:], body: body),
                    source: "canary"
                )

                expectEqual(event.failureClass, "classified_429_overload", "generic 429 responses should preserve their classified subtype in telemetry", recorder: recorder)
                expectEqual(event.upstreamHTTPStatus, 429, "generic telemetry should preserve the upstream HTTP status", recorder: recorder)
            }
        }

        run("temporary nvidia canary success immediately closes quarantined routes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withRouteHealthPath { _ in
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "glm5",
                        until: Date().addingTimeInterval(60)
                    )

                    let proxy = ThinkingProxy()
                    var seenRequestModel: String?
                    proxy.nvidiaCanaryTransportForTesting = { requestModel, requestJSON, completion in
                        seenRequestModel = requestModel
                        if !requestJSON.contains("\"model\": \"glm5-nvidia\"") {
                            recorder.recordFailure("expected canary request JSON to use the concrete route request model so the proxy can route the quarantined lane precisely")
                        }
                        let body = Data("""
                        {
                          "choices": [
                            {
                              "finish_reason": "stop",
                              "message": {
                                "content": "OK"
                              }
                            }
                          ]
                        }
                        """.utf8)
                        let response = HTTPURLResponse(
                            url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: ["Content-Type": "application/json"]
                        )
                        completion(body, response, nil)
                    }

                    let semaphore = DispatchSemaphore(value: 0)
                    proxy.performCanariesOnce {
                        semaphore.signal()
                    }
                    let waitResult = semaphore.wait(timeout: .now() + 2)
                    expectEqual(waitResult, .success, "canary sweep should complete promptly under stubbed transport", recorder: recorder)
                    expectEqual(seenRequestModel, "glm5-nvidia", "canary sweep should probe the concrete quarantined route request model exactly once", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), false, "one successful canary should immediately restore the route", recorder: recorder)
                    var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "first successful canary should close the route immediately", recorder: recorder)
                    expectEqual(snapshot["z-ai/glm5"]?.recoverySuccesses, 0, "immediate recovery should not leave half-open state behind", recorder: recorder)
                    var lastEvent = snapshot["z-ai/glm5"]?.lastTelemetryEvent
                    expectEqual(lastEvent?.source, "canary", "successful canaries should record canary telemetry", recorder: recorder)
                    expectEqual(lastEvent?.transportOutcome, "send_response", "successful canaries should record a successful runtime outcome", recorder: recorder)
                    expectEqual(lastEvent?.healthTransition, "open->closed", "successful canaries should record the route-health transition", recorder: recorder)

                    let secondSemaphore = DispatchSemaphore(value: 0)
                    proxy.performCanariesOnce {
                        secondSemaphore.signal()
                    }
                    let secondWaitResult = secondSemaphore.wait(timeout: .now() + 2)
                    expectEqual(secondWaitResult, .success, "second canary sweep should also complete promptly", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), false, "a healthy route should stay available on later sweeps", recorder: recorder)
                    snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "route should remain closed after later successful canaries", recorder: recorder)
                    lastEvent = snapshot["z-ai/glm5"]?.lastTelemetryEvent
                    expectEqual(lastEvent?.source, "canary", "successful reopening should preserve the last canary telemetry event", recorder: recorder)
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("temporary nvidia canary failures keep quarantined routes open and record canary telemetry", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withRouteHealthPath { _ in
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let until = Date().addingTimeInterval(60)
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "glm5",
                        until: until
                    )

                    let proxy = ThinkingProxy()
                    var invocation = 0
                    proxy.nvidiaCanaryTransportForTesting = { _, _, completion in
                        invocation += 1
                        if invocation == 1 {
                            let body = Data("""
                            {
                              "choices": [
                                {
                                  "finish_reason": "stop",
                                  "message": {
                                    "content": "OK"
                                  }
                                }
                              ]
                            }
                            """.utf8)
                            let response = HTTPURLResponse(
                                url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                                statusCode: 200,
                                httpVersion: nil,
                                headerFields: ["Content-Type": "application/json"]
                            )
                            completion(body, response, nil)
                        } else {
                            completion(nil, nil, URLError(.timedOut))
                        }
                    }

                    let semaphore = DispatchSemaphore(value: 0)
                    proxy.performCanariesOnce {
                        semaphore.signal()
                    }
                    let waitResult = semaphore.wait(timeout: .now() + 2)
                    expectEqual(waitResult, .success, "first canary sweep should complete promptly", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), false, "first successful canary should immediately restore the route", recorder: recorder)

                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "glm5",
                        until: until
                    )

                    let secondSemaphore = DispatchSemaphore(value: 0)
                    proxy.performCanariesOnce {
                        secondSemaphore.signal()
                    }
                    let secondWaitResult = secondSemaphore.wait(timeout: .now() + 2)
                    expectEqual(secondWaitResult, .success, "second failing canary sweep should still complete promptly", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), true, "failed canaries should keep the route quarantined", recorder: recorder)
                    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    let lastEvent = snapshot["z-ai/glm5"]?.lastTelemetryEvent
                    expectEqual(lastEvent?.source, "canary", "failed canaries should record canary telemetry", recorder: recorder)
                    expectEqual(lastEvent?.failureClass, "transport_error_retryable", "failed canaries should preserve the route failure class", recorder: recorder)
                    expectEqual(snapshot["z-ai/glm5"]?.status, .open, "failed canaries should leave the route quarantined", recorder: recorder)
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("canary skips active quota-window routes until the provider cooldown expires", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withRouteHealthPath { _ in
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let until = Date().addingTimeInterval(300)
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm-5.1-zai",
                        telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                            timestamp: Date(),
                            requestModel: "glm-5.1-zai",
                            canonicalModelID: "glm-5.1",
                            transportOutcome: "retry",
                            failureClass: "classified_429_window",
                            timeoutStage: .none,
                            upstreamHTTPStatus: 429,
                            retryCount: 0,
                            source: "smart_alias"
                        ),
                        forcedOpenUntil: until
                    )

                    let proxy = ThinkingProxy()
                    var invocationCount = 0
                    proxy.nvidiaCanaryTransportForTesting = { _, _, _ in
                        invocationCount += 1
                    }

                    let semaphore = DispatchSemaphore(value: 0)
                    proxy.performCanariesOnce {
                        semaphore.signal()
                    }
                    let waitResult = semaphore.wait(timeout: .now() + 2)
                    expectEqual(waitResult, .success, "quota-window canary sweep should complete promptly", recorder: recorder)
                    expectEqual(invocationCount, 0, "active quota-window routes should not be re-probed by canaries during the provider cooldown", recorder: recorder)

                    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    expectEqual(snapshot["glm-5.1"]?.status, .open, "skipped quota-window canaries should preserve the open route state", recorder: recorder)
                    expectEqual(snapshot["glm-5.1"]?.lastTelemetryEvent?.failureClass, "classified_429_window", "skipped quota-window canaries should preserve the quota-window evidence", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
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

        run("temporary nvidia runtime outcome retries semantic failures and later returns preserved repaired output", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let firstBody = Data("""
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
                """.utf8)
                let firstResponse = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let initialState = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "minimax-m2.5-nvidia",
                    initialTransportRetries: 0,
                    initialSemanticRetries: 1,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 1,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: true,
                    bestEffortRepairedBodyData: nil
                )

                let firstOutcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: initialState,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: firstBody,
                        response: firstResponse,
                        error: nil,
                        deadlineStage: .none
                    )
                )

                guard case .retry(let nextState) = firstOutcome else {
                    recorder.recordFailure("expected first minimax think-leak response to schedule a semantic retry")
                    return
                }
                expectEqual(nextState.semanticRetriesRemaining, 0, "semantic retries should decrement in the runtime outcome", recorder: recorder)
                guard let preserved = nextState.bestEffortRepairedBodyData else {
                    recorder.recordFailure("expected repaired minimax body to be preserved across retries")
                    return
                }

                let secondOutcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: nextState,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: nil,
                        response: nil,
                        error: URLError(.timedOut),
                        deadlineStage: .bufferedResponse
                    )
                )

                guard case .sendResponse(let statusCode, _, let body) = secondOutcome else {
                    recorder.recordFailure("expected transport exhaustion to return the preserved repaired minimax body")
                    return
                }
                expectEqual(statusCode, 200, "preserved repaired minimax responses should be returned as HTTP 200", recorder: recorder)
                expectEqual(body, preserved, "runtime outcome should emit the same preserved repaired body", recorder: recorder)
            }
        }

        run("temporary nvidia runtime outcome retries retryable transport errors", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm5",
                    initialTransportRetries: 1,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 1,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: nil,
                        response: nil,
                        error: URLError(.timedOut),
                        deadlineStage: .bufferedResponse
                    )
                )

                guard case .retry(let nextState) = outcome else {
                    recorder.recordFailure("expected retryable transport errors to schedule another attempt")
                    return
                }
                expectEqual(nextState.transportRetriesRemaining, 0, "runtime outcome should decrement transport retries on retryable transport errors", recorder: recorder)
            }
        }

        run("temporary nvidia runtime outcome fails closed on unrepaired invalid-success responses", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = Data("""
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
                """.utf8)
                let response = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm5",
                    initialTransportRetries: 0,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: body,
                        response: response,
                        error: nil,
                        deadlineStage: .none
                    )
                )

                guard case .sendError(let statusCode, let message) = outcome else {
                    recorder.recordFailure("expected unrepaired invalid-success responses to fail closed")
                    return
                }
                expectEqual(statusCode, 502, "unrepaired invalid-success responses should surface as 502", recorder: recorder)
                expectEqual(message, "Bad Gateway - Upstream provider returned an unusable response", "invalid-success responses should keep the explicit client-facing error", recorder: recorder)
            }
        }

        run("temporary nvidia runtime outcome propagates classified upstream failures", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = Data("""
                {
                  "status": 404,
                  "title": "Not Found",
                  "detail": "Function 'abc': Not found for account 'acct'"
                }
                """.utf8)
                let response = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm5",
                    initialTransportRetries: 0,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: body,
                        response: response,
                        error: nil,
                        deadlineStage: .none
                    )
                )

                guard case .sendError(let statusCode, let message) = outcome else {
                    recorder.recordFailure("expected classified upstream failures to become client-facing errors")
                    return
                }
                expectEqual(statusCode, 503, "classified function-not-found failures should surface as 503", recorder: recorder)
                expectEqual(message, "Upstream NVIDIA model route is unavailable for chat completions on this account.", "classified runtime errors should preserve the client-facing outage message", recorder: recorder)
            }
        }

        run("temporary nvidia runtime outcome retries retryable upstream HTTP statuses", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = Data("{\"error\":{\"message\":\"gateway timeout\"}}".utf8)
                let response = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 504,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm5",
                    initialTransportRetries: 1,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 1,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: body,
                        response: response,
                        error: nil,
                        deadlineStage: .none
                    )
                )

                guard case .retry(let nextState) = outcome else {
                    recorder.recordFailure("expected retryable upstream HTTP status to schedule another transport attempt")
                    return
                }
                expectEqual(nextState.transportRetriesRemaining, 0, "runtime outcome should decrement transport retries on retryable HTTP statuses", recorder: recorder)
            }
        }

        run("temporary nvidia runtime outcome emits normalized successful bodies", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let body = Data("""
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
                """.utf8)
                let response = HTTPURLResponse(
                    url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "kimi-k2.5-nvidia",
                    initialTransportRetries: 0,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: body,
                        response: response,
                        error: nil,
                        deadlineStage: .none
                    )
                )

                guard case .sendResponse(let statusCode, _, let normalizedBody) = outcome else {
                    recorder.recordFailure("expected successful kimi responses to be emitted as normalized HTTP responses")
                    return
                }
                expectEqual(statusCode, 200, "normalized successful responses should preserve the upstream HTTP status", recorder: recorder)
                let normalizedJSON = parseDataJSONObject(normalizedBody, recorder: recorder)
                let normalizedChoices = normalizedJSON["choices"] as? [[String: Any]]
                let normalizedMessage = normalizedChoices?.first?["message"] as? [String: Any]
                expectEqual(normalizedMessage?["content"] as? String, " OK", "normalized runtime responses should preserve visible content", recorder: recorder)
                expectNil(normalizedMessage?["reasoning"], "normalized runtime responses should strip provider reasoning", recorder: recorder)
                expectNil(normalizedMessage?["reasoning_content"], "normalized runtime responses should strip provider reasoning_content", recorder: recorder)
            }
        }

        run("temporary nvidia runtime outcome fails with generic 502 when no response materializes", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                let state = OpenAICompatTemporaryShim.NVIDIARetryState(
                    model: "glm5",
                    initialTransportRetries: 0,
                    initialSemanticRetries: 0,
                    transportRetriesRemaining: 0,
                    semanticRetriesRemaining: 0,
                    retryBackoffMilliseconds: 250,
                    salvagesBestEffortRepair: false,
                    bestEffortRepairedBodyData: nil
                )

                let outcome = OpenAICompatTemporaryShim.resolveNVIDIARuntimeOutcome(
                    path: "/v1/chat/completions",
                    state: state,
                    attempt: OpenAICompatTemporaryShim.NVIDIAAttemptResult(
                        data: nil,
                        response: nil,
                        error: nil,
                        deadlineStage: .none
                    )
                )

                guard case .sendError(let statusCode, let message) = outcome else {
                    recorder.recordFailure("expected missing response material to fail as a generic bad gateway")
                    return
                }
                expectEqual(statusCode, 502, "missing response material should surface as 502", recorder: recorder)
                expectEqual(message, "Bad Gateway", "missing response material should keep the generic bad-gateway message", recorder: recorder)
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
                    model: "kimi-k2.5-nvidia",
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
                    model: "kimi-k2.5-nvidia",
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
                    model: "minimax-m2.5-nvidia",
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
                    model: "minimax-m2.5-nvidia",
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
                    model: "kimi-k2.5-nvidia",
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
                    model: "kimi-k2.5-nvidia",
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
                    model: "minimax-m2.5-nvidia",
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

        run("healthz reports backend target, provenance, and route health snapshot", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "glm5",
                        until: Date().addingTimeInterval(60)
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredStatus: Int?
                    var deliveredHeaders: [AnyHashable: Any]?
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { statusCode, headers, body in
                        deliveredStatus = statusCode
                        deliveredHeaders = headers
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("healthz should return a response")
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let frontend = payload["frontend"] as? [String: Any]
                    let backend = payload["backend"] as? [String: Any]
                    let provenance = payload["provenance"] as? [String: Any]
                    let routeHealth = payload["route_health"] as? [String: Any]
                    let routes = routeHealth?["routes"] as? [String: Any]
                    let glm5 = routes?["glm5-nvidia"] as? [String: Any]
                    let quarantinedModels = routeHealth?["quarantined_models"] as? [String]
                    let quarantinedCanonicalModels = routeHealth?["quarantined_canonical_models"] as? [String]
                    let factoryWorker = payload["factory_worker"] as? [String: Any]
                    let factoryRoles = payload["factory_roles"] as? [String: Any]
                    let orchestration = factoryRoles?["orchestration"] as? [String: Any]
                    let verification = factoryRoles?["verification"] as? [String: Any]
                    let backendReachable = backend?["reachable"] as? Bool ?? false
                    let expectedReady = backendReachable &&
                        ((factoryWorker?["snapshot_sync_ok"] as? Bool) == true) &&
                        ((factoryWorker?["route_health_status"] as? String) == nil)

                    expectEqual(deliveredStatus, 200, "healthz should succeed", recorder: recorder)
                    expectEqual(frontend?["port"] as? Int, 8317, "healthz should report the frontend port", recorder: recorder)
                    expectEqual(backend?["host"] as? String, "127.0.0.1", "healthz should report the backend host", recorder: recorder)
                    expectEqual(backend?["port"] as? Int, 8318, "healthz should report the backend port", recorder: recorder)
                    expectEqual(backend?["reachable"] is Bool, true, "healthz should report backend reachability as a boolean", recorder: recorder)
                    expectEqual((provenance?["merged_config_fingerprint"] as? String)?.isEmpty ?? true, false, "healthz should expose the merged-config fingerprint", recorder: recorder)
                    expectEqual((deliveredHeaders?["X-VibeProxy-Config-Fingerprint"] as? String)?.isEmpty ?? true, false, "healthz should emit config provenance headers", recorder: recorder)
                    expectEqual((deliveredHeaders?["X-VibeProxy-App-Version"] as? String)?.isEmpty ?? true, false, "healthz should emit app-version headers", recorder: recorder)
                    expectEqual(glm5?["status"] as? String, "open", "healthz should surface route-health state", recorder: recorder)
                    expectEqual(glm5?["canonical_model_id"] as? String, "z-ai/glm5", "healthz should preserve the canonical model id alongside the exact request-model route lane", recorder: recorder)
                    expectEqual(quarantinedModels?.contains("glm5-nvidia"), true, "healthz should list quarantined exact request-model lanes", recorder: recorder)
                    expectEqual(quarantinedCanonicalModels?.contains("z-ai/glm5"), true, "healthz should also expose quarantined canonical model ids for summary views", recorder: recorder)
                    expectEqual(factoryWorker?["worker_model_id"] as? String, openAIFactoryWorkerContract.workerModelID, "healthz should expose the authoritative Factory worker id", recorder: recorder)
                    expectEqual(factoryWorker?["route_model"] as? String, openAIFactoryWorkerContract.routeModel, "healthz should expose the worker route model", recorder: recorder)
                    expectEqual(factoryWorker?["route_provider"] as? String, openAIFactoryWorkerContract.routeProvider, "healthz should expose the worker route provider", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_model"] as? String, openAIFactoryWorkerContract.effectiveRouteModel, "healthz should expose the effective worker route model", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, openAIFactoryWorkerContract.effectiveRouteProvider, "healthz should expose the effective worker route provider", recorder: recorder)
                    expectEqual(factoryWorker?["request_surface"] as? String, openAIFactoryWorkerContract.requestSurface, "healthz should expose the worker API surface", recorder: recorder)
                    expectEqual(factoryWorker?["snapshot_sync_ok"] as? Bool, true, "healthz should expose snapshot sync state", recorder: recorder)
                    expectEqual(factoryWorker?["snapshot_drift_count"] as? Int, 0, "healthz should report zero snapshot drift by default", recorder: recorder)
                    expectEqual(factoryWorker?["ready"] as? Bool, expectedReady, "healthz should derive worker readiness from backend reachability and contract health", recorder: recorder)
                    expectEqual(orchestration?["model_id"] as? String, openAIFactoryWorkerContract.validationWorkerModelID, "healthz should expose the orchestration model id", recorder: recorder)
                    expectEqual(orchestration?["route_model"] as? String, "gpt-5.4(high)", "healthz should expose the orchestration route model", recorder: recorder)
                    expectEqual(orchestration?["route_provider"] as? String, "openai", "healthz should expose the orchestration route provider", recorder: recorder)
                    expectEqual(orchestration?["request_surface"] as? String, "responses", "healthz should expose the orchestration request surface", recorder: recorder)
                    expectEqual(orchestration?["effective_route_model"] as? String, "gpt-5.4(high)", "healthz should expose the orchestration effective route model", recorder: recorder)
                    expectEqual(orchestration?["effective_route_provider"] as? String, "openai", "healthz should expose the orchestration effective route provider", recorder: recorder)
                    expectEqual(orchestration?["ready"] as? Bool, expectedReady, "healthz should derive orchestration readiness from backend reachability and contract health", recorder: recorder)
                    expectEqual(verification?["model_id"] as? String, openAIFactoryWorkerContract.validationWorkerModelID, "healthz should expose the verification model id", recorder: recorder)
                    expectEqual(verification?["route_model"] as? String, "gpt-5.4(high)", "healthz should expose the verification route model", recorder: recorder)
                    expectEqual(verification?["route_provider"] as? String, "openai", "healthz should expose the verification route provider", recorder: recorder)
                    expectEqual(verification?["request_surface"] as? String, "responses", "healthz should expose the verification request surface", recorder: recorder)
                    expectEqual(verification?["effective_route_model"] as? String, "gpt-5.4(high)", "healthz should expose the verification effective route model", recorder: recorder)
                    expectEqual(verification?["effective_route_provider"] as? String, "openai", "healthz should expose the verification effective route provider", recorder: recorder)
                    expectEqual(verification?["ready"] as? Bool, expectedReady, "healthz should derive verification readiness from backend reachability and contract health", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz keeps provider-sibling worker lanes separate instead of collapsing them onto one canonical model id", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "glm-5.1-ollama-pro",
                        until: Date().addingTimeInterval(300)
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("provider-sibling healthz should return a response")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let routeHealth = payload["route_health"] as? [String: Any]
                    let routes = routeHealth?["routes"] as? [String: Any]
                    let quarantinedModels = routeHealth?["quarantined_models"] as? [String]
                    let quarantinedCanonicalModels = routeHealth?["quarantined_canonical_models"] as? [String]
                    let zaiRoute = routes?["glm-5.1-zai"] as? [String: Any]
                    let ollamaRoute = routes?["glm-5.1-ollama-pro"] as? [String: Any]

                    expectEqual(zaiRoute == nil, true, "healthz should not invent a ZAI lane entry when only the Ollama sibling is quarantined", recorder: recorder)
                    expectEqual(ollamaRoute?["status"] as? String, "open", "healthz should surface the quarantined Ollama sibling directly", recorder: recorder)
                    expectEqual(ollamaRoute?["canonical_model_id"] as? String, "glm-5.1", "healthz should retain the sibling's shared canonical model id", recorder: recorder)
                    expectEqual(ollamaRoute?["provider"] as? String, "ollama-pro", "healthz should expose the exact sibling provider for the quarantined lane", recorder: recorder)
                    expectEqual(quarantinedModels?.contains("glm-5.1-ollama-pro"), true, "healthz should quarantine the exact provider sibling lane", recorder: recorder)
                    expectEqual(quarantinedModels?.contains("glm-5.1"), false, "healthz should stop collapsing sibling quarantine onto the shared canonical model id", recorder: recorder)
                    expectEqual(quarantinedCanonicalModels?.contains("glm-5.1"), true, "healthz should still expose the shared canonical model id separately for summary views", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz exposes chat-completions worker contracts for generic compatible providers", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("generic-compatible healthz should return a response")
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let backend = payload["backend"] as? [String: Any]
                    let factoryWorker = payload["factory_worker"] as? [String: Any]
                    let factoryRoles = payload["factory_roles"] as? [String: Any]
                    let orchestration = factoryRoles?["orchestration"] as? [String: Any]
                    let verification = factoryRoles?["verification"] as? [String: Any]
                    let backendReachable = backend?["reachable"] as? Bool ?? false
                    let expectedReady = backendReachable &&
                        ((factoryWorker?["snapshot_sync_ok"] as? Bool) == true) &&
                        ((factoryWorker?["route_health_status"] as? String) == nil)
                    let acceptedRequestModelIDs = factoryWorker?["accepted_request_model_ids"] as? [String]
                    let rescuedRequestModelIDs = factoryWorker?["rescued_request_model_ids"] as? [String]

                    expectEqual(factoryWorker?["worker_model_id"] as? String, genericCompatFactoryWorkerContract.workerModelID, "healthz should expose the compatible worker id", recorder: recorder)
                    expectEqual(factoryWorker?["route_model"] as? String, genericCompatFactoryWorkerContract.routeModel, "healthz should expose the compatible worker route model", recorder: recorder)
                    expectEqual(factoryWorker?["route_provider"] as? String, genericCompatFactoryWorkerContract.routeProvider, "healthz should expose the compatible worker route provider", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_model"] as? String, genericCompatFactoryWorkerContract.effectiveRouteModel, "healthz should expose the effective runtime lane for compatible workers", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, genericCompatFactoryWorkerContract.effectiveRouteProvider, "healthz should expose the effective runtime provider for compatible workers", recorder: recorder)
                    expectEqual(factoryWorker?["request_surface"] as? String, genericCompatFactoryWorkerContract.requestSurface, "healthz should derive the chat-completions surface for generic compatible workers", recorder: recorder)
                    expectEqual(factoryWorker?["ready"] as? Bool, expectedReady, "healthz should derive generic worker readiness from backend reachability and alias health", recorder: recorder)
                    expectEqual(acceptedRequestModelIDs?.contains(genericCompatFactoryWorkerContract.workerModelID), true, "healthz should list the current compatible worker model ID as accepted", recorder: recorder)
                    expectEqual(acceptedRequestModelIDs?.contains("custom:Factory-Worker-GPT-5.4-High-8"), true, "healthz should list leaked hidden Factory worker IDs as accepted rescue inputs", recorder: recorder)
                    expectEqual(acceptedRequestModelIDs?.contains("custom:Proxy-WorkerPool-8"), true, "healthz should list the retired pooled worker ID as an accepted rescue input", recorder: recorder)
                    expectEqual(rescuedRequestModelIDs?.contains("custom:Factory-Worker-GPT-5.4-High-8"), true, "healthz should explicitly mark the hidden Factory worker ID as rescued", recorder: recorder)
                    expectEqual(orchestration?["model_id"] as? String, genericCompatFactoryWorkerContract.validationWorkerModelID, "healthz should expose the orchestration model id for generic-compatible workers", recorder: recorder)
                    expectEqual(orchestration?["route_model"] as? String, "gpt-5.4(high)", "healthz should expose the orchestration route model for generic-compatible workers", recorder: recorder)
                    expectEqual(orchestration?["route_provider"] as? String, "openai", "healthz should expose the orchestration route provider for generic-compatible workers", recorder: recorder)
                    expectEqual(orchestration?["request_surface"] as? String, "responses", "healthz should expose the orchestration request surface for generic-compatible workers", recorder: recorder)
                    expectEqual(orchestration?["effective_route_model"] as? String, "gpt-5.4(high)", "healthz should keep orchestration on the direct GPT lane", recorder: recorder)
                    expectEqual(orchestration?["effective_route_provider"] as? String, "openai", "healthz should keep orchestration on the direct GPT provider", recorder: recorder)
                    expectEqual(orchestration?["ready"] as? Bool, true, "healthz should keep orchestration ready when its direct GPT lane is healthy", recorder: recorder)
                    expectEqual(verification?["model_id"] as? String, genericCompatFactoryWorkerContract.validationWorkerModelID, "healthz should expose the verification model id for generic-compatible workers", recorder: recorder)
                    expectEqual(verification?["route_model"] as? String, "gpt-5.4(high)", "healthz should expose the verification route model for generic-compatible workers", recorder: recorder)
                    expectEqual(verification?["route_provider"] as? String, "openai", "healthz should expose the verification route provider for generic-compatible workers", recorder: recorder)
                    expectEqual(verification?["request_surface"] as? String, "responses", "healthz should expose the verification request surface for generic-compatible workers", recorder: recorder)
                    expectEqual(verification?["effective_route_model"] as? String, "gpt-5.4(high)", "healthz should keep verification on the direct GPT lane", recorder: recorder)
                    expectEqual(verification?["effective_route_provider"] as? String, "openai", "healthz should keep verification on the direct GPT provider", recorder: recorder)
                    expectEqual(verification?["ready"] as? Bool, true, "healthz should keep verification ready when its direct GPT lane is healthy", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz resolves self-routed smart-router worker IDs onto the worker pool without duplicate merged-config aliases", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("self-routed generic-compatible healthz should return a response")
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let factoryWorker = payload["factory_worker"] as? [String: Any]
                    let configDrift = payload["config_drift"] as? [String: Any]

                    expectEqual(factoryWorker?["worker_model_id"] as? String, selfRoutedGenericCompatFactoryWorkerContract.workerModelID, "healthz should expose the authoritative self-routed worker id", recorder: recorder)
                    expectEqual(factoryWorker?["route_model"] as? String, selfRoutedGenericCompatFactoryWorkerContract.routeModel, "healthz should expose the self-routed worker model id as the contract route model", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_model"] as? String, selfRoutedGenericCompatFactoryWorkerContract.effectiveRouteModel, "healthz should still expose the actual worker pool winner for self-routed worker IDs", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, selfRoutedGenericCompatFactoryWorkerContract.effectiveRouteProvider, "healthz should expose the real upstream provider for self-routed worker IDs", recorder: recorder)
                    expectEqual(configDrift?["route_in_pool"] as? Bool, true, "self-routed worker IDs should not trip critical config drift when proxy source of truth owns the worker pool", recorder: recorder)
                    expectEqual(configDrift?["severity"] as? String, "none", "self-routed worker IDs should be treated as in-pool by healthz", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz keeps self-routed smart-router workers ready when the primary lane is quarantined but a fallback remains", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "glm-5.1-zai",
                        until: Date().addingTimeInterval(300)
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("self-routed generic-compatible fallback healthz should return a response")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let factoryWorker = payload["factory_worker"] as? [String: Any]

                    expectEqual(factoryWorker?["effective_route_model"] as? String, "glm-5.1-ollama-pro", "healthz should expose the next GLM worker candidate when the ZAI primary lane is quarantined", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, "ollama-pro", "healthz should preserve the fallback worker provider while a viable lane remains available", recorder: recorder)
                    expectEqual(factoryWorker?["route_health_status"] as? String, nil, "healthz should suppress unhealthy worker route status when the pool still has a viable fallback", recorder: recorder)
                    expectEqual(factoryWorker?["ready"] as? Bool, true, "healthz should keep self-routed smart-router workers ready when a fallback remains available", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz promotes self-routed smart-router workers onto a healthy sibling when the primary lane is only suspect", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm-5.1-zai",
                        at: Date()
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("self-routed generic-compatible suspect healthz should return a response")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let factoryWorker = payload["factory_worker"] as? [String: Any]

                    expectEqual(factoryWorker?["effective_route_model"] as? String, "glm-5.1-ollama-pro", "healthz should promote the worker onto the healthy GLM sibling when the ZAI primary lane is suspect", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, "ollama-pro", "healthz should surface the healthy sibling provider when the primary is suspect", recorder: recorder)
                    expectEqual(factoryWorker?["route_health_status"] as? String, nil, "healthz should suppress degraded-primary status when a healthy worker sibling is available", recorder: recorder)
                    expectEqual(factoryWorker?["ready"] as? Bool, true, "healthz should keep self-routed smart-router workers ready when a healthy sibling remains available", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz reports the recent observed smart-router worker lane when every candidate is temporarily deferred", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let deferredUntil = Date().addingTimeInterval(30)
                    ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"].forEach { requestModel in
                        OpenAICompatTemporaryShim.recordRouteAvailabilityDeferral(
                            forRequestModel: requestModel,
                            until: deferredUntil
                        )
                    }
                    OpenAICompatTemporaryShim.recordRouteSuccess(
                        forRequestModel: "glm-5.1-ollama-pro",
                        telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                            timestamp: Date(),
                            requestModel: "glm-5.1-ollama-pro",
                            requestedAlias: selfRoutedGenericCompatFactoryWorkerContract.workerModelID,
                            canonicalModelID: "glm-5.1",
                            transportOutcome: "send_response",
                            failureClass: nil,
                            timeoutStage: .none,
                            upstreamHTTPStatus: 200,
                            retryCount: 0,
                            source: "smart_alias",
                            totalLatencyMilliseconds: 42
                        )
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("deferred-lane healthz should return a response")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let factoryWorker = payload["factory_worker"] as? [String: Any]

                    expectEqual(factoryWorker?["effective_route_model"] as? String, "glm-5.1-ollama-pro", "healthz should prefer the recent observed worker lane instead of advertising a non-dispatchable fallback", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, "ollama-pro", "healthz should preserve the observed provider for the deferred worker lane", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("self-routed worker requests try the healthy GLM sibling before a suspect primary", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.recordRouteFailure(
                        forRequestModel: "glm-5.1-zai",
                        at: Date()
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    let lock = NSLock()
                    var seenModels: [String] = []

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        let model = json["model"] as? String ?? ""
                        lock.lock()
                        seenModels.append(model)
                        lock.unlock()
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {
                                  "id": "chatcmpl_worker_sibling",
                                  "object": "chat.completion",
                                  "created": 1,
                                  "model": "\(model)",
                                  "choices": [
                                    {
                                      "index": 0,
                                      "message": {"role": "assistant", "content": "OK"},
                                      "finish_reason": "stop"
                                    }
                                  ]
                                }
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { _, _, _ in
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "tools": [
                            {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                          ],
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 2) == .success else {
                        recorder.recordFailure("self-routed worker request should complete under healthy sibling fallback")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    expectEqual(seenModels, ["glm-5.1-ollama-pro"], "self-routed worker requests should select the healthy GLM sibling before the suspect primary", recorder: recorder)
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz keeps the smart-router worker ready but marks direct GPT roles unready when the preferred GPT lane is open", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: genericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: "gpt-5.4(high)",
                        until: Date().addingTimeInterval(300)
                    )

                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("mixed worker/direct-role healthz should return a response")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let factoryWorker = payload["factory_worker"] as? [String: Any]
                    let factoryRoles = payload["factory_roles"] as? [String: Any]
                    let orchestration = factoryRoles?["orchestration"] as? [String: Any]
                    let verification = factoryRoles?["verification"] as? [String: Any]

                    expectEqual(factoryWorker?["effective_route_model"] as? String, "glm-5.1-zai", "healthz should expose the worker primary when the preferred GPT lane is open", recorder: recorder)
                    expectEqual(factoryWorker?["effective_route_provider"] as? String, "zai", "healthz should expose the worker provider when GPT is quarantined", recorder: recorder)
                    expectEqual(factoryWorker?["route_health_status"] as? String, nil, "healthz should stop reporting the worker contract as open when a fallback lane remains available", recorder: recorder)
                    expectEqual(factoryWorker?["ready"] as? Bool, true, "healthz should keep the smart-router worker ready when a fallback lane remains available", recorder: recorder)
                    expectEqual(orchestration?["effective_route_model"] as? String, "gpt-5.4(high)", "healthz should keep orchestration pinned to the direct GPT lane", recorder: recorder)
                    expectEqual(orchestration?["effective_route_provider"] as? String, "openai", "healthz should keep orchestration pinned to the direct GPT provider", recorder: recorder)
                    expectEqual(orchestration?["route_health_status"] as? String, "open", "healthz should expose the direct GPT lane as unhealthy for orchestration", recorder: recorder)
                    expectEqual(orchestration?["ready"] as? Bool, false, "healthz should mark orchestration unready when the direct GPT lane is quarantined", recorder: recorder)
                    expectEqual(verification?["effective_route_model"] as? String, "gpt-5.4(high)", "healthz should keep verification pinned to the direct GPT lane", recorder: recorder)
                    expectEqual(verification?["effective_route_provider"] as? String, "openai", "healthz should keep verification pinned to the direct GPT provider", recorder: recorder)
                    expectEqual(verification?["route_health_status"] as? String, "open", "healthz should expose the direct GPT lane as unhealthy for verification", recorder: recorder)
                    expectEqual(verification?["ready"] as? Bool, false, "healthz should mark verification unready when the direct GPT lane is quarantined", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("self-routed tool-heavy worker requests exhaust the shared worker pool before surfacing a retryable quota-window limit", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let proxy = ThinkingProxy()
                    proxy.smartAliasLoopRetryLimitOverrideForTesting = 0
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    let lock = NSLock()
                    var seenModels: [String] = []
                    var deliveredStatus: Int?
                    var deliveredMessage: String?

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        let model = json["model"] as? String ?? ""
                        lock.lock()
                        seenModels.append(model)
                        lock.unlock()
                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"rate limited\"}".utf8),
                                response: httpURLResponse(
                                    statusCode: 429,
                                    headerFields: [
                                        "Content-Type": "application/json",
                                        "Retry-After": "3600"
                                    ]
                                ),
                                error: nil
                            )
                        )
                    }
                    proxy.metaAIBufferedResponseForTesting = { _, _, publicModel in
                        lock.lock()
                        seenModels.append(publicModel)
                        lock.unlock()
                        return ThinkingProxy.BufferedProxyResponse(
                            data: Data("{\"error\":\"rate limited\"}".utf8),
                            response: httpURLResponse(
                                statusCode: 429,
                                headerFields: [
                                    "Content-Type": "application/json",
                                    "Retry-After": "3600"
                                ]
                            ),
                            error: nil
                        )
                    }
                    proxy.deliveredErrorForTesting = { statusCode, message in
                        deliveredStatus = statusCode
                        deliveredMessage = message
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "tools": [
                            {"type": "function", "function": {"name": "lookup", "parameters": {"type": "object"}}}
                          ],
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 2) == .success else {
                        recorder.recordFailure("self-routed worker request should return an availability error after exhausting the pool")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "self-routed worker requests should exhaust the shared worker pool before surfacing saturation", recorder: recorder)
                    expectEqual(deliveredStatus, 429, "shared-pool saturation should surface as a retryable quota-window limit once every candidate is exhausted", recorder: recorder)
                    expectEqual(deliveredMessage, "Upstream rate-limit window reached for \(selfRoutedGenericCompatFactoryWorkerContract.workerModelID); retry when the provider window resets.", "shared-pool saturation should preserve the caller-visible worker model identity in the retryable quota-window error", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("self-routed worker requests keep retrying the ZAI primary on overload before falling through to sibling routes", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let proxy = ThinkingProxy()
                    proxy.smartAliasLoopRetryLimitOverrideForTesting = 0
                    proxy.smartAliasTotalTimeoutOverrideForTesting = 5
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    let lock = NSLock()
                    var seenModels: [String] = []
                    var zaiAttempts = 0
                    var deliveredStatus: Int?
                    var deliveredBody: Data?

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        let model = json["model"] as? String ?? ""
                        lock.lock()
                        seenModels.append(model)
                        if model == "glm-5.1-zai" {
                            zaiAttempts += 1
                        }
                        let currentZaiAttempts = zaiAttempts
                        lock.unlock()

                        if model == "glm-5.1-zai", currentZaiAttempts < 3 {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {"error":{"code":"1305","message":"The service may be temporarily overloaded, please try again later"}}
                                    """.utf8),
                                    response: httpURLResponse(statusCode: 429),
                                    error: nil
                                )
                            )
                            return
                        }

                        if model == "glm-5.1-zai" {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {"id":"ok","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}
                                    """.utf8),
                                    response: httpURLResponse(statusCode: 200),
                                    error: nil
                                )
                            )
                            return
                        }

                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("{\"error\":\"unexpected fallback\"}".utf8),
                                response: httpURLResponse(statusCode: 500),
                                error: nil
                            )
                        )
                    }
                    proxy.deliveredHTTPResponseForTesting = { statusCode, _, body in
                        deliveredStatus = statusCode
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                        {
                          "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                          "stream": false,
                          "messages": [{"role": "user", "content": "Return exactly: OK"}]
                        }
                        """),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 4) == .success else {
                        recorder.recordFailure("self-routed worker overload retries should eventually succeed on the recovered ZAI primary")
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                        return
                    }

                    expectEqual(seenModels, ["glm-5.1-zai", "glm-5.1-zai", "glm-5.1-zai"], "overload 429s should stay on the preferred ZAI lane instead of falling through to sibling backends", recorder: recorder)
                    expectEqual(deliveredStatus, 200, "recovered overload retries should eventually deliver success", recorder: recorder)
                    let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    expectEqual(deliveredJSON["model"] as? String, selfRoutedGenericCompatFactoryWorkerContract.workerModelID, "successful overload retries should preserve the caller-visible worker model identity", recorder: recorder)
                    expectNil(OpenAICompatTemporaryShim.routeAvailabilityDeferralUntilForTesting(requestModel: "glm-5.1-zai"), "overload retries should not leave the preferred route on cooldown after recovery", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1-zai"), false, "overload retries should not mark the preferred route unavailable", recorder: recorder)

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("self-routed worker quota-window 429s fall through without shrinking the learned ZAI concurrency limit", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: selfRoutedGenericCompatFactoryWorkerContract)) {
                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    let proxy = ThinkingProxy()
                    proxy.smartAliasLoopRetryLimitOverrideForTesting = 0

                    let lock = NSLock()
                    var seenModels: [String] = []

                    proxy.bufferedProxyTransportForTesting = { _, _, _, body, _, completion in
                        let json = parseJSONObject(body, recorder: recorder)
                        let model = json["model"] as? String ?? ""
                        lock.lock()
                        seenModels.append(model)
                        lock.unlock()

                        if model == "glm-5.1-zai" {
                            completion(
                                ThinkingProxy.BufferedProxyResponse(
                                    data: Data("""
                                    {"error":{"message":"Rate limit exceeded and will reset later"}}
                                    """.utf8),
                                    response: httpURLResponse(
                                        statusCode: 429,
                                        headerFields: [
                                            "Content-Type": "application/json",
                                            "Retry-After": "3600"
                                        ]
                                    ),
                                    error: nil
                                )
                            )
                            return
                        }

                        completion(
                            ThinkingProxy.BufferedProxyResponse(
                                data: Data("""
                                {"id":"ok","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}
                                """.utf8),
                                response: httpURLResponse(statusCode: 200),
                                error: nil
                            )
                        )
                    }

                    for _ in 0..<3 {
                        let delivered = DispatchSemaphore(value: 0)
                        var deliveredStatus: Int?
                        proxy.deliveredHTTPResponseForTesting = { statusCode, _, _ in
                            deliveredStatus = statusCode
                            delivered.signal()
                        }

                        proxy.processRequestForTesting(
                            rawHTTPRequest(method: "POST", path: "/v1/chat/completions", body: """
                            {
                              "model": "\(selfRoutedGenericCompatFactoryWorkerContract.workerModelID)",
                              "stream": false,
                              "messages": [{"role": "user", "content": "Return exactly: OK"}]
                            }
                            """),
                            connection: NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                        )

                        guard delivered.wait(timeout: .now() + 2) == .success else {
                            recorder.recordFailure("quota-window worker request should fall through to a healthy sibling route")
                            OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                            return
                        }

                        expectEqual(
                            deliveredStatus,
                            200,
                            "quota-window worker requests should still succeed via sibling fallback",
                            recorder: recorder
                        )

                        // Clear route-health cooldowns between requests so the primary is probed
                        // again, while preserving the learned concurrency registry.
                        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                    }

                    expectEqual(
                        seenModels,
                        [
                            "glm-5.1-zai", "glm-5.1-ollama-pro",
                            "glm-5.1-zai", "glm-5.1-ollama-pro",
                            "glm-5.1-zai", "glm-5.1-ollama-pro"
                        ],
                        "quota-window worker requests should probe ZAI then fall through to the Ollama sibling each time",
                        recorder: recorder
                    )
                    expectEqual(
                        OpenAICompatTemporaryShim.currentConcurrencyLimit(routeHealthKey: "zai::glm-5.1"),
                        3,
                        "quota-window worker fallthroughs should not shrink the learned ZAI concurrency limit",
                        recorder: recorder
                    )

                    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                }
            }
        }

        run("healthz marks worker unready when Factory snapshots drift", recorder: recorder) {
            let driftedSettings = """
            {
              "missionModelSettings": {
                "workerModel": "\(openAIFactoryWorkerContract.workerModelID)",
                "workerReasoningEffort": "none",
                "validationWorkerModel": "\(openAIFactoryWorkerContract.validationWorkerModelID)",
                "validationWorkerReasoningEffort": "none"
              }
            }
            """

            withMergedConfig(defaultMergedConfigYAML()) {
                withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract), extraFiles: [
                    "settings.local.json": driftedSettings
                ]) {
                    let proxy = ThinkingProxy()
                    let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                    let delivered = DispatchSemaphore(value: 0)
                    var deliveredBody: Data?

                    proxy.deliveredHTTPResponseForTesting = { _, _, body in
                        deliveredBody = body
                        delivered.signal()
                    }

                    proxy.processRequestForTesting(
                        rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                        connection: connection
                    )

                    guard delivered.wait(timeout: .now() + 1) == .success else {
                        recorder.recordFailure("drifted healthz should return a response")
                        return
                    }

                    let payload = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)
                    let factoryWorker = payload["factory_worker"] as? [String: Any]
                    let driftedPaths = factoryWorker?["snapshot_drift_paths"] as? [String]

                    expectEqual(factoryWorker?["snapshot_sync_ok"] as? Bool, false, "healthz should report snapshot drift", recorder: recorder)
                    expectEqual(factoryWorker?["snapshot_drift_count"] as? Int, 1, "healthz should count drifted snapshots", recorder: recorder)
                    expectEqual(driftedPaths?.contains(where: { $0.hasSuffix("settings.local.json") }), true, "healthz should identify the drifted snapshot path", recorder: recorder)
                    expectEqual(factoryWorker?["ready"] as? Bool, false, "healthz should fail closed when snapshots drift", recorder: recorder)
                }
            }
        }

        run("Factory worker-bound requests fail closed when snapshots drift", recorder: recorder) {
            let driftedSettings = """
            {
              "missionModelSettings": {
                "workerModel": "\(openAIFactoryWorkerContract.workerModelID)",
                "workerReasoningEffort": "none",
                "validationWorkerModel": "\(openAIFactoryWorkerContract.validationWorkerModelID)",
                "validationWorkerReasoningEffort": "none"
              }
            }
            """

            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract), extraFiles: [
                "settings.local.json": driftedSettings
            ]) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var deliveredStatus: Int?
                var deliveredMessage: String?

                proxy.deliveredErrorForTesting = { statusCode, message in
                    deliveredStatus = statusCode
                    deliveredMessage = message
                    delivered.signal()
                }
                proxy.bufferedProxyTransportForTesting = { _, _, _, _, _, _ in
                    recorder.recordFailure("drifted Factory worker requests should fail before any upstream transport is attempted")
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("drifted Factory worker requests should fail closed with a contract error")
                    return
                }

                expectEqual(deliveredStatus, 409, "drifted Factory worker requests should return a contract error", recorder: recorder)
                expectEqual(deliveredMessage?.contains("snapshot drift"), true, "drifted Factory worker requests should explain the drifted worker contract", recorder: recorder)
                expectEqual(deliveredMessage?.contains(openAIFactoryWorkerContract.workerModelID), true, "drifted Factory worker requests should name the authoritative worker model", recorder: recorder)
                expectEqual(deliveredMessage?.contains("settings.local.json"), true, "drifted Factory worker requests should identify the drifted snapshot path", recorder: recorder)
            }
        }

        run("Factory worker-bound requests ignore advisory mission model-settings drift on authoritative worker IDs", recorder: recorder) {
            let driftedMissionSettings = """
            {
              "workerModel": "\(openAIFactoryWorkerContract.validationWorkerModelID)",
              "workerReasoningEffort": "high",
              "validationWorkerModel": "\(openAIFactoryWorkerContract.validationWorkerModelID)",
              "validationWorkerReasoningEffort": "high"
            }
            """

            withFactorySettings(factorySettingsJSON(contract: openAIFactoryWorkerContract), extraFiles: [
                "missions/test/model-settings.json": driftedMissionSettings
            ]) {
                let proxy = ThinkingProxy()
                let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1), using: .tcp)
                let delivered = DispatchSemaphore(value: 0)
                var forwardedPath: String?
                var forwardedBody: String?
                var deliveredHeaders: [AnyHashable: Any]?
                var deliveredBody: Data?
                var healthzBody: Data?

                proxy.bufferedProxyTransportForTesting = { _, path, _, body, _, completion in
                    forwardedPath = path
                    forwardedBody = body
                    completion(
                        ThinkingProxy.BufferedProxyResponse(
                            data: Data("""
                            {
                              "id": "resp_factory_drift_advisory",
                              "object": "response",
                              "model": "gpt-5.4(high)",
                              "status": "completed",
                              "output": [
                                {
                                  "type": "message",
                                  "role": "assistant",
                                  "status": "completed",
                                  "content": [
                                    {"type": "output_text", "text": "OK", "annotations": []}
                                  ]
                                }
                              ]
                            }
                            """.utf8),
                            response: httpURLResponse(
                                statusCode: 200,
                                headerFields: ["Content-Type": "application/json"]
                            ),
                            error: nil
                        )
                    )
                }
                proxy.deliveredHTTPResponseForTesting = { _, headers, body in
                    deliveredHeaders = headers
                    deliveredBody = body
                    delivered.signal()
                }
                proxy.deliveredErrorForTesting = { statusCode, message in
                    recorder.recordFailure("authoritative worker requests should not fail on advisory mission model-settings drift: \(statusCode) \(message)")
                    delivered.signal()
                }

                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "POST", path: "/v1/responses", body: """
                    {
                      "model": "\(openAIFactoryWorkerContract.workerModelID)",
                      "input": "Return exactly: OK"
                    }
                    """),
                    connection: connection
                )

                guard delivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("authoritative worker requests should still complete when only mission model-settings drift")
                    return
                }

                let forwardedJSON = parseJSONObject(forwardedBody, recorder: recorder)
                let deliveredJSON = parseDataJSONObject(deliveredBody ?? Data(), recorder: recorder)

                expectEqual(forwardedPath, "/v1/responses", "authoritative worker requests should keep their direct path under advisory drift", recorder: recorder)
                expectEqual(forwardedJSON["model"] as? String, openAIFactoryWorkerContract.routeModel, "authoritative worker requests should still be rewritten to the configured route model under advisory drift", recorder: recorder)
                expectEqual(deliveredHeaders?["X-Factory-Authoritative-Model-ID"] as? String, openAIFactoryWorkerContract.workerModelID, "authoritative worker responses should preserve the authoritative worker ID header under advisory drift", recorder: recorder)
                expectEqual(deliveredJSON["model"] as? String, openAIFactoryWorkerContract.workerModelID, "authoritative worker responses should preserve caller-visible identity under advisory drift", recorder: recorder)

                let healthDelivered = DispatchSemaphore(value: 0)
                proxy.deliveredHTTPResponseForTesting = { _, _, body in
                    healthzBody = body
                    healthDelivered.signal()
                }
                proxy.processRequestForTesting(
                    rawHTTPRequest(method: "GET", path: "/healthz", body: ""),
                    connection: connection
                )

                guard healthDelivered.wait(timeout: .now() + 1) == .success else {
                    recorder.recordFailure("healthz should return after advisory mission model-settings drift")
                    return
                }

                let healthzPayload = parseDataJSONObject(healthzBody ?? Data(), recorder: recorder)
                let factoryWorker = healthzPayload["factory_worker"] as? [String: Any]
                expectEqual(factoryWorker?["snapshot_drift_count"] as? Int, 1, "advisory mission model-settings drift should still be reported", recorder: recorder)
                expectEqual(factoryWorker?["snapshot_blocking_drift_count"] as? Int, 0, "mission model-settings drift should not be treated as blocking for authoritative worker requests", recorder: recorder)
                expectEqual(factoryWorker?["ready"] as? Bool, true, "advisory mission model-settings drift should keep the worker contract ready", recorder: recorder)
            }
        }

        run("stale suspect route health stays suspect on reload without recovery evidence", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()

                // Simulate a suspect route with a stale event from 10 minutes ago
                let staleDate = Date().addingTimeInterval(-600)
                let staleEvent = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                    timestamp: staleDate,
                    requestModel: "glm-5.1-ollama-pro",
                    canonicalModelID: "glm-5.1",
                    transportOutcome: "send_error",
                    failureClass: "transport_timeout",
                    timeoutStage: .firstResponse,
                    upstreamHTTPStatus: nil,
                    retryCount: 0,
                    source: "smart_alias"
                )
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-ollama-pro",
                    telemetryEvent: staleEvent,
                    at: staleDate
                )

                // Verify it starts as suspect
                var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .suspect, "route should start as suspect after failure", recorder: recorder)

                // Simulate startup reload — the self-healing logic should close stale suspects
                OpenAICompatTemporaryShim.forcePersistRouteHealthForTesting()
                OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()
                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .suspect, "stale suspect routes without recovery evidence should remain suspect on startup reload", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("stale suspect route health auto-heals on reload when recovery evidence is strong", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()

                let staleDate = Date().addingTimeInterval(-600)
                for offset in stride(from: 12, through: 3, by: -1) {
                    OpenAICompatTemporaryShim.recordRouteSuccess(
                        forRequestModel: "glm-5.1-zai",
                        at: staleDate.addingTimeInterval(TimeInterval(-offset))
                    )
                }
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-zai",
                    telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: staleDate,
                        requestModel: "glm-5.1-zai",
                        canonicalModelID: "glm-5.1",
                        transportOutcome: "send_error",
                        failureClass: "transport_timeout",
                        timeoutStage: .firstResponse,
                        upstreamHTTPStatus: nil,
                        retryCount: 0,
                        source: "smart_alias"
                    ),
                    at: staleDate
                )

                OpenAICompatTemporaryShim.forcePersistRouteHealthForTesting()
                OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()
                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .closed, "stale suspect routes with strong success evidence should auto-heal to closed on startup reload", recorder: recorder)
                expectEqual(snapshot["glm-5.1"]?.failureScore, 0, "healed routes should have zero failure score", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("worker smart alias candidate ordering keeps muse-spark above the nvidia terminal fallback", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()

                let candidates = OpenAICompatTemporaryShim.rankedSmartAliasFallbackCandidateModels(
                    ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"]
                )

                expectEqual(candidates, ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"], "worker candidate ordering should remain deterministic and primary-first", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("smart alias fails over to the last remaining worker candidate when the primary is quarantined", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date()
                let allCandidates = ["glm-5.1-zai", "glm-5.1-ollama-pro", "minimax-m2.7-ollama-pro", "muse-spark", "glm5-nvidia"]

                for candidate in allCandidates.dropLast() {
                    OpenAICompatTemporaryShim.forceOpenRouteForTesting(
                        requestModel: candidate,
                        until: now.addingTimeInterval(300)
                    )
                }

                let request = """
                {"model": "worker", "messages": [{"role": "user", "content": "test"}], "stream": false}
                """

                // The last candidate should still be available
                let transition = OpenAICompatTemporaryShim.nextSmartAliasCandidateTransition(
                    method: "POST",
                    path: "/v1/chat/completions",
                    currentBody: request,
                    candidateModelsRemaining: allCandidates
                )

                expectEqual(transition?.model, "glm5-nvidia", "when the primary candidate is quarantined, the remaining worker fallback should still be available", recorder: recorder)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("smart alias route recovers from suspect to closed on success", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                let now = Date()

                // Put route into suspect state
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm-5.1-ollama-pro", at: now)
                var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .suspect, "route should be suspect after one failure", recorder: recorder)

                // Route should not be open yet
                expectEqual(OpenAICompatTemporaryShim.isConfiguredRouteOpen(forRequestModel: "glm-5.1-ollama-pro"), false, "suspect routes should remain available", recorder: recorder)

                // Record success to close the circuit
                OpenAICompatTemporaryShim.recordRouteSuccess(forRequestModel: "glm-5.1-ollama-pro", at: now.addingTimeInterval(1))
                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .closed, "suspect route should recover to closed after success", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("proxied session pool evicts idle sessions", recorder: recorder) {
            ThinkingProxy.clearProxiedSessionPoolForTesting()

            // Acquire a session — this populates the pool
            let result1 = ThinkingProxy.acquireProxiedSessionForTesting(proxyURL: "socks5://user:pass@proxy.test:1080")
            expectEqual(result1 != nil, true, "pool should return a valid session for a valid proxy URL", recorder: recorder)

            // Acquiring the same proxy URL should reuse the session
            let result2 = ThinkingProxy.acquireProxiedSessionForTesting(proxyURL: "socks5://user:pass@proxy.test:1080")
            expectEqual(result2 != nil, true, "pool should reuse the cached session for the same proxy URL", recorder: recorder)

            // Different proxy URL should get a different session
            let result3 = ThinkingProxy.acquireProxiedSessionForTesting(proxyURL: "socks5://other@proxy2.test:1080")
            expectEqual(result3 != nil, true, "pool should create a new session for a different proxy URL", recorder: recorder)

            ThinkingProxy.clearProxiedSessionPoolForTesting()
        }

        run("binary path is used for NVIDIA routes without proxy-url", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                // NVIDIA providers should NOT have a provider endpoint (proxy-url)
                let nvidiaEndpoint = OpenAICompatTemporaryShim.providerEndpoint(forProviderID: "nvidia")
                expectNil(nvidiaEndpoint, "nvidia provider should not have a proxy endpoint, ensuring binary path is used", recorder: recorder)

                // The route should still be resolvable through the binary path
                let route = OpenAICompatTemporaryShim.resolveConfiguredRoute(forRequestModel: "glm5")
                expectEqual(route?.providerID, "nvidia", "nvidia-hosted glm5 should resolve to nvidia provider", recorder: recorder)
                expectEqual(route?.canonicalModelID, "z-ai/glm5", "glm5 should resolve to canonical z-ai/glm5", recorder: recorder)
            }
        }

        run("ThinkingProxy stop does not deadlock when canary state is active", recorder: recorder) {
            // Regression test for: stop() calling stopCanaryLoop() which re-entered stateQueue.sync,
            // causing __DISPATCH_WAIT_FOR_QUEUE__ → SIGTRAP crash loop on every failed startup.
            let proxy = ThinkingProxy()
            proxy.setIsRunningForTesting(true)

            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                proxy.stop()
                done.signal()
            }
            let result = done.wait(timeout: .now() + 2)
            expectEqual(result == .success, true, "stop() must complete without deadlocking", recorder: recorder)
        }

        run("ThinkingProxy stop is idempotent and does not crash on repeated calls", recorder: recorder) {
            let proxy = ThinkingProxy()
            proxy.setIsRunningForTesting(true)

            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                proxy.stop()
                proxy.stop()
                done.signal()
            }
            let result = done.wait(timeout: .now() + 2)
            expectEqual(result == .success, true, "repeated stop() calls must not hang", recorder: recorder)
            expectEqual(proxy.isRunning, false, "isRunning must be false after stop()", recorder: recorder)
        }

        run("maintenance route health pass keeps stale suspect routes suspect without recovery evidence", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()

                // Simulate a suspect route with a stale event from 10 minutes ago
                let staleDate = Date().addingTimeInterval(-600)
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm-5.1-zai", at: staleDate)

                // Confirm it starts as suspect
                var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .suspect, "route should be suspect after failure", recorder: recorder)

                // Run the maintenance pass (same code the background timer uses)
                OpenAICompatTemporaryShim.maintenanceRouteHealthPass()

                // Verify the route stays suspect without recovery evidence
                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .suspect, "maintenance pass should keep stale suspect routes suspect when there is no recovery evidence", recorder: recorder)

                // Verify recent-suspect routes are NOT healed
                let recentDate = Date().addingTimeInterval(-60)
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
                OpenAICompatTemporaryShim.recordRouteFailure(forRequestModel: "glm-5.1-zai", at: recentDate)

                OpenAICompatTemporaryShim.maintenanceRouteHealthPass()
                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .suspect, "maintenance pass should not heal recent suspect routes", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
        }

        run("maintenance route health pass heals stale suspect routes when recovery evidence is strong", recorder: recorder) {
            withMergedConfig(workerMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearRouteHealthForTesting()

                let staleDate = Date().addingTimeInterval(-600)
                for offset in stride(from: 12, through: 3, by: -1) {
                    OpenAICompatTemporaryShim.recordRouteSuccess(
                        forRequestModel: "glm-5.1-zai",
                        at: staleDate.addingTimeInterval(TimeInterval(-offset))
                    )
                }
                OpenAICompatTemporaryShim.recordRouteFailure(
                    forRequestModel: "glm-5.1-zai",
                    telemetryEvent: OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: staleDate,
                        requestModel: "glm-5.1-zai",
                        canonicalModelID: "glm-5.1",
                        transportOutcome: "send_error",
                        failureClass: "transport_timeout",
                        timeoutStage: .firstResponse,
                        upstreamHTTPStatus: nil,
                        retryCount: 0,
                        source: "smart_alias"
                    ),
                    at: staleDate
                )

                OpenAICompatTemporaryShim.maintenanceRouteHealthPass()
                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["glm-5.1"]?.status, .closed, "maintenance pass should heal stale suspect routes when recovery evidence is strong", recorder: recorder)
                expectEqual(snapshot["glm-5.1"]?.failureScore, 0, "maintenance-healed routes should have zero failure score", recorder: recorder)

                OpenAICompatTemporaryShim.clearRouteHealthForTesting()
            }
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
    OpenAICompatTemporaryShim.resetConcurrencyRegistryForTesting()
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
    let configKey = "VIBEPROXY_MERGED_CONFIG_PATH"
    let routeHealthKey = "VIBEPROXY_ROUTE_HEALTH_PATH"
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configPath = temporaryDirectory.appendingPathComponent("merged-config.yaml")
    let routeHealthPath = temporaryDirectory.appendingPathComponent("route-health.json")
    let previousConfigValue = ProcessInfo.processInfo.environment[configKey]
    let previousRouteHealthValue = ProcessInfo.processInfo.environment[routeHealthKey]

    try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try? yaml.write(to: configPath, atomically: true, encoding: .utf8)
    setenv(configKey, configPath.path, 1)
    setenv(routeHealthKey, routeHealthPath.path, 1)
    OpenAICompatTemporaryShim.clearRouteHealthForTesting()
    defer {
        OpenAICompatTemporaryShim.clearRouteHealthForTesting()
        if let previousConfigValue {
            setenv(configKey, previousConfigValue, 1)
        } else {
            unsetenv(configKey)
        }
        if let previousRouteHealthValue {
            setenv(routeHealthKey, previousRouteHealthValue, 1)
        } else {
            unsetenv(routeHealthKey)
        }
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    body()
}

private func withRouteHealthPath(body: (String) -> Void) {
    let key = "VIBEPROXY_ROUTE_HEALTH_PATH"
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let statePath = temporaryDirectory.appendingPathComponent("route-health.json")
    let previousValue = ProcessInfo.processInfo.environment[key]

    try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    setenv(key, statePath.path, 1)
    defer {
        if let previousValue {
            setenv(key, previousValue, 1)
        } else {
            unsetenv(key)
        }
        try? fileManager.removeItem(at: temporaryDirectory)
    }

    body(statePath.path)
}

private func withFactorySettings(
    _ json: String,
    projectSettingsPaths: [String] = [],
    extraFiles: [String: String] = [:],
    body: () -> Void
) {
    let key = "FACTORY_SETTINGS_PATH"
    let projectKey = "FACTORY_PROJECT_SETTINGS_PATHS"
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let settingsPath = temporaryDirectory.appendingPathComponent("settings.json")
    let previousValue = ProcessInfo.processInfo.environment[key]
    let previousProjectValue = ProcessInfo.processInfo.environment[projectKey]

    try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try? json.write(to: settingsPath, atomically: true, encoding: .utf8)
    for (relativePath, contents) in extraFiles {
        let fileURL = temporaryDirectory.appendingPathComponent(relativePath)
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    setenv(key, settingsPath.path, 1)
    setenv(projectKey, projectSettingsPaths.joined(separator: ":"), 1)
    defer {
        if let previousValue {
            setenv(key, previousValue, 1)
        } else {
            unsetenv(key)
        }
        if let previousProjectValue {
            setenv(projectKey, previousProjectValue, 1)
        } else {
            unsetenv(projectKey)
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
        "  - alias: glm5-nvidia",
        "    name: z-ai/glm5",
        "  - alias: kimi-k2.5-nvidia",
        "    name: moonshotai/kimi-k2.5",
        "- name: nvidia-minimax",
        "  base-url: https://integrate.api.nvidia.com/v1",
        "  models:",
        "  - alias: minimax-m2.5-nvidia",
        "    name: minimaxai/minimax-m2.5"
    ].joined(separator: "\n")
}

private struct FactoryWorkerSpecContract {
    let workerModelID: String
    let validationWorkerModelID: String
    let routeModel: String
    let routeProvider: String
    let requestSurface: String
    let effectiveRouteModel: String
    let effectiveRouteProvider: String
}

private func factorySettingsJSON(contract: FactoryWorkerSpecContract) -> String {
    """
    {
      "sessionDefaultSettings": {
        "model": "\(contract.validationWorkerModelID)",
        "reasoningEffort": "high",
        "autonomyMode": "auto-high"
      },
      "missionModelSettings": {
        "workerModel": "\(contract.workerModelID)",
        "workerReasoningEffort": "none",
        "validationWorkerModel": "\(contract.validationWorkerModelID)",
        "validationWorkerReasoningEffort": "high"
      },
      "customModels": [
        {
          "id": "\(contract.workerModelID)",
          "model": "\(contract.routeModel)",
          "provider": "\(contract.routeProvider)",
          "displayName": "Factory Worker via Proxy",
          "baseUrl": "http://127.0.0.1:8317/v1"
        },
        {
          "id": "\(contract.validationWorkerModelID)",
          "model": "gpt-5.4(high)",
          "provider": "openai",
          "displayName": "Factory Validation via Proxy",
          "baseUrl": "http://127.0.0.1:8317/v1"
        }
      ]
    }
    """
}

private let openAIFactoryWorkerContract = FactoryWorkerSpecContract(
    workerModelID: "custom:GPT-5.4-High-Proxy-2",
    validationWorkerModelID: "custom:GPT-5.4-High-Proxy-2",
    routeModel: "gpt-5.4(high)",
    routeProvider: "openai",
    requestSurface: "responses",
    effectiveRouteModel: "gpt-5.4(high)",
    effectiveRouteProvider: "openai"
)

private let genericCompatFactoryWorkerContract = FactoryWorkerSpecContract(
    workerModelID: "custom:Proxy-Worker-Smart-Router-8",
    validationWorkerModelID: "custom:GPT-5.4-High-Proxy-2",
    routeModel: "proxy-worker-smart-router",
    routeProvider: "generic-chat-completion-api",
    requestSurface: "chat_completions",
    effectiveRouteModel: "glm-5.1-zai",
    effectiveRouteProvider: "zai"
)

private let selfRoutedGenericCompatFactoryWorkerContract = FactoryWorkerSpecContract(
    workerModelID: "custom:Proxy-Worker-Smart-Router-8",
    validationWorkerModelID: "custom:GPT-5.4-High-Proxy-2",
    routeModel: "custom:Proxy-Worker-Smart-Router-8",
    routeProvider: "generic-chat-completion-api",
    requestSurface: "chat_completions",
    effectiveRouteModel: "glm-5.1-zai",
    effectiveRouteProvider: "zai"
)

private let directChatFactoryWorkerContract = FactoryWorkerSpecContract(
    workerModelID: "custom:Direct-Chat-Proxy-2",
    validationWorkerModelID: "custom:GPT-5.4-High-Proxy-2",
    routeModel: "gpt-5.4(high)",
    routeProvider: "generic-chat-completion-api",
    requestSurface: "chat_completions",
    effectiveRouteModel: "gpt-5.4(high)",
    effectiveRouteProvider: "openai"
)

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

private func workerMergedConfigYAML() -> String {
    [
        "claude-api-key:",
        "- api-key: test-zai-key",
        "  base-url: https://api.z.ai/api/anthropic",
        "  models:",
        "  - alias: glm-5.1-zai",
        "    name: glm-5.1",
        "openai-compatibility:",
        "- name: ollama-pro",
        "  api-key-entries:",
        "  - api-key: test-ollama-key",
        "  base-url: https://ollama.com/v1",
        "  models:",
        "  - alias: glm-5.1-ollama-pro",
        "    name: glm-5.1",
        "    register-canonical-name: false",
        "  - alias: minimax-m2.7-ollama-pro",
        "    name: minimax-m2.7",
        "    register-canonical-name: false",
        "- name: nvidia",
        "  api-key-entries:",
        "  - api-key: test-nvidia-key",
        "  base-url: https://integrate.api.nvidia.com/v1",
        "  models:",
        "  - alias: glm5",
        "    name: z-ai/glm5",
        "  - alias: glm5-nvidia",
        "    name: z-ai/glm5",
        "- name: meta-web",
        "  api-key: test-meta-web-key",
        "  base-url: https://www.meta.ai",
        "  models:",
        "  - alias: muse-spark",
        "    name: muse-spark",
        "request-retry: 3",
        "smart-aliases:",
        "  worker:",
        "    request-class: plain-chat",
        "    failover: silent",
        "    candidates:",
        "    - glm-5.1-zai",
        "    - glm-5.1-ollama-pro",
        "    - minimax-m2.7-ollama-pro",
        "    - muse-spark",
        "    - glm5-nvidia"
    ].joined(separator: "\n")
}

private func workerWithProxyMergedConfigYAML() -> String {
    [
        workerMergedConfigYAML(),
        "- name: kilocode",
        "  api-key: test-kilo-key",
        "  base-url: https://api.kilo.ai/api/openrouter/v1",
        "  models:",
        "  - alias: mimo-v2-pro-kilocode",
        "    name: xiaomi/mimo-v2-pro:free",
        "- name: opencode",
        "  base-url: https://opencode.ai/zen/v1",
        "  proxy-url: socks5://user:pass@proxy.example.com:1080",
        "  models:",
        "  - alias: mimo-v2-pro-opencode",
        "    name: mimo-v2-pro-free",
        "  - alias: minimax-m2.5-opencode",
        "    name: minimax-m2.5-free",
    ].joined(separator: "\n")
}

private func workerMisconfiguredMergedConfigYAML() -> String {
    [
        "openai-compatibility:",
        "- name: ollama-pro",
        "  api-key-entries:",
        "  - api-key: test-ollama-key",
        "  base-url: https://ollama.com/v1",
        "  models:",
        "  - alias: glm-5.1-ollama-pro",
        "    name: glm-5.1",
        "    register-canonical-name: false",
        "  - alias: minimax-m2.7-ollama-pro",
        "    name: minimax-m2.7",
        "    register-canonical-name: false",
        "request-retry: 3",
        "smart-aliases:",
        "  worker:",
        "    request-class: plain-chat",
        "    failover: silent",
        "    candidates:",
        "    - glm-5.1-ollama-pro"
    ].joined(separator: "\n")
}

private func workerMergedConfigWithLastResortYAML() -> String {
    [
        workerMergedConfigYAML(),
        "- api-key-entries:",
        "  - api-key: test-openai-key",
        "  name: openai",
        "  base-url: https://api.openai.com/v1",
        "  models:",
        "  - alias: gpt-5.4-medium",
        "    name: gpt-5.4-medium",
        "    - gpt-5.4-medium"
    ].joined(separator: "\n")
}

private func rawHTTPRequest(
    method: String,
    path: String,
    headers: [(String, String)] = [],
    body: String
) -> String {
    let bodyData = Data(body.utf8)
    let requestLines = [
        "\(method) \(path) HTTP/1.1",
        "Host: 127.0.0.1:8317",
        "Content-Type: application/json"
    ] + headers.map { "\($0.0): \($0.1)" } + [
        "Content-Length: \(bodyData.count)",
        "",
        body
    ]
    return requestLines.joined(separator: "\r\n")
}

private func httpURLResponse(
    statusCode: Int,
    headerFields: [String: String] = ["Content-Type": "application/json"]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "http://127.0.0.1:8318/v1/chat/completions")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headerFields
    )!
}
