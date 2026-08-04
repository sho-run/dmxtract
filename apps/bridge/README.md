# DMXtract Bridge shell

This Tauri 2 tray shell packages `dmxtract_bridge` as a sidecar. It keeps the browser-facing bridge process out of the web application, reports pairing requests in the native tray menu, works alongside the visible loopback Bridge controls, and kills the sidecar on Quit.

Before building, place a target-suffixed bridge binary in `src-tauri/binaries/` as required by Tauri's sidecar convention. Release automation must build that binary from `crates/dmxtract_bridge`, copy it under the name expected by Tauri, and then sign/notarize the complete bundle.

The macOS release pipeline also places the pinned OLA daemon and its plugins beside the sidecar. Windows uses the bridge's native transports.
