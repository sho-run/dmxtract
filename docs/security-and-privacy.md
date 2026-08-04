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

## MCP privacy boundary

MCP receives only the canonical fixture JSON explicitly supplied by its caller.
It has no fixture-library lookup tool and cannot read or return website provider
configuration, GDTF Share credentials, browser storage, manuals, pairing tokens,
or environment variables. Hardware tools remain absent until native approval.
The terminal pairing line contains the compatibility code only; the requesting
web origin and code are excluded from structured logs. The origin is shown on
the local Bridge-control page so the user can see exactly who is asking.

DMX lighting can still create hazardous motion, flashes, lamp strikes, or maintenance actions. Users should keep the fixture isolated from people and rigging while creating a profile.
