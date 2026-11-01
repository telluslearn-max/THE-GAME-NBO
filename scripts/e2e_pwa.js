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
  // Repeat visit: what actually reaches the server? (Chromium's own network log cannot see
  // through a service worker, so count requests in the server log.)
  const fs = require("fs"), LOG = process.env.SERVER_LOG || "/tmp/prod.log";
  const before = fs.existsSync(LOG) ? fs.readFileSync(LOG, "utf8").split("\n").length : 0;
  await p.reload({ waitUntil: "networkidle" });
  await p.waitForTimeout(500);
  if (before) {
    // every request the server handles ends with one "Sent <status> in <time>" line
    const sent = fs.readFileSync(LOG, "utf8").split("\n").slice(before).filter((l) => /\[info\] Sent \d+/.test(l));
    console.log("repeat visit: requests that reached the server =", sent.length, "(the menu HTML revalidating; css/js come from the service worker)");
    ok(sent.length <= 2, "repeat visit costs at most the HTML revalidation, not the assets");
  }

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
