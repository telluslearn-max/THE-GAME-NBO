// Admin Insights: staff cannot open it, admin can; the page renders, is accessible, has no CSP
// violations, and does not overflow a phone. Needs a staff and an admin login (see env below).
const { chromium } = require("playwright");
const fs = require("fs");
const base = process.env.URL || "http://localhost:4100";
const staffCreds = [process.env.STAFF_EMAIL || "owner@thegame.test", process.env.STAFF_PASSWORD || "a long staff passphrase"];
const adminCreds = [process.env.ADMIN_EMAIL || "admin@thegame.test", process.env.ADMIN_PASSWORD || "a long admin passphrase"];
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) process.exitCode = 1; };
async function login(ctx, [email, password]) {
  const p = await ctx.newPage(); p.setDefaultTimeout(20000);
  await p.goto(base + "/staff/login"); await p.fill("#email", email); await p.fill("#password", password); await p.click("button[type=submit]");
  await p.waitForURL(/\/staff/); return p;
}
(async () => {
  const b = await chromium.launch();
  // ordinary staff: no Insights
  const sp = await login(await b.newContext({ viewport: { width: 1280, height: 800 } }), staffCreds);
  ok(sp.url().endsWith("/staff"), "staff land on the board");
  ok((await sp.locator('a[href="/staff/insights"]').count()) === 0, "staff do not see an Insights link");
  await sp.goto(base + "/staff/insights"); await sp.waitForTimeout(1500);
  ok(!sp.url().endsWith("/insights"), "staff are turned away from /staff/insights");

  // admin
  const errs = [], csp = [];
  const actx = await b.newContext({ viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const ap = await actx.newPage(); ap.setDefaultTimeout(20000);
  ap.on("pageerror", (e) => errs.push(e.message)); ap.on("console", (m) => { if (/Content Security Policy|Refused to/.test(m.text())) csp.push(m.text().slice(0, 120)); });
  await ap.goto(base + "/staff/login"); await ap.fill("#email", adminCreds[0]); await ap.fill("#password", adminCreds[1]); await ap.click("button[type=submit]");
  await ap.waitForURL("**/staff/insights");
  ok(true, "admin lands on Insights after signing in");
  await ap.waitForSelector(".stats.six"); await ap.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  for (const t of ["Revenue", "Sales by day", "Busiest hours", "Top drinks", "How they paid", "Service speed", "Orders per waiter", "Running low"]) ok((await ap.textContent("main")).includes(t), "section: " + t);
  ok((await ap.locator("svg.bars").count()) === 2, "two charts rendered");
  await ap.getByRole("button", { name: "Today" }).click(); await ap.waitForSelector('button[aria-pressed="true"]:has-text("Today")');
  ok(true, "range switch works live");
  await ap.getByRole("button", { name: "7 days" }).click();
  const ov = await ap.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  ok(ov <= 0, "no horizontal overflow at 375px");
  await ap.screenshot({ path: "/tmp/shots/insights-375.png", fullPage: true });
  ok(csp.length === 0, "no CSP violations " + JSON.stringify(csp));
  ok(errs.length === 0, "no JS errors " + JSON.stringify(errs));

  const dctx = await b.newContext({ viewport: { width: 1280, height: 900 } }); const dp = await login(dctx, adminCreds);
  await dp.goto(base + "/staff/insights"); await dp.waitForSelector(".stats.six"); await dp.waitForTimeout(600);
  await dp.screenshot({ path: "/tmp/shots/insights-1280.png", fullPage: true });

  if (fs.existsSync(process.env.AXE || "/tmp/axe.min.js")) {
    await dp.evaluate(fs.readFileSync(process.env.AXE || "/tmp/axe.min.js", "utf8"));
    const r = await dp.evaluate(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"] } }));
    ok(r.violations.length === 0, "axe: " + r.violations.length + " violations " + r.violations.map((v) => v.id + "(" + v.nodes.length + ")").join(","));
    for (const v of r.violations) console.log("   -", v.impact, v.id, v.help, v.nodes[0].target.join(" "));
  }
  await b.close();
})();
