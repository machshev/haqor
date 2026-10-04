#!/usr/bin/env bash
# Rinf's generated signed i64 codec uses ByteData accessors unavailable on web.
set -euo pipefail
cd "$(dirname "$0")/.."
rinf gen
dart run tool/patch_bindings.dart
