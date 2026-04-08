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
  exit 0
fi

"$SCRIPT_DIR/sync-factory-worker-contract.sh" --write >/dev/null
"$SCRIPT_DIR/sync-factory-worker-contract.sh" --check >/dev/null

printf '%s repaired Factory worker contract drift\n' "$(timestamp)" >>"$LOG_PATH"
