#!/usr/bin/env bash
# Add the isolation headers required by threaded WASM to Flutter's generated
# offline service worker. This keeps caching and isolation under one worker.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
worker="${1:-"$here/../build/web/flutter_service_worker.js"}"

if [[ ! -f "$worker" ]]; then
  echo "Flutter service worker not found: $worker" >&2
  exit 1
fi

respond_with_count="$(grep -c 'event\.respondWith(' "$worker" || true)"
root_key_count="$(
  grep -c 'substring(origin.length + 1)' "$worker" || true
)"
if [[ "$respond_with_count" -ne 2 ]]; then
  echo "Expected 2 generated respondWith calls, found $respond_with_count" >&2
  echo "Flutter's service-worker format may have changed; refusing to patch it." >&2
  exit 1
fi
if [[ "$root_key_count" -ne 3 ]]; then
  echo "Expected 3 generated root-relative cache keys, found $root_key_count" >&2
  echo "Flutter's service-worker format may have changed; refusing to patch it." >&2
  exit 1
fi

temp="$(mktemp "${worker}.XXXXXX")"
trap 'rm -f "$temp"' EXIT

awk '
  NR == 1 {
    print
    print ""
    print "// GitHub Pages cannot set these response headers itself. Add them to"
    print "// every same-origin response while retaining Flutter'\''s offline cache."
    print "async function addCrossOriginIsolationHeaders(response) {"
    print "  response = await response;"
    print "  if (!response || response.type === '\''opaque'\'') return response;"
    print ""
    print "  const headers = new Headers(response.headers);"
    print "  headers.set('\''Cross-Origin-Embedder-Policy'\'', '\''require-corp'\'');"
    print "  headers.set('\''Cross-Origin-Opener-Policy'\'', '\''same-origin'\'');"
    print "  return new Response(response.body, {"
    print "    headers,"
    print "    status: response.status,"
    print "    statusText: response.statusText,"
    print "  });"
    print "}"
    print ""
    print "function respondWithCrossOriginIsolation(event, response) {"
    print "  event.respondWith("
    print "    Promise.resolve(response).then(addCrossOriginIsolationHeaders),"
    print "  );"
    print "}"
    print ""
    print "// Ensure a newly installed worker takes control before the bootstrap page"
    print "// reloads to enter a cross-origin-isolated browsing context."
    print "self.addEventListener('\''activate'\'', (event) => {"
    print "  event.waitUntil(self.clients.claim());"
    print "});"
    print ""
    print "// Flutter'\''s generated worker calculates keys from the origin root,"
    print "// which misses every resource when the app is hosted below /haqor/."
    print "const serviceWorkerScope = new URL(self.registration.scope);"
    print "function getResourceKey(url) {"
    print "  const resource = new URL(url);"
    print "  if (resource.origin !== serviceWorkerScope.origin ||"
    print "      !resource.pathname.startsWith(serviceWorkerScope.pathname)) {"
    print "    return null;"
    print "  }"
    print "  const relativePath = resource.pathname.substring("
    print "    serviceWorkerScope.pathname.length,"
    print "  );"
    print "  return `${relativePath || '\''/'\''}${resource.search}`;"
    print "}"
    next
  }
  {
    gsub(/event\.respondWith\(/, "respondWithCrossOriginIsolation(event, ")
    gsub(/event\.request\.url\.substring\(origin\.length \+ 1\)/, "getResourceKey(event.request.url)")
    gsub(/request\.url\.substring\(origin\.length \+ 1\)/, "getResourceKey(request.url)")
    if ($0 ~ /var key = getResourceKey\(event\.request\.url\)/) {
      print
      print "  if (key == null) return;"
      next
    }
    if ($0 ~ /if \(event\.request\.url == origin/) {
      print "  if (event.request.mode === '\''navigate'\'' || key == '\'''\'') {"
      next
    }
    print
  }
' "$worker" > "$temp"

patched_calls="$(grep -c 'respondWithCrossOriginIsolation(event,' "$temp" || true)"
header_calls="$(grep -c 'addCrossOriginIsolationHeaders' "$temp" || true)"
scope_key_calls="$(grep -c 'getResourceKey(' "$temp" || true)"
navigation_calls="$(grep -c "event.request.mode === 'navigate'" "$temp" || true)"
if [[ "$patched_calls" -ne 3 ||
      "$header_calls" -ne 2 ||
      "$scope_key_calls" -ne 4 ||
      "$navigation_calls" -ne 1 ]]; then
  echo "Generated service-worker patch failed validation." >&2
  exit 1
fi

mv "$temp" "$worker"
trap - EXIT
