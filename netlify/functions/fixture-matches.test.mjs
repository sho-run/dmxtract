import assert from "node:assert/strict";
import test from "node:test";

import handler from "./fixture-matches.mjs";

test("disabled lookup returns no matches without contacting a provider", async () => {
  globalThis.Netlify = { env: { get: () => undefined } };
  globalThis.fetch = () => {
    throw new Error("fetch must not run");
  };
  const result = await handler(new Request("https://dmxtract.test/api/fixture-matches", {
    method: "POST",
    body: JSON.stringify({ manufacturer: "Chauvet DJ", model: "COLORpalette", modeFootprints: [27] }),
  }));
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { enabled: false, matches: [] });
});

test("proxy forwards a minimal query and strips provider-only data", async () => {
  const values = new Map([
    ["DMXTRACT_FIXTURE_LOOKUP_URL", "https://fixture-provider.example/v1/matches"],
    ["DMXTRACT_FIXTURE_LOOKUP_TOKEN", "server-secret"],
  ]);
  globalThis.Netlify = { env: { get: (name) => values.get(name) } };
  let upstreamRequest;
  globalThis.fetch = async (url, options) => {
    upstreamRequest = { url: String(url), options };
    return new Response(JSON.stringify({
      matches: [{
        id: "42",
        manufacturer: "Chauvet DJ",
        fixture: "COLORpalette",
        revision: "Release",
        source: "manufacturer",
        score: 0.97,
        url: "https://gdtf-share.com/share.php",
        rating: 4.8,
        modeFootprints: [27, 15, 9, 6, 3],
        creator: "private-user-name",
        providerToken: "must-not-escape",
      }],
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  const result = await handler(new Request("https://dmxtract.test/api/fixture-matches", {
    method: "POST",
    headers: { Cookie: "browser-private=1", "X-Forwarded-For": "192.0.2.1" },
    body: JSON.stringify({
      manufacturer: "Chauvet DJ",
      model: "COLORpalette",
      modeFootprints: [27, 15, 9, 6, 3],
      manualName: "private-manual.pdf",
    }),
  }));

  assert.equal(upstreamRequest.url, "https://fixture-provider.example/v1/matches");
  assert.equal(upstreamRequest.options.headers.Authorization, "Bearer server-secret");
  assert.equal(upstreamRequest.options.headers.Cookie, undefined);
  assert.equal(upstreamRequest.options.headers["X-Forwarded-For"], undefined);
  assert.deepEqual(JSON.parse(upstreamRequest.options.body), {
    manufacturer: "Chauvet DJ",
    model: "COLORpalette",
    modeFootprints: [27, 15, 9, 6, 3],
  });

  const body = await result.json();
  assert.equal(body.enabled, true);
  assert.equal(body.matches.length, 1);
  assert.equal(body.matches[0].creator, undefined);
  assert.equal(body.matches[0].providerToken, undefined);
  assert.equal(JSON.stringify(body).includes("server-secret"), false);
  assert.equal(JSON.stringify(body).includes("private-user-name"), false);
});
