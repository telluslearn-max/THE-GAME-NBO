# QC report

## Gates, all green at the final commit
| Gate | Result |
|---|---|
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | clean |
| `mix test` | 124 tests, 0 failures, repeated runs stable (incl. concurrency races) |
| Performance budgets (`scripts/budget.js`) | all met; menu 6.4 KB, cart 6.8 KB, live order 39 KB (brotli) |
| Accessibility (axe-core, WCAG 2.x A/AA + best practice) | 0 violations on menu, cart, orders, order (2 states), offline, staff login |
| Browser flows (Chromium, real WebSocket) | menu, checkout, live order, two-browser customer+staff, PWA/offline |
| Responsive | no horizontal overflow at 320/375/414/768/1280 px |
| Release | `mix release` boots from its own binary on a fresh database; smoke script passes |
| Burst | 200 concurrent clients: ~2,300 req/s, 0 errors, p95 ~130 ms (shared sandbox) |

## Defects found by the gates and fixed
Cart double-counted a product listed in two categories; payment "latest" ordering tied within a second
(now microsecond timestamps); auto M-Pesa prompt could be triggered by anyone holding an order link (now only
the checking-out browser); invalid phone fell through order creation; contrast 3.29:1 (now 5.0:1); menu lacked h1/landmarks;
vulnerable pinned `jose` avoided by upgrading toolchain; staff styles shipped to customers (split out).

## NOT verified. Do these before taking real money
1. **Daraja against Safaricom.** The adapter matches the public docs and is request-shape tested, but has never talked to the sandbox or live API. Run the sandbox end to end, including a cancelled prompt, a timeout and a late callback.
2. **Web Push on real devices.** `web_push_elixir` uses the legacy `aesgcm` encoding. Verify on Android Chrome and an installed iOS PWA. Push is secondary; the page alert and staff board do not depend on it.
3. **Docker image.** No Docker daemon here; the Dockerfile, compose file and Caddyfile are written but unbuilt. The release they package is verified.
4. **Real devices and other browsers.** Only Chromium was driven. Check iOS Safari and a low-end Android (service worker, safe-area insets, audio unlock, vibration).
5. **Manual WCAG review** (screen reader pass, zoom, reduced motion). Automated axe only.
6. **Menu.** Seed data is only what was seen on the old site; real menu, images and variants (bottle vs tot) are the owner's.

## Known limits (see DECISIONS.md)
Single node (ETS rate limit and menu cache); refunds and C2B (paying the till by hand) are manual / unbuilt; one staff role.
