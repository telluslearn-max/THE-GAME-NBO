// Regression test: pay by till. Client orders and sees the till steps; waiter writes the M-Pesa
// code + time and takes it to the counter; "Confirmed at counter" makes it paid; bar and delivery follow.
// Needs a prod-mode server with the automatic prompt OFF:  AUTO_PROMPT=false ./scripts/prodrun.sh
const { chromium } = require("playwright");
const base = process.env.URL || "http://localhost:4100";
const email = process.env.STAFF_EMAIL || "owner@thegame.test", password = process.env.STAFF_PASSWORD || "a long staff passphrase";
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const cust = await b.newContext({ viewport: { width: 375, height: 812 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, permissions: ["clipboard-read", "clipboard-write"] });
  const staff = await b.newContext({ viewport: { width: 1280, height: 800 } });
  const c = await cust.newPage(), s = await staff.newPage();
  c.setDefaultTimeout(20000); s.setDefaultTimeout(20000);
  const errs = []; c.on("pageerror", (e) => errs.push("c:" + e.message)); s.on("pageerror", (e) => errs.push("s:" + e.message));

  await s.goto(base + "/staff/login"); await s.fill("#email", email); await s.fill("#password", password); await s.click("button[type=submit]");
  await s.waitForSelector("#board"); await s.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());

  await c.goto(base + "/", { waitUntil: "networkidle" });
  await c.evaluate(() => localStorage.clear()); await c.reload({ waitUntil: "networkidle" });
  await c.tap('#c-popular .row[data-name="Water"] [data-a="add"]'); await c.tap('#c-popular .row[data-name="Water"] [data-a="inc"]');
  await c.tap(".cartbar a"); await c.waitForURL("**/cart"); await c.waitForSelector("#lines .row");
  const phoneNum = "0755 " + Math.floor(100 + Math.random() * 899) + " " + Math.floor(100 + Math.random() * 899);
  await c.fill("#phone", phoneNum);
  await Promise.all([c.waitForURL(/\/order\/[0-9a-f-]{36}/), c.tap("#pay")]);
  await c.waitForSelector(".till"); const orderUrl = c.url(); await c.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected());
  const code = (await c.textContent(".ticket-code")).trim();
  ok(/^[A-Z0-9]{4}$/.test(code), "client sees their order reference " + code);
  ok(!(await c.textContent("body")).toLowerCase().includes("tell your waiter your code"), "client is not told to give a code to the waiter");
  ok((await c.textContent(".cancelsec")).includes("Don’t enter your PIN"), "a Cancel section with the don't-pay-twice warning");
  ok((await c.textContent(".dont")).includes("Don’t pay again"), "'Already paid? Don't pay again' is shown");
  ok((await c.textContent(".till")).includes("3308963") && (await c.textContent(".till")).includes("KES 200"), "till number and exact amount shown");
  ok(!(await c.textContent("body")).includes("Check your phone"), "no M-Pesa prompt was sent");
  await c.click("#copy-till");
  ok((await c.evaluate(() => navigator.clipboard.readText())) === "3308963", "Copy puts the till number on the clipboard");
  await c.click("#copy-amount");
  ok((await c.evaluate(() => navigator.clipboard.readText())) === "200", "Copy puts the exact amount on the clipboard");
  await c.screenshot({ path: "/tmp/shots/till-375.png" });

  // while this order is unpaid, the same number cannot start another one
  await c.goto(base + "/", { waitUntil: "networkidle" });
  await c.tap('#c-popular .row[data-name="Water"] [data-a="add"]');
  await c.tap(".cartbar a"); await c.waitForURL("**/cart"); await c.waitForSelector("#lines .row");
  ok(!(await c.textContent("body")).includes("3308963"), "the cart shows no payment details");
  await c.fill("#phone", phoneNum);
  await c.waitForSelector("#blocked:not([hidden])");
  ok((await c.textContent("#pay")).includes("Finish or cancel the unpaid order first") && (await c.$eval("#pay", (e) => e.disabled)), "Pay is disabled while the number has an unpaid order");
  ok((await c.getAttribute("#blocked-open", "href")) === new URL(orderUrl).pathname, "link to the client's own unpaid order");
  await c.fill("#phone", "0766 " + Math.floor(100 + Math.random() * 899) + " " + Math.floor(100 + Math.random() * 899));
  await c.waitForSelector("#blocked", { state: "hidden" });
  ok(!(await c.$eval("#pay", (e) => e.disabled)), "a different number is not blocked");
  await c.goto(orderUrl, { waitUntil: "networkidle" }); await c.waitForSelector(".till");

  // waiter: the unpaid order appears under "Waiting for payment"
  const card = s.locator(`article:has(.scode:text("${code}"))`);
  await card.waitFor();
  ok((await s.textContent("#board")).includes("Waiting for payment") && (await card.textContent()).includes("Unpaid"), "order is under Waiting for payment");
  await s.fill("#waiter", "Amina");
  await card.locator("input.last4").fill("K932"); await card.locator("input.time").fill("4:52 PM");
  await card.getByRole("button", { name: "I’ve got this one" }).click();
  await c.waitForSelector("text=has your payment details and is confirming your payment");
  ok(true, "client sees Amina has their payment details");
  await card.screenshot({ path: "/tmp/shots/till-waiter-card.png" });
  const txt = await card.textContent();
  ok(txt.includes("K932") && txt.includes("4:52 PM") && txt.includes("KES 200") && txt.includes("2×") && txt.includes("Water"), "her card shows the drinks, the amount, the time and the code she wrote");
  ok(!(await c.textContent("body")).includes("Yes, cancel"), "client can no longer cancel once the waiter has their details");

  // the counter confirmed on the POS -> one tap
  await card.getByRole("button", { name: "Confirmed at counter" }).click();
  await c.waitForSelector("text=Paid. The bar has your order");
  ok((await c.textContent(".served")).includes("Amina"), "client: paid, served by Amina");
  ok((await c.textContent("body")).includes("Payment confirmed at the till"), "client sees 'Payment confirmed at the till'");
  await card.getByRole("button", { name: "Start" }).click(); await c.waitForSelector("text=Being prepared");
  await card.getByRole("button", { name: "Ready" }).click(); await c.waitForSelector("text=Amina will bring it");
  await card.getByRole("button", { name: "Delivered" }).click(); await c.waitForSelector("text=Delivered by Amina");
  ok(true, "bar and delivery follow");
  ok(errs.length === 0, "no JS errors " + JSON.stringify(errs));
  await b.close();
})();
