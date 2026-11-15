#!/usr/bin/env bash
# Opt this checkout into a sibling haqor-core and refresh Cargo.lock.
set -euo pipefail

if [[ ! -f Cargo.toml || ! -f native/hub/Cargo.toml ]]; then
  echo "Run this from the haqor repository root." >&2
  exit 2
fi

if [[ $# -gt 1 ]]; then
  echo "usage: update-local-core-lock [path-to-haqor-core]" >&2
  exit 2
fi

core="${1:-../haqor-core}"
if [[ ! -f "$core/crates/haqor-core/Cargo.toml" ]]; then
  echo "No haqor-core crate at $core/crates/haqor-core" >&2
  exit 1
fi
core="$(cd "$core" && pwd -P)"
crate="$core/crates/haqor-core"
config=.cargo/config.toml
mkdir -p .cargo
if [[ -e "$config" ]]; then
  if ! grep -Fqx "haqor-core = { path = \"$crate\" }" "$config"; then
    echo "$config already exists with a different configuration; update its [patch.crates-io] haqor-core path manually." >&2
    exit 1
  fi
else
  printf '[patch.crates-io]\nhaqor-core = { path = "%s" }\n' "$crate" > "$config"
fi

cargo update -p haqor-core
echo "Cargo.lock now uses $crate. Run bash tool/sync-dbs.sh to copy its rebuilt database into the app."
