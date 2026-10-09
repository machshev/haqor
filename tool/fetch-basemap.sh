#!/usr/bin/env bash
# Rebuild assets/map/basemap.json from Natural Earth (public domain) at a
# pinned release, and assets/map/relief.png from the Terrain Tiles (SRTM,
# public domain). The assets are committed; run this only to change them, and
# review the maps afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
readonly release="v5.1.2"
readonly base_url="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/${release}/geojson"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
for layer in ne_50m_land ne_10m_land ne_10m_lakes ne_10m_rivers_lake_centerlines; do
  curl -sS -L --fail --retry 3 --output "${work}/${layer}.geojson" "${base_url}/${layer}.geojson"
done
dart run tool/build_basemap.dart "${work}" assets/map/basemap.json
# The Terrain Tiles dataset is not versioned; it has been unchanged since 2018.
readonly tiles_url="https://s3.amazonaws.com/elevation-tiles-prod/terrarium"
mkdir -p "${work}/tiles"
for tile in $(dart run tool/build_relief.dart --tiles); do
  curl -sS -L --fail --retry 3 --output "${work}/tiles/${tile//\//_}.png" "${tiles_url}/${tile}.png"
done
dart run tool/build_relief.dart "${work}/tiles" assets/map/relief.png
