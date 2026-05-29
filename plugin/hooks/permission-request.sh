#!/usr/bin/env bash
# Push Bridge — Claude Code permission-request hook
# Fires when Claude Code requests user permission. Forwards to configured webhook
# and long-polls for the user's Approve/Deny decision.
# Never sends Anthropic API key, source code, or file contents.

set -euo pipefail

CONFIG="${PUSH_BRIDGE_CONFIG:-$HOME/.claude/plugins/push-bridge/config.json}"
# RELAY_URL is resolved after the config is validated below.
# Precedence: PUSH_BRIDGE_RELAY_URL env > config.relay_url > public default.
TIMEOUT_SECS="${PUSH_BRIDGE_TIMEOUT:-280}"   # exit (defer) before Claude Code's hook timeout (set timeout:300 in settings.json)
POLL_WAIT_MS="${PUSH_BRIDGE_POLL_WAIT_MS:-20000}"
SANITIZE_SCRIPT="${PUSH_BRIDGE_SANITIZE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sanitize.jq}"

if ! command -v jq >/dev/null 2>&1; then
  echo "push-bridge: jq is required (brew install jq)" >&2
  exit 0
fi
if [ ! -f "$CONFIG" ]; then
  echo "push-bridge: config not found at $CONFIG" >&2
  exit 0
fi

MODE=$(jq -r '.mode // "pro"' "$CONFIG")
DEVICE_LABEL=$(jq -r '.device_label // "unknown"' "$CONFIG")
RELAY_URL="${PUSH_BRIDGE_RELAY_URL:-$(jq -r '.relay_url // "https://relay.push-bridge.dev"' "$CONFIG")}"
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen 2>/dev/null || echo "anon-$$")}"
CALLBACK_HINT=$(uuidgen 2>/dev/null || echo "cb-$RANDOM-$RANDOM")

# Emit a PreToolUse decision in Claude Code's CURRENT hook schema.
# Usage: emit allow|deny "reason"   (omit entirely + exit 0 to defer to normal prompt)
emit() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

# Hook input from Claude Code (stdin JSON): { tool_name, tool_input, session_id, ... }
INPUT=$(cat || echo "{}")
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Tool"')
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -c '.tool_input // {}')

# Redact secrets from the tool input before it leaves the machine.
if [ -f "$SANITIZE_SCRIPT" ]; then
  TOOL_INPUT_SAFE=$(printf '%s' "$TOOL_INPUT" | jq -c -f "$SANITIZE_SCRIPT" 2>/dev/null || echo '{}')
else
  TOOL_INPUT_SAFE=$(printf '%s' "$TOOL_INPUT" | jq -c '
    def redact: . |
      gsub("sk-ant-[A-Za-z0-9_-]+"; "REDACTED_ANTHROPIC_KEY") |
      gsub("sk-[A-Za-z0-9]{32,}"; "REDACTED_OPENAI_KEY") |
      gsub("ghp_[A-Za-z0-9]{30,}"; "REDACTED_GH_TOKEN") |
      gsub("AKIA[0-9A-Z]{16}"; "REDACTED_AWS_KEY") |
      gsub("AIzaSy[A-Za-z0-9_-]{33}"; "REDACTED_GCP_KEY");
    walk(if type == "string" then redact else . end)
  ' 2>/dev/null || echo '{}')
fi

# What the relay/phone shows: { action: <tool_name>, ...tool_input }
PROMPT_SAFE=$(printf '%s' "$TOOL_INPUT_SAFE" | jq -c --arg a "$TOOL_NAME" '. + {action:$a}')

PAYLOAD=$(jq -n \
  --arg session_id "$SESSION_ID" \
  --arg callback_hint "$CALLBACK_HINT" \
  --arg device_label "$DEVICE_LABEL" \
  --argjson prompt "$PROMPT_SAFE" \
  '{
    event: "permission_request",
    session_id: $session_id,
    callback_id: $callback_hint,
    device_label: $device_label,
    prompt: $prompt,
    timestamp: now | floor
  }')

# BYO mode: fire-and-forget; we have no Relay to poll.
if [ "$MODE" = "byo" ]; then
  WEBHOOK_URL=$(jq -r '.webhook_url // ""' "$CONFIG")
  if [ -z "$WEBHOOK_URL" ]; then
    echo "push-bridge: webhook_url missing in byo mode" >&2
    exit 0
  fi
  curl -sS --max-time 10 \
    -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null || true
  # Notify-only: no decision channel, so defer to Claude Code's normal prompt.
  exit 0
fi

# Pro mode: POST to relay, then long-poll until decision or timeout.
if [ "$MODE" != "pro" ]; then
  echo "push-bridge: unknown mode '$MODE'" >&2
  exit 0
fi

LICENSE_KEY=$(jq -r '.license_key // ""' "$CONFIG")
if [ -z "$LICENSE_KEY" ] || [ "$LICENSE_KEY" = "pk_live_REPLACE_ME" ]; then
  echo "push-bridge: license_key missing in pro mode" >&2
  exit 0
fi

WEBHOOK_RESPONSE=$(curl -sS --max-time 15 \
  -X POST "$RELAY_URL/api/webhook" \
  -H "Authorization: Bearer $LICENSE_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" || echo '{"error":"webhook_failed"}')

CB_ID=$(echo "$WEBHOOK_RESPONSE" | jq -r '.callback_id // empty')
USER_ID=$(echo "$WEBHOOK_RESPONSE" | jq -r '.user_id // empty')
EXP=$(echo "$WEBHOOK_RESPONSE" | jq -r '.exp // empty')
SIG=$(echo "$WEBHOOK_RESPONSE" | jq -r '.sig // empty')

if [ -z "$CB_ID" ] || [ -z "$USER_ID" ] || [ -z "$EXP" ] || [ -z "$SIG" ]; then
  echo "push-bridge: webhook returned no callback ($WEBHOOK_RESPONSE) — deferring" >&2
  exit 0
fi

POLL_PAYLOAD=$(jq -n \
  --arg cb "$CB_ID" \
  --arg uid "$USER_ID" \
  --argjson exp "$EXP" \
  --arg sig "$SIG" \
  --argjson wait_ms "$POLL_WAIT_MS" \
  '{callback_id:$cb, user_id:$uid, exp:$exp, sig:$sig, wait_ms:$wait_ms}')

DEADLINE_EPOCH=$EXP
ABSOLUTE_DEADLINE=$(($(date +%s) + TIMEOUT_SECS))
if [ "$ABSOLUTE_DEADLINE" -lt "$DEADLINE_EPOCH" ]; then
  DEADLINE_EPOCH=$ABSOLUTE_DEADLINE
fi

while true; do
  NOW=$(date +%s)
  if [ "$NOW" -ge "$DEADLINE_EPOCH" ]; then
    # No phone response in time → defer to Claude Code's normal prompt.
    echo "push-bridge: no phone response before timeout — deferring" >&2
    exit 0
  fi

  POLL_RESPONSE=$(curl -sS --max-time 30 \
    -X POST "$RELAY_URL/api/poll" \
    -H "Content-Type: application/json" \
    -d "$POLL_PAYLOAD" || echo '{"decision":"network_error"}')

  DECISION=$(echo "$POLL_RESPONSE" | jq -r '.decision // "unknown"')

  case "$DECISION" in
    approve)
      emit allow "Approved from your phone via Push Bridge"
      exit 0
      ;;
    deny)
      emit deny "Denied from your phone via Push Bridge"
      exit 0
      ;;
    timeout|expired)
      exit 0   # defer to normal prompt
      ;;
    pending|unknown|network_error)
      sleep 1
      continue
      ;;
    *)
      exit 0   # defer
      ;;
  esac
done
