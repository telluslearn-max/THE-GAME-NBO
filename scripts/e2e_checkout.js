// Regression test: menu -> cart -> checkout -> order page. Run against the prod-mode server.
const { chromium } = require("playwright");
const base = process.env.URL || "http://localhost:4100";
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const p = await ctx.newPage(); p.setDefaultTimeout(5000);
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) process.exitCode = 1; };

  await p.goto(base + "/menu", { waitUntil: "networkidle" });
  await p.evaluate(() => localStorage.clear());
  await p.reload({ waitUntil: "networkidle" });
  const g = '#c-popular .row[data-name="KC Ginger"]';
  await p.tap(g + ' [data-a="add"]'); await p.tap(g + ' [data-a="inc"]');
  await p.tap('#c-popular .row[data-name="Coke"] [data-a="add"]');
  await p.tap(".cartbar a");
  await p.waitForURL("**/cart");
  await p.waitForSelector("#lines .row");
  ok((await p.$$("#lines .row")).length === 2, "cart shows 2 lines");
  ok((await p.textContent("#total")) === "KES 2,600", "total KES 2,600");
  ok((await p.textContent("#pay")).includes("KES 2,600"), "pay button shows amount");
  await p.screenshot({ path: "/tmp/shots/checkout-375.png" });

  // stock/price reconciliation: tamper a price in storage, expect the server price to win
  await p.evaluate(() => { const c = JSON.parse(localStorage.getItem("tg.cart.v1")); for (const k in c) c[k].p = 1; localStorage.setItem("tg.cart.v1", JSON.stringify(c)); });
  await p.reload({ waitUntil: "networkidle" });
  await p.waitForFunction(() => document.querySelector("#total").textContent === "KES 2,600");
  ok(true, "tampered client prices are replaced by live prices");
  ok((await p.textContent("#cart-msg")).includes("Updated price"), "price change is explained");

  await p.fill("#phone", "12");
  await p.tap("#pay");
  ok(p.url().endsWith("/cart"), "invalid phone blocked by the browser");
  await p.fill("#phone", "0712 345 678");
  await Promise.all([p.waitForURL(/\/order\/[0-9a-f-]{36}/), p.tap("#pay")]);
  // app.js clears the spent cart and strips ?new=1 shortly after the page loads
  await p.waitForFunction(() => !location.search && localStorage.getItem("tg.cart.v1") === "{}");
  ok(/\/order\/[0-9a-f-]{36}$/.test(p.url()), "redirected to order page, ?new=1 stripped: " + p.url().split("/").pop().slice(0, 8));
  ok((await p.evaluate(() => localStorage.getItem("tg.cart.v1"))) === "{}", "cart cleared after checkout");
  console.log("errors:", errs);
  await b.close();
})();
