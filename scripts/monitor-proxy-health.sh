#!/bin/bash
#
# Proxy Health Monitoring Script
# Monitors the frontend VibeProxy health surface (8317) and trusts that payload
# for backend reachability, rather than probing the backend with a nonexistent
# /healthz endpoint.
#
# Usage: ./monitor-proxy-health.sh [--daemon]
#   --daemon: Run continuously in the background (default: check once and exit)
#
# Dependencies: curl, pgrep/launchctl

set -euo pipefail

FRONTEND_PORT=8317
PROXY_NAME="VibeProxy"
LAUNCH_TARGET="gui/$(id -u)/com.vibeproxy.repo"
INSTALLED_VIBEPROXY_AGENT_PLIST="${INSTALLED_VIBEPROXY_AGENT_PLIST:-$HOME/Library/LaunchAgents/com.vibeproxy.repo.plist}"
LOG_FILE="${HOME}/Library/Logs/vibeproxy-health.log"
CHECK_INTERVAL=60

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_frontend_health() {
    local body_file
    body_file="$(mktemp "${TMPDIR:-/tmp}/vibeproxy-monitor-health.XXXXXX")"
    trap 'rm -f "$body_file"' RETURN

    local http_code
    http_code="$(curl -sS -o "$body_file" -w "%{http_code}" --connect-timeout 5 --max-time 10 "http://127.0.0.1:${FRONTEND_PORT}/healthz" 2>/dev/null || echo "000")"
    if [[ "$http_code" != "200" ]]; then
        echo "$http_code"
        return 0
    fi

    if jq -e '
        .status == "ok"
        and .backend.reachable == true
        and .factory_worker.ready == true
        and .factory_roles.orchestration.ready == true
        and .factory_roles.verification.ready == true
    ' "$body_file" >/dev/null 2>&1; then
        echo "200"
    else
        echo "503"
    fi
}

restart_proxy() {
    if launchctl print "$LAUNCH_TARGET" >/dev/null 2>&1; then
        log "Restarting $PROXY_NAME via launchctl kickstart"
        launchctl kickstart -k "$LAUNCH_TARGET"
        sleep 3
        return 0
    fi

    if [[ -f "$INSTALLED_VIBEPROXY_AGENT_PLIST" ]]; then
        log "Bootstrapping $PROXY_NAME launch agent from $INSTALLED_VIBEPROXY_AGENT_PLIST"
        launchctl bootstrap "gui/$(id -u)" "$INSTALLED_VIBEPROXY_AGENT_PLIST" >/dev/null 2>&1 || true
        launchctl kickstart -k "$LAUNCH_TARGET"
        sleep 3
        return 0
    fi

    log "ERROR: Could not find installed launch agent for $PROXY_NAME"
    return 1
}

health_check() {
    local http_code
    http_code=$(check_frontend_health)

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        log "OK: $PROXY_NAME (frontend port ${FRONTEND_PORT}) health surface is ready"
        log "All proxies healthy"
        return 0
    fi

    if [[ "$http_code" == "000" ]]; then
        log "ERROR: $PROXY_NAME frontend health endpoint is unreachable"
    else
        log "WARNING: $PROXY_NAME frontend health endpoint returned HTTP $http_code"
    fi

    local restart_file="/tmp/vibeproxy-restart-${FRONTEND_PORT}.lock"
    local now cooldown_remaining
    now=$(date +%s)
    if [[ ! -f "$restart_file" ]] || \
       (( now - $(cat "$restart_file" 2>/dev/null || echo 0) > 300 )); then
        restart_proxy || true
        echo "$now" > "$restart_file"
    else
        cooldown_remaining=$(( 300 - (now - $(cat "$restart_file")) ))
        log "SKIP: Recent restart attempted for $PROXY_NAME, cooldown ${cooldown_remaining}s remaining"
    fi

    return 1
}

run_daemon() {
    log "Starting proxy health monitor daemon (check interval: ${CHECK_INTERVAL}s)"
    while true; do
        health_check
        sleep "$CHECK_INTERVAL"
    done
}

main() {
    if [[ "${1:-}" == "--daemon" ]]; then
        run_daemon
    else
        health_check
    fi
}

main "$@"
