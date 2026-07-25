#!/usr/bin/env bash
# Copy the generated database files from haqor-core into the Flutter asset
# bundle, then make the new copies take effect.
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

mkdir -p "$dst"
dbs=(bible sedra hebrew lexicon)
for db in "${dbs[@]}"; do
  cp -v "$src/$db.db" "$dst/$db.db"
done

# Version = the newest build time among the databases copied, in UTC ISO-8601.
# Taken from the *sources*, since cp stamps its output with the time of the
# copy — this has to identify the build, not the sync. Equality decides
# reinstall; ordering lets a sync server tell whether it holds a newer build
# than a client.
newest=0
for db in "${dbs[@]}"; do
  stamp="$(stat -c %Y "$src/$db.db")"
  ((stamp > newest)) && newest="$stamp"
done
version="$(date -u -d "@$newest" +%Y-%m-%dT%H:%M:%SZ)"
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
