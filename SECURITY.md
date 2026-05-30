# Security & Privacy

Push Bridge sees the commands your AI agent wants to run, so its job is to leak
as little as possible. This document is exact about what leaves your machine,
what the relay stores, and how to route around our infrastructure entirely.

TL;DR: **only the single command awaiting approval leaves your machine — with
secrets redacted first — and the relay never writes that command to disk.**

## What leaves your machine
When your agent hits an action that needs approval, Push Bridge sends to the relay:

- the **redacted** permission prompt (the command/summary, with secrets masked — see below)
- a random `callback_id`
- your license id and a `device_label`
- a timestamp

It does **not** send your source code, your files, your repo, your environment
variables, your shell history, or your agent's conversation/session. Just the one
command awaiting your decision.

> Contrast: tools that mirror or "control your session from your phone" stream
> your whole working session to their cloud. Push Bridge deliberately doesn't.

## What the relay stores
The hosted relay stores:

- your **push subscription** (so it can deliver notifications to your device), and
- a **transient callback record** whose value is literally just `pending` →
  `approve`/`deny`, set with a short TTL so it auto-expires.

The **command text is never persisted on the relay.** It travels inside the
end-to-end-encrypted Web Push payload to your device and is kept only in your
device's local history (in the browser, on your phone).

## Secret redaction (before anything leaves)
Both integration paths mask known secret patterns **on your machine**, before the
prompt is sent. The secret *value* is masked; the command *context* is kept so you
can still make an approve/deny decision. Both files are MIT and in this repo:

- Claude Code hook → [`plugin/hooks/sanitize.jq`](plugin/hooks/sanitize.jq)
- MCP server (Codex / Gemini CLI / Cursor / any MCP agent) → [`mcp/server.mjs`](mcp/server.mjs) (`redact()`)

Patterns masked include: Anthropic / OpenAI / Groq keys, GitHub tokens & PATs,
AWS / GCP keys, Slack tokens, JWTs, `password|token|secret|api_key|bearer = …`
assignments, and `postgres://`, `mongodb://`, `redis://` connection URLs.

**Example — this is exactly what happens:**
```
Agent wants to run:
  psql "postgres://admin:hunter2@db.internal:5432/prod"

What Push Bridge actually sends to the relay:
  {
    "event": "permission_request",
    "callback_id": "mcp-abc123",
    "device_label": "agent",
    "prompt": "psql \"REDACTED_PG_URL\"",   <-- masked before leaving your machine
    "timestamp": 1764000000
  }

What the relay stores:
  callback_id  ->  "pending"   (then "approve" / "deny"), auto-expiring.
  (the command text is not stored)
```

Redaction is best-effort pattern matching, not a guarantee against every possible
secret. If you handle especially sensitive material, route around our relay (below)
and/or add patterns to `sanitize.jq` / `redact()` — they're plain files you control.

## Transport & integrity
- All API traffic is HTTPS.
- Web Push payloads are end-to-end encrypted (VAPID / `aes128gcm`); only your
  device can decrypt the command.
- Decision callbacks are **HMAC-signed**. A tampered or replayed decision is
  rejected (`401 invalid_signature`); expired callbacks are rejected.
- Requests are license-scoped; an invalid license is rejected (`402`).

## Don't want to use our relay at all?
The plugin and MCP server are MIT ([`plugin/`](plugin), [`mcp/`](mcp)) and the
notification target is yours to choose:

- **Free / BYO path:** point the hook at your own webhook / notifier (e.g.
  [ntfy.sh](https://ntfy.sh)) and skip our hosted relay entirely.
- **Custom relay:** the relay URL is configurable (`PUSH_BRIDGE_RELAY_URL` for the
  MCP server, the relay URL in the hook config), so you can self-route.

The hosted relay + iOS app are the paid convenience (Pro) — not a requirement.

## Reporting a vulnerability
Email **tatusige0819@gmail.com** with details and steps to reproduce. Please don't
open a public issue for security reports. We'll acknowledge and work a fix before
any disclosure.
