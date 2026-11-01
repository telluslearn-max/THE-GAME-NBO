/* THE GAME service worker.
 *
 * Goals: the menu opens instantly and works offline, repeat visits cost almost no data,
 * and money pages are NEVER served from a cache.
 *
 *   /assets/*        cache-first (fingerprinted, immutable)
 *   /                network first (2.5 s budget), falls back to the last good copy
 *   /cart /orders /order/*  network only; offline shows /offline
 *   /menu.json, /staff, /live, /mpesa   never touched (prices, stock, auth, sockets, money)
 */
const VERSION = "v1";
const CACHE = "tg-" + VERSION;

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Discover the current fingerprinted asset URLs from the pages that use them.
    const assets = new Set(["/favicon.svg"]);
    for (const path of ["/", "/cart"]) {
      try {
        const res = await fetch(path, { cache: "reload" });
        const html = await res.clone().text();
        (html.match(/\/(?:assets\/|logo\.svg)[^"'\s>]*/g) || []).forEach((a) => assets.add(a));
        if (path === "/" && res.ok) await cache.put("/", res);
      } catch (e) {}
    }
    await Promise.all([...assets, "/offline"].map((u) => cache.add(u).catch(() => {})));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

const withTimeout = (p, ms) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), ms))]);

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;
  const p = url.pathname;
  if (p.startsWith("/staff") || p.startsWith("/live") || p.startsWith("/mpesa") || p === "/menu.json" || p === "/sw.js") return;

  if (p.startsWith("/assets/") || p.startsWith("/icons/") || p === "/favicon.svg" || p === "/logo.svg") {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      const hit = await cache.match(req);
      if (hit) return hit;
      const res = await fetch(req);
      if (res.ok) cache.put(req, res.clone());
      return res;
    })());
    return;
  }

  if (req.mode === "navigate") {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      try {
        const res = await withTimeout(fetch(req), p === "/" ? 2500 : 20000);
        if (p === "/" && res.ok) cache.put("/", res.clone());
        return res;
      } catch (e) {
        if (p === "/") { const hit = await cache.match("/"); if (hit) return hit; }
        return (await cache.match("/offline")) || new Response("Offline", { status: 503 });
      }
    })());
  }
});

/* Web Push: "your drinks are ready". Strong, persistent, felt in a pocket in a loud bar. */
self.addEventListener("push", (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) {}
  event.waitUntil(self.registration.showNotification(d.title || "THE GAME", {
    body: d.body || "",
    icon: "/icons/icon-192.png",
    badge: "/icons/icon-192.png",
    vibrate: [400, 150, 400, 150, 400, 150, 600],
    requireInteraction: true,
    tag: "order-ready",
    renotify: true,
    data: { url: d.url || "/" },
  }));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "/";
  event.waitUntil((async () => {
    for (const w of await clients.matchAll({ type: "window", includeUncontrolled: true })) {
      if (w.url.endsWith(url) && "focus" in w) return w.focus();
    }
    return clients.openWindow(url);
  })());
});
