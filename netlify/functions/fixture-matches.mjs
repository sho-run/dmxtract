const JSON_HEADERS = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "private, no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

const GDTF_LOGIN_URL = "https://gdtf-share.com/apis/public/login.php";
const GDTF_LIST_URL = "https://gdtf-share.com/apis/public/getList.php";
const GDTF_SHARE_URL = "https://gdtf-share.com/share.php";
const GDTF_LIST_TTL_MS = 10 * 60 * 1000;
const MAX_PROVIDER_BYTES = 32 * 1024 * 1024;

let gdtfListCache = { expiresAt: 0, list: null, pending: null };

export default async (request) => {
  if (request.method !== "POST") {
    return response(405, { error: "Method not allowed." }, { Allow: "POST" });
  }

  const configuredUrl = Netlify.env.get("DMXTRACT_FIXTURE_LOOKUP_URL");
  const gdtfUsername = Netlify.env.get("GDTF_SHARE_USERNAME");
  const gdtfPassword = Netlify.env.get("GDTF_SHARE_PASSWORD");
  const hasGdtfCredentials = Boolean(gdtfUsername && gdtfPassword);
  if (!configuredUrl && !hasGdtfCredentials) {
    return response(200, { enabled: false, matches: [] });
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

  try {
    const matches = configuredUrl
      ? await lookupConfiguredProvider(configuredUrl, query)
      : await lookupGdtfShare(query, gdtfUsername, gdtfPassword);
    return response(200, { enabled: true, matches });
  } catch {
    // Intentionally omit upstream URLs, response bodies, credentials, session
    // cookies, and query values from logs and client errors.
    return response(503, { enabled: false, matches: [] });
  }
};

async function lookupConfiguredProvider(configuredUrl, query) {
  const lookupUrl = new URL(configuredUrl);
  if (!safeProviderUrl(lookupUrl)) throw new Error("unsafe provider URL");

  const token = Netlify.env.get("DMXTRACT_FIXTURE_LOOKUP_TOKEN");
  const headers = {
    Accept: "application/json",
    "Content-Type": "application/json",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const upstream = await fetch(lookupUrl, {
    method: "POST",
    headers,
    body: JSON.stringify(query),
    redirect: "error",
    signal: AbortSignal.timeout(5000),
  });
  const payload = await readJson(upstream, 262144);
  return Array.isArray(payload.matches)
    ? payload.matches.slice(0, 5).map(cleanMatch).filter(Boolean)
    : [];
}

async function lookupGdtfShare(query, username, password) {
  const list = await getGdtfList(username, password);
  return list
    .map((revision) => gdtfMatch(revision, query))
    .filter(Boolean)
    .sort((left, right) => right.score - left.score || (right.rating || 0) - (left.rating || 0))
    .slice(0, 5)
    .map(cleanMatch)
    .filter(Boolean);
}

async function getGdtfList(username, password) {
  const now = Date.now();
  if (gdtfListCache.list && gdtfListCache.expiresAt > now) return gdtfListCache.list;
  if (gdtfListCache.pending) return gdtfListCache.pending;

  gdtfListCache.pending = fetchGdtfList(username, password)
    .then((list) => {
      gdtfListCache = { expiresAt: Date.now() + GDTF_LIST_TTL_MS, list, pending: null };
      return list;
    })
    .catch((error) => {
      gdtfListCache.pending = null;
      throw error;
    });
  return gdtfListCache.pending;
}

async function fetchGdtfList(username, password) {
  const login = await fetch(GDTF_LOGIN_URL, {
    method: "POST",
    headers: { Accept: "application/json", "Content-Type": "application/json" },
    body: JSON.stringify({ user: username, password }),
    redirect: "error",
    signal: AbortSignal.timeout(5000),
  });
  const loginPayload = await readJson(login, 8192);
  if (loginPayload.result !== true) throw new Error("GDTF Share login failed");
  const cookie = sessionCookie(login.headers);
  if (!cookie) throw new Error("GDTF Share session missing");

  const listing = await fetch(GDTF_LIST_URL, {
    method: "GET",
    headers: { Accept: "application/json", Cookie: cookie },
    redirect: "error",
    signal: AbortSignal.timeout(10000),
  });
  const listPayload = await readJson(listing, MAX_PROVIDER_BYTES);
  if (listPayload.result !== true || !Array.isArray(listPayload.list)) {
    throw new Error("GDTF Share list unavailable");
  }
  return listPayload.list.slice(0, 200000);
}

async function readJson(upstream, maximumBytes) {
  if (!upstream.ok) throw new Error("lookup unavailable");
  const contentLength = Number(upstream.headers.get("content-length") || 0);
  if (contentLength > maximumBytes) throw new Error("lookup response too large");
  const raw = await upstream.text();
  if (Buffer.byteLength(raw, "utf8") > maximumBytes) {
    throw new Error("lookup response too large");
  }
  return JSON.parse(raw);
}

function sessionCookie(headers) {
  const values = typeof headers.getSetCookie === "function"
    ? headers.getSetCookie()
    : [headers.get("set-cookie")];
  return values
    .filter(Boolean)
    .map((value) => value.split(";", 1)[0].trim())
    .filter((value) => /^[!#$%&'*+.^_`|~0-9A-Za-z-]+=[^;\r\n]+$/.test(value))
    .join("; ");
}

function gdtfMatch(revision, query) {
  if (!revision || typeof revision !== "object") return null;
  const manufacturer = cleanText(revision.manufacturer, 96);
  const fixture = cleanText(revision.fixture, 128);
  if (!manufacturer || !fixture) return null;

  const manufacturerScore = textScore(manufacturer, query.manufacturer);
  const fixtureScore = textScore(fixture, query.model);
  if (manufacturerScore < 0.55 || fixtureScore < 0.55) return null;
  const modeFootprints = extractModeFootprints(revision.modes);
  const footprintScore = query.modeFootprints.length === 0
    ? 0.5
    : query.modeFootprints.some((value) => modeFootprints.includes(value)) ? 1 : 0;
  const score = 0.35 * manufacturerScore + 0.6 * fixtureScore + 0.05 * footprintScore;
  if (score < 0.72) return null;

  return {
    id: String(revision.rid || revision.uuid || ""),
    manufacturer,
    fixture,
    revision: cleanText(revision.revision, 96),
    source: revision.uploader === "Manuf." ? "manufacturer" : "community",
    score,
    url: GDTF_SHARE_URL,
    rating: revision.rating,
    version: cleanText(revision.version, 16),
    modeFootprints,
  };
}

function textScore(left, right) {
  const a = normalizeName(left);
  const b = normalizeName(right);
  if (!a || !b) return 0;
  if (a === b) return 1;
  if ((a.length >= 4 && b.includes(a)) || (b.length >= 4 && a.includes(b))) return 0.88;
  const aTokens = new Set(a.split(" "));
  const bTokens = new Set(b.split(" "));
  const shared = [...aTokens].filter((token) => bTokens.has(token)).length;
  return shared / new Set([...aTokens, ...bTokens]).size;
}

function normalizeName(value) {
  return cleanText(value, 256)
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function extractModeFootprints(value) {
  const found = [];
  const visit = (item, depth = 0) => {
    if (depth > 5 || item == null || found.length >= 64) return;
    if (Array.isArray(item)) {
      for (const child of item) visit(child, depth + 1);
      return;
    }
    if (typeof item !== "object") return;
    for (const [key, child] of Object.entries(item)) {
      if (key.toLowerCase() === "dmxfootprint") found.push(child);
      else visit(child, depth + 1);
    }
  };
  visit(value);
  return cleanFootprints(found);
}

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
