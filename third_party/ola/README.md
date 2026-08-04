# Open Lighting Architecture bundle record

DMXtract's macOS release is designed to bundle a separately built OLA daemon. The current acceptance candidate is pinned to upstream commit `99b26c65d45e807032c1337ca7ebf1ac51ff3995` (recorded 2026-08-03). OLA is not embedded in this source snapshot yet.

Before a public binary release, record the exact upstream Git commit, build command, enabled plugins, binary hashes, patches, and corresponding-source archive here. Ship OLA's license notices and provide the corresponding source alongside each signed build. The Windows bridge uses DMXtract's native Art-Net, sACN, and Open DMX transports and does not require OLA.

The release gate includes daemon startup/shutdown, loopback binding, plugin discovery, crash cleanup, and license/source-offer checks.
