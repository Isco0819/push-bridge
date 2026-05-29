# Push Bridge — Unblock Claude Code from your wrist

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![npm version](https://badge.fury.io/js/push-bridge.svg)](https://badge.fury.io/js/push-bridge)
[![GitHub stars](https://img.shields.io/github/stars/push-bridge/plugin.svg)](https://github.com/push-bridge/plugin/stargazers)

**Push Bridge** is an open-source hook for Claude Code that intercepts permission requests and forwards them to your phone or Apple Watch. Stop babysitting your terminal—tap **Approve** from your wrist while you make coffee, and your AI agent instantly resumes work.

```bash
curl -fsSL https://push-bridge.dev/install.sh | bash
```

![Push Bridge Demo on Apple Watch](https://push-bridge.dev/assets/placeholder-watch-demo.png)

## Why Push Bridge?

If you use Claude Code for complex, multi-step tasks, you've likely experienced the "coordination tax": walking away for 10 minutes, only to find the agent paused on step 2, waiting for you to approve a simple `npm install`.

While there are other notification scripts out there, **Push Bridge** is built specifically for a seamless, frictionless developer experience:

- **Actionable Notifications**: Not just an alert. Our hosted PWA sends iOS 18.4+ Declarative Web Push notifications with native **Approve** and **Deny** buttons.
- **Apple Watch Native Feel**: Approvals mirror instantly to your Apple Watch. No need to unlock your phone.
- **Rigorous Local Sanitization**: Secrets never leave your machine (see Privacy below).

### Comparison

| Feature | Push Bridge (Pro) | `claude-push` (ntfy) | `claude-telegram-bridge` | `clay` (Web App) |
|---|---|---|---|---|
| **Primary UX** | **1-Tap from Lock Screen / Watch** | 1-Tap from Lock Screen | Chat Reply / Typing | Browser Dashboard |
| **Requires Native App** | No (PWA) | Yes (ntfy app) | Yes (Telegram) | No (Browser) |
| **Local Secret Masking** | **Built-in (regex + jq)** | None | None | None |
| **Setup Time** | 2 minutes | 5 minutes | 15+ minutes | 15+ minutes |

## Install & Configure

Run the one-line installer:
```bash
curl -fsSL https://push-bridge.dev/install.sh | bash
```

Edit your config at `~/.claude/plugins/push-bridge/config.json`:

### Option A: Hosted Pro (Actionable Push + Apple Watch)
Get a license key at [push-bridge.dev](https://push-bridge.dev).

```json
{
  "mode": "pro",
  "license_key": "pk_live_YOUR_LICENSE_KEY",
  "device_label": "MacBook Pro"
}
```

### Option B: Free / DIY (ntfy.sh fire-and-forget)
```json
{
  "mode": "byo",
  "webhook_url": "https://ntfy.sh/your-private-topic",
  "device_label": "MacBook Pro"
}
```

## Privacy: What we send & What we never send

Security is the #1 priority for autonomous AI agents. The Push Bridge hook intercepts the prompt **locally** and scrubs it before hitting the network.

**What gets sent to the Relay:**
- The action type and truncated target (e.g., `Bash: rm -rf node_modules`)
- A secure callback ID
- Your license key (to verify your account)

**What is NEVER sent:**
- Anthropic API Keys (`sk-ant-***`)
- OpenAI, AWS, Google Cloud, GitHub tokens
- Slack tokens or JWTs
- The contents of your files
- Your conversation history with Claude

Our sanitization script (`sanitize.jq`) rigorously masks 11+ common credential patterns into `REDACTED_***_KEY`. 

## How it works internally

1. **Intercept**: Claude Code triggers the `permission_request` hook.
2. **Sanitize**: The hook parses the prompt, applies regex filters, and generates a Webhook POST.
3. **Relay**: The Edge-based Relay verifies your license, signs a callback URL (HMAC), and pushes the notification to your PWA via FCM/VAPID.
4. **Action**: You tap "Approve" on your phone. The PWA posts back to the Relay, which sets a flag in Upstash Redis.
5. **Resume**: The local hook, which has been polling the Edge, sees the "approve" state and allows Claude Code to proceed.

## Contributing & License

Contributions are welcome! Please open an issue before submitting a major PR.

This plugin is licensed under the **MIT License**. The hosted Push Bridge Relay service and PWA are proprietary. 

---
⭐️ **If you find Push Bridge useful, please star this repository!** ⭐️