# Bridge and MCP

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

Run the MCP server with `dmxtract_bridge --mcp`. Fixture validation, exports, bridge status, and output discovery are always available. Hardware tools are omitted from discovery until the native approval flow authorizes that MCP process; `DMXTRACT_MCP_HARDWARE=1` is the development-only approval override. Approved tools support preview, Art-Net, sACN, and Open DMX, start at zero, reject risky frames unless explicitly unlocked at test start, and black out on end or process exit. MCP accepts canonical DMXtract fixture JSON rather than raw manuals.

MCP intentionally has no fixture-library lookup or configuration-inspection
tool. Website lookup credentials, provider cookies, browser storage, and process
environment variables are outside its contract and must never appear in tool
results or structured logs.
