'use strict';
// Haqor's offline service worker, written into build/web as
// flutter_service_worker.js by tool/generate_service_worker.dart, which fills
// in RESOURCES and CORE. Flutter generated this worker itself until 3.41,
// which replaced it with one that unregisters itself; this keeps Flutter's
// caching (and its cache names, so an installed copy upgrades in place) and
// adds what Haqor needs on GitHub Pages: the cross-origin isolation headers
// threaded WASM requires, and cache keys relative to the /haqor/ scope.
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = $$RESOURCES_MAP;
// The application shell files that are downloaded before a service worker can
// start.
const CORE = $$CORE_LIST;

// GitHub Pages cannot set these response headers itself. Add them to every
// response this worker serves.
async function addCrossOriginIsolationHeaders(response) {
  response = await response;
  if (!response || response.type === 'opaque') return response;

  const headers = new Headers(response.headers);
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  return new Response(response.body, {
    headers,
    status: response.status,
    statusText: response.statusText,
  });
}

function respondWithCrossOriginIsolation(event, response) {
  event.respondWith(
    Promise.resolve(response).then(addCrossOriginIsolationHeaders),
  );
}

// A resource's key relative to the worker's scope, which is below /haqor/ on
// GitHub Pages, or null when it lies outside the scope.
const serviceWorkerScope = new URL(self.registration.scope);
function getResourceKey(url) {
  const resource = new URL(url);
  if (resource.origin !== serviceWorkerScope.origin ||
      !resource.pathname.startsWith(serviceWorkerScope.pathname)) {
    return null;
  }
  const relativePath = resource.pathname.substring(
    serviceWorkerScope.pathname.length,
  );
  return `${relativePath || '/'}${resource.search}`;
}

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener('install', (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});

// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files. A newly
// installed worker takes control at once, before the bootstrap page reloads
// to enter a cross-origin-isolated browsing context.
self.addEventListener('activate', function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      if (!manifest) {
        // When there is no prior manifest, clear the entire cache.
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
      } else {
        var oldManifest = await manifest.json();
        for (var request of await contentCache.keys()) {
          var key = getResourceKey(request.url);
          // If a resource from the old manifest is not in the new cache, or
          // if its hash has changed, delete it. Otherwise it is left in the
          // cache and can be reused by the new service worker.
          if (key == null || !RESOURCES[key] ||
              RESOURCES[key] != oldManifest[key]) {
            await contentCache.delete(request);
          }
        }
      }
      // Populate the cache with the app shell TEMP files, potentially
      // overwriting cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
    await self.clients.claim();
  }());
});

// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var key = getResourceKey(event.request.url);
  if (key == null) return;
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  // Pages, whatever their query, are the index.html.
  if (event.request.mode === 'navigate' || key == '') {
    key = '/';
  }
  // If the URL is not in the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  respondWithCrossOriginIsolation(event, caches.open(CACHE_NAME)
    .then((cache) => {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully
        // fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      });
    })
  );
});

self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});

// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = getResourceKey(request.url);
    if (key != null) currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}

// Attempt to download the resource online before falling back to the offline
// cache.
function onlineFirst(event) {
  return respondWithCrossOriginIsolation(event,
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
