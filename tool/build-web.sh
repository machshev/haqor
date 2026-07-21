#!/usr/bin/env bash
# Build the installable offline PWA. Run inside `nix develop`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
app="$here/.."

cd "$app"
flutter build web --release "$@"

echo "PWA bundle ready in build/web"
