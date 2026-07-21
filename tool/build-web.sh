#!/usr/bin/env bash
# Build the installable offline PWA. Run inside `nix develop`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/.."

cd "$app"
if [[ -z "${WASM_CC:-}" ]]; then
  echo "WASM_CC is not set; run this from nix develop." >&2
  exit 1
fi

# Rinf's threaded wasm command omits __heap_base, which wasm-bindgen needs
# while preparing the module. Build the same hub with that one additional
# export, then run wasm-bindgen exactly as Rinf does.
export CC_wasm32_unknown_unknown="$WASM_CC"
export CFLAGS_wasm32_unknown_unknown='--target=wasm32-unknown-unknown -matomics -mbulk-memory'
export RUSTFLAGS='-C target-feature=+atomics,+bulk-memory,+mutable-globals -C link-arg=--shared-memory -C link-arg=--max-memory=1073741824 -C link-arg=--import-memory -C link-arg=--export=__wasm_init_tls -C link-arg=--export=__tls_size -C link-arg=--export=__tls_align -C link-arg=--export=__tls_base -C link-arg=--export=__heap_base'

# wasm-bindgen's CLI must exactly match the crate that produces hub.wasm.
wasm_bindgen_version="$(awk '
  /^name = "wasm-bindgen"$/ { found = 1; next }
  found && /^version = / { gsub(/"/, "", $3); print $3; exit }
' Cargo.lock)"
test -n "$wasm_bindgen_version"
installed_wasm_bindgen_version="$(wasm-bindgen --version 2>/dev/null | awk '{ print $2 }' || true)"
if [[ "$installed_wasm_bindgen_version" != "$wasm_bindgen_version" ]]; then
  cargo install wasm-bindgen-cli --version "$wasm_bindgen_version" --locked
fi

cargo +nightly build --release --target wasm32-unknown-unknown \
  -Z build-std=std,panic_abort -p hub
wasm-bindgen target/wasm32-unknown-unknown/release/hub.wasm \
  --out-dir web/pkg --no-typescript --target web --out-name hub

flutter build web --release "$@"

echo "PWA bundle ready in build/web"
