#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
toolchain_root="$repository_root/.netlify-toolchain"
flutter_version="3.44.8"
flutter_archive="$toolchain_root/flutter.tar.xz"
flutter_sha256="672089e001571a9fbb209a495c583580c0c6c73ef98999264ba07fa93ace332d"
wasm_hash_file="$repository_root/apps/web/web/wasm/source.sha256"

if [[ ! -s "$repository_root/apps/web/web/wasm/dmxtract_core_bg.wasm" || ! -s "$wasm_hash_file" ]]; then
  echo "The checked-in Rust/WASM bundle is missing. Run ./scripts/build-wasm.sh and commit its output." >&2
  exit 1
fi

expected_wasm_hash="$(tr -d '[:space:]' < "$wasm_hash_file")"
actual_wasm_hash="$("$repository_root/scripts/wasm-source-hash.sh")"
if [[ "$expected_wasm_hash" != "$actual_wasm_hash" ]]; then
  echo "The checked-in Rust/WASM bundle is stale. Run ./scripts/build-wasm.sh and commit its output." >&2
  exit 1
fi

mkdir -p "$toolchain_root"
if [[ ! -x "$toolchain_root/flutter/bin/flutter" ]]; then
  curl --fail --location --silent --show-error \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz" \
    --output "$flutter_archive"
  printf '%s  %s\n' "$flutter_sha256" "$flutter_archive" | sha256sum --check -
  tar --extract --xz --file "$flutter_archive" --directory "$toolchain_root"
fi

export PATH="$toolchain_root/flutter/bin:$PATH"
flutter config --no-analytics
cd "$repository_root/apps/web"
flutter pub get
flutter build web --release --base-href / \
  --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/ \
  --dart-define=DMXTRACT_CUSTOM_THEME="${DMXTRACT_CUSTOM_THEME:-false}"

# Publish the canonical fixture schema at the stable URL embedded in projects.
mkdir -p build/web/schemas
cp "$repository_root/schemas/fixture-v1.json" build/web/schemas/fixture-v1.json
# Flutter omits underscore-prefixed web files, so copy Netlify's static deploy
# directives explicitly for manual drag-and-drop releases.
cp web/_headers build/web/_headers
cp web/_redirects build/web/_redirects
node "$repository_root/scripts/check-static-links.mjs" build/web
node "$repository_root/scripts/check-netlify-release.mjs" build/web
