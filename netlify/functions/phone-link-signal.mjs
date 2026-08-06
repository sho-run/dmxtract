// Signaling relay for the QR phone-photo hand-off. It never sees a photo: it
// only relays a WebRTC offer and answer, each already AES-GCM encrypted in
// the browser with a key that lives solely in the URL fragment (see
// apps/web/web/phone_link_shared.js). This function stores and forwards
// ciphertext bytes it cannot decrypt.
import { getStore } from "@netlify/blobs";

const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "private, no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

const STORE_NAME = "phone-link-signal";
const SESSION_ID_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;
const MAX_BODY_BYTES = 16 * 1024; // encrypted SDP + ICE candidates, generous bound
const TTL_MS = 5 * 60 * 1000; // rendezvous window; stale sessions are swept lazily
const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;
const RATE_LIMIT_MAX_WRITES = 20; // generous for legitimate offer/answer retries; blocks scripted floods

export default async (request) => {
  let store;
  try {
    store = adaptStore(getStore({ name: STORE_NAME, consistency: "strong" }));
  } catch {
    // No Netlify Blobs context (e.g. self-hosted without it configured).
    // Degrade to "unavailable" rather than crashing the function.
    store = null;
  }
  return handle(request, store);
};

// Exported so tests can inject a fake store instead of mocking the
// `@netlify/blobs` module.
export async function handle(request, store) {
  const url = new URL(request.url);
  if (request.method === "GET") return handleGet(url, store);
  if (request.method === "POST") return handlePost(request, store);
  return response(405, { error: "Method not allowed." }, { Allow: "GET, POST" });
}

function adaptStore(blobStore) {
  return {
    async getJSON(key) {
      return (await blobStore.get(key, { type: "json" })) ?? null;
    },
    async setJSON(key, value) {
      await blobStore.setJSON(key, value);
    },
    async deleteKey(key) {
      await blobStore.delete(key);
    },
  };
}

async function handleGet(url, store) {
  const sessionId = url.searchParams.get("sessionId");
  if (!sessionId) {
    // Feature probe: report availability without creating any state, so the
    // desktop UI can hide the QR affordance when the relay isn't usable.
    return response(200, { available: await probeAvailable(store) });
  }
  if (!store) return response(503, { error: "Signaling relay is not configured." });
  if (!SESSION_ID_PATTERN.test(sessionId)) {
    return response(400, { error: "Invalid session id." });
  }
  const slot = url.searchParams.get("slot");
  if (slot !== "offer" && slot !== "answer") {
    return response(400, { error: "slot must be offer or answer." });
  }

  const record = await loadFresh(store, sessionId);
  const entry = record?.[slot];
  if (!entry) return response(200, { ready: false });

  if (slot === "answer") {
    // The offering side reading the answer completes the handshake; the
    // relay has nothing further to do and drops all state for the session.
    await store.deleteKey(sessionId);
  }
  return response(200, { ready: true, iv: entry.iv, ciphertext: entry.ciphertext });
}

async function handlePost(request, store) {
  if (!store) return response(503, { error: "Signaling relay is not configured." });
  if (!isTrustedOrigin(request)) return response(403, { error: "Cross-origin requests are not allowed." });

  const ip = clientIp(request);
  if (!(await checkAndRecordWrite(store, ip))) {
    return response(429, { error: "Too many requests. Try again in a few minutes." });
  }

  let body;
  try {
    // Reject on the declared length before buffering, then re-check the
    // decoded byte length: Content-Length can be absent or wrong, and a
    // JS string's .length is UTF-16 code units, not bytes, so a string
    // within budget can still decode to a larger UTF-8 payload.
    const declaredLength = Number(request.headers.get("content-length") || 0);
    if (declaredLength > MAX_BODY_BYTES) return response(413, { error: "Payload is too large." });
    const raw = await request.text();
    if (Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) {
      return response(413, { error: "Payload is too large." });
    }
    body = JSON.parse(raw);
  } catch {
    return response(400, { error: "Invalid request body." });
  }

  const sessionId = typeof body.sessionId === "string" ? body.sessionId : "";
  const slot = body.slot;
  const iv = typeof body.iv === "string" ? body.iv : "";
  const ciphertext = typeof body.ciphertext === "string" ? body.ciphertext : "";

  if (!SESSION_ID_PATTERN.test(sessionId)) return response(400, { error: "Invalid session id." });
  if (slot !== "offer" && slot !== "answer") return response(400, { error: "slot must be offer or answer." });
  if (!isBase64Url(iv) || !isBase64Url(ciphertext) || ciphertext.length > MAX_BODY_BYTES) {
    return response(400, { error: "Invalid signaling payload." });
  }

  const existing = await loadFresh(store, sessionId);
  let record;
  if (slot === "offer") {
    if (existing?.answer) return response(409, { error: "Session already connected." });
    record = {
      createdAt: Date.now(),
      expiresAt: Date.now() + TTL_MS,
      offer: { iv, ciphertext },
      answer: null,
    };
  } else {
    if (!existing?.offer) return response(404, { error: "No offer waiting for this session." });
    if (existing.answer) return response(409, { error: "Session already has an answer." });
    record = { ...existing, answer: { iv, ciphertext } };
  }

  await store.setJSON(sessionId, record);
  return response(200, { ok: true });
}

// The app only ever POSTs to this same origin (see phone_link.js building
// signalUrl from location.origin); a browser always sends Origin on a
// same-site POST too, so a present-but-mismatched Origin means the request
// was initiated by a different site (e.g. embedded in a malicious page) and
// is rejected. A missing Origin (non-browser clients, some proxies) is not
// itself proof of abuse, so it falls through to rate limiting below instead
// of being trusted or rejected outright.
function isTrustedOrigin(request) {
  const origin = request.headers.get("origin");
  if (!origin) return true;
  const host = request.headers.get("host");
  if (!host) return true;
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

// Netlify sets this at the edge from the real connection; unlike
// X-Forwarded-For it cannot be spoofed by the client.
function clientIp(request) {
  return request.headers.get("x-nf-client-connection-ip") || "unknown";
}

// Best-effort per-IP write budget stored alongside sessions. Not atomic, so
// a race can let a couple of concurrent requests slip past the limit, but
// that's an acceptable slack for abuse mitigation rather than correctness.
async function checkAndRecordWrite(store, ip) {
  const key = `ratelimit:${ip}`;
  const now = Date.now();
  const existing = await store.getJSON(key);
  if (!existing || existing.windowStart + RATE_LIMIT_WINDOW_MS <= now) {
    await store.setJSON(key, { windowStart: now, count: 1 });
    return true;
  }
  if (existing.count >= RATE_LIMIT_MAX_WRITES) return false;
  await store.setJSON(key, { windowStart: existing.windowStart, count: existing.count + 1 });
  return true;
}

async function loadFresh(store, sessionId) {
  const record = await store.getJSON(sessionId);
  if (!record) return null;
  if (!record.expiresAt || record.expiresAt < Date.now()) {
    await store.deleteKey(sessionId);
    return null;
  }
  return record;
}

async function probeAvailable(store) {
  if (!store) return false;
  try {
    // A read of a key that is never written; failures mean Blobs is not
    // usable in this environment.
    await store.getJSON("__phone_link_probe__");
    return true;
  } catch {
    return false;
  }
}

function isBase64Url(value) {
  return typeof value === "string" && value.length > 0 && /^[A-Za-z0-9_-]+$/.test(value);
}

function response(status, body, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...extraHeaders },
  });
}
