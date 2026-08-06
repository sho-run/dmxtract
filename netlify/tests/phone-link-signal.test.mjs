import assert from "node:assert/strict";
import test from "node:test";

import { handle } from "../functions/phone-link-signal.mjs";

const SESSION = "session1234567890AB";
const ENDPOINT = "https://dmxtract.test/api/phone-link-signal";

function fakeStore(seed = {}) {
  const map = new Map(Object.entries(seed));
  return {
    async getJSON(key) {
      return map.has(key) ? map.get(key) : null;
    },
    async setJSON(key, value) {
      map.set(key, value);
    },
    async deleteKey(key) {
      map.delete(key);
    },
    has: (key) => map.has(key),
  };
}

function post(body) {
  return new Request(ENDPOINT, { method: "POST", body: JSON.stringify(body) });
}

function get(query) {
  return new Request(`${ENDPOINT}${query ? `?${query}` : ""}`);
}

function postFrom(body, headers) {
  return new Request(ENDPOINT, { method: "POST", body: JSON.stringify(body), headers });
}

test("probe reports available without creating any session state", async () => {
  const store = fakeStore();
  const result = await handle(get(), store);
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { available: true });
  assert.equal(store.has("__phone_link_probe__"), false);
});

test("probe reports unavailable when the relay has no working store", async () => {
  const result = await handle(get(), null);
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { available: false });
});

test("offer then answer relay only ciphertext, and reading the answer deletes the session", async () => {
  const store = fakeStore();

  const postOffer = await handle(
    post({ sessionId: SESSION, slot: "offer", iv: "aGVsbG8", ciphertext: "d29ybGQtY2lwaGVy" }),
    store,
  );
  assert.equal(postOffer.status, 200);

  const getOffer = await handle(get(`sessionId=${SESSION}&slot=offer`), store);
  assert.deepEqual(await getOffer.json(), {
    ready: true,
    iv: "aGVsbG8",
    ciphertext: "d29ybGQtY2lwaGVy",
  });

  const notYetAnswer = await handle(get(`sessionId=${SESSION}&slot=answer`), store);
  assert.deepEqual(await notYetAnswer.json(), { ready: false });

  const postAnswer = await handle(
    post({ sessionId: SESSION, slot: "answer", iv: "YW5zdw", ciphertext: "cmVwbHktY2lwaGVy" }),
    store,
  );
  assert.equal(postAnswer.status, 200);

  const getAnswer = await handle(get(`sessionId=${SESSION}&slot=answer`), store);
  assert.deepEqual(await getAnswer.json(), {
    ready: true,
    iv: "YW5zdw",
    ciphertext: "cmVwbHktY2lwaGVy",
  });

  // The handshake is complete once the offering side reads the answer; the
  // relay must not keep the ciphertext (or anything else) around after that.
  assert.equal(store.has(SESSION), false);
  const readAgain = await handle(get(`sessionId=${SESSION}&slot=answer`), store);
  assert.deepEqual(await readAgain.json(), { ready: false });
});

test("an answer cannot be posted before an offer exists", async () => {
  const store = fakeStore();
  const result = await handle(
    post({ sessionId: SESSION, slot: "answer", iv: "aa", ciphertext: "bb" }),
    store,
  );
  assert.equal(result.status, 404);
});

test("a session cannot be answered twice", async () => {
  const store = fakeStore();
  await handle(post({ sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "bb" }), store);
  await handle(post({ sessionId: SESSION, slot: "answer", iv: "cc", ciphertext: "dd" }), store);
  const second = await handle(
    post({ sessionId: SESSION, slot: "answer", iv: "ee", ciphertext: "ff" }),
    store,
  );
  assert.equal(second.status, 409);
});

test("an offer cannot overwrite a session that already has an answer", async () => {
  const store = fakeStore();
  await handle(post({ sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "bb" }), store);
  await handle(post({ sessionId: SESSION, slot: "answer", iv: "cc", ciphertext: "dd" }), store);
  const result = await handle(
    post({ sessionId: SESSION, slot: "offer", iv: "ee", ciphertext: "ff" }),
    store,
  );
  assert.equal(result.status, 409);
});

test("a retried offer before any answer overwrites the pending offer", async () => {
  const store = fakeStore();
  await handle(post({ sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "bb" }), store);
  const retry = await handle(
    post({ sessionId: SESSION, slot: "offer", iv: "cc", ciphertext: "dd" }),
    store,
  );
  assert.equal(retry.status, 200);
  const getOffer = await handle(get(`sessionId=${SESSION}&slot=offer`), store);
  assert.deepEqual(await getOffer.json(), { ready: true, iv: "cc", ciphertext: "dd" });
});

test("expired sessions are rejected and swept from the store", async () => {
  const store = fakeStore({
    [SESSION]: { createdAt: 0, expiresAt: 1, offer: { iv: "a", ciphertext: "b" }, answer: null },
  });
  const result = await handle(get(`sessionId=${SESSION}&slot=offer`), store);
  assert.deepEqual(await result.json(), { ready: false });
  assert.equal(store.has(SESSION), false);
});

test("rejects a malformed session id or slot", async () => {
  const store = fakeStore();
  const badSession = await handle(get("sessionId=not valid!&slot=offer"), store);
  assert.equal(badSession.status, 400);
  const badSlot = await handle(get(`sessionId=${SESSION}&slot=nope`), store);
  assert.equal(badSlot.status, 400);
});

test("rejects non-base64url iv or ciphertext", async () => {
  const store = fakeStore();
  const result = await handle(
    post({ sessionId: SESSION, slot: "offer", iv: "not base64!", ciphertext: "bb" }),
    store,
  );
  assert.equal(result.status, 400);
});

test("rejects oversized payloads", async () => {
  const store = fakeStore();
  const result = await handle(
    post({ sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "b".repeat(20000) }),
    store,
  );
  assert.equal(result.status, 413);
});

test("returns 503 for reads and writes when the relay has no store", async () => {
  const getResult = await handle(get(`sessionId=${SESSION}&slot=offer`), null);
  assert.equal(getResult.status, 503);
  const postResult = await handle(
    post({ sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "bb" }),
    null,
  );
  assert.equal(postResult.status, 503);
});

test("rejects a POST whose Origin does not match the request Host", async () => {
  const store = fakeStore();
  const result = await handle(
    postFrom(
      { sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "bb" },
      { Origin: "https://evil.example", Host: "dmxtract.test" },
    ),
    store,
  );
  assert.equal(result.status, 403);
});

test("allows a POST whose Origin matches the request Host", async () => {
  const store = fakeStore();
  const result = await handle(
    postFrom(
      { sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: "bb" },
      { Origin: "https://dmxtract.test", Host: "dmxtract.test" },
    ),
    store,
  );
  assert.equal(result.status, 200);
});

test("rejects a body whose UTF-8 byte length exceeds the limit even though its UTF-16 string length does not", async () => {
  const store = fakeStore();
  // Each astral-plane character is 2 UTF-16 code units but 4 UTF-8 bytes, so
  // this string's UTF-16 .length stays under the 16 KiB char-length check
  // yet it decodes to over 16 KiB of UTF-8 — this must still be rejected.
  const oversizedCiphertext = "\u{1F600}".repeat(4200);
  const raw = JSON.stringify({ sessionId: SESSION, slot: "offer", iv: "aa", ciphertext: oversizedCiphertext });
  assert.ok(raw.length <= 16 * 1024, "test fixture should stay under the char-length bound");
  const result = await handle(new Request(ENDPOINT, { method: "POST", body: raw }), store);
  assert.equal(result.status, 413);
});

test("caps writes per IP within the rate-limit window", async () => {
  const store = fakeStore();
  const headers = { "x-nf-client-connection-ip": "203.0.113.7" };
  for (let i = 0; i < 20; i += 1) {
    const result = await handle(
      postFrom({ sessionId: `${SESSION}${i}`, slot: "offer", iv: "aa", ciphertext: "bb" }, headers),
      store,
    );
    assert.equal(result.status, 200, `write ${i} should be accepted`);
  }
  const blocked = await handle(
    postFrom({ sessionId: `${SESSION}X`, slot: "offer", iv: "aa", ciphertext: "bb" }, headers),
    store,
  );
  assert.equal(blocked.status, 429);
});

test("rate limit is scoped per IP, not global", async () => {
  const store = fakeStore();
  for (let i = 0; i < 20; i += 1) {
    await handle(
      postFrom(
        { sessionId: `${SESSION}${i}`, slot: "offer", iv: "aa", ciphertext: "bb" },
        { "x-nf-client-connection-ip": "203.0.113.7" },
      ),
      store,
    );
  }
  const otherIp = await handle(
    postFrom(
      { sessionId: `${SESSION}Y`, slot: "offer", iv: "aa", ciphertext: "bb" },
      { "x-nf-client-connection-ip": "198.51.100.9" },
    ),
    store,
  );
  assert.equal(otherIp.status, 200);
});

test("only GET and POST are allowed", async () => {
  const store = fakeStore();
  const result = await handle(new Request(ENDPOINT, { method: "DELETE" }), store);
  assert.equal(result.status, 405);
  assert.equal(result.headers.get("Allow"), "GET, POST");
});
