const CACHE = "smart-shop-v20";

self.addEventListener("install", event => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then(cache =>
      cache.addAll([
        "./manifest.webmanifest"
      ]).catch(() => {})
    )
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const req = event.request;

  // Always try the internet first for HTML/navigation.
  // This prevents an old index.html from being served after each GitHub/Cloudflare update.
  if (req.mode === "navigate" || (req.headers.get("accept") || "").includes("text/html")) {
    event.respondWith(
      fetch(req, { cache: "no-store" })
        .then(response => response)
        .catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Static assets may use cache, but are refreshed from the network when available.
  event.respondWith(
    caches.match(req).then(cached => {
      const network = fetch(req).then(response => {
        if (response && response.ok && req.method === "GET") {
          const copy = response.clone();
          caches.open(CACHE).then(cache => cache.put(req, copy));
        }
        return response;
      }).catch(() => cached);

      return cached || network;
    })
  );
});
