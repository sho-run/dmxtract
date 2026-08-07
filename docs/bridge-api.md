# Bridge and MCP

The bridge is a small native helper, not the primary way to test a fixture. It exists to reach an Art-Net or sACN network node, and as the way to reach a USB-DMX interface in a browser without Web Serial support.

The HTTP/WebSocket contract is defined in [`schemas/bridge-v1.openapi.yaml`](../schemas/bridge-v1.openapi.yaml). The default endpoint is `http://127.0.0.1:46321`.

The ordinary flow is:

1. Read `/v1/health` and `/v1/outputs`.
2. Open the visible Bridge controls at `http://127.0.0.1:46321/`.
3. Request pairing with the browser's exact origin.
4. The user confirms that origin in Bridge controls; the browser polls the request until it receives an origin-bound token. The six-digit terminal confirmation remains a compatibility fallback.
5. Begin a test with an output configuration. The first transmitted frame is zero.
6. Send a heartbeat every 500 ms and channel changes through HTTP or WebSocket.
7. Black out, then end the lease. The local Bridge controls can also force a blackout without relying on the requesting site.

The watchdog expires a lease after 1.5 seconds without activity. WebSocket disconnect, explicit end, and process cleanup also black out. Strobe, lamp, reset, and maintenance values must set `risky: true`; the bridge rejects those frames until the user explicitly unlocks them.

## Pairing lifetime

A pairing request left unanswered for 10 minutes stops being actionable and must be requested again. Once the user approves it in the local Bridge controls, the browser gets a fresh 10-minute window to poll `/v1/pair/{requestId}/status` and claim the bearer token — that window is independent of how long the original request sat waiting for a click.

Polling an expired request returns `{"status": "expired"}` (HTTP 200), not an error, so a client can tell "ask again" apart from "that request never existed" or "denied."

`/v1/pair/request` is rate-limited per browser origin: a token bucket allows bursts up to 5 requests, refilling at 5 per minute. Once exhausted, the endpoint returns `429 Too Many Requests` with a clear message. This bounds how many native approval prompts a hostile local page can trigger.

## Idle self-exit

The bridge process exits on its own after a configurable idle period with no active output lease, no open WebSocket, and no pairing request awaiting approval or a token claim — 30 minutes by default. This keeps a forgotten tray icon or terminal session from lingering indefinitely. Configure it with the `--idle-timeout <seconds>` CLI flag or the `DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS` environment variable (the flag wins if both are set); `0` disables it. Any lease activity, live WebSocket traffic, or pairing request resets the idle clock.

Run the MCP server with `dmxtract_bridge --mcp`. Fixture validation, exports, bridge status, and output discovery are always available. Hardware tools are omitted from discovery until the native approval flow authorizes that MCP process; `DMXTRACT_MCP_HARDWARE=1` is the development-only approval override. Approved tools support preview, Art-Net, sACN, and Open DMX, start at zero, reject risky frames unless explicitly unlocked at test start, and black out on end or process exit. MCP accepts canonical DMXtract fixture JSON rather than raw manuals. The `--mcp` process is stdio-driven and is not subject to the idle self-exit above; it exits when its stdin closes.

MCP intentionally has no fixture-library lookup or configuration-inspection
tool. Website lookup credentials, provider cookies, browser storage, and process
environment variables are outside its contract and must never appear in tool
results or structured logs.

## What the bridge leaves on your machine and how to remove it

The bridge writes no configuration file, database, or cache to disk on its own — it holds pairing, lease, and rate-limit state only in memory for the life of the process, and that state (including all bearer tokens) is gone the moment it exits.

What's actually on disk is the installed application itself:

- **macOS (tray shell):** the `.app` bundle you installed (typically under `/Applications`), which contains the `dmxtract_bridge` sidecar binary and the bundled OLA daemon/plugins it uses for some USB-DMX transports.
- **Windows (tray shell):** the installed program directory, containing the `dmxtract_bridge.exe` sidecar; it uses the bridge's native transports rather than an external daemon.
- **Running the bridge from source** (`cargo run -p dmxtract_bridge`) leaves only the compiled binary in that checkout's `target/` directory.

If you turned on the tray menu's "Start at login" toggle (off by default), the OS also has a login item pointing at the installed app: a Launch Agent plist under `~/Library/LaunchAgents` on macOS, or a Run-key value in the current user's registry on Windows. Turning the toggle back off before uninstalling always removes it cleanly. If you uninstall first, macOS never cleans this up on its own — remove it from System Settings → General → Login Items. Whether Windows cleans it up depends on which installer you used, so check Settings → Apps → Startup and remove it there if it's still listed.

The tray shell also registers itself as the handler for `dmxtract://` links (used by the website's "Launch bridge" button) — an Info.plist entry baked into the `.app` on macOS, and a per-user registry key the Windows installer writes on install and removes on uninstall. Neither needs manual cleanup.

To fully remove the bridge: quit it from the tray menu (or stop the process if run from a terminal), turn off "Start at login" if it's on, then uninstall the application the normal way for your OS (drag the `.app` to Trash on macOS, or use "Apps & Features" / the uninstaller on Windows). No account, cloud service, or system-level daemon is registered — the login item is the one thing worth turning off before you uninstall, since cleanup after the fact isn't guaranteed on every platform (see above).
