#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${CONFIG_PATH:-$HOME/.cli-proxy-api/merged-config.yaml}"
PROXY_URL="${PROXY_URL:-http://127.0.0.1:8317/v1/chat/completions}"
DIRECT_URL="${DIRECT_URL:-https://integrate.api.nvidia.com/v1/chat/completions}"
COUNT="${1:-10}"
DIRECT_TIMEOUT="${DIRECT_TIMEOUT:-35}"
PROXY_TIMEOUT="${PROXY_TIMEOUT:-30}"

python3 - "$CONFIG_PATH" "$PROXY_URL" "$DIRECT_URL" "$COUNT" "$DIRECT_TIMEOUT" "$PROXY_TIMEOUT" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
import time

config_path, proxy_url, direct_url, count, direct_timeout, proxy_timeout = sys.argv[1:]
count = int(count)
direct_timeout = int(direct_timeout)
proxy_timeout = int(proxy_timeout)

MODELS = [
    ("glm5", "z-ai/glm5"),
    ("kimi-k2.5-nvidia", "moonshotai/kimi-k2.5"),
    ("minimax-m2.5-nvidia", "minimaxai/minimax-m2.5"),
]


def parse_config(path: str):
    providers = {}
    current_entry = None
    in_api_keys = False
    in_models = False

    def flush_entry():
        nonlocal current_entry
        if current_entry and current_entry.get("name"):
            providers[current_entry["name"]] = {
                "keys": current_entry.get("keys", []),
                "models": current_entry.get("models", []),
            }
        current_entry = None

    with open(path, "r", encoding="utf-8") as fh:
        for raw_line in fh:
            line = raw_line.rstrip("\n")
            stripped = line.strip()
            if not stripped:
                continue
            if line.startswith("- api-key-entries:"):
                flush_entry()
                current_entry = {"name": None, "keys": [], "models": []}
                in_api_keys = True
                in_models = False
                continue
            if current_entry is None:
                continue
            if line and not line.startswith(" ") and not line.startswith("- "):
                flush_entry()
                in_api_keys = False
                in_models = False
                continue
            if line.startswith("  models:"):
                in_models = True
                in_api_keys = False
                continue
            if line.startswith("  name: "):
                current_entry["name"] = stripped.split(": ", 1)[1]
                in_api_keys = False
                in_models = False
                continue
            if in_api_keys and stripped.startswith("- api-key: "):
                current_entry["keys"].append(stripped.split(": ", 1)[1])
                continue
            if in_models and stripped.startswith("- alias: "):
                current_entry["models"].append(stripped.split(": ", 1)[1])
                continue

    flush_entry()
    return providers


def parse_response(body: str):
    try:
        payload = json.loads(body)
    except Exception:
        return {}
    choice = (payload.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content = message.get("content")
    reasoning = message.get("reasoning")
    return {
        "finish_reason": choice.get("finish_reason"),
        "content_null": content is None,
        "content_empty": isinstance(content, str) and content.strip() == "",
        "think_prefix": isinstance(content, str) and content.lstrip().lower().startswith("<think>"),
        "reasoning_present": isinstance(reasoning, str) and reasoning.strip() != "",
        "content_preview": None if content is None else content[:120],
    }


def call(url: str, payload: dict, headers: list[str], timeout: int):
    with tempfile.NamedTemporaryFile(delete=False) as fh:
        body_path = fh.name
    cmd = [
        "curl",
        "-sS",
        "-o",
        body_path,
        "-w",
        "%{http_code} %{time_total}",
        "--max-time",
        str(timeout),
    ]
    for header in headers:
        cmd.extend(["-H", header])
    cmd.extend(["-X", "POST", url, "--data", json.dumps(payload)])

    started = time.time()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - started

    try:
        with open(body_path, "r", encoding="utf-8", errors="replace") as fh:
            body = fh.read()
    finally:
        os.unlink(body_path)

    if proc.returncode != 0:
        return {
            "curl_code": proc.returncode,
            "elapsed": round(elapsed, 2),
            "stderr": proc.stderr.strip(),
        }

    parts = (proc.stdout or "").strip().split()
    http = int(parts[0]) if parts and parts[0].isdigit() else None
    timing = float(parts[1]) if len(parts) > 1 else round(elapsed, 2)
    result = {
        "curl_code": 0,
        "http": http,
        "elapsed": round(timing, 2),
    }
    result.update(parse_response(body))
    return result


providers = parse_config(config_path)
nvidia_provider = providers.get("nvidia", {})
minimax_provider = providers.get("nvidia-minimax", {})

provider_keys = {
    "glm5": nvidia_provider.get("keys", []),
    "kimi-k2.5-nvidia": nvidia_provider.get("keys", []),
    "minimax-m2.5-nvidia": minimax_provider.get("keys", []),
}

matrix = []
for alias, direct_model in MODELS:
    keys = provider_keys.get(alias, [])
    direct_results = []
    proxy_results = []

    for index in range(count):
        if not keys:
            direct_results.append({"error": f"no direct keys found for {alias}"})
            continue
        direct_payload = {
            "model": direct_model,
            "messages": [{"role": "user", "content": "Return exactly: OK"}],
            "max_tokens": 32,
        }
        key = keys[index % len(keys)]
        direct_results.append(
            call(
                direct_url,
                direct_payload,
                [
                    "Content-Type: application/json",
                    f"Authorization: Bearer {key}",
                ],
                direct_timeout,
            )
        )

    for _ in range(count):
        proxy_payload = {
            "model": alias,
            "messages": [{"role": "user", "content": "Return exactly: OK"}],
            "max_tokens": 32,
        }
        proxy_results.append(
            call(
                proxy_url,
                proxy_payload,
                ["Content-Type: application/json"],
                proxy_timeout,
            )
        )

    matrix.append({"model": alias, "direct": direct_results, "proxy": proxy_results})

print(json.dumps({
    "config_path": config_path,
    "proxy_url": proxy_url,
    "direct_url": direct_url,
    "count": count,
    "direct_timeout": direct_timeout,
    "proxy_timeout": proxy_timeout,
    "results": matrix,
}, indent=2))
PY
