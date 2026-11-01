// Usage: node scripts/measure.js [url] [outdir]
// Reports per-asset brotli sizes (what Caddy sends), load timing under a slow-3G-ish profile,
// horizontal-overflow checks, and writes screenshots at phone/tablet widths.
const { chromium } = require("playwright");
const zlib = require("zlib");
const url = process.argv[2] || "http://localhost:4100/";
const out = process.argv[3] || "/tmp/shots";
require("fs").mkdirSync(out, { recursive: true });

const br = (b) => zlib.brotliCompressSync(b, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 } }).length;

(async () => {
  const browser = await chromium.launch();
  const sizes = [[320, 640], [375, 812], [414, 896], [768, 1024], [1280, 800]];
  let fail = false;
  for (const [w, h] of sizes) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 2, isMobile: w < 800, hasTouch: w < 800 });
    const page = await ctx.newPage();
    const assets = [];
    page.on("response", async (r) => {
      try { const b = await r.body(); assets.push([new URL(r.url()).pathname, b.length, br(b)]); } catch (e) {}
    });
    await page.goto(url, { waitUntil: "networkidle" });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    if (overflow > 0) { fail = true; console.log(`  !! horizontal overflow ${overflow}px at ${w}`); }
    await page.screenshot({ path: `${out}/menu-${w}.png`, fullPage: false });
    if (w === 375) {
      console.log("Assets (raw / brotli bytes):");
      let tot = 0;
      for (const [p, raw, c] of assets) { tot += c; console.log(`  ${p.padEnd(28)} ${String(raw).padStart(7)} ${String(c).padStart(7)}`); }
      console.log(`  TOTAL brotli first-visit: ${tot} B (${(tot / 1024).toFixed(1)} KB)`);
    }
    await ctx.close();
  }
  // Slow 3G-ish timing on a mid-range device profile
  const ctx = await browser.newContext({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 300, downloadThroughput: (400 * 1024) / 8, uploadThroughput: (400 * 1024) / 8 });
  await cdp.send("Emulation.setCPUThrottlingRate", { rate: 4 });
  await page.goto(url, { waitUntil: "load" });
  const t = await page.evaluate(() => {
    const n = performance.getEntriesByType("navigation")[0];
    const fcp = performance.getEntriesByName("first-contentful-paint")[0];
    return { ttfb: Math.round(n.responseStart), fcp: fcp ? Math.round(fcp.startTime) : null, load: Math.round(n.loadEventEnd) };
  });
  console.log(`Throttled (400kbps, 300ms RTT, 4x CPU): TTFB ${t.ttfb}ms, FCP ${t.fcp}ms, load ${t.load}ms`);
  await browser.close();
  process.exit(fail ? 1 : 0);
})();
