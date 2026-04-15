#!/usr/bin/env python3

import argparse
import collections
import datetime as dt
import json
import pathlib
import re
import sys
import urllib.request


LINE_PATTERN = re.compile(
    r"CLIProxyMenuBar\[(?P<pid>\d+):[^\]]+\].*?\[ThinkingProxy\] Route telemetry (?P<json>\{.*\})\s*$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize recent route telemetry winners, attempts, and failures."
    )
    parser.add_argument(
        "--log",
        default=str(pathlib.Path.home() / ".cli-proxy-api" / "launchd-vibeproxy.err.log"),
        help="Path to the proxy stderr log",
    )
    parser.add_argument(
        "--health-url",
        default="http://127.0.0.1:8317/healthz",
        help="Live health endpoint used to map request models onto providers",
    )
    parser.add_argument(
        "--hours",
        type=float,
        default=2.0,
        help="Lookback window in hours",
    )
    parser.add_argument(
        "--pid",
        default="all",
        help="Filter to a specific PID, or use 'current' to select the most recent PID seen in the log",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of text",
    )
    return parser.parse_args()


def parse_timestamp(timestamp: str) -> dt.datetime:
    return dt.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))


def format_key(source: str, provider: str, model: str) -> str:
    return f"{source} -> {provider} / {model}"


def format_failure_key(source: str, provider: str, model: str, failure_class: str) -> str:
    return f"{source} -> {provider} / {model} / {failure_class}"


def detect_current_pid(log_path: pathlib.Path) -> str | None:
    current_pid: str | None = None
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = LINE_PATTERN.search(line)
            if match:
                current_pid = match.group("pid")
    return current_pid


def fetch_provider_map(health_url: str) -> dict[str, dict[str, str]]:
    with urllib.request.urlopen(health_url, timeout=5) as response:
        payload = json.load(response)
    routes = payload.get("route_health", {}).get("routes", {})
    provider_map: dict[str, dict[str, str]] = {}
    for request_model, route_payload in routes.items():
        provider_map[request_model] = {
            "provider": route_payload.get("provider", "unknown"),
            "canonical_model_id": route_payload.get("canonical_model_id", request_model),
        }
    return provider_map


def provider_details_for_event(
    event: dict[str, object], provider_map: dict[str, dict[str, str]]
) -> tuple[str, str]:
    request_model = str(event.get("request_model") or "unknown")
    route_payload = provider_map.get(request_model)
    if route_payload:
        return route_payload["provider"], request_model

    canonical_model_id = str(event.get("canonical_model_id") or request_model)
    if request_model.endswith("-ollama-pro"):
        return "ollama-pro", request_model
    if request_model.endswith("-nvidia"):
        return "nvidia", request_model
    if request_model == "muse-spark":
        return "meta-web", request_model
    if request_model.startswith("gpt-"):
        return "openai", request_model
    if request_model.endswith("-zai") or canonical_model_id.startswith("glm-5.1"):
        return "zai", request_model
    return "unknown", request_model


def summarize_events(
    events: list[dict[str, object]],
    provider_map: dict[str, dict[str, str]],
) -> dict[str, object]:
    traffic_split = collections.Counter()
    winners = collections.Counter()
    attempts = collections.Counter()
    failures = collections.Counter()

    for event in events:
        source = str(event.get("source") or "unknown")
        provider, request_model = provider_details_for_event(event, provider_map)
        traffic_split[source] += 1
        attempts[(source, provider, request_model)] += 1

        upstream_http_status = event.get("upstream_http_status")
        failure_class = event.get("failure_class")
        transport_outcome = str(event.get("transport_outcome") or "")

        if (
            transport_outcome == "send_response"
            and failure_class is None
            and isinstance(upstream_http_status, int)
            and 200 <= upstream_http_status < 300
        ):
            winners[(source, provider, request_model)] += 1

        if failure_class is not None:
            failures[(source, provider, request_model, str(failure_class))] += 1

    correlation_ids = {str(e["correlation_id"]) for e in events if e.get("correlation_id")}

    return {
        "traffic_split": dict(sorted(traffic_split.items())),
        "winner_distribution": {
            format_key(*key): count
            for key, count in sorted(
                winners.items(), key=lambda item: (-item[1], item[0])
            )
        },
        "attempt_distribution": {
            format_key(*key): count
            for key, count in sorted(
                attempts.items(), key=lambda item: (-item[1], item[0])
            )
        },
        "failure_distribution": {
            format_failure_key(*key): count
            for key, count in sorted(
                failures.items(), key=lambda item: (-item[1], item[0])
            )
        },
        "correlation_ids": sorted(correlation_ids),
    }


def load_events(
    log_path: pathlib.Path,
    lookback_hours: float,
    pid_filter: str | None,
) -> tuple[list[dict[str, object]], dt.datetime, dt.datetime]:
    now = dt.datetime.now(dt.timezone.utc)
    window_start = now - dt.timedelta(hours=lookback_hours)
    events: list[dict[str, object]] = []

    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = LINE_PATTERN.search(line)
            if not match:
                continue
            if pid_filter is not None and match.group("pid") != pid_filter:
                continue
            try:
                event = json.loads(match.group("json"))
                timestamp = parse_timestamp(str(event["timestamp"]))
            except (json.JSONDecodeError, KeyError, ValueError):
                continue
            if timestamp < window_start:
                continue
            event["pid"] = match.group("pid")
            events.append(event)

    return events, window_start, now


def emit_text(
    summary: dict[str, object],
    window_start: dt.datetime,
    now: dt.datetime,
    pid_filter: str | None,
    event_count: int,
) -> None:
    print(f"Window: {window_start.isoformat()} -> {now.isoformat()}")
    print(f"PID filter: {pid_filter or 'all'}")
    print(f"Events: {event_count}")
    print()

    print("Traffic split:")
    for source, count in summary["traffic_split"].items():
        print(f"  {source}: {count}")
    print()

    print("Winner distribution:")
    for key, count in summary["winner_distribution"].items():
        print(f"  {key}: {count}")
    if not summary["winner_distribution"]:
        print("  <none>")
    print()

    print("Attempt distribution:")
    for key, count in summary["attempt_distribution"].items():
        print(f"  {key}: {count}")
    if not summary["attempt_distribution"]:
        print("  <none>")
    print()

    print("Failure distribution:")
    for key, count in summary["failure_distribution"].items():
        print(f"  {key}: {count}")
    if not summary["failure_distribution"]:
        print("  <none>")


def main() -> int:
    args = parse_args()
    log_path = pathlib.Path(args.log)
    if not log_path.exists():
        print(f"Log file not found: {log_path}", file=sys.stderr)
        return 1

    pid_filter: str | None
    if args.pid == "all":
        pid_filter = None
    elif args.pid == "current":
        pid_filter = detect_current_pid(log_path)
        if pid_filter is None:
            print("Could not determine current PID from log", file=sys.stderr)
            return 1
    else:
        pid_filter = args.pid

    provider_map = fetch_provider_map(args.health_url)
    events, window_start, now = load_events(log_path, args.hours, pid_filter)

    # Warn on any request models that map to "unknown"
    all_models = {str(e.get("request_model") or "unknown") for e in events}
    unmapped = {m for m in all_models if provider_details_for_event({"request_model": m}, provider_map)[0] == "unknown"}
    if unmapped:
        print(f"WARNING: Unmapped request models (no provider classification): {sorted(unmapped)}", file=sys.stderr)

    summary = summarize_events(events, provider_map)

    if args.json:
        print(
            json.dumps(
                {
                    "window_start": window_start.isoformat(),
                    "window_end": now.isoformat(),
                    "pid_filter": pid_filter,
                    "event_count": len(events),
                    **summary,
                },
                indent=2,
                sort_keys=True,
            )
        )
    else:
        emit_text(summary, window_start, now, pid_filter, len(events))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
