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

  // Team: the manager adds a waiter, who sees only the board; promoting them widens their access
  const tp = dp; const who = "waiter-" + Math.floor(Math.random() * 1e6) + "@bar.test";
  await tp.goto(base + "/staff/team"); await tp.waitForSelector(".rolekey");
  await tp.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  ok((await tp.textContent("main")).includes("Floor staff"), "Team page explains the roles");
  await tp.click("summary:has-text('Add a person')");
  await tp.fill('form[phx-submit=add] input[name=name]', "E2E Waiter"); await tp.fill('form[phx-submit=add] input[name=email]', who);
  await tp.selectOption('form[phx-submit=add] select[name=role]', "waiter"); await tp.fill('form[phx-submit=add] input[name=password]', "Game1234");
  await tp.click('form[phx-submit=add] button[type=submit]'); await tp.waitForSelector("text=added as Waiter");
  ok(true, "manager added a waiter");
  const wctx = await b.newContext({ viewport: { width: 375, height: 812 } }); const wp = await login(wctx, [who, "Game1234"]);
  ok(wp.url().endsWith("/staff"), "the waiter lands on the board");
  const navLinks = async () => wp.$$eval("nav.snav a", (a) => a.map((x) => x.textContent.trim().replace(/\s+\d+$/, "")));
  ok(JSON.stringify(await navLinks()) === JSON.stringify(["Board"]), "the waiter's menu is just: Board — " + JSON.stringify(await navLinks()));
  ok((await wp.locator("button.switch").count()) === 0, "no pause switch for a waiter");
  await wp.goto(base + "/staff/menu"); await wp.waitForTimeout(1200);
  ok(!wp.url().endsWith("/menu"), "the waiter can't open Menu");
  await tp.selectOption("#u-" + (await tp.$eval('#main li:has-text("' + who + '")', (e) => e.id.slice(2))) + " select", "staff");
  await tp.waitForSelector("text=is now Floor staff");
  await wp.goto(base + "/staff"); await wp.waitForSelector("nav.snav");
  ok((await navLinks()).includes("Menu") && !(await navLinks()).includes("Team"), "after promotion to Floor staff: Menu appears, Team does not");
  if (fs.existsSync(process.env.AXE || "/tmp/axe.min.js")) {
    await tp.evaluate(fs.readFileSync(process.env.AXE || "/tmp/axe.min.js", "utf8"));
    const r = await tp.evaluate(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"] } }));
    ok(r.violations.length === 0, "axe on Team: " + r.violations.length + " violations " + r.violations.map((v) => v.id).join(","));
    for (const v of r.violations) console.log("   -", v.impact, v.id, v.help, v.nodes[0].target.join(" "));
  }
  await tp.screenshot({ path: "/tmp/shots/team-1280.png", fullPage: true });
  await b.close();
})();
