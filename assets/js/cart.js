// THE GAME — cart page. Renders the saved cart, reconciles it against the live menu
// (price + stock) and posts it. The server re-validates everything; this is UX only.
(function () {
  var TG = window.TG;
  if (!TG) return;
  var $ = function (s) { return document.querySelector(s); };
  var form = $("#cart-form"), list = $("#lines"), empty = $("#cart-empty"), msg = $("#cart-msg");
  var pay = $("#pay"), totalEl = $("#total"), fItems = $("#f-items"), fTotal = $("#f-total");
  var paused = pay.disabled; // server-rendered pause state
  var cart = TG.read(), feed = null, notes = {};

  function ids() { return Object.keys(cart).filter(function (k) { return cart[k].q > 0; }); }
  function units() { return ids().reduce(function (n, k) { return n + cart[k].q; }, 0); }
  function gone(id) { return !!feed && (!feed.p[id] || !feed.p[id][1]); }

  function reconcile() {
    if (!feed) return;
    var changed = [];
    ids().forEach(function (id) {
      var live = feed.p[id];
      if (live && live[0] !== cart[id].p) { changed.push(cart[id].n); cart[id].p = live[0]; }
    });
    if (changed.length) { TG.write(cart); notes.price = "Updated price: " + changed.join(", ") + "."; }
    else delete notes.price;
    paused = paused || feed.paused;
    if (feed.paused) notes.paused = "Ordering is paused for a short stock count. Check back soon.";
    else delete notes.paused;
  }

  function render() {
    var keys = ids(), total = 0, blocked = false;
    list.textContent = "";
    keys.forEach(function (id) {
      var l = cart[id], out = gone(id), li = document.createElement("li");
      li.className = "row" + (out ? " out" : "");
      li.dataset.id = id; li.dataset.n = l.q;
      if (out) blocked = true; else total += l.q * l.p;
      li.innerHTML =
        '<div><span class="name"></span><span class="price"></span></div><div class="act"></div>';
      li.querySelector(".name").textContent = l.n;
      li.querySelector(".price").textContent = out ? "Sold out" : TG.kes(l.p) + (l.q > 1 ? " × " + l.q + " = " + TG.kes(l.p * l.q) : "");
      li.querySelector(".act").innerHTML = out
        ? '<button type="button" class="add" data-a="rm">Remove</button>'
        : '<span class="step" role="group"><button type="button" data-a="dec" aria-label="Remove one">−</button><output aria-live="polite">' + l.q + '</output><button type="button" data-a="inc" aria-label="Add one">+</button></span>';
      list.appendChild(li);
    });
    var any = keys.length > 0;
    form.hidden = !any; empty.hidden = any;
    totalEl.textContent = TG.kes(total);
    fItems.value = JSON.stringify(keys.filter(function (k) { return !gone(k); }).map(function (k) { return { id: k, q: cart[k].q }; }));
    fTotal.value = total;
    var n = Object.keys(notes).map(function (k) { return notes[k]; });
    if (blocked) n.push("Remove the sold-out drinks to continue.");
    msg.hidden = !n.length; msg.textContent = n.join(" ");
    pay.disabled = !any || blocked || paused || total <= 0;
    pay.textContent = paused ? "Ordering paused" : "Pay " + TG.kes(total) + " with M-Pesa";
  }

  list.addEventListener("click", function (e) {
    var b = e.target.closest("[data-a]"); if (!b) return;
    var id = b.closest(".row").dataset.id, q = cart[id].q;
    if (b.dataset.a === "inc") { if (units() >= TG.MAX) { notes.max = "Orders can hold up to " + TG.MAX + " drinks."; render(); return; } q++; }
    else if (b.dataset.a === "dec") q--; else q = 0;
    delete notes.max;
    if (q <= 0) delete cart[id]; else cart[id].q = q;
    TG.write(cart); render();
  });

  form.addEventListener("submit", function (e) {
    if (pay.disabled) { e.preventDefault(); return; }
    pay.disabled = true; pay.textContent = "Sending…"; // no double submits
  });
  window.addEventListener("pageshow", function (e) { if (e.persisted) { cart = TG.read(); render(); } });

  function refresh() {
    if (document.visibilityState === "hidden") return;
    fetch("/menu.json", { cache: "no-cache" }).then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { if (j) { feed = j; reconcile(); render(); } }).catch(function () {});
  }
  render(); refresh();
  setInterval(refresh, 25000);
  ["visibilitychange", "focus", "online"].forEach(function (ev) { window.addEventListener(ev, refresh); });
  window.addEventListener("storage", function (e) { if (e.key === "tg.cart.v1") { cart = TG.read(); render(); } });
})();
