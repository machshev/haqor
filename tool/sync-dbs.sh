#!/usr/bin/env bash
# Copy the generated database files from haqor-core into the Flutter asset
# bundle. Run after regenerating any of them (`db gen-*` in haqor-core).
#
# Remember to bump `_dbVersion` in lib/src/db_installer.dart so installed
# copies on devices are refreshed on the next app start.
set -euo pipefail

src="$(dirname "$0")/../../haqor-core/data"
dst="$(dirname "$0")/../assets/db"

mkdir -p "$dst"
for db in bible sedra hebrew lexicon; do
  cp -v "$src/$db.db" "$dst/$db.db"
done
