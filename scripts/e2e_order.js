// Regression test: checkout -> live order page -> prompt -> paid (live, no reload).
// Needs the prod-mode server with the fake gateway auto-settling (scripts/prodrun.sh does this).
const { chromium } = require("playwright");
const zlib = require("zlib");
const base = process.env.URL || "http://localhost:4100";
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const p = await ctx.newPage(); p.setDefaultTimeout(15000);
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) process.exitCode = 1; };
  let bytes = 0; const files = [];
  p.on("response", async (r) => { try { const x = await r.body(); const c = zlib.brotliCompressSync(x).length; bytes += c; files.push([new URL(r.url()).pathname.slice(0, 40), c]); } catch (e) {} });

  await p.goto(base + "/menu", { waitUntil: "networkidle" });
  await p.evaluate(() => localStorage.clear());
  await p.reload({ waitUntil: "networkidle" });
  await p.tap('#c-popular .row[data-name="Coke"] [data-a="add"]');
  await p.tap(".cartbar a"); await p.waitForURL("**/cart"); await p.waitForSelector("#lines .row");
  await p.fill("#phone", "0733 " + String(Math.floor(100 + Math.random() * 899)) + " " + String(Math.floor(100 + Math.random() * 899)));
  bytes = 0; files.length = 0;
  await Promise.all([p.waitForURL(/\/order\/[0-9a-f-]{36}/), p.tap("#pay")]);
  await p.waitForSelector("#ticket");
  await p.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  ok(true, "LiveView connected");
  await p.waitForSelector("text=Check your phone");
  ok(true, "M-Pesa prompt sent automatically on arrival");
  ok((await p.getAttribute("#ticket", "data-status")) === "pending_payment", "status pending_payment");
  ok(/^\d+:\d\d$/.test((await p.textContent("#hold")).trim()), "reservation countdown ticking: " + (await p.textContent("#hold")).trim());
  await p.screenshot({ path: "/tmp/shots/order-pending-375.png" });
  console.log("order page first-visit transfer (brotli):", bytes, "B", files.map((f) => f.join(":")).join(" "));

  await p.waitForSelector("text=Paid. The bar has your order", { timeout: 20000 });
  ok(true, "page flipped to Paid live, no reload");
  ok((await p.textContent("#ticket")).includes("Order reference"), "order reference shown after payment");
  await p.screenshot({ path: "/tmp/shots/order-paid-375.png" });
  ok(errs.length === 0, "no JS errors " + JSON.stringify(errs));
  await b.close();
})();
