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

        run("temporary nvidia route circuit opens after repeated failures, enters half-open on first success, and closes after recovery threshold", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)

                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), false, "glm5 should start healthy", recorder: recorder)

                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: "glm5", at: now)
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), false, "one failure should not open the circuit yet", recorder: recorder)

                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: "glm5", at: now)
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), true, "two failures should quarantine the route", recorder: recorder)

                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(forRequestModel: "glm5")
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), true, "one success should only move the route into half-open recovery", recorder: recorder)

                var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .halfOpen, "first recovery success should transition to half-open", recorder: recorder)
                expectEqual(snapshot["z-ai/glm5"]?.recoverySuccesses, 1, "half-open state should track recovery successes", recorder: recorder)

                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(forRequestModel: "glm5")
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), false, "recovery threshold successes should close the route again", recorder: recorder)
                snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "second recovery success should restore the healthy state", recorder: recorder)
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
            }
        }

        run("temporary nvidia half-open routes reopen immediately on another failure", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                let now = Date(timeIntervalSince1970: 1_700_000_000)

                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: "glm5", at: now)
                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: "glm5", at: now)
                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteSuccess(forRequestModel: "glm5")
                OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(forRequestModel: "glm5", at: now.addingTimeInterval(10))

                let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                expectEqual(snapshot["z-ai/glm5"]?.status, .open, "a half-open failure should immediately reopen quarantine", recorder: recorder)
                expectEqual(snapshot["z-ai/glm5"]?.recoverySuccesses, 0, "reopening should reset the recovery counter", recorder: recorder)
                expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5", at: now), true, "half-open failure should keep the route unavailable", recorder: recorder)
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
            }
        }

        run("temporary nvidia preflight rejects quarantined hosted routes before spending timeout budget", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                OpenAICompatTemporaryShim.forceOpenNVIDIAHostedRouteForTesting(
                    requestModel: "kimi-k2.5",
                    until: Date().addingTimeInterval(60)
                )
                let request = """
                {
                  "model": "kimi-k2.5",
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
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
            }
        }

        run("temporary nvidia model list filtering hides quarantined aliases", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                OpenAICompatTemporaryShim.forceOpenNVIDIAHostedRouteForTesting(
                    requestModel: "glm5",
                    until: Date().addingTimeInterval(60)
                )
                let body = """
                {
                  "object": "list",
                  "data": [
                    {"id": "glm5", "object": "model", "owned_by": "nvidia"},
                    {"id": "kimi-k2.5", "object": "model", "owned_by": "nvidia"},
                    {"id": "gpt-5", "object": "model", "owned_by": "openai"}
                  ]
                }
                """

                guard let filtered = OpenAICompatTemporaryShim.filteredModelListBodyRemovingOpenNVIDIARoutes(Data(body.utf8)) else {
                    recorder.recordFailure("expected quarantined route to be removed from /v1/models response")
                    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                    return
                }

                let json = parseDataJSONObject(filtered, recorder: recorder)
                let data = json["data"] as? [[String: Any]]
                let ids = (data ?? []).compactMap { $0["id"] as? String }
                expectEqual(ids.contains("glm5"), false, "quarantined glm5 alias should be removed from /v1/models", recorder: recorder)
                expectEqual(ids.contains("kimi-k2.5"), true, "healthy NVIDIA aliases should remain visible", recorder: recorder)
                expectEqual(ids.contains("gpt-5"), true, "non-NVIDIA models should remain visible", recorder: recorder)
                OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
            }
        }

        run("temporary nvidia route health persists quarantine state and telemetry across reload", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withRouteHealthPath { path in
                    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                    let now = Date(timeIntervalSince1970: 1_700_000_000)
                    let event = OpenAICompatTemporaryShim.RouteTelemetryEvent(
                        timestamp: now,
                        requestModel: "glm5",
                        canonicalModelID: "z-ai/glm5",
                        outcome: "send_error",
                        failureClass: "transport_timeout",
                        timeoutStage: .bufferedResponse,
                        upstreamHTTPStatus: nil,
                        retryCount: 1,
                        source: "live_request"
                    )

                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                        forRequestModel: "glm5",
                        telemetryEvent: event,
                        at: now
                    )
                    OpenAICompatTemporaryShim.recordNVIDIAHostedRouteFailure(
                        forRequestModel: "glm5",
                        telemetryEvent: event,
                        at: now
                    )

                    guard FileManager.default.fileExists(atPath: path) else {
                        recorder.recordFailure("expected persistent NVIDIA route-health cache file to be written")
                        return
                    }

                    OpenAICompatTemporaryShim.reloadPersistedRouteHealthForTesting()

                    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    let persisted = snapshot["z-ai/glm5"]
                    expectEqual(persisted?.status, .open, "persisted route health should retain open-circuit state", recorder: recorder)
                    expectEqual(persisted?.failureScore ?? 0, 2, "persisted route health should retain the failure score", recorder: recorder)
                    expectEqual(persisted?.isUnavailable(at: now), true, "persisted route health should remain unavailable after reload", recorder: recorder)
                    expectEqual(persisted?.lastTelemetryEvent, event, "persisted route health should retain the last telemetry event", recorder: recorder)

                    guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                        recorder.recordFailure("expected to read persisted route-health cache file")
                        return
                    }
                    let rawJSON = parseDataJSONObject(rawData, recorder: recorder)
                    let routes = rawJSON["routes"] as? [String: Any]
                    let glm5 = routes?["z-ai/glm5"] as? [String: Any]
                    expectEqual(glm5?["status"] as? String, "open", "persisted route-health file should store route status", recorder: recorder)
                    expectEqual(glm5?["failure_score"] as? Int, 2, "persisted route-health file should store the failure score", recorder: recorder)
                }
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
                expectEqual(event.outcome, "send_error", "telemetry should encode the runtime outcome label", recorder: recorder)
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
                    model: "kimi-k2.5",
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
                expectEqual(event.failureClass, "classified_429", "classified upstream failures should carry their normalized class", recorder: recorder)
                expectEqual(event.upstreamHTTPStatus, 429, "telemetry should preserve the upstream HTTP status when available", recorder: recorder)
                expectEqual(event.retryCount, 1, "telemetry should count prior transport retries", recorder: recorder)
            }
        }

        run("temporary nvidia canary success moves quarantined routes into half-open recovery before reopening", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withRouteHealthPath { _ in
                    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                    OpenAICompatTemporaryShim.forceOpenNVIDIAHostedRouteForTesting(
                        requestModel: "glm5",
                        until: Date().addingTimeInterval(60)
                    )

                    let proxy = ThinkingProxy()
                    var seenRequestModel: String?
                    proxy.nvidiaCanaryTransportForTesting = { requestModel, requestJSON, completion in
                        seenRequestModel = requestModel
                        if !requestJSON.contains("\"model\": \"z-ai/glm5\"") {
                            recorder.recordFailure("expected canary request JSON to target the quarantined canonical route")
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
                    proxy.performNVIDIACanariesOnce {
                        semaphore.signal()
                    }
                    let waitResult = semaphore.wait(timeout: .now() + 2)
                    expectEqual(waitResult, .success, "canary sweep should complete promptly under stubbed transport", recorder: recorder)
                    expectEqual(seenRequestModel, "z-ai/glm5", "canary sweep should probe the quarantined canonical route exactly once", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), true, "one successful canary should keep the route unavailable while it is half-open", recorder: recorder)
                    var snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    expectEqual(snapshot["z-ai/glm5"]?.status, .halfOpen, "first successful canary should move the route into half-open recovery", recorder: recorder)
                    expectEqual(snapshot["z-ai/glm5"]?.recoverySuccesses, 1, "half-open recovery should count successful canaries", recorder: recorder)
                    var lastEvent = snapshot["z-ai/glm5"]?.lastTelemetryEvent
                    expectEqual(lastEvent?.source, "canary", "successful canaries should record canary telemetry", recorder: recorder)
                    expectEqual(lastEvent?.outcome, "send_response", "successful canaries should record a successful runtime outcome", recorder: recorder)

                    let secondSemaphore = DispatchSemaphore(value: 0)
                    proxy.performNVIDIACanariesOnce {
                        secondSemaphore.signal()
                    }
                    let secondWaitResult = secondSemaphore.wait(timeout: .now() + 2)
                    expectEqual(secondWaitResult, .success, "second canary sweep should also complete promptly", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), false, "recovery threshold successful canaries should reopen the route", recorder: recorder)
                    snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    expectEqual(snapshot["z-ai/glm5"]?.status, .closed, "route should close after enough successful canaries", recorder: recorder)
                    lastEvent = snapshot["z-ai/glm5"]?.lastTelemetryEvent
                    expectEqual(lastEvent?.source, "canary", "successful reopening should preserve the last canary telemetry event", recorder: recorder)
                    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                }
            }
        }

        run("temporary nvidia canary failures reopen half-open routes and record canary telemetry", recorder: recorder) {
            withMergedConfig(defaultMergedConfigYAML()) {
                withRouteHealthPath { _ in
                    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
                    let until = Date().addingTimeInterval(60)
                    OpenAICompatTemporaryShim.forceOpenNVIDIAHostedRouteForTesting(
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
                    proxy.performNVIDIACanariesOnce {
                        semaphore.signal()
                    }
                    let waitResult = semaphore.wait(timeout: .now() + 2)
                    expectEqual(waitResult, .success, "first canary sweep should complete promptly", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), true, "first successful canary should still leave the route unavailable", recorder: recorder)

                    let secondSemaphore = DispatchSemaphore(value: 0)
                    proxy.performNVIDIACanariesOnce {
                        secondSemaphore.signal()
                    }
                    let secondWaitResult = secondSemaphore.wait(timeout: .now() + 2)
                    expectEqual(secondWaitResult, .success, "second failing canary sweep should still complete promptly", recorder: recorder)
                    expectEqual(OpenAICompatTemporaryShim.isNVIDIAHostedRouteOpen(forRequestModel: "glm5"), true, "failed canaries should keep the route quarantined", recorder: recorder)
                    let snapshot = OpenAICompatTemporaryShim.routeHealthSnapshotForTesting()
                    let lastEvent = snapshot["z-ai/glm5"]?.lastTelemetryEvent
                    expectEqual(lastEvent?.source, "canary", "failed canaries should record canary telemetry", recorder: recorder)
                    expectEqual(lastEvent?.failureClass, "transport_error_retryable", "failed canaries should preserve the route failure class", recorder: recorder)
                    expectEqual(snapshot["z-ai/glm5"]?.status, .open, "failed canaries after half-open recovery should reopen quarantine", recorder: recorder)
                    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
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
                    model: "minimax-m2.5",
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
                    model: "kimi-k2.5",
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
    let configKey = "VIBEPROXY_MERGED_CONFIG_PATH"
    let routeHealthKey = "VIBEPROXY_NVIDIA_ROUTE_HEALTH_PATH"
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let configPath = temporaryDirectory.appendingPathComponent("merged-config.yaml")
    let routeHealthPath = temporaryDirectory.appendingPathComponent("nvidia-route-health.json")
    let previousConfigValue = ProcessInfo.processInfo.environment[configKey]
    let previousRouteHealthValue = ProcessInfo.processInfo.environment[routeHealthKey]

    try? fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    try? yaml.write(to: configPath, atomically: true, encoding: .utf8)
    setenv(configKey, configPath.path, 1)
    setenv(routeHealthKey, routeHealthPath.path, 1)
    OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
    defer {
        OpenAICompatTemporaryShim.clearNVIDIAHostedRouteHealthForTesting()
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
    let key = "VIBEPROXY_NVIDIA_ROUTE_HEALTH_PATH"
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let statePath = temporaryDirectory.appendingPathComponent("nvidia-route-health.json")
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
