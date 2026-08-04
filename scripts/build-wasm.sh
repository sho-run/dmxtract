#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

cargo build --release --target wasm32-unknown-unknown -p dmxtract_core
mkdir -p apps/web/web/wasm
wasm_bindgen_bin="${WASM_BINDGEN_BIN:-$HOME/.cargo/bin/wasm-bindgen}"
"$wasm_bindgen_bin" \
  --target web \
  --out-dir apps/web/web/wasm \
  --out-name dmxtract_core \
  target/wasm32-unknown-unknown/release/dmxtract_core.wasm

"$repository_root/scripts/wasm-source-hash.sh" \
  > apps/web/web/wasm/source.sha256
