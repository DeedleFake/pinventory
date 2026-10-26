// Pinventory service worker.
//
// It exists to make the app installable and to show a friendly page when the
// network is down. It deliberately caches very little:
//
//   * /offline.html and the icons, fetched when the worker installs.
//   * Digested assets under /assets (those with a ?vsn= query), cached on first use.
//
// It never caches HTML, LiveView or form requests, or anything else that can
// carry a CSRF token or session state. Only the requests handled below go
// through respondWith. Everything else, including the LiveView longpoll
// fallback, goes straight to the network. Websockets never reach a service worker.
//
// Bump VERSION when changing PRECACHE, a precached file, or the caching rules.
// Activating deletes every pinventory cache that doesn't belong to the current
// version.

const VERSION = "v2"
const CACHE = `pinventory-static-${VERSION}`
const OFFLINE_URL = "/offline.html"
const PRECACHE = [OFFLINE_URL, "/images/icon-192.png", "/images/icon-512.png"]

self.addEventListener("install", event => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then(cache => cache.addAll(PRECACHE.map(url => new Request(url, {cache: "reload"}))))
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener("activate", event => {
  event.waitUntil(
    caches
      .keys()
      .then(names =>
        Promise.all(
          names.filter(name => name.startsWith("pinventory-") && name !== CACHE).map(name => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  )
})

self.addEventListener("fetch", event => {
  const request = event.request
  if (request.method !== "GET") return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  if (request.mode === "navigate") {
    // Always the network. The cache is only used when the network is unreachable.
    event.respondWith(fetch(request).catch(() => caches.match(OFFLINE_URL)))
  } else if (isCacheableAsset(url)) {
    event.respondWith(cacheFirst(request))
  }
})

// Digested assets are named by content, so a cached copy never goes stale.
// Without ?vsn= (as in development) the file can change under the same URL, so
// those always go to the network.
function isCacheableAsset(url) {
  if (url.pathname.startsWith("/assets/")) return url.searchParams.has("vsn")
  return PRECACHE.includes(url.pathname)
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE)
  const cached = await cache.match(request)
  if (cached) return cached

  const response = await fetch(request)
  if (response.ok && response.type === "basic") cache.put(request, response.clone())
  return response
}
