#!/bin/bash

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FACTORY_ROOT="${FACTORY_ROOT:-$HOME/.factory}"
GLOBAL_SETTINGS_PATH="${GLOBAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.json}"
DROID_LOG_PATH="${DROID_LOG_PATH:-$FACTORY_ROOT/logs/droid-log-single.log}"
MISSIONS_ROOT="${MISSIONS_ROOT:-$FACTORY_ROOT/missions}"
FRONTEND_URL="${VIBEPROXY_FRONTEND_URL:-http://127.0.0.1:8317}"
HEALTH_URL="$FRONTEND_URL/healthz"
ROUTE_HEALTH_PATH="${ROUTE_HEALTH_PATH:-$HOME/.cli-proxy-api/route-health.json}"
AUDIT_ROOT="${AUDIT_ROOT:-$FACTORY_ROOT/monitoring/factory-audit}"
AUDIT_HISTORY_PATH="$AUDIT_ROOT/history.jsonl"
AUDIT_LATEST_PATH="$AUDIT_ROOT/latest.json"
AUDIT_STDOUT_LOG="${AUDIT_STDOUT_LOG:-$AUDIT_ROOT/runner.out.log}"
AUDIT_STDERR_LOG="${AUDIT_STDERR_LOG:-$AUDIT_ROOT/runner.err.log}"
VIBEPROXY_AGENT_LABEL="${VIBEPROXY_AGENT_LABEL:-com.vibeproxy.repo}"
INSTALLED_VIBEPROXY_AGENT_PLIST="${INSTALLED_VIBEPROXY_AGENT_PLIST:-$HOME/Library/LaunchAgents/com.vibeproxy.repo.plist}"

tmp_base="${TMPDIR:-$HOME/.tmp}"
mkdir -p "$tmp_base" "$AUDIT_ROOT"
tmp_dir="$(mktemp -d "$tmp_base/factory-audit.XXXXXX")"
lock_dir="$AUDIT_ROOT/.lock"
lock_acquired=0

cleanup() {
  if [[ "$lock_acquired" == "1" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "factory audit is already running" >&2
  exit 0
fi
lock_acquired=1

if [[ ! -f "$GLOBAL_SETTINGS_PATH" ]]; then
  echo "missing global settings: $GLOBAL_SETTINGS_PATH" >&2
  exit 1
fi

uid="$(id -u)"
launch_target="gui/$uid/$VIBEPROXY_AGENT_LABEL"
health_json="$tmp_dir/health.json"
route_health_json="$tmp_dir/route-health.json"
doctor_stdout="$tmp_dir/doctor.stdout"
doctor_stderr="$tmp_dir/doctor.stderr"

actions_json='[]'

record_action() {
  local kind="$1"
  local detail="$2"
  actions_json="$(
    jq -cn \
      --argjson actions "$actions_json" \
      --arg kind "$kind" \
      --arg detail "$detail" \
      '$actions + [{kind: $kind, detail: $detail}]'
  )"
}

count_matches() {
  local pattern="$1"
  local path="$2"
  local count

  if [[ ! -f "$path" ]]; then
    printf '0'
    return 0
  fi

  count="$(rg -c -- "$pattern" "$path" 2>/dev/null || true)"
  count="${count##*$'\n'}"
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    count=0
  fi

  printf '%s' "$count"
}

refresh_health() {
  curl -fsS "$HEALTH_URL" -o "$health_json"
}

kickstart_proxy() {
  if launchctl print "$launch_target" >/dev/null 2>&1; then
    launchctl kickstart -k "$launch_target" >/dev/null
    record_action "launchctl_kickstart" "Restarted $VIBEPROXY_AGENT_LABEL via launchctl kickstart."
    return 0
  fi

  if [[ -f "$INSTALLED_VIBEPROXY_AGENT_PLIST" ]]; then
    launchctl bootstrap "gui/$uid" "$INSTALLED_VIBEPROXY_AGENT_PLIST" >/dev/null 2>&1 || true
    launchctl kickstart -k "$launch_target" >/dev/null
    record_action "launchctl_bootstrap" "Bootstrapped and restarted $VIBEPROXY_AGENT_LABEL from $INSTALLED_VIBEPROXY_AGENT_PLIST."
    return 0
  fi

  return 1
}

run_doctor() {
  if "$SCRIPT_DIR/factory-worker-preflight.sh" >"$doctor_stdout" 2>"$doctor_stderr"; then
    return 0
  fi
  return 1
}

echo "==> Syncing Factory role contract"
"$SCRIPT_DIR/sync-factory-worker-contract.sh" --write >/dev/null
record_action "sync_contract" "Rewrote Factory snapshots from the global authority."

echo "==> Checking proxy health"
health_refresh_succeeded=0
if refresh_health; then
  health_refresh_succeeded=1
else
  record_action "healthz_failure" "Initial /healthz probe failed; attempting proxy restart."
  kickstart_proxy || true
  sleep 4
  if refresh_health; then
    health_refresh_succeeded=1
  fi
fi

if [[ "$health_refresh_succeeded" != "1" ]]; then
  echo "failed to refresh proxy health after repair attempts" >&2
  exit 1
fi

backend_reachable="$(jq -r '.backend.reachable // false' "$health_json")"
factory_ready="$(jq -r '.factory_worker.ready // false' "$health_json")"
orchestration_ready="$(jq -r '.factory_roles.orchestration.ready // false' "$health_json")"
verification_ready="$(jq -r '.factory_roles.verification.ready // false' "$health_json")"
snapshot_sync_ok="$(jq -r '.factory_worker.snapshot_sync_ok // false' "$health_json")"

if [[ "$backend_reachable" != "true" || "$snapshot_sync_ok" != "true" || "$factory_ready" != "true" || "$orchestration_ready" != "true" || "$verification_ready" != "true" ]]; then
  record_action "healthz_unready" "Health endpoint reported backend_reachable=$backend_reachable snapshot_sync_ok=$snapshot_sync_ok worker_ready=$factory_ready orchestration_ready=$orchestration_ready verification_ready=$verification_ready; re-syncing and restarting proxy."
  "$SCRIPT_DIR/sync-factory-worker-contract.sh" --write >/dev/null
  kickstart_proxy || true
  sleep 4
  refresh_health
fi

echo "==> Running worker doctor"
if ! run_doctor; then
  record_action "doctor_failed" "Doctor failed; resyncing and restarting proxy before retry."
  "$SCRIPT_DIR/sync-factory-worker-contract.sh" --write >/dev/null
  kickstart_proxy || true
  sleep 4
  refresh_health
  if ! run_doctor; then
    echo "Factory worker doctor failed after repair attempts" >&2
    cat "$doctor_stderr" >&2 || true
    exit 1
  fi
fi

if [[ -f "$ROUTE_HEALTH_PATH" ]]; then
  cp "$ROUTE_HEALTH_PATH" "$route_health_json"
else
  printf '{"routes":{}}' >"$route_health_json"
fi

echo "==> Auditing Factory and mission logs"
worker_model_id="$(jq -r '.missionModelSettings.workerModel' "$GLOBAL_SETTINGS_PATH")"
validation_model_id="$(jq -r '.missionModelSettings.validationWorkerModel' "$GLOBAL_SETTINGS_PATH")"
session_model_id="$(jq -r '.sessionDefaultSettings.model' "$GLOBAL_SETTINGS_PATH")"
worker_route_model="$(jq -r --arg id "$worker_model_id" '.customModels[] | select(.id == $id) | .model' "$GLOBAL_SETTINGS_PATH")"
worker_route_provider="$(jq -r --arg id "$worker_model_id" '.customModels[] | select(.id == $id) | .provider' "$GLOBAL_SETTINGS_PATH")"
validation_route_model="$(jq -r --arg id "$validation_model_id" '.customModels[] | select(.id == $id) | .model' "$GLOBAL_SETTINGS_PATH")"
validation_route_provider="$(jq -r --arg id "$validation_model_id" '.customModels[] | select(.id == $id) | .provider' "$GLOBAL_SETTINGS_PATH")"
session_route_model="$(jq -r --arg id "$session_model_id" '.customModels[] | select(.id == $id) | .model' "$GLOBAL_SETTINGS_PATH")"
session_route_provider="$(jq -r --arg id "$session_model_id" '.customModels[] | select(.id == $id) | .provider' "$GLOBAL_SETTINGS_PATH")"

unknown_model_fallback_count=0
connection_error_count=0
backend_unavailable_count=0
claude_alias_count=0
if [[ -f "$DROID_LOG_PATH" ]]; then
  unknown_model_fallback_count="$(count_matches 'Unknown model, falling back to default' "$DROID_LOG_PATH")"
  connection_error_count="$(count_matches 'Connection error\\.' "$DROID_LOG_PATH")"
  backend_unavailable_count="$(count_matches 'All configured worker backends are currently unavailable' "$DROID_LOG_PATH")"
  claude_alias_count="$(count_matches 'claude-opus-4-6-fast' "$DROID_LOG_PATH")"
fi

mission_summary_json="$(
  find "$MISSIONS_ROOT" -name progress_log.jsonl -type f | sort | while IFS= read -r path; do
    mission_id="$(basename "$(dirname "$path")")"
    jq -s \
      --arg mission_id "$mission_id" \
      --arg path "$path" '
        def compact_event($event):
          if ($event | type) != "object" or ($event | length) == 0 then
            null
          else
            {
              timestamp: $event.timestamp,
              type: $event.type,
              featureId: $event.featureId,
              workerSessionId: $event.workerSessionId,
              spawnId: $event.spawnId,
              reason: $event.reason,
              message: $event.message,
              successState: $event.successState
            }
          end;
        {
          mission_id: $mission_id,
          path: $path,
          latest_event: compact_event(last),
          latest_worker_failed: compact_event(([.[] | select(.type == "worker_failed")] | last)),
          latest_worker_started: compact_event(([.[] | select(.type == "worker_started")] | last)),
          latest_worker_completed: compact_event(([.[] | select(.type == "worker_completed")] | last))
        }
      ' "$path"
  done | jq -s '.'
)"

route_statuses_json="$(
  jq '
    (.routes // {})
    | to_entries
    | map({
        route: .key,
        status: (.value.status // null),
        failure_score: (.value.failure_score // null),
        timeout_count: (.value.rolling_metrics.timeout_count // null),
        invalid_success_count: (.value.rolling_metrics.invalid_success_count // null)
      })
  ' "$route_health_json"
)"

suspect_route_health_count="$(
  jq '[.[] | select(.status == "suspect" or .status == "open")] | length' <<<"$route_statuses_json"
)"
if [[ "$suspect_route_health_count" -gt 0 ]]; then
  record_action "suspect_route_health_restart" "Detected $suspect_route_health_count suspect/open routes; restarting proxy to force a clean health reload."
  kickstart_proxy || true
  sleep 4
  refresh_health || true
  if [[ -f "$ROUTE_HEALTH_PATH" ]]; then
    cp "$ROUTE_HEALTH_PATH" "$route_health_json"
  else
    printf '{"routes":{}}' >"$route_health_json"
  fi
  route_statuses_json="$(
    jq '
      (.routes // {})
      | to_entries
      | map({
          route: .key,
          status: (.value.status // null),
          failure_score: (.value.failure_score // null),
          timeout_count: (.value.rolling_metrics.timeout_count // null),
          invalid_success_count: (.value.rolling_metrics.invalid_success_count // null)
        })
    ' "$route_health_json"
  )"
  suspect_route_health_count="$(
    jq '[.[] | select(.status == "suspect" or .status == "open")] | length' <<<"$route_statuses_json"
  )"
fi

root_causes_json="$(
  jq -cn \
    --argjson unknown_model_fallback_count "$unknown_model_fallback_count" \
    --argjson connection_error_count "$connection_error_count" \
    --argjson backend_unavailable_count "$backend_unavailable_count" \
    --argjson claude_alias_count "$claude_alias_count" \
    --argjson route_statuses "$route_statuses_json" \
    '[
      {
        key: "droid_model_fallback",
        present: ($unknown_model_fallback_count > 0),
        detail: ("Unknown-model fallback count in Droid log: " + ($unknown_model_fallback_count|tostring))
      },
      {
        key: "proxy_connectivity",
        present: ($connection_error_count > 0),
        detail: ("Proxy connection-error count in Droid log: " + ($connection_error_count|tostring))
      },
      {
        key: "worker_backends_unavailable",
        present: ($backend_unavailable_count > 0),
        detail: ("Worker backend unavailable count in Droid log: " + ($backend_unavailable_count|tostring))
      },
      {
        key: "historical_claude_alias_drift",
        present: ($claude_alias_count > 0),
        detail: ("Historical claude-opus-4-6-fast references in Droid log: " + ($claude_alias_count|tostring))
      },
      {
        key: "suspect_route_health",
        present: any($route_statuses[]?; .status == "suspect" or .status == "open"),
        detail: (
          "Routes currently not closed: "
          + (
              ($route_statuses
                | map(select(.status == "suspect" or .status == "open"))
                | map(.route + "=" + (.status // "unknown"))
              ) | join(", ")
            )
        )
      }
    ]'
)"

timestamp_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report_json="$(
  jq -cn \
    --arg timestamp "$timestamp_utc" \
    --arg worker_model_id "$worker_model_id" \
    --arg worker_route_model "$worker_route_model" \
    --arg worker_route_provider "$worker_route_provider" \
    --arg validation_model_id "$validation_model_id" \
    --arg validation_route_model "$validation_route_model" \
    --arg validation_route_provider "$validation_route_provider" \
    --arg session_model_id "$session_model_id" \
    --arg session_route_model "$session_route_model" \
    --arg session_route_provider "$session_route_provider" \
    --argjson actions "$actions_json" \
    --argjson root_causes "$root_causes_json" \
    --argjson mission_summary "$mission_summary_json" \
    --slurpfile health "$health_json" \
    --argjson route_statuses "$route_statuses_json" \
    '{
      timestamp_utc: $timestamp,
      models: {
        orchestration: {
          id: $session_model_id,
          model: $session_route_model,
          provider: $session_route_provider
        },
        verification: {
          id: $validation_model_id,
          model: $validation_route_model,
          provider: $validation_route_provider
        },
        worker: {
          id: $worker_model_id,
          model: $worker_route_model,
          provider: $worker_route_provider
        }
      },
      repair_actions: $actions,
      root_causes: $root_causes,
      mission_summary: $mission_summary,
      proxy_health: $health[0],
      route_statuses: $route_statuses
    }'
)"

printf '%s\n' "$report_json" >"$AUDIT_LATEST_PATH"
printf '%s\n' "$report_json" >>"$AUDIT_HISTORY_PATH"

if [[ "$suspect_route_health_count" -gt 0 ]]; then
  echo "suspect/open route health persists after audit repairs" >&2
  echo "$report_json" >&2
  exit 1
fi

echo "==> Audit complete"
echo "Latest report: $AUDIT_LATEST_PATH"
echo "$report_json"
