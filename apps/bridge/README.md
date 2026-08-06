# DMXtract Bridge shell

This Tauri 2 tray shell packages `dmxtract_bridge` as a sidecar. It keeps the browser-facing bridge process out of the web application, reports pairing requests in the native tray menu, works alongside the visible loopback Bridge controls, and kills the sidecar on Quit.

This is not the primary way to test a fixture. Install and run the bridge for Art-Net/sACN network output, or to reach a USB-DMX interface from a browser without Web Serial support.

The `dmxtract_bridge` sidecar also exits on its own after 30 minutes with no active output lease, no open WebSocket, and no pairing request awaiting approval or a token claim, so a forgotten tray icon does not linger indefinitely. That idle timeout is configurable (`--idle-timeout <seconds>` or `DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS`, `0` to disable) — see `docs/bridge-api.md`. Quit from the tray menu stops it immediately regardless of the timeout.

Before building, place a target-suffixed bridge binary in `src-tauri/binaries/` as required by Tauri's sidecar convention. Release automation must build that binary from `crates/dmxtract_bridge`, copy it under the name expected by Tauri, and then sign/notarize the complete bundle.

The macOS release pipeline also places the pinned OLA daemon and its plugins beside the sidecar. Windows uses the bridge's native transports.
