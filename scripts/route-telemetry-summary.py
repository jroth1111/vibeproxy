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
DROID_TIMESTAMP_PATTERN = re.compile(r"^\[(?P<timestamp>[^\]]+)\]")


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
    parser.add_argument(
        "--droid-log",
        default=str(pathlib.Path.home() / ".factory" / "logs" / "droid-log-single.log"),
        help="Path to the Droid log used for best-effort proxy bypass detection",
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


def parse_droid_context_line(line: str) -> tuple[dt.datetime, dict[str, object]] | None:
    if "[LLM] sendMessage" not in line or " | Context: " not in line:
        return None

    timestamp_match = DROID_TIMESTAMP_PATTERN.match(line)
    if not timestamp_match:
        return None

    try:
        timestamp = parse_timestamp(timestamp_match.group("timestamp"))
        context = json.loads(line.rsplit(" | Context: ", 1)[1])
    except (json.JSONDecodeError, ValueError):
        return None

    return timestamp, context


def load_droid_custom_model_activity(
    log_path: pathlib.Path, window_start: dt.datetime
) -> list[dict[str, object]]:
    if not log_path.exists():
        return []

    activity: list[dict[str, object]] = []
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parsed = parse_droid_context_line(line)
            if parsed is None:
                continue

            timestamp, context = parsed
            if timestamp < window_start:
                continue

            tags = context.get("tags")
            if not isinstance(tags, dict):
                continue

            tagged_model_id = str(tags.get("modelId") or "")
            if not tagged_model_id.startswith("custom:"):
                continue

            activity.append(
                {
                    "timestamp": timestamp.isoformat(),
                    "session_id": str(tags.get("sessionId") or ""),
                    "tagged_model_id": tagged_model_id,
                    "resolved_model_id": str(context.get("modelId") or ""),
                    "tool_count": int(context.get("toolCount") or 0),
                }
            )

    return activity


def proxy_event_mentions_custom_model(event: dict[str, object], custom_model_id: str) -> bool:
    return any(
        custom_model_id == str(event.get(field) or "")
        for field in ("request_model", "requested_alias")
    ) or custom_model_id in str(event.get("request_shape") or "")


def summarize_droid_proxy_fallthrough(
    droid_activity: list[dict[str, object]], events: list[dict[str, object]]
) -> dict[str, object]:
    droid_counts = collections.Counter()
    proxy_reference_counts = collections.Counter()
    sample_sessions: dict[str, list[str]] = collections.defaultdict(list)
    sample_resolved_models: dict[str, list[str]] = collections.defaultdict(list)

    custom_model_ids = sorted(
        {str(activity["tagged_model_id"]) for activity in droid_activity}
    )

    for activity in droid_activity:
        custom_model_id = str(activity["tagged_model_id"])
        droid_counts[custom_model_id] += 1

        session_id = str(activity.get("session_id") or "")
        if session_id and session_id not in sample_sessions[custom_model_id]:
            if len(sample_sessions[custom_model_id]) < 3:
                sample_sessions[custom_model_id].append(session_id)

        resolved_model_id = str(activity.get("resolved_model_id") or "")
        if (
            resolved_model_id
            and resolved_model_id not in sample_resolved_models[custom_model_id]
            and len(sample_resolved_models[custom_model_id]) < 3
        ):
            sample_resolved_models[custom_model_id].append(resolved_model_id)

    for custom_model_id in custom_model_ids:
        proxy_reference_counts[custom_model_id] = sum(
            1 for event in events if proxy_event_mentions_custom_model(event, custom_model_id)
        )

    possible_fallthrough = {
        custom_model_id: {
            "droid_send_count": droid_counts[custom_model_id],
            "proxy_reference_count": proxy_reference_counts[custom_model_id],
            "sample_session_ids": sample_sessions[custom_model_id],
            "sample_resolved_model_ids": sample_resolved_models[custom_model_id],
        }
        for custom_model_id in custom_model_ids
        if droid_counts[custom_model_id] > 0 and proxy_reference_counts[custom_model_id] == 0
    }

    return {
        "droid_custom_send_distribution": dict(sorted(droid_counts.items())),
        "proxy_custom_model_reference_distribution": dict(
            sorted(proxy_reference_counts.items())
        ),
        "possible_byok_fallthrough": possible_fallthrough,
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
    print()

    print("Droid custom-model sends:")
    for key, count in summary["droid_custom_send_distribution"].items():
        print(f"  {key}: {count}")
    if not summary["droid_custom_send_distribution"]:
        print("  <none>")
    print()

    print("Proxy custom-model references:")
    for key, count in summary["proxy_custom_model_reference_distribution"].items():
        print(f"  {key}: {count}")
    if not summary["proxy_custom_model_reference_distribution"]:
        print("  <none>")
    print()

    print("Possible BYOK fallthrough:")
    for key, payload in summary["possible_byok_fallthrough"].items():
        print(
            f"  {key}: droid_send_count={payload['droid_send_count']} "
            f"proxy_reference_count={payload['proxy_reference_count']} "
            f"sample_sessions={payload['sample_session_ids']} "
            f"sample_resolved_models={payload['sample_resolved_model_ids']}"
        )
    if not summary["possible_byok_fallthrough"]:
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
    droid_activity = load_droid_custom_model_activity(
        pathlib.Path(args.droid_log), window_start
    )

    # Warn on any request models that map to "unknown"
    all_models = {str(e.get("request_model") or "unknown") for e in events}
    unmapped = {m for m in all_models if provider_details_for_event({"request_model": m}, provider_map)[0] == "unknown"}
    if unmapped:
        print(f"WARNING: Unmapped request models (no provider classification): {sorted(unmapped)}", file=sys.stderr)

    summary = summarize_events(events, provider_map)
    summary.update(summarize_droid_proxy_fallthrough(droid_activity, events))

    if args.json:
        print(
            json.dumps(
                {
                    "window_start": window_start.isoformat(),
                    "window_end": now.isoformat(),
                    "pid_filter": pid_filter,
                    "event_count": len(events),
                    "droid_event_count": len(droid_activity),
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
