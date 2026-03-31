#!/bin/bash
#
# Proxy Health Monitoring Script
# Monitors VibeProxy (8317) and CLIProxyAPIPlus (8318) and auto-restarts if down
#
# Usage: ./monitor-proxy-health.sh [--daemon]
#   --daemon: Run continuously in the background (default: check once and exit)
#
# Dependencies: curl, pgrep/launchctl

set -euo pipefail

PROXY_PORTS=(8317 8318)
PROXY_NAMES=("VibeProxy" "CLIProxyAPIPlus")
LOG_FILE="${HOME}/Library/Logs/vibeproxy-health.log"
CHECK_INTERVAL=60

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_port() {
    local port=$1
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://127.0.0.1:${port}/healthz" 2>/dev/null || echo "000"
}

restart_proxy() {
    local name=$1
    local pid
    pid=$(pgrep -f "$name" 2>/dev/null | head -1)
    
    if [[ -n "$pid" ]]; then
        log "WARNING: $name appears to be running (PID $pid) but port is not responding"
        log "Attempting to restart $name..."
        kill "$pid" 2>/dev/null || true
        sleep 2
    fi
    
    # Try to find and restart the app
    local app_path
    app_path=$(find /Users/gwizz/CascadeProjects/vibeproxy-nvidia/src/.build/debug -name "CLIProxyMenuBar" -type f 2>/dev/null | head -1)
    
    if [[ -n "$app_path" && -x "$app_path" ]]; then
        log "Starting $name..."
        nohup "$app_path" > /dev/null 2>&1 &
        sleep 3
    else
        log "ERROR: Could not find executable to restart $name"
        return 1
    fi
}

health_check() {
    local all_healthy=true
    
    for i in "${!PROXY_PORTS[@]}"; do
        local port=${PROXY_PORTS[$i]}
        local name=${PROXY_NAMES[$i]}
        local http_code
        
        http_code=$(check_port "$port")
        
        if [[ "$http_code" == "000" ]]; then
            log "ERROR: $name (port $port) is DOWN (connection refused)"
            all_healthy=false
            
            # Try restart (with rate limiting via timestamp file)
            local restart_file="/tmp/vibeproxy-restart-${port}.lock"
            local now cooldown_remaining
            now=$(date +%s)
            if [[ ! -f "$restart_file" ]] || \
               (( now - $(cat "$restart_file" 2>/dev/null || echo 0) > 300 )); then
                restart_proxy "$name" || true
                echo "$now" > "$restart_file"
            else
                cooldown_remaining=$(( 300 - (now - $(cat "$restart_file")) ))
                log "SKIP: Recent restart attempted for $name, cooldown ${cooldown_remaining}s remaining"
            fi
        elif [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log "OK: $name (port $port) responding with HTTP $http_code"
        else
            log "WARNING: $name (port $port) responding with HTTP $http_code (unexpected)"
        fi
    done
    
    if $all_healthy; then
        log "All proxies healthy"
        return 0
    else
        return 1
    fi
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
