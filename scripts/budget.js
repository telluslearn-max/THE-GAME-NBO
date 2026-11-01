#!/usr/bin/env node
// Performance budget gate. Fails (exit 1) when any page or asset exceeds its budget.
// Sizes are brotli of the identity body: what a proxy like Caddy puts on the wire.
// Usage: node scripts/budget.js [base_url]    (server must be running: scripts/prodrun.sh)
const zlib = require("zlib");
const base = process.argv[2] || process.env.URL || "http://localhost:4100";
const br = (b) => zlib.brotliCompressSync(b, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 } }).length;
const KB = 1024;

// per-asset and per-page budgets in bytes (brotli)
const BUDGET = {
  menu: { html: 3 * KB, total: 9 * KB },
  cart: { html: 3 * KB, total: 11 * KB },
  order: { html: 5 * KB, total: 45 * KB },
  staff_login: { html: 2 * KB, total: 9 * KB },
  assets: { logo: 3.5 * KB, css: 3 * KB, "staff.css": 2 * KB, "app.js": 2 * KB, "cart.js": 2 * KB, "live.js": 35 * KB },
};

let failed = false;
const row = (name, n, max) => {
  const bad = n > max; if (bad) failed = true;
  console.log(`${bad ? "FAIL" : "ok  "} ${name.padEnd(34)} ${(n / KB).toFixed(2).padStart(6)} KB  (budget ${(max / KB).toFixed(1)} KB)`);
};

async function get(path, headers = {}) {
  const r = await fetch(base + path, { headers: { "accept-encoding": "identity", ...headers }, redirect: "manual" });
  return { r, body: Buffer.from(await r.arrayBuffer()) };
}

async function page(name, path, budget, headers) {
  const { r, body } = await get(path, headers);
  if (r.status !== 200) { failed = true; console.log(`FAIL ${name}: HTTP ${r.status}`); return; }
  const html = body.toString();
  const assets = [...new Set(html.match(/\/(?:assets\/|logo)[^"'\s>]*/g) || [])];
  // every linked resource (icons, manifest, scripts, images) must actually resolve
  for (const m of html.matchAll(/<(?:link|script|img)\b[^>]*?(?:href|src)="(\/[^"]+)"/g)) {
    const r = await fetch(base + m[1], { redirect: "manual" });
    if (r.status !== 200) { failed = true; console.log(`FAIL ${name}: ${m[1]} -> HTTP ${r.status}`); }
  }
  let total = br(body);
  row(`${name} html`, total, budget.html);
  for (const a of assets) {
    const { body: ab } = await get(a); const size = br(ab); total += size;
    const kind = a.includes("logo.svg") ? "logo" : a.includes("/staff-") ? "staff.css" : a.includes(".css") ? "css" : a.match(/\/(app|cart|live)-/) ? a.match(/\/(app|cart|live)-/)[1] + ".js" : "other";
    row(`${name} ${kind}`, size, BUDGET.assets[kind] ?? 4 * KB);
  }
  row(`${name} TOTAL first visit`, total, budget.total);
}

(async () => {
  await page("menu", "/", BUDGET.menu);
  await page("cart", "/cart", BUDGET.cart);
  await page("staff-login", "/staff/login", BUDGET.staff_login);

  // an order page needs a real order: place one the way a browser would
  const cart = await get("/cart");
  const csrf = cart.body.toString().match(/name="_csrf_token" value="([^"]+)"/)[1];
  const cookie = (cart.r.headers.getSetCookie?.() || []).map((c) => c.split(";")[0]).join("; ");
  const menu = await (await fetch(base + "/menu.json")).json();
  const id = Object.keys(menu.p).find((k) => menu.p[k][1] === 1);
  const phone = "07" + String(Math.floor(10000000 + Math.random() * 89999999));
  const res = await fetch(base + "/orders", {
    method: "POST", redirect: "manual",
    headers: { "content-type": "application/x-www-form-urlencoded", cookie },
    body: new URLSearchParams({ _csrf_token: csrf, items: JSON.stringify([{ id, q: 1 }]), expected_total: String(menu.p[id][0]), phone }),
  });
  const loc = res.headers.get("location");
  if (!loc) { failed = true; console.log("FAIL could not place an order for the order-page budget: HTTP " + res.status); }
  else await page("order", loc.split("?")[0], BUDGET.order);
  console.log(failed ? "\nBUDGET FAILED" : "\nAll budgets met");
  process.exit(failed ? 1 : 0);
})();
