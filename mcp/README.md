# Push Bridge — MCP server

Lets **any MCP-capable AI agent** (Claude Code, Codex, Gemini CLI, Cursor, …)
ask you to Approve/Deny an action from your phone, and block until you respond.

The agent calls the `request_approval` tool before doing something risky
(force-push, `rm -rf`, prod deploy, payment, sending email). You get a push on
your phone, tap Approve/Deny, and the decision is returned to the agent.

This is the AI-native, cross-agent path. It reuses the same relay + phone app as
the Claude Code hook — for Codex/Gemini (which can't do blocking approval via
their own hooks), this MCP tool is the way to get remote approval.

## Tools
- `request_approval({ summary, command? })` → `"approved" | "denied" | "no_response"`. Blocks up to ~280s. On `denied`/`no_response`, the agent should NOT proceed.
- `notify({ message })` → one-way push ("task done", "I'm blocked"). Returns immediately.

## Config (env)
| var | required | default |
|---|---|---|
| `PUSH_BRIDGE_LICENSE_KEY` | ✅ | — (`pk_live_…` / `pk_test_…`) |
| `PUSH_BRIDGE_RELAY_URL` | | `https://relay-eight-sage.vercel.app` |
| `PUSH_BRIDGE_DEVICE_LABEL` | | `agent` |
| `PUSH_BRIDGE_TIMEOUT_MS` | | `280000` |

First register your phone once at the PWA, then install the server in your agent:

### Claude Code
```bash
claude mcp add push-bridge \
  -e PUSH_BRIDGE_LICENSE_KEY=pk_live_xxx \
  -- npx -y github:Isco0819/push-bridge
```

### Codex CLI
`~/.codex/config.toml`:
```toml
[mcp_servers.push-bridge]
command = "node"
args = ["-y", "github:Isco0819/push-bridge"]
env = { PUSH_BRIDGE_LICENSE_KEY = "pk_live_xxx" }
```

### Gemini CLI
`~/.gemini/settings.json`:
```json
{
  "mcpServers": {
    "push-bridge": {
      "command": "npx",
      "args": ["-y", "github:Isco0819/push-bridge"],
      "env": { "PUSH_BRIDGE_LICENSE_KEY": "pk_live_xxx" }
    }
  }
}
```

### Cursor
`.cursor/mcp.json`:
```json
{
  "mcpServers": {
    "push-bridge": {
      "command": "npx",
      "args": ["-y", "github:Isco0819/push-bridge"],
      "env": { "PUSH_BRIDGE_LICENSE_KEY": "pk_live_xxx" }
    }
  }
}
```

## Make the agent use it
Add to your project's `AGENTS.md` / `CLAUDE.md` / system prompt:

> Before any destructive or irreversible action (force-push, deleting data,
> production deploy, payments, sending external messages), call the
> `request_approval` tool and only proceed if it returns `approved`.

## Notes
- Once published to npm you'll be able to use `npx -y push-bridge-mcp` instead of an absolute path.
- The relay notification title currently reads "Claude Code: permission needed" regardless of agent — cosmetic, will be parameterized.
