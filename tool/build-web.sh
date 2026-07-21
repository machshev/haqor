#!/usr/bin/env bash
# Build the installable PWA, including the Rust WebAssembly module that Rinf
# loads dynamically at runtime. Run inside `nix develop`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/.."

cd "$app"
rinf wasm --release
flutter build web --release "$@"
mkdir -p build/web/pkg
cp web/pkg/hub.js web/pkg/hub_bg.wasm build/web/pkg/

echo "PWA bundle ready in build/web"
