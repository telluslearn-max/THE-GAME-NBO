# Phases and QC gates

| # | Phase | Deliverable | Gate (must pass) |
|---|---|---|---|
| 0 | Foundation | Phoenix app, Postgres, CI-able `mix check`, brief/study docs | `mix test` green, `mix compile --warnings-as-errors`, `mix format --check-formatted` |
| 1 | Domain + data | Schemas/migrations: products, categories, orders, items, payments, reviews, push subs, settings. Seeds from the real menu shape. Order state machine + stock reservation | Unit tests for every legal and illegal transition, reservation race test, seeds load |
| 2 | Design system + menu | Tokens, type, layout shell, menu page with search, categories, add/stepper, pause banner | Headless-Chromium run at 320/375/414/768 px, no horizontal scroll; menu page within byte budget; Lighthouse-style metrics captured |
| 3 | Cart + checkout | Cart (client-side, tiny), reconciliation with server prices/stock, phone validation, order create | Tests for totals, `expected_total_cents` mismatch, one-unpaid-per-phone, 15-unit cap |
| 4 | Payments | `Mpesa` behaviour, fake + Daraja adapter, STK push, callback (idempotent), STK query, cooldown/unresolved rules, Oban expiry and reconcile | Payment state-machine tests, duplicate-callback test, late-payment-after-expiry goes to review |
| 5 | Order experience | LiveView order page: live status, countdown, pickup code, ready chime/vibration, cancel, recovery paths, order history cookie | LiveView tests for each status; PubSub update test |
| 6 | Staff app | Auth, queue board, transitions, payment reviews, stock/menu edit, pause toggle | Auth tests, authorization tests, transition tests, manual run-through |
| 7 | PWA + offline + push | Manifest, service worker (shell + menu cache), Web Push, offline banner | SW registers, offline menu loads, push subscription stored |
| 8 | Performance hardening | Compression, caching headers, CSP, asset budgets enforced by a script, query tuning | `mix perf.budget` passes; repeat-visit bytes measured |
| 9 | Release | Dockerfile/release config, runbook, env docs, final QC report | Release builds, boots against fresh DB, smoke test script green |

Every phase: implement, test, run, measure, fix, commit, push.
