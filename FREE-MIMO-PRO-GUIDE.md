# Free MiMo-V2-Pro & MiniMax M2.5 Inference Guide

This guide shows how to use free AI inference via **kilocode** and **opencode** providers — no VibeProxy required.

## Providers Overview

| Provider | API Key | Base URL | Free Models |
|----------|---------|----------|-------------|
| **kilocode** | Required | `https://api.kilo.ai/api/openrouter/v1` | `xiaomi/mimo-v2-pro:free` |
| **opencode** | Optional | `https://opencode.ai/zen/v1` | `mimo-v2-pro-free`, `minimax-m2.5-free` |

## Required Header

Both providers require this header for free-tier access:

```
HTTP-Referer: https://openclaw.ai
```

---

## Get Your API Keys

### kilocode
1. Go to https://app.kilo.ai/users/sign_in
2. Sign up or log in
3. Go to Settings → API Keys
4. Copy your API key

### opencode (optional — works without key but rate limits apply)
1. Go to https://opencode.ai/auth
2. Sign up or log in  
3. Go to API Keys
4. Copy your API key

---

## Direct API Calls

### 1. kilocode — MiMo-V2-Pro Free

```bash
curl -s -X POST "https://api.kilo.ai/api/openrouter/v1/chat/completions" \
  -H "Authorization: Bearer YOUR_KILO_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://openclaw.ai" \
  -d '{
    "model": "xiaomi/mimo-v2-pro:free",
    "messages": [{"role": "user", "content": "Hello! Respond with exactly: Hi"}],
    "max_tokens": 10
  }'
```

Replace `YOUR_KILO_API_KEY` with your key from kilo.ai.

### 2. opencode — MiMo-V2-Pro Free (no key required)

```bash
curl -s -X POST "https://opencode.ai/zen/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://openclaw.ai" \
  -d '{
    "model": "mimo-v2-pro-free",
    "messages": [{"role": "user", "content": "Hello! Respond with exactly: Hi"}],
    "max_tokens": 10
  }'
```

### 3. opencode — MiniMax M2.5 Free (no key required)

```bash
curl -s -X POST "https://opencode.ai/zen/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://openclaw.ai" \
  -d '{
    "model": "minimax-m2.5-free",
    "messages": [{"role": "user", "content": "Hello! Respond with exactly: Hi"}],
    "max_tokens": 10
  }'
```

---

## With API Key (opencode only)

If you got an opencode key, add it like this:

```bash
curl -s -X POST "https://opencode.ai/zen/v1/chat/completions" \
  -H "Authorization: Bearer YOUR_OPENCODE_API_KEY" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://openclaw.ai" \
  -d '{
    "model": "mimo-v2-pro-free",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 10
  }'
```

---

## Request Format

```json
{
  "model": "MODEL_ID_FROM_TABLE_ABOVE",
  "messages": [
    {"role": "user", "content": "Your prompt here"}
  ],
  "max_tokens": 100,
  "temperature": 0.7
}
```

## Expected Response

```json
{
  "id": "gen-xxx",
  "object": "chat.completion",
  "model": "...",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Response text here"
      }
    }
  ],
  "usage": {
    "total_tokens": 123,
    "cost": "0"
  }
}
```

Note: `"cost": "0"` means the request was free.

---

## Troubleshooting

### "401 Unauthorized"
- Your API key is invalid or expired
- Get a fresh key from https://app.kilo.ai (kilocode) or https://opencode.ai/auth (opencode)

### "403 Forbidden"
- Missing or wrong `HTTP-Referer` header
- Must be exactly: `HTTP-Referer: https://openclaw.ai`

### "429 Too Many Requests"
- Rate limited. Wait and retry, or use the other provider.

### "model not found"
- Model name may have changed. Check provider docs.

---

## Summary

| Model | Provider | Model ID | API Key Required |
|-------|----------|----------|------------------|
| MiMo-V2-Pro | kilocode | `xiaomi/mimo-v2-pro:free` | Yes |
| MiMo-V2-Pro | opencode | `mimo-v2-pro-free` | No |
| MiniMax M2.5 | opencode | `minimax-m2.5-free` | No |

Start with opencode (no key needed). If it fails, fall back to kilocode (requires key).

---

## Failover Strategy

When a provider fails (rate limit, error, timeout), automatically try the next one. Here's the recommended order:

### Recommended Failover Order

| Priority | Provider | Model | Why |
|----------|----------|-------|-----|
| 1st | opencode | `mimo-v2-pro-free` | No API key needed |
| 2nd | opencode | `minimax-m2.5-free` | Backup model on same provider |
| 3rd | kilocode | `xiaomi/mimo-v2-pro:free` | Requires key but reliable |

### Failover Rules

- **Retry on**: HTTP 429, 500, 502, 503, 504, timeout, network error
- **Stop on**: HTTP 400, 401, 403, 404 — these indicate a problem with the request itself

---

## Simple Failover Script (Bash)

Save this as `free-inference.sh`:

```bash
#!/bin/bash

# Configuration
MESSAGE="${1:-Hello!}"
KILO_KEY="YOUR_KILO_API_KEY"      # Replace with your key
OPENCODE_KEY=""                    # Optional: set if you have one

# The failover chain — edit order as needed
PROVIDERS=(
  "opencode-mimo"
  "opencode-minimax"
  "kilocode-mimo"
)

# API endpoint and model for each
declare -A ENDPOINTS=(
  ["opencode-mimo"]="https://opencode.ai/zen/v1/chat/completions"
  ["opencode-minimax"]="https://opencode.ai/zen/v1/chat/completions"
  ["kilocode-mimo"]="https://api.kilo.ai/api/openrouter/v1/chat/completions"
)

declare -A MODELS=(
  ["opencode-mimo"]="mimo-v2-pro-free"
  ["opencode-minimax"]="minimax-m2.5-free"
  ["kilocode-mimo"]="xiaomi/mimo-v2-pro:free"
)

# Build request body
BODY=$(cat <<EOF
{
  "model": "",
  "messages": [{"role": "user", "content": "$MESSAGE"}],
  "max_tokens": 100
}
EOF
)

# Try each provider in order
for provider in "${PROVIDERS[@]}"; do
  endpoint="${ENDPOINTS[$provider]}"
  model="${MODELS[$provider]}"
  
  # Inject model into request body
  body_with_model=$(echo "$BODY" | sed "s/\"model\": \"\"/\"model\": \"$model\"/")
  
  # Build curl command
  cmd="curl -s -X POST '$endpoint'"
  cmd="$cmd -H 'Content-Type: application/json'"
  cmd="$cmd -H 'HTTP-Referer: https://openclaw.ai'"
  
  # Add auth header if we have a key
  if [[ -n "$OPENCODE_KEY" && "$provider" == opencode* ]]; then
    cmd="$cmd -H 'Authorization: Bearer $OPENCODE_KEY'"
  fi
  if [[ -n "$KILO_KEY" && "$provider" == kilocode* ]]; then
    cmd="$cmd -H 'Authorization: Bearer $KILO_KEY'"
  fi
  
  cmd="$cmd -d '$body_with_model'"
  
  # Execute and capture response
  response=$(eval $cmd 2>/dev/null)
  http_code=$(eval $cmd -w "%{http_code}" -o /dev/null 2>/dev/null)
  
  # Check if successful
  if [[ "$http_code" == "200" ]]; then
    echo "$response"
    exit 0
  fi
  
  echo "Provider $provider failed (HTTP $http_code), trying next..." >&2
done

echo "All providers failed!" >&2
exit 1
```

Usage:
```bash
chmod +x free-inference.sh
./free-inference.sh "What is 2 + 2?"
```

---

## Python Failover Script

Save this as `free_inference.py`:

```python
import requests
import time

# Configuration — edit these
KILO_KEY = "YOUR_KILO_API_KEY"      # Replace with your key
OPENCODE_KEY = ""                    # Optional

# Failover chain in order
PROVIDERS = [
    {"name": "opencode-mimo", "url": "https://opencode.ai/zen/v1/chat/completions", "model": "mimo-v2-pro-free"},
    {"name": "opencode-minimax", "url": "https://opencode.ai/zen/v1/chat/completions", "model": "minimax-m2.5-free"},
    {"name": "kilocode-mimo", "url": "https://api.kilo.ai/api/openrouter/v1/chat/completions", "model": "xiaomi/mimo-v2-pro:free"},
]

HEADERS = {
    "Content-Type": "application/json",
    "HTTP-Referer": "https://openclaw.ai"
}

def call_api(url, model, api_key=None):
    """Make a single API call."""
    headers = HEADERS.copy()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": MESSAGE}],
        "max_tokens": 100
    }
    
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        return resp.status_code, resp.text
    except requests.exceptions.Timeout:
        return 504, "timeout"
    except Exception as e:
        return 500, str(e)

def should_retry(status_code):
    """Return True if we should try the next provider."""
    # Retry on rate limits and server errors
    return status_code in [429, 500, 502, 503, 504]

# Your prompt
MESSAGE = "What is 2 + 2?"

# Try each provider in order
for provider in PROVIDERS:
    name = provider["name"]
    url = provider["url"]
    model = provider["model"]
    
    # Choose the right API key
    api_key = None
    if "kilocode" in name:
        api_key = KILO_KEY
    elif "opencode" in name and OPENCODE_KEY:
        api_key = OPENCODE_KEY
    
    print(f"Trying {name}...", file=__import__('sys').stderr)
    status_code, response = call_api(url, model, api_key)
    
    if status_code == 200:
        print(response)
        exit(0)
    
    if not should_retry(status_code):
        print(f"Non-retryable error ({status_code}): {response}", file=__import__('sys').stderr)
        exit(1)
    
    print(f"Failed with HTTP {status_code}, trying next...", file=__import__('sys').stderr)

print("All providers failed!", file=__import__('sys').stderr)
exit(1)
```

Usage:
```bash
python3 free_inference.py
```

---

## JavaScript (Node.js) Failover

Save this as `free_inference.js`:

```javascript
const https = require('https');

// Configuration
const KILO_KEY = 'YOUR_KILO_API_KEY';      // Replace with your key
const OPENCODE_KEY = '';                    // Optional

// Failover chain
const PROVIDERS = [
  { name: 'opencode-mimo', url: 'https://opencode.ai/zen/v1/chat/completions', model: 'mimo-v2-pro-free' },
  { name: 'opencode-minimax', url: 'https://opencode.ai/zen/v1/chat/completions', model: 'minimax-m2.5-free' },
  { name: 'kilocode-mimo', url: 'https://api.kilo.ai/api/openrouter/v1/chat/completions', model: 'xiaomi/mimo-v2-pro:free' },
];

const MESSAGE = 'What is 2 + 2?';

function makeRequest(provider) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      model: provider.model,
      messages: [{ role: 'user', content: MESSAGE }],
      max_tokens: 100
    });

    const headers = {
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://openclaw.ai'
    };

    // Add auth if we have a key
    if (provider.name.startsWith('kilocode') && KILO_KEY) {
      headers['Authorization'] = `Bearer ${KILO_KEY}`;
    } else if (provider.name.startsWith('opencode') && OPENCODE_KEY) {
      headers['Authorization'] = `Bearer ${OPENCODE_KEY}`;
    }

    const url = new URL(provider.url);
    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname,
      method: 'POST',
      headers: headers
    };

    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        resolve({ status: res.statusCode, body });
      });
    });

    req.on('error', reject);
    req.setTimeout(30000, () => {
      req.destroy();
      reject(new Error('timeout'));
    });

    req.write(data);
    req.end();
  });
}

async function run() {
  for (const provider of PROVIDERS) {
    try {
      console.error(`Trying ${provider.name}...`);
      const result = await makeRequest(provider);
      
      if (result.status === 200) {
        console.log(result.body);
        return;
      }
      
      const shouldRetry = [429, 500, 502, 503, 504].includes(result.status);
      if (!shouldRetry) {
        console.error(`Non-retryable error: ${result.body}`);
        process.exit(1);
      }
      
      console.error(`Failed (${result.status}), trying next...`);
    } catch (err) {
      console.error(`Error: ${err.message}, trying next...`);
    }
  }
  
  console.error('All providers failed!');
  process.exit(1);
}

run();
```

Usage:
```bash
node free_inference.js
```
