# AI Model Gateway — Product Requirements Document

## 1. Overview

A local AI model gateway that unifies access to multiple AI providers through a single OpenAI-compatible endpoint. It runs as a headless daemon, routing requests from CLI tools and agents (Claude Code, Codex, GitHub Copilot, Gemini CLI, etc.) to the appropriate upstream provider with intelligent failover, retry logic, and health management.

**What it is:** A two-server architecture where a Rust request router (port 8317) fronts a credential-management backend (port 8318).

**What it is not:** A cloud service, a GUI application, a model host, or an API key marketplace.

---

## 2. Problem Statement

Users of AI coding tools (Claude Code, Codex, Gemini CLI, etc.) face:

- **Multiple subscriptions** — each tool requires its own auth flow and API configuration.
- **Rate limits and quota exhaustion** — a single provider key hits limits; users juggle accounts manually.
- **Unreliable free tiers** — free model endpoints (NVIDIA build, OpenCode.ai, etc.) return malformed responses, timeout, or go down without warning.
- **No unified endpoint** — each CLI tool expects OpenAI-compatible or Anthropic-compatible APIs at different URLs with different formats.

The gateway solves this by presenting one local endpoint that handles provider selection, credential rotation, failure recovery, and model aliasing transparently.

---

## 3. Users and Use Cases

### Primary Users

- **Individual developers** running multiple AI coding CLI tools locally who want one endpoint to rule them all.
- **Power users** with multiple paid subscriptions (e.g., two Claude Max accounts) who want automatic credential rotation.
- **Users of free-tier models** (NVIDIA build, OpenCode.ai MiMo/MiniMax) who need resilience against flaky upstream responses.

### Use Cases

| # | Use Case | Outcome |
|---|----------|---------|
| UC-1 | Developer runs Claude Code pointing at `localhost:8317` | Requests route to Claude OAuth tokens in config directory, auto-rotating on quota errors |
| UC-2 | User has 3 Claude accounts, one expires | Gateway skips the expired credential, uses the remaining two, logs the expiry |
| UC-3 | User requests model `worker` (a smart alias) | Gateway races multiple free-tier candidates, returns the first successful response |
| UC-4 | NVIDIA endpoint returns an empty response body | Gateway detects the semantic failure, retries with a repaired request |
| UC-5 | All routes to a model fail for 5 minutes | Circuit breaker opens, subsequent requests skip that route, canary probes test recovery |
| UC-6 | User adds a custom OpenAI-compatible provider | User drops config in user overlay file, gateway hot-reloads without restart |
| UC-7 | User routes Claude requests through Vercel AI Gateway | Requests are forwarded to `ai-gateway.vercel.sh` with appropriate auth headers |

---

## 4. Architecture

```
┌─────────────┐     HTTP      ┌──────────────────┐     HTTP      ┌─────────────────────┐
│  AI CLI     │──────────────▶│  Request Router  │──────────────▶│  Credential Backend │
│  Tools      │  localhost:   │  (Rust daemon)   │  localhost:   │  (binary)           │
│             │  8317         │  port 8317        │  8318         │  port 8318          │
└─────────────┘               │                   │               │                     │
                              │  ┌─────────────┐  │               │  - OAuth token      │
                              │  │ Smart Alias │  │               │    rotation         │
                              │  │ Racing      │  │               │  - Model mapping    │
                              │  ├─────────────┤  │               │  - Credential       │
                              │  │ NVIDIA      │  │               │    management       │
                              │  │ Mitigation  │  │               │  - Quota handling   │
                              │  ├─────────────┤  │               │                     │
                              │  │ Circuit     │  │               │                     │
                              │  │ Breaker     │  │               │                     │
                              │  ├─────────────┤  │               │                     │
                              │  │ Config      │  │               │                     │
                              │  │ Composer    │  │               │                     │
                              │  └─────────────┘  │               │                     │
                              └──────────────────┘               └─────────────────────┘
                                       │
                                       │ HTTPS (optional)
                                       ▼
                              ┌──────────────────┐
                              │  Vercel AI       │
                              │  Gateway         │
                              └──────────────────┘
                                       │
                                       │ HTTPS/SOCKS5 (optional)
                                       ▼
                              ┌──────────────────┐
                              │  Direct Provider │
                              │  (OpenCode.ai)   │
                              └──────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **Request Router (Rust, port 8317)** | HTTP proxy: request routing, smart alias failover, NVIDIA retry/mitigation, circuit breakers, health scoring, request transformation, Vercel gateway forwarding |
| **Credential Backend (port 8318)** | OAuth credential rotation, model-to-provider mapping, quota management, passthrough headers |
| **Config system** | Merge bundled base config + user overlay, apply managed provider patches, emit runtime config for the credential backend |
| **Credential stores** | Read/write API key and OAuth token files in the config directory |

---

## 5. Functional Requirements

### 5.1 Daemon Lifecycle

| ID | Requirement | Priority |
|----|-------------|----------|
| F-DAEMON-01 | `<cmd> start` launches the daemon as a background process, writes PID file | P0 |
| F-DAEMON-02 | `<cmd> stop` sends SIGTERM to the daemon process, waits for graceful shutdown, removes PID file | P0 |
| F-DAEMON-03 | `<cmd> status` reports whether the daemon is running, its PID, uptime, and proxy port | P1 |
| F-DAEMON-04 | On start, launch the credential backend as a child process with `-config <merged-config-path>` | P0 |
| F-DAEMON-05 | On stop, send SIGTERM to the credential backend, wait up to 3 seconds, then SIGKILL if needed | P0 |
| F-DAEMON-06 | Kill orphaned credential backend processes from previous runs before starting a new one | P1 |
| F-DAEMON-07 | Graceful shutdown: stop accepting new connections, drain in-flight requests (up to 10s), then terminate | P0 |
| F-DAEMON-08 | Configurable data directory via CLI flag or environment variable | P2 |

### 5.2 Proxy Server

| ID | Requirement | Priority |
|----|-------------|----------|
| F-PROXY-01 | Listen on `0.0.0.0:8317` (configurable) for HTTP/1.1 requests | P0 |
| F-PROXY-02 | Forward all unmatched requests to the credential backend at `127.0.0.1:8318` | P0 |
| F-PROXY-03 | Support streaming (chunked transfer) responses — pipe upstream chunks to client without buffering | P0 |
| F-PROXY-04 | Support buffered requests for NVIDIA mitigation path — collect full response body, inspect, repair if needed | P0 |
| F-PROXY-05 | Expose `/healthz` endpoint returning HTTP 200 when the router and backend are both running | P1 |
| F-PROXY-06 | Inject gateway-specific headers on forwarded requests for observability | P2 |

### 5.3 Provider Routing

| ID | Requirement | Priority |
|----|-------------|----------|
| F-ROUTE-01 | Support OAuth passthrough providers: Claude, Codex, GitHub Copilot, Gemini, Qwen, Antigravity | P0 |
| F-ROUTE-02 | Support OpenAI-compatible providers with API keys: NVIDIA, OpenCode.ai, custom endpoints | P0 |
| F-ROUTE-03 | Support Z.AI GLM provider via `claude-api-key` entries in config | P0 |
| F-ROUTE-04 | Resolve model aliases to canonical model IDs using the provider's `models` mapping | P0 |
| F-ROUTE-05 | Detect model name in request body and route to the matching provider | P0 |
| F-ROUTE-06 | Forward requests to provider `base-url` with appropriate auth headers | P0 |
| F-ROUTE-07 | Support per-provider `proxy-url` for SOCKS5 routing (e.g., OpenCode.ai) | P1 |

### 5.4 Smart Alias System

| ID | Requirement | Priority |
|----|-------------|----------|
| F-ALIAS-01 | Define smart aliases in config: an alias name maps to an ordered list of candidate model names | P0 |
| F-ALIAS-02 | Each alias has a `request-class` (`plain-chat`, `streaming`) and `failover` mode (`silent`, `visible`) | P1 |
| F-ALIAS-03 | Each alias has a `health-sensitivity` (`eager`, `balanced`, `conservative`) controlling circuit breaker thresholds | P1 |
| F-ALIAS-04 | Serial failover: try candidates in health-ranked order, return first success | P0 |
| F-ALIAS-05 | Parallel racing: launch multiple candidates concurrently, return first success, cancel the rest | P0 |
| F-ALIAS-06 | Health-ranked ordering: prefer routes with `closed` status, higher EMA composite score, and higher model tier | P0 |
| F-ALIAS-07 | `failover: visible` returns the winning model name to the client in a response header | P2 |

### 5.5 NVIDIA Mitigation (Retry and Repair)

| ID | Requirement | Priority |
|----|-------------|----------|
| F-MIT-01 | Per-model request policies define: stripped fields, min/max `max_tokens`, attempt timeout, retry budgets | P0 |
| F-MIT-02 | Transform requests before forwarding: strip unsupported fields, floor/ceiling `max_tokens`, force modes | P0 |
| F-MIT-03 | Detect semantic failures in responses: empty body, empty content, reasoning-only content without text, reasoning length leaks, malformed tool arguments | P0 |
| F-MIT-04 | Retry on semantic failure: increment semantic retry counter, apply backoff, re-send with repaired request | P0 |
| F-MIT-05 | Retry on transport failure: increment transport retry counter, re-send the original request | P0 |
| F-MIT-06 | Track first-byte and total response deadlines per attempt; abort and retry if exceeded | P1 |
| F-MIT-07 | Salvage best-effort repair: if all retries fail but a partially valid response exists, return it rather than a gateway error | P1 |
| F-MIT-08 | Model-specific policies for: `z-ai/glm5`, `moonshotai/kimi-k2.5`, `minimaxai/minimax-m2.5`, `xiaomi/mimo-v2-pro:free`, OpenCode.ai models | P0 |

### 5.6 Circuit Breaker and Health

| ID | Requirement | Priority |
|----|-------------|----------|
| F-HEALTH-01 | Track per-route health with states: `closed` (healthy), `suspect` (degraded), `open` (tripped), `half_open` (testing recovery) | P0 |
| F-HEALTH-02 | Compute EMA (exponential moving average) success rate and average latency per route | P0 |
| F-HEALTH-03 | Compute composite score: `success_rate^2 * 1000 - avg_latency_ms` | P0 |
| F-HEALTH-04 | Open circuit after consecutive failures exceed threshold; enter cooldown period | P0 |
| F-HEALTH-05 | Half-open: send canary probe requests to test recovery; close circuit after sufficient successes | P1 |
| F-HEALTH-06 | Persist health state to `route-health.json` in the config directory; reload on restart | P1 |
| F-HEALTH-07 | Apply momentum bonus to recently recovered routes to avoid immediate re-tripping | P2 |
| F-HEALTH-08 | Respect `health-sensitivity` thresholds from smart alias definitions (`eager`: 200, `balanced`: 500, `conservative`: 2000) | P1 |

### 5.7 Vercel AI Gateway

| ID | Requirement | Priority |
|----|-------------|----------|
| F-VERCEL-01 | Optionally route Claude-model requests through Vercel AI Gateway (`ai-gateway.vercel.sh`) | P1 |
| F-VERCEL-02 | Inject `x-api-key` and `anthropic-version` headers when forwarding via Vercel | P1 |
| F-VERCEL-03 | Inject `anthropic-beta: interleaved-thinking-2025-05-14` for extended thinking requests | P1 |
| F-VERCEL-04 | TLS termination via rustls for HTTPS connections to Vercel | P1 |

### 5.8 Configuration

| ID | Requirement | Priority |
|----|-------------|----------|
| F-CONFIG-01 | Load bundled base config from the executable's adjacent `config.yaml` | P0 |
| F-CONFIG-02 | Overlay user config from `<config-dir>/config.yaml` (additive merge) | P0 |
| F-CONFIG-03 | Whitelist of supported user-config keys: `request-timeout`, `request-retry`, `max-retry-credentials`, `oauth-excluded-models`, `openai-compatibility`, `smart-aliases`, `policies`, `proxy-url`, `debug`, `logging-to-file`, `usage-statistics-enabled`, `passthrough-headers`, `routing`, `claude-api-key`, `quota-exceeded` | P0 |
| F-CONFIG-04 | Ignore unsupported keys (e.g., `port`, `host`, `remote-management`) to prevent breaking the architecture | P0 |
| F-CONFIG-05 | Apply managed NVIDIA provider patches: inject `nvidia` and `nvidia-minimax` providers with canonical model aliases | P0 |
| F-CONFIG-06 | Apply managed smart alias patches: inject/update `worker` alias with canonical candidate ordering | P0 |
| F-CONFIG-07 | Compose runtime config: strip UI metadata, deduplicate API keys, inject Z.AI on `claude-api-key`, exclude disabled providers, apply OAuth wildcard exclusions | P0 |
| F-CONFIG-08 | Write merged runtime config to `<config-dir>/merged-config.yaml` for the credential backend to consume | P0 |
| F-CONFIG-09 | Hot-reload config when `<config-dir>/config.yaml` changes on disk (file-system watching or fingerprint polling) | P1 |
| F-CONFIG-10 | Validate custom providers: reject missing `base-url`, whitespace-padded names, reserved provider IDs | P1 |
| F-CONFIG-11 | Validate smart aliases: reject unknown model references, self-referencing aliases, whitespace-padded names | P1 |

### 5.9 Credential Management

| ID | Requirement | Priority |
|----|-------------|----------|
| F-CRED-01 | Scan the config directory for JSON credential files (`*.json`) on startup and on file-system changes | P0 |
| F-CRED-02 | Parse credential files by `type` field: `claude`, `codex`, `github-copilot`, `gemini`, `qwen`, `antigravity`, `zai` | P0 |
| F-CRED-03 | Support multiple accounts per provider (multiple credential files) | P0 |
| F-CRED-04 | Detect expired credentials via `expired` field (ISO 8601 date) and skip them in rotation | P0 |
| F-CRED-05 | Support per-account disable/enable via `disabled` boolean in credential JSON | P1 |
| F-CRED-06 | Store Z.AI API keys as `zai-<label>.json` files with `{"type": "zai", "api-key": "..."}` | P0 |
| F-CRED-07 | Store custom provider credentials as `openai-compat-<provider-id>-<label>.json` | P0 |

### 5.10 Request Transformation

| ID | Requirement | Priority |
|----|-------------|----------|
| F-TRANS-01 | Detect `thinking` / `thinking_config` parameters in Claude-format requests and enable extended thinking mode | P0 |
| F-TRANS-02 | Strip reasoning-related fields (`reasoning_effort`, `response_format`, `stop`, `frequency_penalty`, `presence_penalty`, `ignore_eos`) for NVIDIA models that don't support them | P0 |
| F-TRANS-03 | Floor `max_tokens` to model-specific minimums (e.g., 384 for kimi-k2.5, 128 for minimax-m2.5) | P0 |
| F-TRANS-04 | Ceiling `max_tokens` to model-specific maximums (e.g., 65536 for minimax-m2.5) | P1 |
| F-TRANS-05 | Force `chat_template_kwargs.thinking = false` and `enable_thinking = false` for kimi-k2.5 (instant mode) | P0 |
| F-TRANS-06 | Strip `reasoning_content` / `thinking` from successful NVIDIA responses when the model leaks reasoning into the output | P0 |
| F-TRANS-07 | Validate tool call arguments in responses for well-formed JSON; flag malformed arguments as a retryable failure | P1 |

---

## 6. Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NF-01 | **Startup time**: Daemon ready to accept connections in < 2 seconds (excluding credential backend startup) |
| NF-02 | **Memory**: < 50MB RSS under typical load (< 100 concurrent requests) |
| NF-03 | **Latency overhead**: < 1ms added latency per proxied request (passthrough path, no mitigation) |
| NF-04 | **Concurrency**: Handle 100+ concurrent streaming connections without head-of-line blocking |
| NF-05 | **Portability**: Compile and run on macOS (aarch64, x86_64) and Linux (x86_64) |
| NF-06 | **Observability**: Structured logging with configurable log levels; no stdout spam at default level |
| NF-07 | **Zero data loss**: In-flight requests are drained on shutdown, not abruptly terminated |
| NF-08 | **Config safety**: Malformed user config never crashes the daemon; errors are logged and the last valid config is used |
| NF-09 | **Single binary**: Distribute as a single static binary with no runtime dependencies beyond libc |

---

## 7. Configuration Schema

### Base Config (`config.yaml`)

```yaml
port: 8318
host: 127.0.0.1
auth-dir: "<config-dir>"
debug: false
request-retry: 3
request-timeout: "10m"
max-retry-credentials: 0

quota-exceeded:
  switch-project: true
  switch-preview-model: true

generative-language-api-key: []

openai-compatibility:
  - name: opencode
    base-url: https://opencode.ai/zen/v1
    proxy-url: ""
    models:
      - alias: mimo-v2-pro-opencode
        name: mimo-v2-pro-free
      - alias: minimax-m2.5-opencode
        name: minimax-m2.5-free

smart-aliases:
  worker:
    request-class: plain-chat
    failover: silent
    candidates:
      - glm-5.1-zai
      - mimo-v2-pro-kilocode
      - mimo-v2-pro-opencode
      - minimax-m2.5-opencode
      - minimax-m2.5-nvidia
      - kimi-k2.5-nvidia
```

### User Overlay (`<config-dir>/config.yaml`)

```yaml
# Add custom providers
openai-compatibility:
  - name: my-provider
    base-url: https://my-llm.example.com/v1
    api-key-entries:
      - api-key: sk-xxx
    models:
      - alias: my-model
        name: my-org/my-model

# Override timeouts
request-timeout: "30m"

# Exclude specific models from OAuth rotation
oauth-excluded-models:
  claude:
    - claude-sonnet-4
```

### Credential File (`<config-dir>/claude-user@example.com-abc123.json`)

```json
{
  "type": "claude",
  "email": "user@example.com",
  "expired": "2026-04-15T00:00:00Z"
}
```

---

## 8. CLI Interface

```
<cmd> start    [-c <config-dir>] [-p <port>] [--backend <path-to-credential-backend>]
<cmd> stop     [--force]
<cmd> status   [--json]
```

| Flag | Description |
|------|-------------|
| `-c, --config-dir` | Override config directory |
| `-p, --port` | Override proxy listen port (default: `8317`) |
| `--backend` | Path to credential backend binary (default: adjacent to gateway binary) |
| `--force` | Kill daemon with SIGKILL instead of SIGTERM |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `<PREFIX>_PORT` | Override listen port |
| `<PREFIX>_CONFIG_DIR` | Override config directory |
| `<PREFIX>_BACKEND` | Path to credential backend |
| `<PREFIX>_LOG` | Log filter (e.g., `debug`, `info`) |

---

## 9. File System Layout

```
<config-dir>/
  config.yaml                  # User overlay config
  merged-config.yaml           # Composed runtime config (auto-generated)
  gateway.pid                  # Daemon PID file
  route-health.json            # Persisted circuit breaker state
  claude-*.json                # Claude OAuth credentials
  codex-*.json                 # Codex OAuth credentials
  github-copilot-*.json        # GitHub Copilot OAuth credentials
  gemini-*.json                # Gemini OAuth credentials
  qwen-*.json                  # Qwen OAuth credentials
  antigravity-*.json           # Antigravity OAuth credentials
  zai-*.json                   # Z.AI API keys
  openai-compat-*.json         # Custom provider credentials
```

---

## 10. Supported Providers and Models

### OAuth Passthrough (credentials from config directory)

| Provider | Type | Auth Method |
|----------|------|-------------|
| Claude Code | OAuth | Token files |
| Codex (OpenAI) | OAuth | Token files |
| GitHub Copilot | OAuth | Token files |
| Gemini | OAuth | Token files |
| Qwen | OAuth | Token files |
| Antigravity | OAuth | Token files |

### API-Key Providers (configured in `openai-compatibility`)

| Provider | Base URL | Notes |
|----------|----------|-------|
| NVIDIA | `https://integrate.api.nvidia.com/v1` | GLM-5, Kimi-K2.5, MiniMax-M2.5 |
| OpenCode.ai | `https://opencode.ai/zen/v1` | Free MiMo-V2-Pro, MiniMax-M2.5; requires proxy |
| Z.AI GLM | `https://api.z.ai/api/coding/paas/v4` | Injected on `claude-api-key` |
| Custom | User-defined | Any OpenAI-compatible endpoint |

### Smart Alias Candidates (default `worker` pool)

1. `glm-5.1-zai` — Z.AI GLM-5.1 (primary)
2. `mimo-v2-pro-kilocode` — MiMo free tier (Kilocode)
3. `mimo-v2-pro-opencode` — MiMo free tier (OpenCode.ai)
4. `minimax-m2.5-opencode` — MiniMax free tier (OpenCode.ai)
5. `minimax-m2.5-nvidia` — MiniMax (NVIDIA build)
6. `kimi-k2.5-nvidia` — Kimi-K2.5 (NVIDIA build)

---

## 11. Error Handling

| Scenario | Behavior |
|----------|----------|
| Upstream returns HTTP error | Log error, apply retry policy, failover to next candidate if available |
| Upstream returns empty body | Flag as semantic failure (`empty_body`), retry with backoff |
| Upstream returns empty content array | Flag as semantic failure (`empty_content`), retry |
| Upstream returns reasoning without text content | Flag as `reasoning_only_content_missing`, strip reasoning, retry |
| Upstream response exceeds deadline | Abort request, flag as timeout, retry with fresh attempt |
| All retries exhausted | Return best-effort repair if available, otherwise return gateway error (502) |
| Credential backend crashes | Log error, stop accepting requests, emit error to healthz |
| Malformed config.yaml | Log parse error, continue with last valid config |
| Credential file parse error | Log warning, skip that file, continue with remaining credentials |
| PID file exists but process dead | Stale PID detected, remove file, proceed with start |

---

## 12. Out of Scope

- **Web UI / Dashboard** — No management interface; config is file-based
- **Cloudflare tunnel** — Not included; users can run their own tunnel if needed
- **Auto-update mechanism** — Use package managers for distribution
- **Platform-specific integrations** — No Keychain, no system notifications, no menu bar
- **Model hosting** — Gateway only proxies to existing providers; it does not run models
- **API key management UI** — Credentials are managed via files
- **Multi-user / multi-tenant** — Single-user, local-machine scope only
- **Billing / usage tracking** — No billing integration; `usage-statistics-enabled` controls upstream telemetry only

---

## 13. Migration

Users migrating from a previous version:

1. Credential files in the config directory are unchanged — no migration needed
2. User config `config.yaml` format is unchanged — same overlay format
3. Route health state in `route-health.json` is reused — circuit breaker state persists
4. The credential backend binary is the same — no changes required
5. Proxy port (8317) and backend port (8318) remain the same
