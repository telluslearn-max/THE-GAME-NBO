// THE GAME — live pages (order status, staff). Loaded only where LiveView is used.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

const pad = (n) => String(n).padStart(2, "0");

function chime() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    [880, 1320].forEach((f, i) => {
      const o = ctx.createOscillator(), g = ctx.createGain(), t = ctx.currentTime + i * 0.18;
      o.type = "sine"; o.frequency.value = f; o.connect(g); g.connect(ctx.destination);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.35, t + 0.04);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.5);
      o.start(t); o.stop(t + 0.5);
    });
  } catch (e) {}
}

const Hooks = {
  // Staff board: ring when the count of new (paid) orders goes up.
  QueueBell: {
    mounted() { this.n = +this.el.dataset.new; },
    updated() {
      const n = +this.el.dataset.new;
      if (n > this.n) { chime(); if (navigator.vibrate) navigator.vibrate([200, 100, 200]); }
      this.n = n;
    },
  },

  // Ticking mm:ss until a deadline. When it hits zero, ask the server to re-evaluate.
  Countdown: {
    mounted() { this.start(); },
    updated() { this.start(); },
    destroyed() { clearInterval(this.t); },
    start() {
      clearInterval(this.t);
      const until = +this.el.dataset.until;
      const tick = () => {
        const s = Math.max(0, Math.ceil((until - Date.now()) / 1000));
        this.el.textContent = Math.floor(s / 60) + ":" + pad(s % 60);
        if (s === 0) { clearInterval(this.t); this.pushEvent("refresh", {}); }
      };
      tick();
      this.t = setInterval(tick, 1000);
    },
  },

  // Loud, unmissable "your drinks are ready": chime + vibration. A short buzz on payment.
  Alert: {
    mounted() { this.prev = this.el.dataset.status; },
    updated() {
      const now = this.el.dataset.status;
      if (now === "ready" && this.prev !== "ready") {
        this.chime();
        if (navigator.vibrate) navigator.vibrate([400, 150, 400, 150, 400]);
      } else if (now === "paid" && this.prev === "pending_payment") {
        if (navigator.vibrate) navigator.vibrate([180, 90, 180]);
      }
      this.prev = now;
    },
    chime() { chime(); },
  },
};

const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const live = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrf },
  hooks: Hooks,
  longPollFallbackMs: 2500, // poor networks: fall back to long-polling instead of failing
});
live.connect();
window.liveSocket = live;
