// Regression test: service worker, offline menu, offline cart, and that money pages are never cached.
const { chromium } = require("playwright");
const zlib = require("zlib");
const base = process.env.URL || "http://localhost:4100";
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 375, height: 812 }, isMobile: true, hasTouch: true, serviceWorkers: "allow" });
  const p = await ctx.newPage(); p.setDefaultTimeout(15000);
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));

  await p.goto(base + "/", { waitUntil: "networkidle" });
  await p.evaluate(() => navigator.serviceWorker.ready.then(() => true));
  await p.waitForFunction(() => navigator.serviceWorker.controller || true);
  await p.reload({ waitUntil: "networkidle" });
  ok(await p.evaluate(() => !!navigator.serviceWorker.controller), "service worker controls the page");

  const keys = await p.evaluate(async () => { const c = await caches.open((await caches.keys())[0]); return (await c.keys()).map((r) => new URL(r.url).pathname); });
  ok(keys.includes("/") && keys.includes("/offline"), "shell + offline page precached");
  ok(keys.some((k) => k.startsWith("/assets/css/")) && keys.some((k) => k.startsWith("/assets/js/app-")), "css + js precached");
  ok(keys.some((k) => k.startsWith("/assets/js/cart-")), "cart script precached (so the cart works offline)");
  ok(!keys.includes("/cart") && !keys.some((k) => k.startsWith("/order") || k.startsWith("/staff") || k === "/menu.json"), "no money / auth pages in the cache: " + keys.length + " entries");

  // repeat visit: how much comes over the network?
  // The worker relays every response, so use the browser's own network log (CDP) for truth.
  const cdp = await ctx.newCDPSession(p); await cdp.send("Network.enable");
  const wire = []; cdp.on("Network.loadingFinished", (e) => wire.push(e.encodedDataLength));
  const reqs = []; cdp.on("Network.requestWillBeSent", (e) => reqs.push(e.request.url));
  await p.reload({ waitUntil: "networkidle" });
  console.log("repeat visit: bytes on the wire =", wire.reduce((a, b) => a + b, 0), "across", wire.length, "network responses");

  await ctx.setOffline(true);
  await p.reload({ waitUntil: "domcontentloaded" });
  ok((await p.locator(".row").count()) > 5, "menu opens fully offline");
  await p.waitForSelector(".offline");
  ok(true, "offline banner shown");
  await p.tap('#c-popular .row[data-name="Coke"] [data-a="add"]');
  ok((await p.textContent(".cartbar .l")).includes("1 drink"), "can add to cart offline");
  await p.goto(base + "/cart").catch(() => {});
  ok((await p.textContent("body")).includes("You’re offline"), "/cart offline shows the offline page, not a stale cart");
  await p.screenshot({ path: "/tmp/shots/offline-375.png" });

  await ctx.setOffline(false);
  await p.goto(base + "/cart", { waitUntil: "networkidle" });
  await p.waitForSelector("#lines .row");
  ok(true, "back online, the saved cart is intact");
  ok(errs.length === 0, "no JS errors " + JSON.stringify(errs));
  await b.close();
})();
