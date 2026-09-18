# Security and privacy

- Manuals are parsed in the browser and are never sent to a hosted application service.
- Fonts, textures, PDF parsing, OCR, language data, and format logic are self-hosted.
- Browser autosave contains the editable fixture project, not the original manual bytes.
- The bridge listens on loopback only and does not expose a LAN service.
- Pairing requires an explicit decision on the visible loopback Bridge-control page. Its approval forms contain a secret that is never returned to the requesting website. Session tokens are origin-bound and die with the bridge process.
- Only one controller lease can produce output.
- Output starts at zero. The watchdog, disconnect paths, explicit Stop action, and lease end black out all tracked universes.
- Hazardous ranges require a distinct unlock. UI labels are not trusted as the only safety boundary.

## Optional fixture-library lookup

The optional lookup sends only the extracted manufacturer, model, and distinct
mode footprints to the same-origin `/api/fixture-matches` endpoint. It never
sends the manual, manual filename, extracted channel table, autosaved project,
browser identifiers, bridge token, DMX network details, or hardware identity.
Lookup runs only when both manufacturer and model were detected in manual text;
identity inferred solely from a filename is never submitted.

The Netlify function is a fixed integration, not an open proxy. A configured
provider URL and bearer token, or GDTF Share username, password, and session
cookie, exist only in the host secret manager and server-side function. It
forwards no browser cookies, IP headers, origin, referrer, or user agent, and it returns a small
allowlisted response that omits provider account names and uploader usernames.
Provider errors are deliberately generic and do not log queries, credentials,
URLs, cookies, or response bodies. With neither provider configuration nor a
complete GDTF Share credential pair, lookup is disabled and returns an empty result.

Self-hosters may configure their own compatible provider using
`DMXTRACT_FIXTURE_LOOKUP_URL`, `DMXTRACT_FIXTURE_LOOKUP_TOKEN`, and an optional
`DMXTRACT_FIXTURE_LINK_HOSTS` allowlist, or connect directly with
`GDTF_SHARE_USERNAME` and `GDTF_SHARE_PASSWORD`. Provider credentials must
never be compiled into Flutter, placed in repository files, or exposed as MCP
tools.

## Optional phone photo hand-off

The QR "Send photos from your phone" affordance lets a phone send manual
photos straight into an open desktop tab, without ever uploading them
anywhere. It is entirely optional and only appears when the desktop can
confirm the signaling relay is configured; offline, or self-hosted without
it, the affordance stays hidden and the file picker and drag-and-drop paths
work exactly as before.

When started, the desktop generates a session id and an AES-GCM key from the
browser's `crypto.getRandomValues` and encodes both only in the QR code's URL
fragment (`/phone/#sessionId.key`). A URL fragment is never sent in an HTTP
request by the browser, so the key never reaches the signaling relay or any
other server. It does briefly sit in the address bar on both devices; the
phone page strips it via `history.replaceState` as soon as it has read the
key, but until then (and, unavoidably, on the desktop for as long as the QR
dialog is open) browser tab/history sync — Chrome Sync, iCloud Tabs, Firefox
Sync — or a screenshot of the address bar can still carry the fragment off
either device. The desktop and, once scanned, the phone use
that key to encrypt their WebRTC offer and answer client-side (AES-GCM via
WebCrypto) before posting either to the `/api/phone-link-signal` Netlify
function. That function stores and forwards ciphertext it cannot read: it
sees a session id, an initialization vector, and encrypted bytes, nothing
else. Reading the answer completes the handshake and deletes the session's
stored state immediately. A session that is never completed — the QR dialog
is closed before a phone scans it, for example — is marked to expire after a
few minutes, but that expiry is enforced lazily: the encrypted offer stays in
Netlify Blobs until something requests that same session id again (or a
future access sweeps it), not on a fixed timer. The relay also enforces a
same-origin check and a per-IP write budget on POST, and rejects malformed,
oversized, or out-of-order requests (an answer with no matching offer, a
second answer for an already-connected session).

Once the encrypted handshake lets the two devices agree on a direct WebRTC
DataChannel, every photo travels peer-to-peer over that channel — the
signaling function is never contacted again for that session, and no photo
bytes are ever uploaded, buffered, or logged server-side. STUN
(`stun:stun.l.google.com:19302`) helps the two devices find each other's
network address; there is no TURN relay, so on some networks (symmetric NAT,
restrictive firewalls) a direct connection cannot form. When that happens,
or the connection drops, the UI says so honestly — photos never left either
device — and suggests the same Wi-Fi network or a manual transfer (AirDrop,
email) instead of retrying silently.

The phone page itself (`/phone/`) is a small static page with its own,
stricter Content-Security-Policy: no WebAssembly, and `connect-src` limited
to this origin's signaling endpoint. CSP source lists do not govern WebRTC
ICE traffic, so the STUN lookup above is not, and cannot be, additionally
gated by `connect-src`; an earlier `stun:stun.l.google.com:19302` entry in
that directive did not parse as a valid CSP source expression and has been
removed as a no-op. It captures photos
through the operating system's own camera and photo-library pickers, not an
in-page camera stream, so it needs no camera permission grant and
`Permissions-Policy: camera=()` stays in effect there as everywhere else.

Received photos are handed to the exact same code path as photos added
through "Add several photos" (`DmxtractState.addPhotos`), so they get the
same deduplication, manual-text extraction, and autosave behavior as any
other photo, regardless of how they arrived.

## Diagnostic-report download

The Check step and the "we could not find a DMX channel table" card both
offer a low-key "Not what the manual says? Download what we read" link. It
builds a `<manufacturer>-<model>.dmxtract-report.json` file entirely
client-side (`lib/src/diagnostic_report.dart`) and hands it to the browser's
own `Blob`/`createObjectURL` download, the same mechanism the OFL/GDTF/project
downloads on the Download step already use — nothing is uploaded or
transmitted by triggering the download itself.

The file contains only what the local parser already produced from the
manual:

- the page-marked text it read (the same `=== DMXTRACT PAGE N ===`-delimited
  text handed to the extraction rules — OCR/PDF text, not an image),
- the canonical fixture JSON built from that text (manufacturer, model,
  channels, modes, confidence scores — the same shape as a `.dmxtract.json`
  project export),
- the source file's name, and
- this bundle's own schema/version identifiers, for anyone triaging reports.

It never contains the original manual PDF or photo bytes, browser storage,
bridge tokens, or anything that did not already pass through the local
extraction pipeline.

Downloading the file does not send it anywhere. Sending it at all is a
separate, manual act: the affordance also links to the deployment's existing
bug-report destination (`DMXTRACT_BUG_REPORT_URL` — a mailto address on a
configured deployment, or the public GitHub issue tracker by default) and
asks the person to attach the file themselves if they choose to report a
problem. No new network path was added for this feature.

## Offline behavior

DMXtract has no offline-caching layer today, and — as of the Flutter version
this project builds with — cannot get one cheaply from Flutter itself. Recent
Flutter releases quietly gutted `flutter build web`'s service-worker
generation: the `offlineFirst` strategy (still the default) now emits the
exact same "unregister any previously installed service worker and reload"
no-op that the `none` strategy does, and the `--pwa-strategy` flag itself is
deprecated (see https://github.com/flutter/flutter/issues/156910). `web/flutter_bootstrap.js`
does not even pass a `serviceWorker` config to the loader, so no service
worker is registered for this app at all. This was verified by inspecting an
actual `flutter build web --release` output's `flutter_service_worker.js` (a
32-line no-op, not the old asset-caching version) and by reading the
generator source shipped with the installed Flutter SDK, not assumed from
older Flutter documentation.

`web/manifest.json` still declares this a `"display": "standalone"` installable
PWA, so browsers may offer to install it — that only affects window chrome,
not offline availability, since installability comes from the manifest alone
and does not imply or require a caching service worker.

In practice:

- Fetching the app for the first time (or after the browser evicts it from
  cache) always needs a network connection — to load `main.dart.js`, the
  WASM core, `vendor/pdfjs`, `vendor/tesseract`, and fonts.
- Once loaded in an open tab, every processing step — manual/photo OCR, PDF
  text extraction, fixture-profile building, channel editing, DMX test
  guidance, OFL/GDTF export — runs entirely client-side and makes no network
  call, so an already-open tab keeps working with no network (aside from the
  two optional features below, which already degrade gracefully).
- A page *reload* while offline is not guaranteed to work. It depends
  entirely on whichever ordinary HTTP cache entries the browser still holds
  for the self-hosted vendor assets, WASM bundle, and fonts — none of which
  get an explicit `Cache-Control` header today (`web/_headers` and
  `netlify.toml` set only security headers), so caching follows Netlify's and
  the browser's own defaults. Setting a long-lived, immutable `Cache-Control`
  on these files was considered and deliberately not done: none of their
  filenames are content-hashed or otherwise versioned per release, so an
  aggressive cache would risk serving a returning visitor stale JS against a
  newer WASM ABI (or vice versa) after the next deploy — a worse failure mode
  than the offline gap it would partially close.
- A real offline-first guarantee would need either Flutter's now-defunct
  built-in strategy (gone) or a hand-rolled service worker with its own
  cache-busting and versioning. Both are out of scope here as the "heavy
  custom service worker" this audit was explicitly asked to avoid.

Two features call out to the network, and both already fail soft with no
code change needed here:

- Optional fixture-library lookup (`GdtfLookupClient.search`): a 12 s timeout
  wraps the whole request in `try`/`catch`; any failure (offline, DNS,
  non-200, wrong content type) returns a disabled, empty result, silently
  skipping the "matches found" panel.
- Phone photo hand-off availability (`DmxtractState._checkPhoneLinkAvailability`):
  a 6 s timeout and `try`/`catch` around the same-origin
  `/api/phone-link-signal` probe leaves the QR affordance hidden on any
  failure — see "Optional phone photo hand-off" above.
- The Bridge (loopback helper app) connectivity probe (`BridgeClient.isAvailable`)
  has the same timeout/try-catch shape, showing "Bridge not running" instead
  of hanging.

The manual-console-test flow added to the Test step introduces no new network
calls or asset types — only the same `Blob`/`createObjectURL` download the
Download step already performs under this same Content-Security-Policy — so
no CSP change was needed for it, and it sends zero DMX from the browser by
design (no transport is ever attached for that option).

## MCP privacy boundary

MCP receives only the canonical fixture JSON explicitly supplied by its caller.
It has no fixture-library lookup tool and cannot read or return website provider
configuration, GDTF Share credentials, browser storage, manuals, pairing tokens,
or environment variables. Hardware tools remain absent until native approval.
The terminal pairing line contains the compatibility code only; the requesting
web origin and code are excluded from structured logs. The origin is shown on
the local Bridge-control page so the user can see exactly who is asking.

DMX lighting can still create hazardous motion, flashes, lamp strikes, or maintenance actions. Users should keep the fixture isolated from people and rigging while creating a profile.
