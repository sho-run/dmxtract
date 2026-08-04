# DMXtract

Turn a lighting-fixture manual into an editable OFL or GDTF profile without uploading the manual. DMXtract is an MIT-licensed, beginner-first project by [sho.run](https://sho.run).

Canonical web app: [dmxtract.sho.run](https://dmxtract.sho.run)

[Source code](https://github.com/sho-run/dmxtract) ·
[Privacy](https://dmxtract.sho.run/privacy/)

The normal workflow is deliberately short:

1. Add manual
2. Check what we found
3. Test your light
4. Download profile

The current vertical slice includes local PDF.js/Tesseract extraction, table-region recovery, IndexedDB autosave, an editable canonical fixture model, Rust/WASM validation and exporters, and a guided tester with fixture-address offsets, expected observations, correction/retest editing, and automatic Art-Net node discovery. Its loopback hardware bridge supports Art-Net, sACN, Open DMX/FTDI, and preview output. The bridge also exposes stdio MCP fixture tools and approval-gated hardware tools.

## Repository layout

- `apps/web` — Flutter web app and local extraction workers
- `apps/bridge` — Tauri 2 tray shell
- `crates/dmxtract_core` — canonical model, validation, OFL, and GDTF
- `crates/dmxtract_bridge` — loopback API, transports, safety lease, and MCP
- `schemas` — versioned fixture, lookup, and bridge contracts
- `golden` — synthetic, redistributable format fixtures
- `testcorpus` — local real-world manuals; PDFs are intentionally gitignored
- `third_party` — licenses and OLA bundle records

## Develop

Requirements: Flutter 3.41+, Rust 1.92+, wasm-bindgen CLI 0.2.126, and Chrome or Edge.

```sh
./scripts/build-wasm.sh
cd apps/web
flutter pub get
flutter run -d chrome
```

Run the native bridge with `cargo run -p dmxtract_bridge`. Run the complete checked-in tests with:

```sh
cargo test --workspace
cd apps/web && flutter analyze && flutter test
```

The generated Rust/WASM bundle is checked in so Netlify does not need a Rust
toolchain. `scripts/netlify-build.sh` verifies its source hash and fails rather
than deploying a stale exporter. After changing `dmxtract_core`, run
`./scripts/build-wasm.sh` before committing.

## Privacy and safety

Manuals and photos stay in the browser. The site has no analytics, document-upload endpoint, account requirement, or hosted AI dependency. The bridge listens only on loopback, requires origin-bound pairing, permits one controller lease, starts at zero, locks hazardous ranges, and blackouts when its heartbeat stops.

An optional same-origin fixture lookup can send only manufacturer, model, and
mode footprints to a deployer-controlled API. It is disabled by default. To
enable it on Netlify, set `DMXTRACT_FIXTURE_LOOKUP_URL` and optionally
`DMXTRACT_FIXTURE_LOOKUP_TOKEN` in the host's encrypted environment settings;
never put live values in `.env.example`, Flutter build defines, or source code.
The provider contract is documented in
`schemas/fixture-lookup-v1.openapi.yaml`.

Treat generated profiles as drafts until they are checked on an isolated fixture. See `docs/`, `THIRD_PARTY_NOTICES.md`, and `third_party/` for protocol, validation, and licensing details.

Project-specific code and artwork in this repository were authored for
DMXtract. No source, assets, schemas, credentials, or private fixture data from
other sho.run products are bundled.

Netlify and DNS setup for the canonical `dmxtract.sho.run` origin is recorded
in `docs/netlify-deployment.md`.
