#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$HOME/.claude/plugins/push-bridge"
HOOKS_DIR="$HOME/.claude/hooks"
CONFIG_FILE="$PLUGIN_DIR/config.json"

mkdir -p "$PLUGIN_DIR/hooks"
mkdir -p "$HOOKS_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/hooks/permission-request.sh" "$PLUGIN_DIR/hooks/permission-request.sh"
cp "$SCRIPT_DIR/hooks/sanitize.jq" "$PLUGIN_DIR/hooks/sanitize.jq"
chmod +x "$PLUGIN_DIR/hooks/permission-request.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "push-bridge: jq is required. Install with: brew install jq"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  cp "$SCRIPT_DIR/hooks/config.example.json" "$CONFIG_FILE"
  echo "Created config: $CONFIG_FILE"
  echo "Edit it to set your mode (pro / byo) and credentials."
fi

HOOK_LINK="$HOOKS_DIR/push-bridge-permission-request"
ln -sf "$PLUGIN_DIR/hooks/permission-request.sh" "$HOOK_LINK"

cat <<'EOF'

Push Bridge installed.

Next steps:
  1. Edit ~/.claude/plugins/push-bridge/config.json
  2. (Pro mode) Set license_key from https://push-bridge.dev/account
     (Free BYO mode) Set webhook_url to your ntfy.sh topic
  3. Install the PWA receiver on your iPhone: https://push-bridge.dev/install-pwa
  4. Trigger a Claude Code permission request to test.

EOF
