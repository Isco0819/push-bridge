# Push Bridge

**Approve your AI coding agent's risky commands from your phone — so it keeps working while you're away.**

When Claude Code / Codex / Gemini CLI / Cursor needs permission to run something risky
(force-push, `rm -rf`, a deploy, sending email), Push Bridge sends the request to your phone.
You see the exact command, tap **Approve / Deny**, and your agent continues.

The whole promise of agentic coding is "it works while you do other things" — until it stops and
waits for you to approve one command. Push Bridge closes that gap.

## How it works

- **Claude Code** — a `PreToolUse` hook forwards the prompt to a relay and long-polls for your decision.
- **Any MCP agent (Codex, Gemini CLI, Cursor, …)** — a `request_approval` tool that blocks until you respond.
- **Phone side** — a PWA using Web Push. You get the notification; you decide.

A remote approve is also a remote kill switch — so you can run agents *more* autonomously without
losing control. Human-in-the-loop, but the human can be anywhere.

## Install

### Claude Code (hook)
```bash
curl -fsSL https://pwa-artvibes-projects.vercel.app/install.sh | bash
```
Then add the hook to `~/.claude/settings.json` (the installer prints the exact snippet). See [`plugin/README.md`](plugin/README.md).

### MCP (Codex / Gemini CLI / Cursor / Claude Code)
See [`mcp/README.md`](mcp/README.md) — exposes `request_approval` and `notify` tools to any MCP client.

## Free vs Pro

- **Free / OSS** (this repo, MIT): the plugin + MCP server. Bring your own webhook (e.g. [ntfy.sh](https://ntfy.sh)) — get pinged when your agent needs you.
- **Pro ($9/mo)**: hosted relay + the phone app with Approve/Deny. → https://pwa-artvibes-projects.vercel.app

## A note on iOS

iOS web push doesn't render notification **action buttons** yet, so on iOS you tap the notification
and Approve/Deny inside the app (one extra tap). Android & desktop get the buttons directly on the
notification.

## License

MIT — see [LICENSE](LICENSE).
