#!/bin/bash

set -euo pipefail

MODE="write"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
elif [[ "${1:-}" == "--write" ]]; then
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=factory-common.sh
source "$SCRIPT_DIR/factory-common.sh"

require_global_settings
load_factory_models
make_temp_dir factory-sync

mismatches=()

managed_custom_ids="$(jq -c '
  [
    .sessionDefaultSettings.model,
    .missionModelSettings.workerModel,
    .missionModelSettings.validationWorkerModel
  ]
  | map(select(type == "string" and startswith("custom:")))
  | unique
' "$GLOBAL_SETTINGS_PATH")"
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
  local temp_file="$FACTORY_TMP_DIR/$(basename "$path").tmp"
  jq \
    --arg worker_id "$FACTORY_WORKER_MODEL" \
    --arg validation_worker_id "$FACTORY_VALIDATION_MODEL" \
    --arg session_model_id "$FACTORY_SESSION_MODEL" \
    --arg session_reasoning "$FACTORY_SESSION_REASONING" \
    --arg session_autonomy "$FACTORY_SESSION_AUTONOMY" \
    --arg worker_reasoning "$FACTORY_WORKER_REASONING" \
    --arg validation_reasoning "$FACTORY_VALIDATION_REASONING" \
    --argjson canonical_custom_models "$FACTORY_CANONICAL_CUSTOM_MODELS" \
    --argjson managed_custom_ids "$managed_custom_ids" \
    --argjson managed_models "$managed_models_json" \
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
    echo "  session/orchestrator: $FACTORY_SESSION_MODEL" >&2
    echo "  worker: $FACTORY_WORKER_MODEL" >&2
    echo "  validation: $FACTORY_VALIDATION_MODEL" >&2
    printf '  %s\n' "${mismatches[@]}" >&2
    exit 1
  fi
  echo "factory role contract is in sync"
  echo "  session/orchestrator: $FACTORY_SESSION_MODEL"
  echo "  worker: $FACTORY_WORKER_MODEL"
  echo "  validation: $FACTORY_VALIDATION_MODEL"
  exit 0
fi

echo "synced factory role contract from $GLOBAL_SETTINGS_PATH"
echo "  session/orchestrator: $FACTORY_SESSION_MODEL"
echo "  worker: $FACTORY_WORKER_MODEL"
echo "  validation: $FACTORY_VALIDATION_MODEL"
