// GitHub Pages cannot configure response headers. Once this worker controls
// the page, it adds the headers required for the threaded Rust WASM runtime.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
  event.respondWith(
    fetch(event.request).then((response) => {
      if (response.type === 'opaque') return response;

      const headers = new Headers(response.headers);
      headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
      headers.set('Cross-Origin-Opener-Policy', 'same-origin');
      return new Response(response.body, {
        headers,
        status: response.status,
        statusText: response.statusText,
      });
    }),
  );
});
