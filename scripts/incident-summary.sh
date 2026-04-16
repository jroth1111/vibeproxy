#!/bin/bash

# Incident summary — operator command for rapid triage.
# Usage: ./scripts/incident-summary.sh [--hours N]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEALTH_URL="http://127.0.0.1:8317/healthz"
HOURS=2

while [[ $# -gt 0 ]]; do
    case $1 in
        --hours) HOURS="$2"; shift 2 ;;
        *) echo "Usage: $0 [--hours N]" >&2; exit 1 ;;
    esac
done

echo "══════════════════════════════════════════════════════"
echo "  VibeProxy Incident Summary  ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Current PID ─────────────────────────────────────────────────────────
echo "▸ Current PID"
PID=$(pgrep -f "VibeProxy" 2>/dev/null | head -1 || echo "not running")
echo "  $PID"
echo ""

# ── Winner distribution (last N hours) ──────────────────────────────────
echo "▸ Winner distribution (last ${HOURS}h)"
"$ROOT_DIR/scripts/route-telemetry-summary.py" --hours "$HOURS" --pid current --json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    winners = d.get('winner_distribution', {})
    if not winners:
        print('  <no winners>')
    else:
        for k, v in sorted(winners.items(), key=lambda x: -x[1]):
            print(f'  {k}: {v}')
except Exception:
    print('  <no telemetry data>')
" 2>/dev/null || echo "  <no telemetry data>"
echo ""

# ── Attempt lane distribution ───────────────────────────────────────────
echo "▸ Attempt lane distribution"
"$ROOT_DIR/scripts/route-telemetry-summary.py" --hours "$HOURS" --pid current --json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for k, v in sorted(d.get('attempt_distribution', {}).items(), key=lambda x: -x[1]):
        print(f'  {k}: {v}')
except Exception:
    print('  <no data>')
" 2>/dev/null || echo "  <no data>"
echo ""

# ── Failure distribution ────────────────────────────────────────────────
echo "▸ Failure distribution"
"$ROOT_DIR/scripts/route-telemetry-summary.py" --hours "$HOURS" --pid current --json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    failures = d.get('failure_distribution', {})
    if not failures:
        print('  <no failures>')
    else:
        for k, v in sorted(failures.items(), key=lambda x: -x[1]):
            print(f'  {k}: {v}')
except Exception:
    print('  <no data>')
" 2>/dev/null || echo "  <no data>"
echo ""

# ── Worker effective route (from healthz) ───────────────────────────────
echo "▸ Worker effective route"
curl -sf "$HEALTH_URL" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    fw = d.get('factory_worker', {})
    if isinstance(fw, dict) and 'effective_route_model' in fw:
        print(f'  {fw.get(\"effective_route_model\")} (source: {fw.get(\"effective_route_model_source\", \"unknown\")})')
except Exception:
    print('  <no healthz data>')
" 2>/dev/null || echo "  <healthz not reachable>"
echo ""

# ── Possible BYOK fallthrough ───────────────────────────────────────────
echo "▸ Possible BYOK fallthrough"
"$ROOT_DIR/scripts/route-telemetry-summary.py" --hours "$HOURS" --pid current --json 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    fallthrough = d.get('possible_byok_fallthrough', {})
    if not fallthrough:
        print('  <none>')
    else:
        for model_id, payload in sorted(fallthrough.items()):
            print(
                f'  {model_id}: droid_send_count={payload.get(\"droid_send_count\", 0)} '
                f'proxy_reference_count={payload.get(\"proxy_reference_count\", 0)} '
                f'sessions={payload.get(\"sample_session_ids\", [])}'
            )
except Exception:
    print('  <no data>')
" 2>/dev/null || echo "  <no data>"
echo ""

# ── Route health summary ────────────────────────────────────────────────
echo "▸ Route health (non-closed routes)"
curl -sf "$HEALTH_URL" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    routes = d.get('route_health', {}).get('routes', {})
    for model, info in sorted(routes.items()):
        status = info.get('status', 'unknown')
        if status != 'closed':
            fc = info.get('last_failure_class', 'none')
            print(f'  {model}: status={status}, last_failure={fc}')
except Exception:
    print('  <no healthz data>')
" 2>/dev/null || echo "  <healthz not reachable>"
echo ""

# ── Mission worker_failed count ─────────────────────────────────────────
echo "▸ Mission worker_failed (last ${HOURS}h from mission logs)"
python3 - <<PY 2>/dev/null || echo "  <no mission data>"
import datetime as dt
import glob
import json
from pathlib import Path

hours = float("${HOURS}")
window_start = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=hours)
count = 0

for path in glob.glob(str(Path.home() / ".factory" / "missions" / "*" / "progress_log.jsonl")):
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                event = json.loads(line)
                if event.get("type") != "worker_failed":
                    continue
                timestamp = dt.datetime.fromisoformat(str(event["timestamp"]).replace("Z", "+00:00"))
            except Exception:
                continue
            if timestamp >= window_start:
                count += 1

print(f"  {count} events")
PY
echo ""

echo "══════════════════════════════════════════════════════"
