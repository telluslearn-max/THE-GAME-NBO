// Automated accessibility audit (axe-core, WCAG 2.x A/AA) on the main screens.
// Usage: AXE=/path/to/axe.min.js node scripts/a11y.js   (server on :4100; npm i axe-core to get the file)
const { chromium } = require("playwright"); const fs = require("fs");
const base = process.env.URL || "http://localhost:4100";
const axeSrc = fs.readFileSync(process.env.AXE || "/tmp/axe.min.js", "utf8");
(async () => {
  const b = await chromium.launch(); let bad = 0;
  const ctx = await b.newContext({ viewport: { width: 375, height: 812 }, isMobile: true });
  const p = await ctx.newPage();
  async function audit(name, path, prep) {
    await p.goto(base + path, { waitUntil: "networkidle" }); if (prep) await prep();
    await p.evaluate(axeSrc);
    const r = await p.evaluate(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"] } }));
    const v = r.violations;
    console.log(`${v.length ? "FAIL" : "PASS"} ${name}: ${v.length} violations (${r.passes.length} rules passed)`);
    for (const x of v) { bad++; console.log(`   - [${x.impact}] ${x.id}: ${x.help} (${x.nodes.length} nodes) e.g. ${x.nodes[0].target.join(" ")} :: ${(x.nodes[0].failureSummary || "").split("\n")[1] || ""}`); }
  }
  await audit("menu", "/");
  await audit("menu with items in cart", "/", async () => { await p.tap?.('.row .add').catch(() => {}); await p.click(".row .add"); });
  await audit("cart", "/cart", async () => { await p.waitForTimeout(500); });
  await audit("offline page", "/offline");
  await audit("orders list", "/orders");
  // a real order page (live view) and the ready state
  await p.goto(base + "/", { waitUntil: "networkidle" });
  await p.evaluate(() => localStorage.clear()); await p.reload({ waitUntil: "networkidle" });
  await p.click('#c-popular .row[data-name="Water"] .add'); await p.click(".cartbar a"); await p.waitForURL("**/cart");
  await p.waitForSelector("#lines .row"); await p.fill("#phone", "07" + Math.floor(10000000 + Math.random() * 89999999));
  await Promise.all([p.waitForURL(/\/order\/[0-9a-f-]{36}/), p.click("#pay")]);
  await p.waitForSelector("text=Check your phone");
  await audit("order: waiting for payment", p.url().replace(base, ""));
  await p.waitForSelector("text=Paid. The bar has your order", { timeout: 20000 });
  await audit("order: paid", p.url().replace(base, ""));
  await audit("staff login", "/staff/login");
  await b.close(); process.exit(bad ? 1 : 0);
})();
