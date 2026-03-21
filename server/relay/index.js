/**
 * easy-markdown Pro AI Relay Server
 *
 * Lightweight API relay per [A-009] and FEAT-046:
 * 1. Validates App Store subscription receipt (StoreKit 2 JWS)
 * 2. Forwards selected text to AI provider (Anthropic Claude)
 * 3. Streams SSE response back to client
 * 4. Logs ZERO user content (no prompts, responses, or user data) per [D-AI-8]
 *
 * Deploy as: standalone Node.js server, Cloudflare Worker, AWS Lambda, etc.
 */

import { createServer } from "node:http";
import { verifySubscription } from "./verify-subscription.js";

const PORT = parseInt(process.env.PORT || "8080", 10);
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const ANTHROPIC_API_URL =
  process.env.ANTHROPIC_API_URL ||
  "https://api.anthropic.com/v1/messages";
const ANTHROPIC_MODEL = process.env.ANTHROPIC_MODEL || "claude-sonnet-4-20250514";

if (!ANTHROPIC_API_KEY) {
  console.error("FATAL: ANTHROPIC_API_KEY environment variable is required");
  process.exit(1);
}

/**
 * Main request handler — POST /v1/generate
 */
async function handleGenerate(req, res) {
  // CORS headers for client requests
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method !== "POST") {
    res.writeHead(405, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  // --- Step 1: Validate subscription receipt ---
  const authHeader = req.headers["authorization"];
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Missing subscription token" }));
    return;
  }

  const jws = authHeader.slice(7);

  try {
    const subscriptionValid = await verifySubscription(jws);
    if (!subscriptionValid) {
      // Log only: subscription rejected (no user data)
      console.log("subscription_rejected");
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Invalid or expired subscription" }));
      return;
    }
  } catch {
    console.log("subscription_verification_error");
    res.writeHead(401, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Subscription verification failed" }));
    return;
  }

  // --- Step 2: Parse request body ---
  let body;
  try {
    body = await readJSON(req);
  } catch {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Invalid request body" }));
    return;
  }

  const { prompt, system, context } = body;

  if (!prompt || typeof prompt !== "string") {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Missing prompt field" }));
    return;
  }

  // --- Step 3: Forward to Anthropic Claude with streaming ---
  const userContent = context
    ? `Context:\n${context}\n\nText to work with:\n${prompt}`
    : prompt;

  const anthropicBody = {
    model: ANTHROPIC_MODEL,
    max_tokens: 4096,
    stream: true,
    system: system || undefined,
    messages: [{ role: "user", content: userContent }],
  };

  let anthropicRes;
  try {
    anthropicRes = await fetch(ANTHROPIC_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify(anthropicBody),
    });
  } catch {
    // Log only: upstream connectivity issue (no user data)
    console.log("anthropic_connection_error");
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "AI provider unavailable" }));
    return;
  }

  if (!anthropicRes.ok) {
    // Log only: status code (no response body which may contain user content)
    console.log(`anthropic_error status=${anthropicRes.status}`);
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "AI provider error" }));
    return;
  }

  // --- Step 4: Stream SSE response back to client ---
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });

  const startTime = Date.now();

  try {
    const reader = anthropicRes.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const data = line.slice(6).trim();
        if (data === "[DONE]") continue;

        try {
          const event = JSON.parse(data);

          if (
            event.type === "content_block_delta" &&
            event.delta?.type === "text_delta"
          ) {
            res.write(`data: ${event.delta.text}\n\n`);
          }
        } catch {
          // Skip malformed SSE lines
        }
      }
    }
  } catch {
    // Stream interrupted — client likely disconnected
  }

  // Signal completion
  res.write("data: [DONE]\n\n");
  res.end();

  // Log only: latency metric (no user content)
  const latencyMs = Date.now() - startTime;
  console.log(`request_complete latency_ms=${latencyMs}`);
}

/**
 * Read and parse JSON from an incoming request.
 */
function readJSON(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    const MAX_BODY = 64 * 1024; // 64 KB limit

    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new Error("Body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString()));
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

// --- HTTP Server ---

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === "/v1/generate") {
    await handleGenerate(req, res);
  } else if (url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
  } else {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  }
});

server.listen(PORT, () => {
  console.log(`relay listening on port ${PORT}`);
});
