#!/usr/bin/env node
// Push Bridge — MCP server.
// Exposes a `request_approval` tool any MCP-capable agent (Claude Code, Codex,
// Gemini CLI, Cursor) can call to get a human Approve/Deny from their phone.
// Reuses the same relay as the Claude Code hook — this is just another client.
//
// Config (env):
//   PUSH_BRIDGE_LICENSE_KEY   required (pk_live_… / pk_test_…)
//   PUSH_BRIDGE_RELAY_URL     default https://relay-eight-sage.vercel.app
//   PUSH_BRIDGE_DEVICE_LABEL  default "agent"
//   PUSH_BRIDGE_TIMEOUT_MS    default 280000 (how long to wait for the tap)

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const RELAY_URL = process.env.PUSH_BRIDGE_RELAY_URL ?? "https://relay-eight-sage.vercel.app";
const LICENSE = process.env.PUSH_BRIDGE_LICENSE_KEY ?? "";
const DEVICE = process.env.PUSH_BRIDGE_DEVICE_LABEL ?? "agent";
const TIMEOUT_MS = Number(process.env.PUSH_BRIDGE_TIMEOUT_MS ?? 280000);
const POLL_WAIT_MS = 5000;

const TOOLS = [
  {
    name: "request_approval",
    description:
      "Ask the human to Approve or Deny an action from their phone, and BLOCK until they respond. " +
      "Call this before any destructive, irreversible, or sensitive action (force-push, rm -rf, " +
      "production deploy, payment, sending email/DM, deleting data) so a human can sign off remotely. " +
      "Returns 'approved', 'denied', or 'no_response' (deferred). On 'denied' or 'no_response', do NOT proceed.",
    inputSchema: {
      type: "object",
      properties: {
        summary: {
          type: "string",
          description: "Short human-readable description of what you want to do, e.g. 'Force-push to main'.",
        },
        command: {
          type: "string",
          description: "Optional exact command or detail to show the human, e.g. 'git push --force origin main'.",
        },
      },
      required: ["summary"],
    },
  },
  {
    name: "notify",
    description:
      "Send a one-way push notification to the human's phone (no response awaited). Use for 'task done', " +
      "'I'm blocked', or status pings. Returns immediately.",
    inputSchema: {
      type: "object",
      properties: {
        message: { type: "string", description: "The message to push to the phone." },
      },
      required: ["message"],
    },
  },
];

function newCallbackId() {
  return "mcp-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

async function postWebhook(promptText) {
  const res = await fetch(`${RELAY_URL}/api/webhook`, {
    method: "POST",
    headers: { Authorization: `Bearer ${LICENSE}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      event: "permission_request",
      session_id: "mcp",
      callback_id: newCallbackId(),
      device_label: DEVICE,
      prompt: promptText,
      timestamp: Math.floor(Date.now() / 1000),
    }),
  });
  if (!res.ok) throw new Error(`webhook ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res.json();
}

async function pollOnce(env) {
  const res = await fetch(`${RELAY_URL}/api/poll`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      callback_id: env.callback_id,
      user_id: env.user_id,
      exp: env.exp,
      sig: env.sig,
      wait_ms: POLL_WAIT_MS,
    }),
  });
  if (!res.ok) return "network_error";
  const data = await res.json();
  return data.decision ?? "unknown";
}

async function requestApproval(summary, command) {
  if (!LICENSE) {
    return "error: PUSH_BRIDGE_LICENSE_KEY is not set — cannot reach the relay.";
  }
  const promptText = command ? `${summary}\n${command}` : summary;
  let env;
  try {
    env = await postWebhook(promptText);
  } catch (e) {
    return `no_response (relay error: ${String(e).slice(0, 160)}). Falling back to manual approval.`;
  }
  if (!env.callback_id || !env.sig) {
    return "no_response (relay did not return a callback). Falling back to manual approval.";
  }
  const deadline = Date.now() + TIMEOUT_MS;
  while (Date.now() < deadline) {
    let decision;
    try {
      decision = await pollOnce(env);
    } catch {
      decision = "network_error";
    }
    if (decision === "approve") return "approved";
    if (decision === "deny") return "denied";
    if (decision === "timeout" || decision === "expired") return "no_response";
    // pending / unknown / network_error → keep waiting
  }
  return "no_response";
}

async function notify(message) {
  if (!LICENSE) return "error: PUSH_BRIDGE_LICENSE_KEY is not set.";
  try {
    await postWebhook(message);
    return "sent";
  } catch (e) {
    return `failed: ${String(e).slice(0, 160)}`;
  }
}

const server = new Server(
  { name: "push-bridge", version: "0.1.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params;
  if (name === "request_approval") {
    const result = await requestApproval(args?.summary ?? "Approve this action?", args?.command);
    return { content: [{ type: "text", text: result }] };
  }
  if (name === "notify") {
    const result = await notify(args?.message ?? "(empty)");
    return { content: [{ type: "text", text: result }] };
  }
  return { content: [{ type: "text", text: `unknown tool: ${name}` }], isError: true };
});

const transport = new StdioServerTransport();
await server.connect(transport);
// stderr is safe for logs (stdout is the MCP channel)
console.error(`push-bridge MCP server ready (relay: ${RELAY_URL})`);
