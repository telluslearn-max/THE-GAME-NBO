#!/usr/bin/env node
// Burst test for the read path: node scripts/load.js [url] [concurrency] [seconds]
const url = process.argv[2] || "http://localhost:4100/";
const conc = +(process.argv[3] || 200), secs = +(process.argv[4] || 10);
const lat = []; let errors = 0, done = 0; const end = Date.now() + secs * 1000;
async function worker() {
  while (Date.now() < end) {
    const t = performance.now();
    try { const r = await fetch(url, { headers: { "accept-encoding": "gzip" } }); await r.arrayBuffer(); if (r.status !== 200) errors++; } catch (e) { errors++; }
    lat.push(performance.now() - t); done++;
  }
}
(async () => {
  await Promise.all(Array.from({ length: conc }, worker));
  lat.sort((a, b) => a - b); const q = (p) => lat[Math.floor(lat.length * p)].toFixed(1);
  console.log(`${url}  ${conc} concurrent x ${secs}s: ${done} requests, ${(done / secs).toFixed(0)} req/s, errors ${errors}`);
  console.log(`latency ms  p50 ${q(0.5)}  p95 ${q(0.95)}  p99 ${q(0.99)}  max ${lat[lat.length - 1].toFixed(1)}`);
  process.exit(errors ? 1 : 0);
})();
