import assert from "node:assert/strict";
import test from "node:test";

import handler from "../functions/fixture-matches.mjs";

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

test("GDTF Share login and list lookup keep credentials and cookies server-side", async () => {
  const values = new Map([
    ["GDTF_SHARE_USERNAME", "server-user"],
    ["GDTF_SHARE_PASSWORD", "server-password"],
  ]);
  globalThis.Netlify = { env: { get: (name) => values.get(name) } };
  const requests = [];
  globalThis.fetch = async (url, options) => {
    requests.push({ url: String(url), options });
    if (String(url).endsWith("/login.php")) {
      return new Response(JSON.stringify({ result: true }), {
        status: 200,
        headers: { "content-type": "application/json", "set-cookie": "PHPSESSID=session-secret; Path=/; HttpOnly; Secure" },
      });
    }
    return new Response(JSON.stringify({
      result: true,
      list: [
        {
          rid: 42,
          manufacturer: "Chauvet DJ",
          fixture: "COLORpalette",
          revision: "Release",
          uploader: "Manuf.",
          rating: "4.8",
          version: "1.2",
          creator: "private-uploader",
          modes: [{ name: "27-channel", dmxfootprint: 27 }, { nested: { dmxfootprint: 15 } }],
        },
        { rid: 99, manufacturer: "Unrelated", fixture: "Other Light", modes: [] },
      ],
    }), { status: 200, headers: { "content-type": "application/json" } });
  };

  const result = await handler(new Request("https://dmxtract.test/api/fixture-matches", {
    method: "POST",
    headers: { Cookie: "browser-private=1", "X-Forwarded-For": "192.0.2.1" },
    body: JSON.stringify({
      manufacturer: "Chauvet DJ",
      model: "COLORpalette",
      modeFootprints: [27],
      manualName: "private-manual.pdf",
    }),
  }));

  assert.equal(result.status, 200);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].url, "https://gdtf-share.com/apis/public/login.php");
  assert.deepEqual(JSON.parse(requests[0].options.body), {
    user: "server-user",
    password: "server-password",
  });
  assert.equal(requests[0].options.headers.Cookie, undefined);
  assert.equal(requests[1].url, "https://gdtf-share.com/apis/public/getList.php");
  assert.equal(requests[1].options.headers.Cookie, "PHPSESSID=session-secret");

  const body = await result.json();
  assert.equal(body.enabled, true);
  assert.equal(body.matches.length, 1);
  assert.equal(body.matches[0].id, "42");
  assert.equal(body.matches[0].source, "manufacturer");
  assert.deepEqual(body.matches[0].modeFootprints, [27, 15]);
  assert.equal(body.matches[0].url, "https://gdtf-share.com/share.php");
  assert.equal(JSON.stringify(body).includes("server-user"), false);
  assert.equal(JSON.stringify(body).includes("server-password"), false);
  assert.equal(JSON.stringify(body).includes("session-secret"), false);
  assert.equal(JSON.stringify(body).includes("private-uploader"), false);
});
