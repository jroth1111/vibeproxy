#!/bin/bash

set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=factory-common.sh
source "$SCRIPT_DIR/factory-common.sh"

require_global_settings

GUARD_ROOT="${FACTORY_ROOT}/monitoring/factory-contract-guard"
mkdir -p "$GUARD_ROOT"

LOCK_DIR="$GUARD_ROOT/.lock"
LOG_PATH="$GUARD_ROOT/history.log"
lock_acquired=0

cleanup() {
  if [[ "$lock_acquired" == "1" ]]; then
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
lock_acquired=1

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

if "$SCRIPT_DIR/sync-factory-worker-contract.sh" --check >/dev/null 2>&1; then
  # Contract is healthy — still run path stripping health check below
  :
else
  "$SCRIPT_DIR/sync-factory-worker-contract.sh" --write >/dev/null
  "$SCRIPT_DIR/sync-factory-worker-contract.sh" --check >/dev/null

  printf '%s repaired Factory worker contract drift\n' "$(timestamp)" >>"$LOG_PATH"
fi

# Verify Factory API path stripping works (Droid BYOK fallback mitigation).
# Tests all three Factory fallback path formats: OpenAI, Anthropic, Gemini.
# Runs every cycle regardless of contract drift status.
_strip_ok=true
for _path_label in "openai:/api/llm/o/v1/chat/completions" "anthropic:/api/llm/a/v1/messages" "gemini:/api/llm/g/v1/chat/completions"; do
  _label="${_path_label%%:*}"
  _fpath="${_path_label#*:}"
  _code=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://127.0.0.1:8317${_fpath}" \
    -H "Authorization: Bearer factory-local-proxy" \
    -H "Content-Type: application/json" \
    -H "x-api-key: factory-local-proxy" \
    -d '{"model":"guard-test","messages":[{"role":"user","content":"ping"}]}' \
    --max-time 5 2>/dev/null || echo "000")
  if [[ "$_code" == "000" ]]; then
    printf '%s WARN: Factory path stripping (%s): connection failed\n' "$(timestamp)" "$_label" >>"$LOG_PATH"
    _strip_ok=false
  elif [[ "$_code" == "404" ]]; then
    printf '%s WARN: Factory path stripping (%s): got 404 — path not stripped\n' "$(timestamp)" "$_label" >>"$LOG_PATH"
    _strip_ok=false
  fi
done
if [[ "$_strip_ok" == "true" ]]; then
  # Log healthy status once per hour (not every 15s)
  _hour_marker="$(date -u '+%Y-%m-%dT%H')"
  _last_healthy="$GUARD_ROOT/.last-strip-healthy"
  if [[ "$(cat "$_last_healthy" 2>/dev/null)" != "$_hour_marker" ]]; then
    printf '%s OK: Factory path stripping healthy (openai+anthropic+gemini)\n' "$(timestamp)" >>"$LOG_PATH"
    printf '%s' "$_hour_marker" >"$_last_healthy"
  fi
fi
