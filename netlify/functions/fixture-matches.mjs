const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "private, no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

export default async (request) => {
  if (request.method !== "POST") {
    return response(405, { error: "Method not allowed." }, { Allow: "POST" });
  }

  const configuredUrl = Netlify.env.get("DMXTRACT_FIXTURE_LOOKUP_URL");
  if (!configuredUrl) {
    return response(200, { enabled: false, matches: [] });
  }

  let lookupUrl;
  try {
    lookupUrl = new URL(configuredUrl);
    if (!safeProviderUrl(lookupUrl)) throw new Error("unsafe provider URL");
  } catch {
    return response(503, { enabled: false, matches: [] });
  }

  let query;
  try {
    const raw = await request.text();
    if (raw.length > 4096) return response(413, { error: "Request is too large." });
    const parsed = JSON.parse(raw);
    query = {
      manufacturer: cleanText(parsed.manufacturer, 96),
      model: cleanText(parsed.model, 128),
      modeFootprints: cleanFootprints(parsed.modeFootprints),
    };
    if (!query.manufacturer || !query.model) throw new Error("missing identity");
  } catch {
    return response(400, { error: "Pass a manufacturer and model." });
  }

  const token = Netlify.env.get("DMXTRACT_FIXTURE_LOOKUP_TOKEN");
  const headers = {
    Accept: "application/json",
    "Content-Type": "application/json",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  try {
    const upstream = await fetch(lookupUrl, {
      method: "POST",
      headers,
      body: JSON.stringify(query),
      redirect: "error",
      signal: AbortSignal.timeout(5000),
    });
    if (!upstream.ok) throw new Error("lookup unavailable");
    const contentLength = Number(upstream.headers.get("content-length") || 0);
    if (contentLength > 262144) throw new Error("lookup response too large");
    const raw = await upstream.text();
    if (raw.length > 262144) throw new Error("lookup response too large");
    const payload = JSON.parse(raw);
    const matches = Array.isArray(payload.matches)
      ? payload.matches.slice(0, 5).map(cleanMatch).filter(Boolean)
      : [];
    return response(200, { enabled: true, matches });
  } catch {
    // Intentionally omit upstream URL, response bodies, credentials, and query
    // values from logs and client errors.
    return response(503, { enabled: false, matches: [] });
  }
};

function cleanMatch(value) {
  if (!value || typeof value !== "object") return null;
  const manufacturer = cleanText(value.manufacturer, 96);
  const fixture = cleanText(value.fixture, 128);
  const url = cleanLink(value.url);
  if (!manufacturer || !fixture || !url) return null;
  const rating = Number(value.rating);
  return {
    id: cleanText(value.id, 80),
    manufacturer,
    fixture,
    revision: cleanText(value.revision, 96),
    source: value.source === "manufacturer" ? "manufacturer" : "community",
    score: clamp(Number(value.score), 0, 1),
    url,
    rating: Number.isFinite(rating) ? clamp(rating, 0, 5) : null,
    version: cleanText(value.version, 16),
    modeFootprints: cleanFootprints(value.modeFootprints),
  };
}

function cleanText(value, maximum) {
  if (typeof value !== "string") return "";
  return value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, maximum);
}

function cleanFootprints(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(Number).filter((item) => Number.isInteger(item) && item > 0 && item <= 65535))].slice(0, 64);
}

function cleanLink(value) {
  try {
    const url = new URL(value || "https://gdtf-share.com/");
    if (url.protocol !== "https:") return "";
    const allowed = (Netlify.env.get("DMXTRACT_FIXTURE_LINK_HOSTS") || "gdtf-share.com,www.gdtf-share.com")
      .split(",")
      .map((host) => host.trim().toLowerCase())
      .filter(Boolean);
    if (!allowed.includes(url.hostname.toLowerCase())) return "";
    url.username = "";
    url.password = "";
    url.hash = "";
    return url.toString();
  } catch {
    return "";
  }
}

function safeProviderUrl(url) {
  if (url.protocol === "https:") return true;
  return url.protocol === "http:" && ["127.0.0.1", "localhost", "::1"].includes(url.hostname);
}

function clamp(value, minimum, maximum) {
  return Number.isFinite(value) ? Math.min(maximum, Math.max(minimum, value)) : minimum;
}

function response(status, body, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...JSON_HEADERS, ...extraHeaders },
  });
}
