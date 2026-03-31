#!/bin/bash

set -euo pipefail

FRONTEND_URL="${VIBEPROXY_FRONTEND_URL:-http://127.0.0.1:8317}"
HEALTH_URL="$FRONTEND_URL/healthz"
API_KEY="${FACTORY_PROXY_API_KEY:-factory-local-proxy}"
FACTORY_ROOT="${FACTORY_ROOT:-$HOME/.factory}"
GLOBAL_SETTINGS_PATH="${GLOBAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp_base="${TMPDIR:-$HOME/.tmp}"
mkdir -p "$tmp_base"
tmp_dir="$(mktemp -d "$tmp_base/factory-worker-preflight.XXXXXX")"
cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

health_body="$tmp_dir/health.json"
worker_probe_headers="$tmp_dir/worker-probe.headers"
worker_probe_body="$tmp_dir/worker-probe.json"
session_probe_headers="$tmp_dir/session-probe.headers"
session_probe_body="$tmp_dir/session-probe.json"
validation_probe_headers="$tmp_dir/validation-probe.headers"
validation_probe_body="$tmp_dir/validation-probe.json"

header_value() {
  local file="$1"
  local header_name="$2"
  awk -v target="$(printf '%s' "$header_name" | tr '[:upper:]' '[:lower:]')" '
    {
      line=$0
      sub(/$/, "", line)
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

if [[ ! -f "$GLOBAL_SETTINGS_PATH" ]]; then
  echo "missing global settings: $GLOBAL_SETTINGS_PATH" >&2
  exit 1
fi

worker_model_id="$(jq -r '.missionModelSettings.workerModel' "$GLOBAL_SETTINGS_PATH")"
validation_model_id="$(jq -r '.missionModelSettings.validationWorkerModel' "$GLOBAL_SETTINGS_PATH")"
session_model_id="$(jq -r '.sessionDefaultSettings.model' "$GLOBAL_SETTINGS_PATH")"
worker_route_model="$(jq -r --arg id "$worker_model_id" '.customModels[] | select(.id == $id) | .model' "$GLOBAL_SETTINGS_PATH")"
worker_route_provider="$(jq -r --arg id "$worker_model_id" '.customModels[] | select(.id == $id) | .provider' "$GLOBAL_SETTINGS_PATH")"
validation_route_model="$(jq -r --arg id "$validation_model_id" '.customModels[] | select(.id == $id) | .model' "$GLOBAL_SETTINGS_PATH")"
validation_route_provider="$(jq -r --arg id "$validation_model_id" '.customModels[] | select(.id == $id) | .provider' "$GLOBAL_SETTINGS_PATH")"
session_route_model="$(jq -r --arg id "$session_model_id" '.customModels[] | select(.id == $id) | .model' "$GLOBAL_SETTINGS_PATH")"
session_route_provider="$(jq -r --arg id "$session_model_id" '.customModels[] | select(.id == $id) | .provider' "$GLOBAL_SETTINGS_PATH")"

provider_to_surface() {
  local provider="$1"
  local role="$2"
  case "$provider" in
    generic-chat-completion-api)
      printf 'chat_completions'
      ;;
    openai|xai)
      printf 'responses'
      ;;
    anthropic)
      printf 'messages'
      ;;
    *)
      echo "unsupported Factory $role provider in $GLOBAL_SETTINGS_PATH: $provider" >&2
      exit 1
      ;;
  esac
}

worker_request_surface="$(provider_to_surface "$worker_route_provider" "worker")"
session_request_surface="$(provider_to_surface "$session_route_provider" "session/orchestrator")"
validation_request_surface="$(provider_to_surface "$validation_route_provider" "validation")"

echo "==> Checking proxy health endpoint"
curl -fsS "$HEALTH_URL" -o "$health_body"

echo "==> Checking Factory worker snapshot sync"
"$SCRIPT_DIR/sync-factory-worker-contract.sh" --check >/dev/null

jq -e '.frontend.port == 8317' "$health_body" >/dev/null
jq -e '.backend.host == "127.0.0.1"' "$health_body" >/dev/null
jq -e '.backend.port == 8318' "$health_body" >/dev/null
jq -e '.backend.reachable == true' "$health_body" >/dev/null
jq -e '.provenance.app_version | strings | length > 0' "$health_body" >/dev/null
jq -e '.provenance.merged_config_fingerprint | strings | length > 0' "$health_body" >/dev/null
jq -e --arg worker_model_id "$worker_model_id" '.factory_worker.worker_model_id == $worker_model_id' "$health_body" >/dev/null
jq -e --arg validation_model_id "$validation_model_id" '.factory_worker.validation_worker_model_id == $validation_model_id' "$health_body" >/dev/null
jq -e --arg worker_route_model "$worker_route_model" '.factory_worker.route_model == $worker_route_model' "$health_body" >/dev/null
jq -e --arg worker_route_provider "$worker_route_provider" '.factory_worker.route_provider == $worker_route_provider' "$health_body" >/dev/null
jq -e --arg worker_request_surface "$worker_request_surface" '.factory_worker.request_surface == $worker_request_surface' "$health_body" >/dev/null
jq -e '.factory_worker.snapshot_sync_ok == true' "$health_body" >/dev/null
jq -e '.factory_worker.snapshot_drift_count == 0' "$health_body" >/dev/null
jq -e '.factory_worker.ready == true' "$health_body" >/dev/null
jq -e --arg session_model_id "$session_model_id" '.factory_roles.orchestration.model_id == $session_model_id' "$health_body" >/dev/null
jq -e --arg validation_model_id "$validation_model_id" '.factory_roles.verification.model_id == $validation_model_id' "$health_body" >/dev/null
jq -e --arg session_route_model "$session_route_model" '.factory_roles.orchestration.route_model == $session_route_model' "$health_body" >/dev/null
jq -e --arg session_route_provider "$session_route_provider" '.factory_roles.orchestration.route_provider == $session_route_provider' "$health_body" >/dev/null
jq -e --arg session_request_surface "$session_request_surface" '.factory_roles.orchestration.request_surface == $session_request_surface' "$health_body" >/dev/null
jq -e --arg validation_route_model "$validation_route_model" '.factory_roles.verification.route_model == $validation_route_model' "$health_body" >/dev/null
jq -e --arg validation_route_provider "$validation_route_provider" '.factory_roles.verification.route_provider == $validation_route_provider' "$health_body" >/dev/null
jq -e --arg validation_request_surface "$validation_request_surface" '.factory_roles.verification.request_surface == $validation_request_surface' "$health_body" >/dev/null
jq -e '.factory_roles.orchestration.ready == true' "$health_body" >/dev/null
jq -e '.factory_roles.verification.ready == true' "$health_body" >/dev/null

worker_effective_route_model="$(jq -r '.factory_worker.effective_route_model // empty' "$health_body")"
worker_effective_route_provider="$(jq -r '.factory_worker.effective_route_provider // empty' "$health_body")"
session_effective_route_model="$(jq -r '.factory_roles.orchestration.effective_route_model // empty' "$health_body")"
session_effective_route_provider="$(jq -r '.factory_roles.orchestration.effective_route_provider // empty' "$health_body")"
validation_effective_route_model="$(jq -r '.factory_roles.verification.effective_route_model // empty' "$health_body")"
validation_effective_route_provider="$(jq -r '.factory_roles.verification.effective_route_provider // empty' "$health_body")"

echo "==> Probing the worker lane directly"
case "$worker_request_surface" in
  chat_completions)
    curl -fsS \
      -D "$worker_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --max-time 45 \
      "$FRONTEND_URL/v1/chat/completions" \
      -d "{\"model\":\"$worker_model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"noop\",\"description\":\"No-op verification tool\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}],\"tool_choice\":\"none\",\"max_tokens\":32}" \
      -o "$worker_probe_body"
    jq -e '((.choices[0].message.content // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$worker_probe_body" >/dev/null
    assert_probe_headers "$worker_probe_headers" "worker" "$worker_model_id" "$worker_effective_route_model" "$worker_effective_route_provider"
    ;;
  responses)
    curl -fsS \
      -D "$worker_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --max-time 45 \
      "$FRONTEND_URL/v1/responses" \
      -d "{\"model\":\"$worker_model_id\",\"input\":\"Return exactly: OK\",\"max_output_tokens\":32}" \
      -o "$worker_probe_body"
    jq -e 'any(.output[]?; .type == "message" and any(.content[]?; .type == "output_text" and ((.text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"))' "$worker_probe_body" >/dev/null
    assert_probe_headers "$worker_probe_headers" "worker" "$worker_model_id" "$worker_effective_route_model" "$worker_effective_route_provider"
    ;;
  messages)
    curl -fsS \
      -D "$worker_probe_headers" \
      -H "Content-Type: application/json" \
      -H "x-api-key: $API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      --max-time 45 \
      "$FRONTEND_URL/v1/messages" \
      -d "{\"model\":\"$worker_model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
      -o "$worker_probe_body"
    jq -e '((.content[0].text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$worker_probe_body" >/dev/null
    assert_probe_headers "$worker_probe_headers" "worker" "$worker_model_id" "$worker_effective_route_model" "$worker_effective_route_provider"
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
      -d "{\"model\":\"$session_model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
      -o "$session_probe_body"
    jq -e '((.choices[0].message.content // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$session_probe_body" >/dev/null
    assert_probe_headers "$session_probe_headers" "session" "$session_model_id" "$session_effective_route_model" "$session_effective_route_provider"
    ;;
  responses)
    curl -fsS \
      -D "$session_probe_headers" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      --max-time 45 \
      "$FRONTEND_URL/v1/responses" \
      -d "{\"model\":\"$session_model_id\",\"input\":\"Return exactly: OK\",\"max_output_tokens\":32}" \
      -o "$session_probe_body"
    jq -e 'any(.output[]?; .type == "message" and any(.content[]?; .type == "output_text" and ((.text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"))' "$session_probe_body" >/dev/null
    assert_probe_headers "$session_probe_headers" "session" "$session_model_id" "$session_effective_route_model" "$session_effective_route_provider"
    ;;
  messages)
    curl -fsS \
      -D "$session_probe_headers" \
      -H "Content-Type: application/json" \
      -H "x-api-key: $API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      --max-time 45 \
      "$FRONTEND_URL/v1/messages" \
      -d "{\"model\":\"$session_model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
      -o "$session_probe_body"
    jq -e '((.content[0].text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$session_probe_body" >/dev/null
    assert_probe_headers "$session_probe_headers" "session" "$session_model_id" "$session_effective_route_model" "$session_effective_route_provider"
    ;;
  *)
    echo "unsupported Factory session/orchestrator request surface for proxy preflight: $session_request_surface" >&2
    exit 1
    ;;
esac

if [[ "$validation_model_id" != "$session_model_id" ]]; then
  echo "==> Probing the validation lane directly"
  case "$validation_request_surface" in
    chat_completions)
      curl -fsS \
        -D "$validation_probe_headers" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        --max-time 45 \
        "$FRONTEND_URL/v1/chat/completions" \
        -d "{\"model\":\"$validation_model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
        -o "$validation_probe_body"
      jq -e '((.choices[0].message.content // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$validation_probe_body" >/dev/null
      assert_probe_headers "$validation_probe_headers" "validation" "$validation_model_id" "$validation_effective_route_model" "$validation_effective_route_provider"
      ;;
    responses)
      curl -fsS \
        -D "$validation_probe_headers" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $API_KEY" \
        --max-time 45 \
        "$FRONTEND_URL/v1/responses" \
        -d "{\"model\":\"$validation_model_id\",\"input\":\"Return exactly: OK\",\"max_output_tokens\":32}" \
        -o "$validation_probe_body"
      jq -e 'any(.output[]?; .type == "message" and any(.content[]?; .type == "output_text" and ((.text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"))' "$validation_probe_body" >/dev/null
      assert_probe_headers "$validation_probe_headers" "validation" "$validation_model_id" "$validation_effective_route_model" "$validation_effective_route_provider"
      ;;
    messages)
      curl -fsS \
        -D "$validation_probe_headers" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        --max-time 45 \
        "$FRONTEND_URL/v1/messages" \
        -d "{\"model\":\"$validation_model_id\",\"messages\":[{\"role\":\"user\",\"content\":\"Return exactly: OK\"}],\"max_tokens\":32}" \
        -o "$validation_probe_body"
      jq -e '((.content[0].text // "") | gsub("^\\s+|\\s+$"; "")) == "OK"' "$validation_probe_body" >/dev/null
      assert_probe_headers "$validation_probe_headers" "validation" "$validation_model_id" "$validation_effective_route_model" "$validation_effective_route_provider"
      ;;
    *)
      echo "unsupported Factory validation request surface for proxy preflight: $validation_request_surface" >&2
      exit 1
      ;;
  esac
fi

echo "==> Preflight passed"
