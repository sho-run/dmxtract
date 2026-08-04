#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

paths="$({
  printf '%s\n' Cargo.lock Cargo.toml crates/dmxtract_core/Cargo.toml
  find crates/dmxtract_core/src -type f
} | LC_ALL=C sort)"

if command -v sha256sum >/dev/null 2>&1; then
  while IFS= read -r path; do
    printf '%s\n' "$path"
    sed -n '1,$p' "$path"
  done <<<"$paths" | sha256sum | awk '{print $1}'
else
  while IFS= read -r path; do
    printf '%s\n' "$path"
    sed -n '1,$p' "$path"
  done <<<"$paths" | shasum -a 256 | awk '{print $1}'
fi
