#!/bin/bash

set -euo pipefail

MODE="write"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
elif [[ "${1:-}" == "--write" ]]; then
  shift
fi

FACTORY_ROOT="${FACTORY_ROOT:-$HOME/.factory}"
GLOBAL_SETTINGS_PATH="${GLOBAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.json}"
LOCAL_SETTINGS_PATH="${LOCAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.local.json}"

PROJECT_SETTINGS=(
  "$HOME/CascadeProjects/songbird4/.factory/settings.json"
  "$HOME/CascadeProjects/voc/.factory/settings.json"
  "$HOME/CascadeProjects/merchant-warrior2/.factory/settings.json"
  "$HOME/CascadeProjects/pi_agent_rust/.factory/settings.json"
)

if [[ ! -f "$GLOBAL_SETTINGS_PATH" ]]; then
  echo "missing global settings: $GLOBAL_SETTINGS_PATH" >&2
  exit 1
fi

tmp_base="${TMPDIR:-$HOME/.tmp}"
mkdir -p "$tmp_base"
tmp_dir="$(mktemp -d "$tmp_base/factory-worker-sync.XXXXXX")"
mismatches=()
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

worker_id="$(jq -r '.missionModelSettings.workerModel' "$GLOBAL_SETTINGS_PATH")"
validation_worker_id="$(jq -r '.missionModelSettings.validationWorkerModel' "$GLOBAL_SETTINGS_PATH")"
session_model_id="$(jq -r '.sessionDefaultSettings.model' "$GLOBAL_SETTINGS_PATH")"
session_reasoning="$(jq -r '.sessionDefaultSettings.reasoningEffort' "$GLOBAL_SETTINGS_PATH")"
session_autonomy="$(jq -r '.sessionDefaultSettings.autonomyMode' "$GLOBAL_SETTINGS_PATH")"
worker_reasoning="$(jq -r '.missionModelSettings.workerReasoningEffort' "$GLOBAL_SETTINGS_PATH")"
validation_reasoning="$(jq -r '.missionModelSettings.validationWorkerReasoningEffort' "$GLOBAL_SETTINGS_PATH")"
managed_custom_ids="$(jq -c '
  [
    .sessionDefaultSettings.model,
    .missionModelSettings.workerModel,
    .missionModelSettings.validationWorkerModel
  ]
  | map(select(type == "string" and startswith("custom:")))
  | unique
' "$GLOBAL_SETTINGS_PATH")"
canonical_custom_models_json="$(jq -c '(.customModels // [])' "$GLOBAL_SETTINGS_PATH")"
managed_models_json="$(jq -c --argjson ids "$managed_custom_ids" '
  (.customModels // [])
  | map(select(.id as $id | ($ids | index($id)) != null))
' "$GLOBAL_SETTINGS_PATH")"
managed_model_id_mismatches="$(jq -c --argjson ids "$managed_custom_ids" '
  (.customModels // [])
  | to_entries
  | map(select(.value.id as $id | ($ids | index($id)) != null))
  | map({
      id: .value.id,
      displayName: (.value.displayName // .value.model),
      expectedId: (
        "custom:"
        + (
            ((.value.displayName // .value.model) | gsub("^\\s+|\\s+$"; ""))
            | gsub("\\s+"; "-")
          )
        + "-"
        + ((.value.index // .key) | tostring)
      )
    })
  | map(select(.id != .expectedId))
' "$GLOBAL_SETTINGS_PATH")"
retired_worker_ids="$(jq -cn '[]')"

if [[ -z "$worker_id" || "$worker_id" == "null" ]]; then
  echo "global settings missing missionModelSettings.workerModel" >&2
  exit 1
fi

if [[ -z "$session_model_id" || "$session_model_id" == "null" ]]; then
  echo "global settings missing sessionDefaultSettings.model" >&2
  exit 1
fi

if [[ -z "$validation_worker_id" || "$validation_worker_id" == "null" ]]; then
  echo "global settings missing missionModelSettings.validationWorkerModel" >&2
  exit 1
fi

expected_managed_count="$(jq 'length' <<<"$managed_custom_ids")"
actual_managed_count="$(jq 'length' <<<"$managed_models_json")"
if [[ "$expected_managed_count" != "$actual_managed_count" ]]; then
  missing_managed_ids="$(
    jq -nr \
      --argjson ids "$managed_custom_ids" \
      --argjson models "$managed_models_json" '
        $ids - ($models | map(.id))
      '
  )"
  echo "global settings missing custom model definitions for: $missing_managed_ids" >&2
  exit 1
fi

if [[ "$(jq 'length' <<<"$managed_model_id_mismatches")" != "0" ]]; then
  echo "global settings contain Droid-incompatible managed custom model ids:" >&2
  jq -r '.[] | "  \(.id) != \(.expectedId) (displayName: \(.displayName))"' <<<"$managed_model_id_mismatches" >&2
  exit 1
fi

sync_json_file() {
  local path="$1"
  local jq_filter="$2"

  if [[ ! -f "$path" ]]; then
    if [[ "$MODE" == "check" ]]; then
      mismatches+=("$path (missing)")
    fi
    return 0
  fi
  local temp_file="$tmp_dir/$(basename "$path").tmp"
  jq \
    --arg worker_id "$worker_id" \
    --arg validation_worker_id "$validation_worker_id" \
    --arg session_model_id "$session_model_id" \
    --arg session_reasoning "$session_reasoning" \
    --arg session_autonomy "$session_autonomy" \
    --arg worker_reasoning "$worker_reasoning" \
    --arg validation_reasoning "$validation_reasoning" \
    --argjson canonical_custom_models "$canonical_custom_models_json" \
    --argjson managed_custom_ids "$managed_custom_ids" \
    --argjson managed_models "$managed_models_json" \
    --argjson retired_worker_ids "$retired_worker_ids" \
    "$jq_filter" \
    "$path" > "$temp_file"

  if [[ "$MODE" == "check" ]]; then
    local actual_json expected_json
    actual_json="$(jq -S -c . "$path")"
    expected_json="$(jq -S -c . "$temp_file")"
    if [[ "$actual_json" != "$expected_json" ]]; then
      mismatches+=("$path")
    fi
    return 0
  fi

  mv "$temp_file" "$path"
}

settings_filter='
  (if has("model") then .model = $session_model_id else . end)
  | .sessionDefaultSettings.model = $session_model_id
  | .sessionDefaultSettings.reasoningEffort = $session_reasoning
  | .sessionDefaultSettings.autonomyMode = $session_autonomy
  | .missionModelSettings.workerModel = $worker_id
  | .missionModelSettings.workerReasoningEffort = $worker_reasoning
  | .missionModelSettings.validationWorkerModel = $validation_worker_id
  | .missionModelSettings.validationWorkerReasoningEffort = $validation_reasoning
  | .customModels = $canonical_custom_models
'

runtime_filter='
  .customModels = $canonical_custom_models
'

sync_json_file "$LOCAL_SETTINGS_PATH" "$settings_filter"

for path in "${PROJECT_SETTINGS[@]}"; do
  sync_json_file "$path" "$settings_filter"
done

while IFS= read -r mission_settings; do
  sync_json_file "$mission_settings" "
    .workerModel = \$worker_id
    | .workerReasoningEffort = \$worker_reasoning
    | .validationWorkerModel = \$validation_worker_id
    | .validationWorkerReasoningEffort = \$validation_reasoning
  "
done < <(find "$FACTORY_ROOT/missions" -name model-settings.json -type f | sort)

while IFS= read -r runtime_catalog; do
  sync_json_file "$runtime_catalog" "$runtime_filter"
done < <(find "$FACTORY_ROOT/missions" -name runtime-custom-models.json -type f | sort)

if [[ "$MODE" == "check" ]]; then
  if (( ${#mismatches[@]} > 0 )); then
    echo "factory role contract drift detected:" >&2
    echo "  session/orchestrator: $session_model_id" >&2
    echo "  worker: $worker_id" >&2
    echo "  validation: $validation_worker_id" >&2
    printf '  %s\n' "${mismatches[@]}" >&2
    exit 1
  fi
  echo "factory role contract is in sync"
  echo "  session/orchestrator: $session_model_id"
  echo "  worker: $worker_id"
  echo "  validation: $validation_worker_id"
  exit 0
fi

echo "synced factory role contract from $GLOBAL_SETTINGS_PATH"
echo "  session/orchestrator: $session_model_id"
echo "  worker: $worker_id"
echo "  validation: $validation_worker_id"
