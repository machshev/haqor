#!/usr/bin/env bash
# Copy the generated database files from haqor-core into the Flutter asset
# bundle, then make the new copies take effect.
#
# Regenerating DBs in haqor-core does NOT reach the app on its own: the app
# bundles its own copy under assets/db/ and installs them to the device only
# when db_installer.dart's `_dbVersion` differs from the on-disk marker.
#
# Usage:
#   sync-dbs.sh           Dev loop: sync + delete THIS machine's install marker
#                         so the next launch reinstalls. Local only.
#   sync-dbs.sh --bump    Shipping: sync + increment `_dbVersion`, which
#                         refreshes EVERY installed/released copy on next start.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../../haqor-core/data"
dst="$here/../assets/db"
installer="$here/../lib/src/db_installer_native.dart"

mkdir -p "$dst"
for db in bible sedra hebrew lexicon; do
  cp -v "$src/$db.db" "$dst/$db.db"
done

if [[ "${1:-}" == "--bump" ]]; then
  current="$(grep -oP 'const _dbVersion = \K[0-9]+' "$installer")"
  next=$((current + 1))
  sed -i "s/const _dbVersion = ${current};/const _dbVersion = ${next};/" "$installer"
  echo "bumped _dbVersion: ${current} -> ${next} (refreshes all installed copies)"
  exit 0
fi

# Dev loop: force a reinstall on this machine by removing the version marker
# from the app-support db dir (path mirrors path_provider + APPLICATION_ID).
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
