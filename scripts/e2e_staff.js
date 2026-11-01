// Regression test, two real browsers: customer orders+pays, staff see it live and move it,
// the customer's phone follows. Needs prodrun.sh and a staff user (owner@thegame.test).
const { chromium } = require("playwright");
const base = process.env.URL || "http://localhost:4100";
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const cust = await b.newContext({ viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const staff = await b.newContext({ viewport: { width: 1280, height: 800 } });
  const c = await cust.newPage(), s = await staff.newPage();
  c.setDefaultTimeout(20000); s.setDefaultTimeout(20000);
  const errs = []; c.on("pageerror", (e) => errs.push("c:" + e.message)); s.on("pageerror", (e) => errs.push("s:" + e.message));

  // staff signs in first, board open and empty-ish
  await s.goto(base + "/staff");
  ok(s.url().endsWith("/staff/login"), "unauthenticated /staff goes to login");
  await s.fill("#email", "owner@thegame.test"); await s.fill("#password", "a long staff passphrase");
  await s.click("button[type=submit]");
  await s.waitForSelector("#board");
  await s.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  ok(true, "staff signed in, board live");

  // customer orders
  await c.goto(base + "/", { waitUntil: "networkidle" });
  await c.evaluate(() => localStorage.clear()); await c.reload({ waitUntil: "networkidle" });
  await c.tap('#c-popular .row[data-name="Water"] [data-a="add"]');
  await c.tap(".cartbar a"); await c.waitForURL("**/cart"); await c.waitForSelector("#lines .row");
  await c.fill("#phone", "0744 " + Math.floor(100 + Math.random() * 899) + " " + Math.floor(100 + Math.random() * 899));
  await Promise.all([c.waitForURL(/\/order\/[0-9a-f-]{36}/), c.tap("#pay")]);
  await c.waitForSelector("text=Paid. The bar has your order");
  const code = (await c.textContent(".ticket-code")).trim();
  ok(/^[A-Z0-9]{4}$/.test(code), "customer paid, pickup code " + code);

  // staff sees it appear without reloading
  await s.waitForSelector(`.scode:text("${code}")`);
  ok(true, "order appeared on the staff board live");
  await s.screenshot({ path: "/tmp/shots/staff-board-1280.png" });

  const card = s.locator(`article:has(.scode:text("${code}"))`);
  await card.getByRole("button", { name: "Start" }).click();
  await c.waitForSelector("text=Being prepared");
  ok(true, "customer sees 'Being prepared'");
  await card.getByRole("button", { name: "Ready" }).click();
  await c.waitForSelector("text=Ready. Your waiter will bring it");
  ok((await c.getAttribute("#ticket", "data-status")) === "ready", "customer ticket is ready (alert hook armed)");
  await c.screenshot({ path: "/tmp/shots/customer-ready-375.png" });
  // waiter flow: type name once, "I've got this one", then Delivered
  await s.fill("#waiter", "Amina");
  await card.getByRole("button", { name: "I’ve got this one" }).click();
  await s.waitForSelector(`article:has(.scode:text("${code}")) >> text=You have this`);
  ok(true, "waiter claimed the order");
  await card.getByRole("button", { name: "Delivered" }).click();
  await c.waitForSelector("text=Delivered. Enjoy");
  ok(true, "delivered flows through");
  ok(errs.length === 0, "no JS errors " + JSON.stringify(errs));

  // staff on a phone
  const sp = await (await b.newContext({ viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true })).newPage();
  await sp.goto(base + "/staff/login"); await sp.fill("#email", "owner@thegame.test"); await sp.fill("#password", "a long staff passphrase"); await sp.click("button[type=submit]");
  await sp.waitForSelector("#board");
  const ov = await sp.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  ok(ov <= 0, "no horizontal overflow on staff board at 375px");
  await sp.screenshot({ path: "/tmp/shots/staff-board-375.png" });
  await b.close();
})();
