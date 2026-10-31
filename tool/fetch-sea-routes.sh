#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
readonly revision=65881112a6e5246d0bf3a90ac22dad7a2728cc2d
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -sSL --fail --retry 3 "https://raw.githubusercontent.com/emeeks/orbis_v2/$revision/base_routes.geojson" -o "$work/routes.json"
echo "67ad02e88f572e3422c637afa8d7446fbcbc99a151861eec210b7ca01fda9d2e  $work/routes.json" | sha256sum --check --quiet
dart tool/build_sea_routes.dart "$work/routes.json" assets/map/basemap.json assets/map/sea_routes.json
