# factory-common.sh — shared constants and functions for factory scripts
# Source this file; do not execute it directly.

# --- config constants (all scripts) ---

FACTORY_ROOT="${FACTORY_ROOT:-$HOME/.factory}"
GLOBAL_SETTINGS_PATH="${GLOBAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.json}"
LOCAL_SETTINGS_PATH="${LOCAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.local.json}"
FRONTEND_URL="${VIBEPROXY_FRONTEND_URL:-http://127.0.0.1:8317}"
HEALTH_URL="$FRONTEND_URL/healthz"
API_KEY="${FACTORY_PROXY_API_KEY:-factory-local-proxy}"
FACTORY_PROXY_BASE_URL="${FACTORY_PROXY_BASE_URL:-$FRONTEND_URL/v1/}"
FACTORY_COMPACTION_MODEL_MODE="${FACTORY_COMPACTION_MODEL_MODE:-current-model}"
FACTORY_PUBLIC_WORKER_ROUTE_MODEL="${FACTORY_PUBLIC_WORKER_ROUTE_MODEL:-proxy-worker-smart-router}"
FACTORY_CANONICAL_WORKER_MODEL_ID="${FACTORY_CANONICAL_WORKER_MODEL_ID:-custom:Proxy-Worker-Smart-Router-8}"
FACTORY_CODE_OWNED_WORKER_MODEL_IDS_JSON="${FACTORY_CODE_OWNED_WORKER_MODEL_IDS_JSON:-[\"custom:Proxy-Worker-Smart-Router-8\",\"custom:Factory-Worker-GPT-5.4-High-8\",\"custom:Proxy-WorkerPool-8\"]}"
DROID_LOG_PATH="${DROID_LOG_PATH:-$FACTORY_ROOT/logs/droid-log-single.log}"
MISSIONS_ROOT="${MISSIONS_ROOT:-$FACTORY_ROOT/missions}"
ROUTE_HEALTH_PATH="${ROUTE_HEALTH_PATH:-$HOME/.cli-proxy-api/route-health.json}"
MERGED_CONFIG_PATH="${MERGED_CONFIG_PATH:-${VIBEPROXY_MERGED_CONFIG_PATH:-$HOME/.cli-proxy-api/merged-config.yaml}}"

PROJECT_SETTINGS=(
  "$HOME/CascadeProjects/songbird4/.factory/settings.json"
  "$HOME/CascadeProjects/voc/.factory/settings.json"
  "$HOME/CascadeProjects/merchant-warrior2/.factory/settings.json"
  "$HOME/CascadeProjects/pi_agent_rust/.factory/settings.json"
)

# --- guard ---

require_global_settings() {
  if [[ ! -f "$GLOBAL_SETTINGS_PATH" ]]; then
    echo "missing global settings: $GLOBAL_SETTINGS_PATH" >&2
    return 1
  fi
}

normalized_factory_custom_models() {
  local settings="$1"

  jq -c \
    --arg canonical_worker_id "$FACTORY_CANONICAL_WORKER_MODEL_ID" \
    --arg worker_route_model "$FACTORY_PUBLIC_WORKER_ROUTE_MODEL" \
    --arg proxy_base_url "$FACTORY_PROXY_BASE_URL" \
    --arg api_key "$API_KEY" \
    --arg retired_worker_id "custom:Factory-Worker-GPT-5.4-High-8" \
    --arg retired_worker_display_name "Factory Worker GPT-5.4 High" \
    --argjson retired_worker_index '8' \
    --arg retired_pool_id "custom:Proxy-WorkerPool-8" \
    --arg retired_pool_display_name "Proxy WorkerPool" \
    --argjson retired_pool_index '8' \
    '
      def seed_for($models; $canonical_worker_id; $id):
        (($models[]? | select(.id == $id)) // ($models[]? | select(.id == $canonical_worker_id)) // {});
      def normalized_worker_entry($models; $canonical_worker_id; $worker_route_model; $proxy_base_url; $api_key; $id; $display_name; $index):
          (seed_for($models; $canonical_worker_id; $id) + {
            id: $id,
            model: $worker_route_model,
            provider: "generic-chat-completion-api",
            displayName: $display_name,
            baseUrl: $proxy_base_url,
            apiKey: $api_key,
            noImageSupport: (seed_for($models; $canonical_worker_id; $id).noImageSupport // true),
            maxOutputTokens: (seed_for($models; $canonical_worker_id; $id).maxOutputTokens // 32768),
            index: (seed_for($models; $canonical_worker_id; $id).index // $index)
          });
      def upsert($entry):
          map(if .id == $entry.id then . + $entry else . end)
          | if any(.[]; .id == $entry.id) then . else . + [$entry] end;
      (.customModels // []) as $models
      | $models
      | upsert(normalized_worker_entry($models; $canonical_worker_id; $worker_route_model; $proxy_base_url; $api_key; $canonical_worker_id; "Proxy Worker Smart Router"; 8))
      | upsert(normalized_worker_entry($models; $canonical_worker_id; $worker_route_model; $proxy_base_url; $api_key; $retired_worker_id; $retired_worker_display_name; $retired_worker_index))
      | upsert(normalized_worker_entry($models; $canonical_worker_id; $worker_route_model; $proxy_base_url; $api_key; $retired_pool_id; $retired_pool_display_name; $retired_pool_index))
    ' \
    "$settings"
}

# --- settings reader ---

# Reads ~/.factory/settings.json and exports shell variables for every field
# the factory scripts need.  Returns 1 if any required model ID is null/empty.
#
# Exported variables:
#   FACTORY_SESSION_MODEL          .sessionDefaultSettings.model
#   FACTORY_SESSION_REASONING      .sessionDefaultSettings.reasoningEffort
#   FACTORY_SESSION_AUTONOMY       .sessionDefaultSettings.autonomyMode
#   FACTORY_WORKER_MODEL           .missionModelSettings.workerModel
#   FACTORY_WORKER_REASONING       .missionModelSettings.workerReasoningEffort
#   FACTORY_VALIDATION_MODEL       .missionModelSettings.validationWorkerModel
#   FACTORY_VALIDATION_REASONING   .missionModelSettings.validationWorkerReasoningEffort
#   FACTORY_WORKER_ROUTE_MODEL     wire model resolved from Factory customModels
#   FACTORY_WORKER_ROUTE_PROVIDER  wire provider resolved from Factory customModels
#   FACTORY_SESSION_ROUTE_MODEL    wire model resolved from Factory customModels
#   FACTORY_SESSION_ROUTE_PROVIDER wire provider resolved from Factory customModels
#   FACTORY_VALIDATION_ROUTE_MODEL    wire model resolved from Factory customModels
#   FACTORY_VALIDATION_ROUTE_PROVIDER wire provider resolved from Factory customModels
#   FACTORY_CANONICAL_CUSTOM_MODELS   full customModels array (JSON)

load_factory_models() {
  local settings="$GLOBAL_SETTINGS_PATH"

  FACTORY_SESSION_MODEL="$(jq -r '.sessionDefaultSettings.model' "$settings")"
  FACTORY_SESSION_REASONING="$(jq -r '.sessionDefaultSettings.reasoningEffort' "$settings")"
  FACTORY_SESSION_AUTONOMY="$(jq -r '.sessionDefaultSettings.autonomyMode' "$settings")"
  FACTORY_WORKER_MODEL="$(jq -r '.missionModelSettings.workerModel' "$settings")"
  FACTORY_WORKER_REASONING="$(jq -r '.missionModelSettings.workerReasoningEffort' "$settings")"
  FACTORY_VALIDATION_MODEL="$(jq -r '.missionModelSettings.validationWorkerModel' "$settings")"
  FACTORY_VALIDATION_REASONING="$(jq -r '.missionModelSettings.validationWorkerReasoningEffort' "$settings")"

  local missing=()
  if [[ -z "$FACTORY_SESSION_MODEL" || "$FACTORY_SESSION_MODEL" == "null" ]]; then
    missing+=("sessionDefaultSettings.model")
  fi
  if [[ -z "$FACTORY_WORKER_MODEL" || "$FACTORY_WORKER_MODEL" == "null" ]]; then
    missing+=("missionModelSettings.workerModel")
  fi
  if [[ -z "$FACTORY_VALIDATION_MODEL" || "$FACTORY_VALIDATION_MODEL" == "null" ]]; then
    missing+=("missionModelSettings.validationWorkerModel")
  fi
  if (( ${#missing[@]} > 0 )); then
    echo "global settings missing required fields: ${missing[*]}" >&2
    return 1
  fi

  FACTORY_CANONICAL_CUSTOM_MODELS="$(normalized_factory_custom_models "$settings")"

  # Resolve custom-model IDs to their route model + provider.
  # For non-custom models (e.g. "gpt-5.4"), try:
  #   1. Exact custom model ID match
  #   2. Model name + reasoning effort (e.g. "gpt-5.4" + "high" -> "gpt-5.4(high)")
  #   3. Model name prefix match
  resolve_custom_model() {
    local model_id="$1"
    local reasoning="${2:-}"
    jq -r --arg id "$model_id" --arg model_name "$model_id" --arg reasoning "$reasoning" '
      (.[] | select(.id == $id) | .model) //
      (if ($reasoning | length) > 0 then
        (.[] | select(.model == ($model_name + "(" + $reasoning + ")")) | .model)
      else empty end) //
      (.[] | select($model_name | startswith(.model)) | .model) //
      empty
    ' <<<"$FACTORY_CANONICAL_CUSTOM_MODELS"
  }
  resolve_custom_provider() {
    local model_id="$1"
    local reasoning="${2:-}"
    jq -r --arg id "$model_id" --arg model_name "$model_id" --arg reasoning "$reasoning" '
      (.[] | select(.id == $id) | .provider) //
      (if ($reasoning | length) > 0 then
        (.[] | select(.model == ($model_name + "(" + $reasoning + ")")) | .provider)
      else empty end) //
      (.[] | select($model_name | startswith(.model)) | .provider) //
      empty
    ' <<<"$FACTORY_CANONICAL_CUSTOM_MODELS"
  }
  FACTORY_WORKER_ROUTE_MODEL="$(resolve_custom_model "$FACTORY_WORKER_MODEL" "$FACTORY_WORKER_REASONING")"
  FACTORY_WORKER_ROUTE_PROVIDER="$(resolve_custom_provider "$FACTORY_WORKER_MODEL" "$FACTORY_WORKER_REASONING")"
  FACTORY_SESSION_ROUTE_MODEL="$(resolve_custom_model "$FACTORY_SESSION_MODEL" "$FACTORY_SESSION_REASONING")"
  FACTORY_SESSION_ROUTE_PROVIDER="$(resolve_custom_provider "$FACTORY_SESSION_MODEL" "$FACTORY_SESSION_REASONING")"
  FACTORY_VALIDATION_ROUTE_MODEL="$(resolve_custom_model "$FACTORY_VALIDATION_MODEL" "$FACTORY_VALIDATION_REASONING")"
  FACTORY_VALIDATION_ROUTE_PROVIDER="$(resolve_custom_provider "$FACTORY_VALIDATION_MODEL" "$FACTORY_VALIDATION_REASONING")"

  # Normalise null to empty for non-custom models.
  FACTORY_WORKER_ROUTE_MODEL="${FACTORY_WORKER_ROUTE_MODEL/null/}"
  FACTORY_WORKER_ROUTE_PROVIDER="${FACTORY_WORKER_ROUTE_PROVIDER/null/}"
  FACTORY_SESSION_ROUTE_MODEL="${FACTORY_SESSION_ROUTE_MODEL/null/}"
  FACTORY_SESSION_ROUTE_PROVIDER="${FACTORY_SESSION_ROUTE_PROVIDER/null/}"
  FACTORY_VALIDATION_ROUTE_MODEL="${FACTORY_VALIDATION_ROUTE_MODEL/null/}"
  FACTORY_VALIDATION_ROUTE_PROVIDER="${FACTORY_VALIDATION_ROUTE_PROVIDER/null/}"
  export \
    FACTORY_SESSION_MODEL FACTORY_SESSION_REASONING FACTORY_SESSION_AUTONOMY \
    FACTORY_WORKER_MODEL FACTORY_WORKER_REASONING \
    FACTORY_VALIDATION_MODEL FACTORY_VALIDATION_REASONING \
    FACTORY_WORKER_ROUTE_MODEL FACTORY_WORKER_ROUTE_PROVIDER \
    FACTORY_SESSION_ROUTE_MODEL FACTORY_SESSION_ROUTE_PROVIDER \
    FACTORY_VALIDATION_ROUTE_MODEL FACTORY_VALIDATION_ROUTE_PROVIDER \
    FACTORY_CANONICAL_CUSTOM_MODELS FACTORY_PROXY_BASE_URL \
    FACTORY_COMPACTION_MODEL_MODE \
    FACTORY_PUBLIC_WORKER_ROUTE_MODEL FACTORY_CANONICAL_WORKER_MODEL_ID \
    FACTORY_CODE_OWNED_WORKER_MODEL_IDS_JSON
}

# --- provider helpers ---

provider_to_surface() {
  local provider="$1"
  local role="${2:-provider}"
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
      echo "unsupported Factory $role provider: $provider" >&2
      return 1
      ;;
  esac
}

# --- temp dir ---

# Sets FACTORY_TMP_DIR and installs an EXIT trap to clean it up.
# Call once near the top of the script after sourcing.
make_temp_dir() {
  local prefix="${1:-factory}"
  local tmp_base="${TMPDIR:-$HOME/.tmp}"
  mkdir -p "$tmp_base"
  FACTORY_TMP_DIR="$(mktemp -d "$tmp_base/$prefix.XXXXXX")"
  export FACTORY_TMP_DIR
  trap 'rm -rf "$FACTORY_TMP_DIR"' EXIT
}
