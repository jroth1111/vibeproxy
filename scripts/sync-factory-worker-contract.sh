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

managed_custom_ids="$(jq -cn \
  --arg session_model_id "$FACTORY_SESSION_MODEL" \
  --arg worker_id "$FACTORY_WORKER_MODEL" \
  --arg validation_worker_id "$FACTORY_VALIDATION_MODEL" '
    [$session_model_id, $worker_id, $validation_worker_id]
    | map(select(type == "string" and startswith("custom:")))
    | unique
  ')"
managed_models_json="$(jq -cn --argjson ids "$managed_custom_ids" --argjson canonical_custom_models "$FACTORY_CANONICAL_CUSTOM_MODELS" '
  $canonical_custom_models
  | map(select(.id as $id | ($ids | index($id)) != null))
' )"
managed_model_id_mismatches="$(jq -cn --argjson ids "$managed_custom_ids" --argjson canonical_custom_models "$FACTORY_CANONICAL_CUSTOM_MODELS" '
  $canonical_custom_models
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
' )"

worker_contract_mismatches="$(
  jq -cn \
    --arg worker_id "$FACTORY_WORKER_MODEL" \
    --arg worker_route_model "$FACTORY_PUBLIC_WORKER_ROUTE_MODEL" \
    --arg proxy_base_url "$FACTORY_PROXY_BASE_URL" \
    --argjson code_owned_worker_ids "$FACTORY_CODE_OWNED_WORKER_MODEL_IDS_JSON" \
    --argjson canonical_custom_models "$FACTORY_CANONICAL_CUSTOM_MODELS" '
      if ($code_owned_worker_ids | index($worker_id)) == null then
        []
      else
        (($canonical_custom_models[] | select(.id == $worker_id)) // {}) as $worker
        | [
            (if ($worker.model // "") != $worker_route_model then "model=\($worker.model // "<missing>")" else empty end),
            (if ($worker.provider // "") != "generic-chat-completion-api" then "provider=\($worker.provider // "<missing>")" else empty end),
            (if ($worker.baseUrl // "") != $proxy_base_url then "baseUrl=\($worker.baseUrl // "<missing>")" else empty end)
          ]
      end
    '
)"

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

if [[ "$(jq 'length' <<<"$worker_contract_mismatches")" != "0" ]]; then
  echo "global settings worker contract is not Droid-safe:" >&2
  jq -r '.[] | "  " + .' <<<"$worker_contract_mismatches" >&2
  echo "  expected model=$FACTORY_PUBLIC_WORKER_ROUTE_MODEL provider=generic-chat-completion-api baseUrl=$FACTORY_PROXY_BASE_URL" >&2
  exit 1
fi

if [[ ! -f "$MERGED_CONFIG_PATH" ]]; then
  echo "missing merged proxy config: $MERGED_CONFIG_PATH" >&2
  exit 1
fi

self_routed_managed_ids="$(
  jq -cn \
    --argjson managed_models "$managed_models_json" '
      $managed_models
      | map(select((.id // "") != "" and (.model // "") == (.id // "")))
      | map(.id)
    '
)"

required_alias_mismatches="$(
  jq -cn \
    --arg worker_id "$FACTORY_WORKER_MODEL" \
    --argjson required_ids "$self_routed_managed_ids" \
    --argjson merged_root "$(ruby -e 'require "yaml"; require "json"; puts((YAML.load_file(ARGV[0]) || {}).to_json)' "$MERGED_CONFIG_PATH")" '
      ($merged_root["smart-aliases"] // {}) as $smartAliases
      | $required_ids
      | map(
          select(
            (
              ((($smartAliases[.] // {})["candidates"] // []) | length) == 0
            )
            and
            (
              (. != $worker_id)
              or (((($smartAliases["worker"] // {})["candidates"] // []) | length) == 0)
            )
          )
        )
    '
)"

worker_alias_missing="$(
  jq -cn \
    --arg worker_id "$FACTORY_WORKER_MODEL" \
    --argjson code_owned_worker_ids "$FACTORY_CODE_OWNED_WORKER_MODEL_IDS_JSON" \
    --argjson merged_root "$(ruby -e 'require "yaml"; require "json"; puts((YAML.load_file(ARGV[0]) || {}).to_json)' "$MERGED_CONFIG_PATH")" '
      if ($code_owned_worker_ids | index($worker_id)) == null then
        false
      else
        (((($merged_root["smart-aliases"] // {})["worker"] // {})["candidates"] // []) | length) == 0
      end
    '
)"

if [[ "$(jq 'length' <<<"$required_alias_mismatches")" != "0" ]]; then
  echo "merged proxy config is missing exact smart-alias entries for self-routed managed custom ids:" >&2
  jq -r '.[] | "  \(.)"' <<<"$required_alias_mismatches" >&2
  exit 1
fi

if [[ "$worker_alias_missing" == "true" ]]; then
  echo "merged proxy config is missing the worker smart-alias candidate list required by the Droid-safe Factory worker contract" >&2
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
    --arg compaction_model_mode "$FACTORY_COMPACTION_MODEL_MODE" \
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
  | .general.compactionModelMode = $compaction_model_mode
  | .missionModelSettings.workerModel = $worker_id
  | .missionModelSettings.workerReasoningEffort = $worker_reasoning
  | .missionModelSettings.validationWorkerModel = $validation_worker_id
  | .missionModelSettings.validationWorkerReasoningEffort = $validation_reasoning
  | .customModels = $canonical_custom_models
'

runtime_filter='
  .customModels = $canonical_custom_models
'

sync_json_file "$GLOBAL_SETTINGS_PATH" "$settings_filter"
sync_json_file "$LOCAL_SETTINGS_PATH" "$settings_filter"

for path in "${PROJECT_SETTINGS[@]}"; do
  sync_json_file "$path" "$settings_filter"
done

while IFS= read -r mission_settings; do
  sync_json_file "$mission_settings" "
    .sessionModel = \$session_model_id
    | .sessionReasoningEffort = \$session_reasoning
    | .workerModel = \$worker_id
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
  echo "  compaction-model-mode: $FACTORY_COMPACTION_MODEL_MODE"
  if [[ "$(jq 'length' <<<"$self_routed_managed_ids")" != "0" ]]; then
    echo "  exact proxy smart-aliases:"
    jq -r '.[] | "    " + .' <<<"$self_routed_managed_ids"
  fi
  exit 0
fi

echo "synced factory role contract from $GLOBAL_SETTINGS_PATH"
echo "  session/orchestrator: $FACTORY_SESSION_MODEL"
echo "  worker: $FACTORY_WORKER_MODEL"
echo "  validation: $FACTORY_VALIDATION_MODEL"
echo "  compaction-model-mode: $FACTORY_COMPACTION_MODEL_MODE"
if [[ "$(jq 'length' <<<"$self_routed_managed_ids")" != "0" ]]; then
  echo "  exact proxy smart-aliases:"
  jq -r '.[] | "    " + .' <<<"$self_routed_managed_ids"
fi
