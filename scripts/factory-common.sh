# factory-common.sh — shared constants and functions for factory scripts
# Source this file; do not execute it directly.

# --- config constants (all scripts) ---

FACTORY_ROOT="${FACTORY_ROOT:-$HOME/.factory}"
GLOBAL_SETTINGS_PATH="${GLOBAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.json}"
LOCAL_SETTINGS_PATH="${LOCAL_SETTINGS_PATH:-$FACTORY_ROOT/settings.local.json}"
FRONTEND_URL="${VIBEPROXY_FRONTEND_URL:-http://127.0.0.1:8317}"
HEALTH_URL="$FRONTEND_URL/healthz"
API_KEY="${FACTORY_PROXY_API_KEY:-factory-local-proxy}"
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

  # Resolve custom-model IDs to their route model + provider.
  # For non-custom models (e.g. "gpt-5.4"), try:
  #   1. Exact custom model ID match
  #   2. Model name + reasoning effort (e.g. "gpt-5.4" + "high" -> "gpt-5.4(high)")
  #   3. Model name prefix match
  resolve_custom_model() {
    local model_id="$1"
    local reasoning="${2:-}"
    jq -r --arg id "$model_id" --arg model_name "$model_id" --arg reasoning "$reasoning" '
      (.customModels[] | select(.id == $id) | .model) //
      (if ($reasoning | length) > 0 then
        (.customModels[] | select(.model == ($model_name + "(" + $reasoning + ")")) | .model)
      else empty end) //
      (.customModels[] | select($model_name | startswith(.model)) | .model) //
      empty
    ' "$settings"
  }
  resolve_custom_provider() {
    local model_id="$1"
    local reasoning="${2:-}"
    jq -r --arg id "$model_id" --arg model_name "$model_id" --arg reasoning "$reasoning" '
      (.customModels[] | select(.id == $id) | .provider) //
      (if ($reasoning | length) > 0 then
        (.customModels[] | select(.model == ($model_name + "(" + $reasoning + ")")) | .provider)
      else empty end) //
      (.customModels[] | select($model_name | startswith(.model)) | .provider) //
      empty
    ' "$settings"
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

  FACTORY_CANONICAL_CUSTOM_MODELS="$(jq -c '(.customModels // [])' "$settings")"

  export \
    FACTORY_SESSION_MODEL FACTORY_SESSION_REASONING FACTORY_SESSION_AUTONOMY \
    FACTORY_WORKER_MODEL FACTORY_WORKER_REASONING \
    FACTORY_VALIDATION_MODEL FACTORY_VALIDATION_REASONING \
    FACTORY_WORKER_ROUTE_MODEL FACTORY_WORKER_ROUTE_PROVIDER \
    FACTORY_SESSION_ROUTE_MODEL FACTORY_SESSION_ROUTE_PROVIDER \
    FACTORY_VALIDATION_ROUTE_MODEL FACTORY_VALIDATION_ROUTE_PROVIDER \
    FACTORY_CANONICAL_CUSTOM_MODELS
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
