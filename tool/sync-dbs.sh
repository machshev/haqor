#!/usr/bin/env bash
# Copy the curated runtime database (haqor.db) from haqor-core into the Flutter
# asset bundle, then make the new copy take effect.
#
# Regenerating DBs in haqor-core does NOT reach the app on its own: the app
# bundles its own copy under assets/db/ and installs them to the device only
# when the bundled build version differs from the on-disk marker.
#
# That version is the databases' own build time, written here to
# assets/db/version.txt and read by lib/src/db_version.dart. Nothing is
# maintained by hand and there is no bump step: syncing changed databases is
# what refreshes every installed copy, because the version travels with them.
#
# Usage:
#   sync-dbs.sh           Sync + delete THIS machine's install marker so the
#                         next launch reinstalls immediately.
#   sync-dbs.sh --keep    Sync only; leave the local marker alone.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../haqor-core/data"
dst="$here/../assets/db"

if [[ ! -f "$src/haqor.db" ]]; then
  echo "no $src/haqor.db — run 'cargo run --release -- db gen-runtime' first" >&2
  exit 1
fi

mkdir -p "$dst"
# Only the runtime database ships. The four generation databases beside it are
# its inputs.
rm -f "$dst"/bible.db "$dst"/sedra.db "$dst"/hebrew.db "$dst"/lexicon.db
cp -v "$src/haqor.db" "$dst/haqor.db"

# The database's own build stamp is its version — nothing to maintain by hand.
# Equality decides reinstall; the format also orders, which is what lets a sync
# server tell whether it holds a newer build than a client.
version="$(sqlite3 "$dst/haqor.db" "SELECT value FROM meta WHERE key = 'built';")"
test -n "$version"
printf '%s\n' "$version" > "$dst/version.txt"
echo "database build version: $version"

if [[ "${1:-}" == "--keep" ]]; then
  exit 0
fi

# Force a reinstall on this machine by removing the version marker from the
# app-support db dir (path mirrors path_provider + APPLICATION_ID).
app_id="$(grep -oP 'set\(APPLICATION_ID "\K[^"]+' "$here/../linux/CMakeLists.txt")"
case "$(uname -s)" in
  Darwin) support="$HOME/Library/Application Support/$app_id" ;;
  *)      support="${XDG_DATA_HOME:-$HOME/.local/share}/$app_id" ;;
esac
marker="$support/db/.version"
if [[ -e "$marker" ]]; then
  rm -v "$marker"
  echo "cleared local install marker; next launch reinstalls (this machine only)"
else
  echo "no local install marker at $marker (fresh install will copy anyway)"
fi
