#!/usr/bin/env bash
# Rebuild assets/map/basemap.json from Natural Earth (public domain) at a
# pinned release and, over Israel and Transjordan, OpenBible.info's Bible
# geocoding data at a pinned commit (CC BY 4.0, its OpenStreetMap geometry
# ODbL 1.0; the same commit haqor-core's scripts/fetch-openbible-geocoding.sh
# reads), and assets/map/relief/ from the Terrain Tiles (SRTM, public domain).
# The assets are committed; run this only to change them, and review the maps
# afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
readonly release="v5.1.2"
readonly base_url="https://raw.githubusercontent.com/nvkelso/natural-earth-vector/${release}/geojson"
readonly openbible="https://github.com/openbibleinfo/Bible-Geocoding-Data"
readonly openbible_commit="7eb18a5ee62f27b9b93bd6689ea272d76dd23b8f"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
for layer in ne_50m_land ne_10m_land ne_10m_lakes ne_10m_rivers_lake_centerlines; do
  curl -sS -L --fail --retry 3 --output "${work}/${layer}.geojson" "${base_url}/${layer}.geojson"
done
# git checks every file against the commit's hash.
git -C "${work}" init --quiet openbible
git -C "${work}/openbible" fetch --quiet --depth 1 "${openbible}" "${openbible_commit}"
git -C "${work}/openbible" checkout --quiet FETCH_HEAD
dart run tool/build_basemap.dart "${work}" "${work}/openbible" assets/map/basemap.json
# The Terrain Tiles dataset is not versioned; it has been unchanged since 2018.
readonly tiles_url="https://s3.amazonaws.com/elevation-tiles-prod/terrarium"
mkdir -p "${work}/tiles"
for tile in $(dart run tool/build_relief.dart --tiles); do
  curl -sS -L --fail --retry 3 --output "${work}/tiles/${tile//\//_}.png" "${tiles_url}/${tile}.png"
done
dart run tool/build_relief.dart "${work}/tiles" assets/map/relief
