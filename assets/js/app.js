// THE GAME — storefront script. No framework, no dependencies. Budget: < 4 KB gzipped.
// The page works as plain HTML; this adds the cart, instant search and scroll-spy.
(function () {
  var KEY = "tg.cart.v1";
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  var read = function () {
    try { var c = JSON.parse(localStorage.getItem(KEY)); return c && typeof c === "object" ? c : {}; }
    catch (e) { return {}; }
  };
  var write = function (c) { try { localStorage.setItem(KEY, JSON.stringify(c)); } catch (e) {} };
  var kes = function (cents) { return "KES " + String(Math.round(cents / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ","); };
  var MAX = 15;

  window.TG = { read: read, write: write, kes: kes, MAX: MAX };

  var rows = $$(".row[data-id]");
  if (!rows.length) return; // not the menu page

  var cart = read();
  var bar = $(".cartbar");
  var barL = $(".cartbar .l");

  function units() { var n = 0; for (var k in cart) n += cart[k].q; return n; }

  function paint() {
    // Totals come from the cart (one entry per product), never from the rows: the same
    // product can be listed under several categories.
    var n = 0, total = 0, id;
    for (id in cart) { n += cart[id].q; total += cart[id].q * cart[id].p; }
    rows.forEach(function (row) {
      var line = cart[row.dataset.id];
      if (line && line.q > 0) { row.dataset.n = line.q; $("output", row).textContent = line.q; }
      else row.removeAttribute("data-n");
    });
    if (barL) barL.textContent = n + (n === 1 ? " drink" : " drinks") + " · " + kes(total);
    if (bar) bar.classList.toggle("on", n > 0);
  }

  function set(row, q) {
    var id = row.dataset.id;
    q = Math.max(0, q);
    if (q > 0 && units() - (cart[id] ? cart[id].q : 0) + q > MAX) { q = MAX - (units() - (cart[id] ? cart[id].q : 0)); if (q < 0) q = 0; }
    if (q === 0) delete cart[id];
    else cart[id] = { n: row.dataset.name, p: +row.dataset.price, q: q };
    write(cart); paint();
    if (navigator.vibrate) navigator.vibrate(8);
  }

  document.addEventListener("click", function (e) {
    var b = e.target.closest("[data-a]");
    if (!b) return;
    var row = b.closest(".row");
    var cur = cart[row.dataset.id] ? cart[row.dataset.id].q : 0;
    set(row, b.dataset.a === "add" ? 1 : b.dataset.a === "inc" ? cur + 1 : cur - 1);
  });

  window.addEventListener("storage", function (e) { if (e.key === KEY) { cart = read(); paint(); } });
  window.addEventListener("pageshow", function () { cart = read(); paint(); });
  paint();

  // ---- Instant fuzzy search (substring, word-prefix, or small edit distance) ----
  var q = $("#q"), clear = $("#qx"), none = $("#none"), secs = $$(".sec");
  function lev(a, b) {
    var p = [], i, j, t, c;
    for (j = 0; j <= b.length; j++) p[j] = j;
    for (i = 1; i <= a.length; i++) {
      t = p[0]; p[0] = i;
      for (j = 1; j <= b.length; j++) { c = p[j]; p[j] = Math.min(p[j] + 1, p[j - 1] + 1, t + (a[i - 1] === b[j - 1] ? 0 : 1)); t = c; }
    }
    return p[b.length];
  }
  function match(term, name) {
    if (name.indexOf(term) > -1) return true;
    var tol = Math.max(1, Math.floor(term.length / 3));
    if (term.length > 2 && lev(term, name) <= tol) return true;
    return name.split(/[^a-z0-9]+/).some(function (w) { return w && (w.indexOf(term) === 0 || (term.length > 2 && Math.abs(w.length - term.length) <= tol && lev(term, w) <= tol)); });
  }
  function filter() {
    var term = q.value.trim().toLowerCase(), shown = 0;
    clear.hidden = !term;
    rows.forEach(function (r) { var ok = !term || match(term, r.dataset.name.toLowerCase()); r.hidden = !ok; if (ok) shown++; });
    secs.forEach(function (s) { s.hidden = !$$(".row:not([hidden])", s).length; });
    none.hidden = !!shown;
    if (term) $("#none b").textContent = "No drinks match “" + q.value.trim() + "”";
  }
  if (q) {
    q.addEventListener("input", filter);
    clear.addEventListener("click", function () { q.value = ""; filter(); q.focus(); });
  }

  // ---- Category rail scroll-spy ----
  var chips = $$(".chip");
  if (chips.length && "IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (en) {
        if (!en.isIntersecting) return;
        chips.forEach(function (c) {
          var on = c.getAttribute("href") === "#" + en.target.id;
          c.setAttribute("aria-current", on);
          if (on && c.scrollIntoView) { var r = c.parentNode; r.scrollLeft = c.offsetLeft - 16; }
        });
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    secs.forEach(function (s) { io.observe(s); });
  }
})();
