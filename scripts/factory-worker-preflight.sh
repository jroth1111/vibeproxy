#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=factory-common.sh
source "$SCRIPT_DIR/factory-common.sh"

require_global_settings
load_factory_models
make_temp_dir factory-preflight

health_body="$FACTORY_TMP_DIR/health.json"
worker_probe_headers="$FACTORY_TMP_DIR/worker-probe.headers"
worker_probe_body="$FACTORY_TMP_DIR/worker-probe.json"
session_probe_headers="$FACTORY_TMP_DIR/session-probe.headers"
session_probe_body="$FACTORY_TMP_DIR/session-probe.json"
validation_probe_headers="$FACTORY_TMP_DIR/validation-probe.headers"
validation_probe_body="$FACTORY_TMP_DIR/validation-probe.json"

header_value() {
  local file="$1"
  local header_name="$2"
  awk -v target="$(printf '%s' "$header_name" | tr '[:upper:]' '[:lower:]')" '
    {
      line=$0
      sub(/\r$/, "", line)
      split(line, parts, ":")
      name=tolower(parts[1])
      if (name != target) {
        next
      }
      value=substr(line, index(line, ":") + 1)
      sub(/^[[:space:]]+/, "", value)
      print value
      exit
    }
  ' "$file"
}

assert_probe_headers() {
  local header_file="$1"
  local lane="$2"
  local expected_public="$3"
  local expected_resolved_model="$4"
  local expected_resolved_provider="$5"
  local actual_public
  local actual_resolved_model
  local actual_resolved_provider

  actual_public="$(header_value "$header_file" "X-Public-Model")"
  actual_resolved_model="$(header_value "$header_file" "X-Resolved-Model")"
  actual_resolved_provider="$(header_value "$header_file" "X-Resolved-Provider")"

  if [[ "$actual_public" != "$expected_public" ]]; then
    echo "$lane probe returned X-Public-Model=$actual_public (want $expected_public)" >&2
    exit 1
  fi
  if [[ "$actual_resolved_model" != "$expected_resolved_model" ]]; then
    echo "$lane probe returned X-Resolved-Model=$actual_resolved_model (want $expected_resolved_model)" >&2
    exit 1
  fi
  if [[ -n "$expected_resolved_provider" && "$actual_resolved_provider" != "$expected_resolved_provider" ]]; then
    echo "$lane probe returned X-Resolved-Provider=$actual_resolved_provider (want $expected_resolved_provider)" >&2
    exit 1
  fi
}

assert_worker_probe_headers() {
  local header_file="$1"
  local expected_public="$2"
  local expected_resolved_model="$3"
  local expected_resolved_provider="$4"
  local allowed_pool_models_json="$5"
  local actual_public
  local actual_resolved_model
  local actual_resolved_provider

  actual_public="$(header_value "$header_file" "X-Public-Model")"
  actual_resolved_model="$(header_value "$header_file" "X-Resolved-Model")"
  actual_resolved_provider="$(header_value "$header_file" "X-Resolved-Provider")"

  if [[ "$actual_public" != "$expected_public" ]]; then
    echo "worker probe returned X-Public-Model=$actual_public (want $expected_public)" >&2
    exit 1
  fi

  if [[ "$actual_resolved_model" == "$expected_resolved_model" ]]; then
    if [[ -n "$expected_resolved_provider" && "$actual_resolved_provider" != "$expected_resolved_provider" ]]; then
      echo "worker probe returned X-Resolved-Provider=$actual_resolved_provider (want $expected_resolved_provider)" >&2
      exit 1
    fi
    return 0
  fi

  if [[ -n "$allowed_pool_models_json" ]] &&
     jq -e --arg model "$actual_resolved_model" 'index($model) != null' <<<"$allowed_pool_models_json" >/dev/null; then
    echo "worker probe resolved to alternate pool winner $actual_resolved_model instead of snapshot winner $expected_resolved_model" >&2
    return 0
  fi

  echo "worker probe returned X-Resolved-Model=$actual_resolved_model (want $expected_resolved_model)" >&2
  exit 1
}

worker_request_surface="$(provider_to_surface "$FACTORY_WORKER_ROUTE_PROVIDER" "worker")"
session_request_surface="$(provider_to_surface "$FACTORY_SESSION_ROUTE_PROVIDER" "session/orchestrator")"
validation_request_surface="$(provider_to_surface "$FACTORY_VALIDATION_ROUTE_PROVIDER" "validation")"

echo "==> Checking proxy health endpoint"
health_http_code="$(curl -sS -o "$health_body" -w '%{http_code}' --connect-timeout 10 --max-time 15 "$HEALTH_URL")"
if [[ "$health_http_code" != "200" ]]; then
  echo "healthz returned HTTP $health_http_code" >&2
  exit 1
fi

echo "==> Checking Factory worker snapshot sync"
"$SCRIPT_DIR/sync-factory-worker-contract.sh" --check >/dev/null

jq -e '.frontend.port == 8317' "$health_body" >/dev/null
jq -e '.backend.host == "127.0.0.1"' "$health_body" >/dev/null
jq -e '.backend.port == 8318' "$health_body" >/dev/null
jq -e '.backend.reachable == true' "$health_body" >/dev/null
jq -e '.provenance.app_version | strings | length > 0' "$health_body" >/dev/null
jq -e '.provenance.merged_config_fingerprint | strings | length > 0' "$health_body" >/dev/null
jq -e --arg worker_model_id "$FACTORY_WORKER_MODEL" '.factory_worker.worker_model_id == $worker_model_id' "$health_body" >/dev/null
jq -e --arg validation_model_id "$FACTORY_VALIDATION_MODEL" '.factory_worker.validation_worker_model_id == $validation_model_id' "$health_body" >/dev/null
jq -e --arg worker_route_model "$FACTORY_WORKER_ROUTE_MODEL" '.factory_worker.route_model == $worker_route_model' "$health_body" >/dev/null
jq -e --arg worker_route_provider "$FACTORY_WORKER_ROUTE_PROVIDER" '.factory_worker.route_provider == $worker_route_provider' "$health_body" >/dev/null
jq -e --arg worker_request_surface "$worker_request_surface" '.factory_worker.request_surface == $worker_request_surface' "$health_body" >/dev/null
jq -e '.factory_worker.snapshot_sync_ok == true' "$health_body" >/dev/null
jq -e '.factory_worker.snapshot_drift_count == 0' "$health_body" >/dev/null
jq -e '.factory_worker.ready == true' "$health_body" >/dev/null
jq -e --arg session_model_id "$FACTORY_SESSION_MODEL" '.factory_roles.orchestration.model_id == $session_model_id' "$health_body" >/dev/null
jq -e --arg validation_model_id "$FACTORY_VALIDATION_MODEL" '.factory_roles.verification.model_id == $validation_model_id' "$health_body" >/dev/null
jq -e --arg session_route_model "$FACTORY_SESSION_ROUTE_MODEL" '.factory_roles.orchestration.route_model == $session_route_model' "$health_body" >/dev/null
jq -e --arg session_route_provider "$FACTORY_SESSION_ROUTE_PROVIDER" '.factory_roles.orchestration.route_provider == $session_route_provider' "$health_body" >/dev/null
jq -e --arg session_request_surface "$session_request_surface" '.factory_roles.orchestration.request_surface == $session_request_surface' "$health_body" >/dev/null
jq -e --arg validation_route_model "$FACTORY_VALIDATION_ROUTE_MODEL" '.factory_roles.verification.route_model == $validation_route_model' "$health_body" >/dev/null
jq -e --arg validation_route_provider "$FACTORY_VALIDATION_ROUTE_PROVIDER" '.factory_roles.verification.route_provider == $validation_route_provider' "$health_body" >/dev/null
jq -e --arg validation_request_surface "$validation_request_surface" '.factory_roles.verification.request_surface == $validation_request_surface' "$health_body" >/dev/null
jq -e '.factory_roles.orchestration.ready == true' "$health_body" >/dev/null
jq -e '.factory_roles.verification.ready == true' "$health_body" >/dev/null

worker_effective_route_model="$(jq -r '.factory_worker.effective_route_model // empty' "$health_body")"
worker_effective_route_provider="$(jq -r '.factory_worker.effective_route_provider // empty' "$health_body")"
session_effective_route_model="$(jq -r '.factory_roles.orchestration.effective_route_model // empty' "$health_body")"
session_effective_route_provider="$(jq -r '.factory_roles.orchestration.effective_route_provider // empty' "$health_body")"
validation_effective_route_model="$(jq -r '.factory_roles.verification.effective_route_model // empty' "$health_body")"
validation_effective_route_provider="$(jq -r '.factory_roles.verification.effective_route_provider // empty' "$health_body")"
worker_pool_candidate_models="$(jq -c '.config_drift.proxy_worker_candidates // []' "$health_body")"

echo "==> Probing the worker lane directly"
case "$worker_request_surface" in
  chat_completions)
    curl -fsS \
      -D "$worker_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -H "X-VibeProxy-Probe: factory-worker-preflight" \
      --max-time 45 \
      "$FRONTEND_URL/v1/chat/completions" \
      -d "{\"model\":\"$FACTORY_WORKER_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"noop\",\"description\":\"No-op verification tool\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}],\"tool_choice\":\"none\",\"max_tokens\":32}" \
      -o "$worker_probe_body"
    jq -e '((.choices[0].message.content // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$worker_probe_body" >/dev/null
    assert_worker_probe_headers "$worker_probe_headers" "$FACTORY_WORKER_MODEL" "$worker_effective_route_model" "$worker_effective_route_provider" "$worker_pool_candidate_models"
    ;;
  responses)
    curl -fsS \
      -D "$worker_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -H "X-VibeProxy-Probe: factory-worker-preflight" \
      --max-time 45 \
      "$FRONTEND_URL/v1/responses" \
      -d "{\"model\":\"$FACTORY_WORKER_MODEL\",\"input\":\"Return exactly: OK\",\"max_output_tokens\":32}" \
      -o "$worker_probe_body"
    jq -e 'any(.output[]?; .type == "message" and any(.content[]?; .type == "output_text" and ((.text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"))' "$worker_probe_body" >/dev/null
    assert_worker_probe_headers "$worker_probe_headers" "$FACTORY_WORKER_MODEL" "$worker_effective_route_model" "$worker_effective_route_provider" "$worker_pool_candidate_models"
    ;;
  messages)
    curl -fsS \
      -D "$worker_probe_headers" \
      -H "Content-Type: application/json" \
      -H "x-api-key: $API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "X-VibeProxy-Probe: factory-worker-preflight" \
      --max-time 45 \
      "$FRONTEND_URL/v1/messages" \
      -d "{\"model\":\"$FACTORY_WORKER_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
      -o "$worker_probe_body"
    jq -e '((.content[0].text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$worker_probe_body" >/dev/null
    assert_worker_probe_headers "$worker_probe_headers" "$FACTORY_WORKER_MODEL" "$worker_effective_route_model" "$worker_effective_route_provider" "$worker_pool_candidate_models"
    ;;
  *)
    echo "unsupported Factory worker request surface for proxy preflight: $worker_request_surface" >&2
    exit 1
    ;;
esac

echo "==> Probing the session/validation lane directly"
case "$session_request_surface" in
  chat_completions)
    curl -fsS \
      -D "$session_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --max-time 45 \
      "$FRONTEND_URL/v1/chat/completions" \
      -d "{\"model\":\"$FACTORY_SESSION_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
      -o "$session_probe_body"
    jq -e '((.choices[0].message.content // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$session_probe_body" >/dev/null
    assert_probe_headers "$session_probe_headers" "session" "$FACTORY_SESSION_MODEL" "$session_effective_route_model" "$session_effective_route_provider"
    ;;
  responses)
    curl -fsS \
      -D "$session_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --max-time 45 \
      "$FRONTEND_URL/v1/responses" \
      -d "{\"model\":\"$FACTORY_SESSION_MODEL\",\"input\":\"Return exactly: OK\",\"max_output_tokens\":32}" \
      -o "$session_probe_body"
    jq -e 'any(.output[]?; .type == "message" and any(.content[]?; .type == "output_text" and ((.text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"))' "$session_probe_body" >/dev/null
    assert_probe_headers "$session_probe_headers" "session" "$FACTORY_SESSION_MODEL" "$session_effective_route_model" "$session_effective_route_provider"
    ;;
  messages)
    curl -fsS \
      -D "$session_probe_headers" \
      -H "Content-Type: application/json" \
      -H "x-api-key: $API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      --max-time 45 \
      "$FRONTEND_URL/v1/messages" \
      -d "{\"model\":\"$FACTORY_SESSION_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
      -o "$session_probe_body"
    jq -e '((.content[0].text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$session_probe_body" >/dev/null
    assert_probe_headers "$session_probe_headers" "session" "$FACTORY_SESSION_MODEL" "$session_effective_route_model" "$session_effective_route_provider"
    ;;
  *)
    echo "unsupported Factory session/orchestrator request surface for proxy preflight: $session_request_surface" >&2
    exit 1
    ;;
esac

if [[ "$FACTORY_VALIDATION_MODEL" != "$FACTORY_SESSION_MODEL" ]]; then
  echo "==> Probing the validation lane directly"
  case "$validation_request_surface" in
    chat_completions)
      curl -fsS \
        -D "$validation_probe_headers" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        --max-time 45 \
        "$FRONTEND_URL/v1/chat/completions" \
        -d "{\"model\":\"$FACTORY_VALIDATION_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
        -o "$validation_probe_body"
      jq -e '((.choices[0].message.content // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$validation_probe_body" >/dev/null
      assert_probe_headers "$validation_probe_headers" "validation" "$FACTORY_VALIDATION_MODEL" "$validation_effective_route_model" "$validation_effective_route_provider"
      ;;
    responses)
      curl -fsS \
        -D "$validation_probe_headers" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        --max-time 45 \
        "$FRONTEND_URL/v1/responses" \
        -d "{\"model\":\"$FACTORY_VALIDATION_MODEL\",\"input\":\"Return exactly: OK\",\"max_output_tokens\":32}" \
        -o "$validation_probe_body"
      jq -e 'any(.output[]?; .type == "message" and any(.content[]?; .type == "output_text" and ((.text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"))' "$validation_probe_body" >/dev/null
      assert_probe_headers "$validation_probe_headers" "validation" "$FACTORY_VALIDATION_MODEL" "$validation_effective_route_model" "$validation_effective_route_provider"
      ;;
    messages)
      curl -fsS \
        -D "$validation_probe_headers" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        --max-time 45 \
        "$FRONTEND_URL/v1/messages" \
        -d "{\"model\":\"$FACTORY_VALIDATION_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
        -o "$validation_probe_body"
      jq -e '((.content[0].text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$validation_probe_body" >/dev/null
      assert_probe_headers "$validation_probe_headers" "validation" "$FACTORY_VALIDATION_MODEL" "$validation_effective_route_model" "$validation_effective_route_provider"
      ;;
    *)
      echo "unsupported Factory validation request surface for proxy preflight: $validation_request_surface" >&2
      exit 1
      ;;
  esac
fi

echo "==> Preflight passed"
