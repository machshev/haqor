#!/usr/bin/env bash
# Copy Flutter's Linux shared_preferences JSON store into an Android install.
#
# The Android shared_preferences implementation uses XML and special string
# prefixes for doubles and string lists, so copying the JSON file directly
# would not work. This script converts it without writing its contents (which
# can include the progress-sync token) to a temporary host file.
#
# Usage:
#   scripts/sync-flutter-preferences-to-android.sh
#   scripts/sync-flutter-preferences-to-android.sh --serial SERIAL
#   scripts/sync-flutter-preferences-to-android.sh --source PATH --package ID
#   scripts/sync-flutter-preferences-to-android.sh --dry-run
set -euo pipefail

package='org.haqor'
serial=''
source_file="${XDG_DATA_HOME:-$HOME/.local/share}/org.haqor/shared_preferences.json"
dry_run=false

usage() {
  printf '%s\n' \
    'Usage:' \
    '  scripts/sync-flutter-preferences-to-android.sh' \
    '  scripts/sync-flutter-preferences-to-android.sh --serial SERIAL' \
    '  scripts/sync-flutter-preferences-to-android.sh --source PATH --package ID' \
    '  scripts/sync-flutter-preferences-to-android.sh --dry-run'
}

while (($#)); do
  case "$1" in
    --serial)
      serial=${2:?--serial requires a device serial}
      shift 2
      ;;
    --source)
      source_file=${2:?--source requires a JSON file path}
      shift 2
      ;;
    --package)
      package=${2:?--package requires an Android package ID}
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$package" =~ ^[A-Za-z0-9._]+$ ]] || {
  echo "Invalid Android package ID: $package" >&2
  exit 2
}

for command in adb jq; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$source_file" ]] || {
  echo "Flutter preferences not found: $source_file" >&2
  exit 1
}

# Reject values that cannot be represented by Flutter's legacy preference API.
jq -e '
  type == "object" and
  all(
    .[];
    (type == "boolean") or
    (type == "number") or
    (type == "string") or
    (type == "array" and all(.[]; type == "string"))
  )
' "$source_file" >/dev/null || {
  echo "Preferences must be an object of bool, number, string, or string-list values." >&2
  exit 1
}

preference_count="$(jq 'length' "$source_file")"

if "$dry_run"; then
  echo "Would copy $preference_count Flutter preferences from $source_file to $package."
  exit 0
fi

if [[ -z "$serial" ]]; then
  mapfile -t devices < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  case ${#devices[@]} in
    1) serial=${devices[0]} ;;
    0)
      echo 'No authorized Android device found. Connect one and enable USB debugging.' >&2
      exit 1
      ;;
    *)
      echo 'More than one Android device is connected; select one with --serial.' >&2
      printf '  %s\n' "${devices[@]}" >&2
      exit 1
      ;;
  esac
fi

adb_device=(adb -s "$serial")
if ! "${adb_device[@]}" get-state >/dev/null 2>&1; then
  echo "Device $serial is unavailable." >&2
  exit 1
fi

# Pass the whole command as one argument to Android's `sh -c`; passing it as
# separate adb arguments would lose its quoting before it reached `run-as`.
app_shell() {
  "${adb_device[@]}" shell "run-as $package sh -c $(printf '%q' "$1")"
}

# The app reads this exact file at startup. A private backup is retained on the
# device in case the desktop store was not the desired source of truth.
remote_prefs='shared_prefs/FlutterSharedPreferences.xml'
remote_stage="$remote_prefs.new"
backup="$remote_prefs.before-desktop-sync-$(date -u +%Y%m%dT%H%M%SZ)"

"${adb_device[@]}" shell "am force-stop $package"
app_shell "mkdir -p shared_prefs; rm -f '$remote_stage'; if test -f '$remote_prefs'; then cp '$remote_prefs' '$backup'; fi"

# Android's legacy Flutter API stores doubles and string lists as specially
# prefixed strings. The app currently uses this API through getInstance().
render_android_preferences() {
  jq -r '
    def esc:
      gsub("&"; "&amp;") |
      gsub("<"; "&lt;") |
      gsub(">"; "&gt;") |
      gsub("\""; "&quot;");
    def pref:
      .key as $key | .value as $value |
      if ($value | type) == "boolean" then
        "    <boolean name=\"\($key | esc)\" value=\"\($value)\" />"
      elif ($value | type) == "number" and
           ($key == "flutter.font_size" or $value != ($value | floor)) then
        "    <string name=\"\($key | esc)\">VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu\($value)</string>"
      elif ($value | type) == "number" then
        "    <long name=\"\($key | esc)\" value=\"\($value)\" />"
      elif ($value | type) == "array" then
        "    <string name=\"\($key | esc)\">\(("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!" + ($value | tojson)) | esc)</string>"
      else
        "    <string name=\"\($key | esc)\">\($value | esc)</string>"
      end;
    "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?>",
    "<map>",
    (to_entries[] | pref),
    "</map>"
  ' "$source_file"
}

if ! render_android_preferences | app_shell "cat > '$remote_stage'"; then
  app_shell "rm -f '$remote_stage'" || true
  echo 'Could not prepare Android preferences; the previous file is unchanged.' >&2
  exit 1
fi

staged_count="$(app_shell "grep -o 'name=' '$remote_stage' | wc -l" | tr -d '\r[:space:]')"
if [[ "$staged_count" != "$preference_count" ]]; then
  app_shell "rm -f '$remote_stage'" || true
  echo "Validation failed: expected $preference_count preferences, staged $staged_count." >&2
  exit 1
fi

app_shell "mv '$remote_stage' '$remote_prefs'"
"${adb_device[@]}" shell monkey -p "$package" 1 >/dev/null

echo "Copied $preference_count Flutter preferences to $package on $serial."
echo "Previous phone preferences: $backup"
