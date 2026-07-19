#!/usr/bin/env bash

# Bump Haqor's Flutter application version following SemVer.
#
# Usage:
#   tool/bump-version.sh <major|minor|patch>   bump that component
#   tool/bump-version.sh <X.Y.Z>               set an explicit app version
#   tool/bump-version.sh ... --tag             also commit + create vX.Y.Z
#
# Every bump advances Flutter's build number, which becomes Android's
# versionCode and iOS/macOS's CFBundleVersion. `--tag` does not push.

set -euo pipefail

usage() {
    echo "usage: tool/bump-version.sh <major|minor|patch|X.Y.Z> [--tag]" >&2
    exit 2
}

[ $# -ge 1 ] || usage

bump=""
do_tag=0
for arg in "$@"; do
    case "$arg" in
        --tag) do_tag=1 ;;
        -h | --help) usage ;;
        -*)
            echo "unknown flag: $arg" >&2
            usage
            ;;
        *)
            [ -z "$bump" ] || usage
            bump="$arg"
            ;;
    esac
done
[ -n "$bump" ] || usage

root="$(git rev-parse --show-toplevel)"
manifest="$root/pubspec.yaml"

if [ "$do_tag" -eq 1 ] && { ! git -C "$root" diff --quiet || ! git -C "$root" diff --cached --quiet; }; then
    echo "refusing to tag with uncommitted changes; commit them first" >&2
    exit 1
fi

current="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' "$manifest" | head -1)"
if ! [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(\+([0-9]+))?$ ]]; then
    echo "could not parse Flutter version from $manifest (got '$current')" >&2
    exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"
build="${BASH_REMATCH[5]:-0}"

case "$bump" in
    major) next="$((major + 1)).0.0" ;;
    minor) next="${major}.$((minor + 1)).0" ;;
    patch) next="${major}.${minor}.$((patch + 1))" ;;
    *)
        if [[ "$bump" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            next="$bump"
        else
            echo "invalid bump '$bump': expected major|minor|patch or X.Y.Z" >&2
            exit 1
        fi
        ;;
esac

if [ "$next" = "${major}.${minor}.${patch}" ]; then
    echo "version already $next; choose a different version" >&2
    exit 1
fi

new_build="$((build + 1))"
new="${next}+${new_build}"

if [ "$do_tag" -eq 1 ] && git -C "$root" rev-parse -q --verify "refs/tags/v$next" >/dev/null; then
    echo "tag v$next already exists" >&2
    exit 1
fi

sed -i -E "0,/^version:[[:space:]]*/s|^version:.*|version: $new|" "$manifest"
echo "bumped $current -> $new"

if [ "$do_tag" -eq 1 ]; then
    git -C "$root" add -- pubspec.yaml
    git -C "$root" commit -m "chore: release v$next"
    git -C "$root" tag -a "v$next" -m "v$next"
    echo "committed and tagged v$next (not pushed)"
fi
