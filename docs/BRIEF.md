# THE GAME: engineering brief (optimized prompt)

## Mission
Rebuild the Destination Cocktails ordering product (see `STUDY.md`) as **THE GAME**,
an Elixir/Phoenix PWA for a Nairobi bar. A customer orders on their phone, pays with
M-Pesa STK push, and collects drinks with a pickup code. Staff run the bar from a queue
board. Quality bar: a flagship product from a top-tier design/engineering team. Nothing
generic, nothing filler.

## Non-negotiables
1. **Speed.** Menu first paint < 1.0 s on a throttled 3G / mid-range Android (Moto G class). Server-rendered HTML, critical CSS inline, no render-blocking requests, no web fonts download on first load (system font stack with a carefully tuned display treatment).
2. **Data frugality.** Budgets (gzip/brotli, first visit, menu page): HTML <= 14 KB, CSS <= 12 KB, JS <= 40 KB, zero images required to order (typography and CSS carry the design). Repeat visits < 3 KB via ETag/304 + immutable hashed assets. Live updates over a single WebSocket sending diffs, not polling.
3. **Responsive everywhere.** 320 px to tablet; safe-area insets; 44 px touch targets; works one-handed; landscape OK; respects `prefers-reduced-motion`, `prefers-color-scheme`, dynamic type.
4. **Resilient.** Works on flaky networks and offline-tolerant: menu and cart cached by the service worker, order status survives reconnects, no action silently double-submits. Idempotency on every money-touching call.
5. **Money safety.** Never double-charge, never lose a paid order. Every payment state is explicit, recoverable, and visible to staff.
6. **Accessible.** WCAG 2.2 AA: contrast, focus order, labels, live regions for status changes, keyboard operable.
7. **Design.** One distinctive art direction (dark, warm, confident, editorial type, restrained motion). No stock gradients, no emoji decoration, no lorem, no AI-looking cards-with-glow. Every pixel intentional.
8. **Engineering.** Phoenix 1.7 / LiveView / Ecto / Postgres / Oban. Context modules with clear boundaries, typespecs on public functions, tests for all domain logic and the payment state machine, `mix format`, `mix compile --warnings-as-errors` clean, secrets only via env.

## Scope: customer
Menu with categories and instant search, cart, checkout with Kenyan phone validation, STK push with clear progress, live order status, pickup code, ready alert (chime, vibration, Web Push), order history without accounts, cancel unpaid order, "paid but no code" recovery.

## Scope: staff (`/staff`)
Login, live order queue board (new, preparing, ready), one-tap transitions, payment review (unmatched or late payments, refund/close), menu and stock editing, pause ordering, daily totals.

## Out of scope for v1
Customer accounts, delivery, loyalty, multi-venue. (Design so they can be added.)

## Phases and QC gates
Each phase ends with its gate passing, a commit, and a pushed branch. A phase is not
"done" until its gate is green. See `PHASES.md`.

## Working rules for the autonomous loop
- Plan, build, verify, commit, push, then next phase. Do not stop between phases unless blocked on a decision only the owner can make.
- Verify by running things (tests, the server, curl, headless Chromium measurements), not by reading code.
- When a requirement is unknown (see `STUDY.md` section 7), choose a sensible default, isolate it in config, and record it in `DECISIONS.md`.
- Never fabricate Safaricom behaviour: payment code talks to a `Mpesa` behaviour with a sandbox-accurate fake for dev/test and a real Daraja adapter that is complete but unverified against live credentials; say so.
