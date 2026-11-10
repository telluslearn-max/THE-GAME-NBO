// Regression test for the storefront script. Run against a prod-mode server: node scripts/e2e_menu.js
const { chromium } = require("playwright");
(async()=>{
 const b=await chromium.launch(); const ctx=await b.newContext({viewport:{width:375,height:812},deviceScaleFactor:2,isMobile:true,hasTouch:true}); const p=await ctx.newPage(); p.setDefaultTimeout(3000);
 const errs=[]; p.on("pageerror",e=>errs.push(e.message));
 await p.goto("http://localhost:4100/menu",{waitUntil:"networkidle"});
 const g='#c-popular .row[data-name="KC Ginger"]';
 await p.tap(g+' [data-a="add"]'); await p.tap(g+' [data-a="inc"]');
 await p.tap('#c-popular .row[data-name="Coke"] [data-a="add"]');
 console.log("bar (want 3 drinks · KES 2,600):", await p.textContent(".cartbar .l"));
 await p.reload({waitUntil:"networkidle"}); console.log("after reload:", await p.textContent(".cartbar .l"));
 await p.fill("#q","torero"); console.log("fuzzy 'torero' ->", await p.$$eval(".row:not([hidden]) .name",e=>[...new Set(e.map(x=>x.textContent))]));
 await p.fill("#q","zzzz"); console.log("empty state shown:", await p.$eval("#none",e=>!e.hidden));
 await p.fill("#q","");
 const w='#c-popular .row[data-name="Water"]'; await p.tap(w+' [data-a="add"]');
 for(let i=0;i<20;i++) await p.tap(w+' [data-a="inc"]');
 console.log("cap (want 15 drinks):", await p.textContent(".cartbar .l"));
 await p.waitForTimeout(400); await p.screenshot({path:"/tmp/shots/cart-375.png"});
 console.log("errors:", errs);
 await b.close();
})();
