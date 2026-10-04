#!/usr/bin/env bash
# Pin the Linux binary package to the latest published release (or a given tag).
set -euo pipefail

if (( $# > 1 )); then
  echo "Usage: $0 [vVERSION]" >&2
  exit 2
fi
for command in curl jq nix sha256sum mktemp; do
  command -v "$command" >/dev/null || { echo "Required command: $command" >&2; exit 1; }
done
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
metadata="$repo_root/pkgs/haqor/release.json"
endpoint=https://api.github.com/repos/machshev/haqor/releases/latest
if (( $# == 1 )); then
  [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a release tag such as v0.9.4" >&2; exit 2; }
  endpoint="https://api.github.com/repos/machshev/haqor/releases/tags/$1"
fi
scratch=$(mktemp -d)
pending=""
trap 'rm -rf -- "$scratch"; if [[ -n $pending ]]; then rm -f -- "$pending"; fi' EXIT
curl --fail --silent --show-error --location --retry 3 "$endpoint" -o "$scratch/release.json"
tag=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' "$scratch/release.json")
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Unsupported release tag: $tag" >&2; exit 1; }
version=${tag#v}
asset="haqor-$version-linux-x64.tar.gz"
url=$(jq -er --arg name "$asset" '[.assets[] | select(.name == $name) | .browser_download_url] | select(length == 1) | .[0]' "$scratch/release.json")
checksums_url=$(jq -er '[.assets[] | select(.name == "SHA256SUMS") | .browser_download_url] | select(length == 1) | .[0]' "$scratch/release.json")
# Only consume assets belonging to this repository and release.
prefix="https://github.com/machshev/haqor/releases/download/$tag"
[[ $url == "$prefix/$asset" && $checksums_url == "$prefix/SHA256SUMS" ]] || { echo "Unexpected release asset URLs" >&2; exit 1; }
curl --fail --silent --show-error --location --retry 3 "$checksums_url" -o "$scratch/SHA256SUMS"
expected=$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; count++ } END { if (count != 1) exit 1 }' "$scratch/SHA256SUMS")
[[ $expected =~ ^[[:xdigit:]]{64}$ ]] || { echo "Invalid release checksum" >&2; exit 1; }
echo "Downloading $asset and verifying SHA256SUMS..."
curl --fail --silent --show-error --location --retry 3 "$url" -o "$scratch/$asset"
printf '%s  %s\n' "$expected" "$asset" > "$scratch/checksum"
(cd "$scratch" && sha256sum --check checksum)
hash=$(nix hash convert --hash-algo sha256 --to sri "$expected")
pending=$(mktemp "$metadata.XXXXXX")
jq -n --arg version "$version" --arg url "$url" --arg hash "$hash" '{version: $version, url: $url, hash: $hash}' > "$pending"
chmod 644 "$pending"
mv -- "$pending" "$metadata"
pending=""
echo "Pinned Haqor $version in $metadata"
