# Study: destinationorder.com ("Destination Cocktails · Juja")

Purpose: understand the live product well enough to rebuild it in Elixir.

**Method and limits.** Everything here comes from the site's public pages, its
shipped client JS bundles, `manifest.webmanifest`, `sw.js`, and one public
`GET /api/menu` call. Nothing was authenticated or probed beyond what the
browser client itself does. Server behaviour (DB schema, M-Pesa integration,
expiry rules, staff tooling) is **inferred** from client code and is marked
*(inferred)*. Staff/admin screens are not visible from the client and still
need to be specified with the owner.

## 1. What it is

A mobile-first PWA for a bar. A customer opens the site, picks drinks, enters
the M-Pesa number that will pay, receives an STK push prompt, pays, and gets a
**pickup code** to show at the bar. When the order is ready the phone vibrates,
plays a chime, and (if subscribed) gets a Web Push notification. Staff prepare
and hand over the drinks.

- Prices are integer cents of KES (`price_cents: 125000` is KES 1,250). Displayed as `KES 1,250`.
- Times shown in `Africa/Nairobi` (EAT).
- Theme: dark ("ink" `#0a0a0c`) with gold accents, serif display font, max width ~`md` (phone column), bottom tab bar.

## 2. Architecture as deployed

| Piece | Observed |
|---|---|
| Web frontend | Next.js App Router (React, Tailwind), at `destinationorder.com`, behind Caddy |
| API | Separate origin `https://api.destinationorder.com` (CORS: `Vary: Origin`), JSON |
| CSP | `connect-src 'self' https://api.destinationorder.com`, nonce + `strict-dynamic` scripts, `frame-ancestors 'none'` |
| Same-origin routes | `/api/order-history` (Next route handler, see 5.4) |
| PWA | `manifest.webmanifest` (standalone, 512px icon), `sw.js` (push only, no offline caching) |
| Push | Web Push with VAPID; public key from `GET /api/push/vapid-public-key` |
| Payments | M-Pesa STK push (Daraja) *(inferred from `/pay/stk`, Paybill/till copy)* |

The frontend is thin: all money/state decisions are server-side. The client
sends `expected_total_cents` so the server can reject if prices moved.

## 3. Screens and routes

| Route | Screen | Notes |
|---|---|---|
| `/` | Menu | Splash ("WELCOME TO DESTINATION COCKTAILS · JUJA"), sticky header, fuzzy search (substring + Levenshtein, tolerance `max(1, len/3)`), categories (jump sheet opened by tapping Menu tab again), per-item Add / −N+ stepper, "Sold out" chip, pull-to-refresh, menu re-polled every 25 s and on focus/online/visibility. Shows a banner when `ordering_paused`. Shows an "unpaid order" card above the menu if one exists. |
| `/cart` | Cart + checkout | Lines with stepper/remove, live price/stock reconciliation against a fresh menu, total, M-Pesa number input, "this number has an unpaid order" guard, Place order. |
| `/order/[id]` | Order status | Polled every 4 s while visible. Payment/STK controls, countdown, pickup code, ready alert, cancel. |
| `/orders` | Order history | Saved orders from this browser, restore button, cancel for unpaid. |
| layout | Shell | Bottom nav (Menu / Cart with badge / Orders), offline banner, "opening…" interstitial that bridges to the main site (`target` + `orders` params, validated to `/orders` or `/order/<uuid>`). |

## 4. Domain model (from API shapes)

**Menu** `GET /api/menu`
```json
{ "ordering_paused": false,
  "categories": [ { "category": "Popular",
    "products": [ { "id": "<uuid>", "name": "KC Ginger", "price_cents": 125000, "in_stock": true } ] } ] }
```
- A product can appear in several categories (e.g. "Popular" and "Spirits" share ids); the client de-dupes by id in search.
- Categories seen: Popular, Cocktails, Spirits (plus more). Items: spirits by the bottle (KES 1,100 to 2,100), mixers (Coke, Lemonade, Water), Oris, two cocktails (KES 400).
- No images, descriptions, modifiers, or variants (bottle vs tot) in the payload.

**Order** `GET /api/orders/:id`
`id` (uuid), `status`, `items[{name, qty, ...}]`, `total_cents`, `pickup_code`,
`created_at`, `expires_at`, `payer_phone_last4`, `mpesa_code` (receipt),
`payment` `{status, position, cooldown_seconds, phone_busy}`,
`payment_review` `{status: PENDING|REFUNDED|CLOSED, kind: EXTRA|UNMATCHED}`,
`stk_retry_authorized`, `unresolved_stk`, `stk_wait_seconds`.

**Order status machine** (the statuses the client branches on)

```
PENDING_PAYMENT --paid--> PAID --> PREPARING --> READY --> COMPLETED
      |  \                                                  
      |   '--> FLAGGED   (needs staff attention)
      '--> EXPIRED (reservation timer lapsed)
      '--> CANCELLED (customer)
   (any) --> CLOSED (staff closed a payment review)
```
- `PENDING_PAYMENT` has a reservation countdown (`expires_at`); stock is held until then *(inferred)*.
- An order can sit in `PENDING_PAYMENT`/`EXPIRED`/`CANCELLED` with `payment_review.status = PENDING`: money arrived that doesn't cleanly match (late payment after expiry, or an unmatched/extra payment). UI says "Payment needs staff verification", tells the user not to pay again, and a staff resolution produces `REFUNDED` or `CLOSED`.

**STK payment sub-state** `payment.status`: `QUEUED | PROCESSING | SENT | FAILED` (plus
terminal success which flips the order to `PAID`). There is a per-phone queue
(`position`, `phone_busy`), a retry `cooldown_seconds`, and an
"unresolved STK" lock: after a timeout the user must run **pay/check**
(query STK status) before another prompt is allowed. This exists to prevent
double charges.

## 5. API contract

Base: `https://api.destinationorder.com`. JSON. Errors: `{"error": "msg", "code": "CODE"}`; 5xx is rewritten client-side to a generic "check the order status before trying again". Client timeout 15 s; non-GET requests are never auto-retried.

| Method + path | Body | Purpose |
|---|---|---|
| `GET /api/menu` | | Menu, `ordering_paused` |
| `POST /api/orders` | `{phone, payer_phone, expected_total_cents, items:[{product_id, qty}]}` | Create order (reserves stock). Errors: `PENDING_ORDER` (this phone already has an unpaid order), `ORDERING_PAUSED`; also total mismatch / sold out *(inferred)*. Returns `{id, ...}` |
| `GET /api/orders/:id` | | Order status (note: the client calls it with an empty base, so same-origin proxy, then the API) |
| `POST /api/orders/:id/cancel` | | Cancel unpaid order |
| `POST /api/orders/:id/pay/stk` | `{phone?}` | Send/queue an STK push. Error `STK_UNRESOLVED`. Returns `{cooldown_seconds}` |
| `POST /api/orders/:id/pay/check` | | Ask Safaricom whether the pending STK settled. Returns `{pending}` |
| `POST /api/checkout/status` | `{phone, order_ids[≤100], report_block}` | Does this phone have an unpaid order? Returns `{blocked, ...}`. Polled 15 s on the cart page |
| `GET /api/push/vapid-public-key` | | VAPID key |
| `POST /api/orders/:id/push-subscribe` | PushSubscription JSON | Register Web Push for "order ready" |
| `GET/POST /api/order-history` (same origin, Next) | `{ids:[uuid≤30]}` | Cookie-backed server-side backup of the browser's order ids (see 6) |

Phone validation (client and presumably server): `/^(0|\+?254)?[17]\d{8}$/` after stripping spaces. Max 15 units per order.

## 6. Notable behaviours worth preserving

1. **No accounts.** Identity = browser. Order ids are kept in `localStorage` + `sessionStorage` + a same-origin cookie-backed `/api/order-history` (max 30 uuids), merged on load, so clearing one store doesn't lose orders. Orders are reachable by unguessable uuid. (Rebuild: signed cookie + uuid links; consider optional phone-based lookup.)
2. **Money-safety UX.** Repeated copy: "Do not pay again", "ask staff", disabled retry during cooldown, `pay/check` before re-prompting, one unpaid order per phone, no automatic retry of POSTs. Treat this as a hard requirement, not polish.
3. **Price/stock honesty.** Cart re-fetches menu, flags sold-out lines, shows server price over cached price, sends `expected_total_cents`.
4. **Polling cadence.** Menu 25 s; cart checkout-status 15 s; order status 4 s (backs off once terminal); unpaid-orders card 15 s. In LiveView these become PubSub pushes.
5. **Ready alert.** On transition to `READY`: two-tone WebAudio chime, vibration `[400,150,400,150,400]`, pulsing green card, plus Web Push (`sw.js`: strong vibration, `requireInteraction`, tag `order-ready`, `renotify`). On `PAID`: short haptic.
6. **Ordering pause.** Staff can pause ordering (stock count); banner says not to pay at the till meanwhile.
7. **Pickup code** displayed large, plus M-Pesa receipt code after payment. Staff verifies by code at the bar.
8. **Stuck-payment recovery** ("Paid but no pickup code?", "Paid? Refresh payment status") routes to a staff-reviewed `payment_review` flow.

## 7. Unknowns to resolve before/while rebuilding

- Staff side: how orders are viewed, marked PREPARING/READY/COMPLETED, refunds, pausing, stock toggles, menu editing. Not visible from the client.
- Reservation TTL, STK cooldown length, queue discipline, max retry, how late payments are matched (account reference vs phone+amount).
- Safaricom setup: paybill/till, Daraja app, callback URL, whether C2B confirmation is also used for unmatched payments.
- Hosting/DB of the incumbent (Caddy in front; backend language unknown).
- Whether pickup codes are numeric/alphanumeric and their length.
- Branding assets (logo, `icon.png`) are the owner's to supply.

## 8. Elixir rebuild proposal

| Concern | Choice |
|---|---|
| Web | Phoenix 1.7+ with **LiveView** (menu, cart, order status update live over PubSub, no polling) |
| Persistence | Ecto + PostgreSQL. Tables: `products`, `categories`, `product_categories`, `orders`, `order_items`, `payments` (STK attempts), `payment_reviews`, `push_subscriptions`, `settings` (ordering_paused) |
| State machine | Pure module or `Ecto.Enum` + transition functions; one DB transaction per transition (e.g. `PENDING_PAYMENT → PAID` + stock decrement) |
| Stock reservation | Decrement on order create inside a transaction (`SELECT ... FOR UPDATE`), release on expire/cancel |
| Background jobs | **Oban**: order expiry at `expires_at`, STK status polling (`pay/check` auto-reconcile), reconciliation of late/unmatched payments |
| M-Pesa | Small `Mpesa` client over `Req` (OAuth token cache in ETS/`Cachex`), STK push + STK query + callback controller (verify, idempotent on `CheckoutRequestID`); Mox behaviour for tests, sandbox for dev |
| Per-phone queue | Oban unique jobs / `pg_advisory_xact_lock(phone_hash)` instead of a bespoke queue |
| Realtime | `Phoenix.PubSub` topics `order:<id>` and `menu`; LiveView JS hooks for chime/vibrate |
| Push | `web_push_elixir` (VAPID) + service worker ported from `sw.js` |
| Identity | Signed cookie holding order ids (≤30) + uuid links; no accounts |
| Staff | Separate authenticated LiveView area (`/staff`): queue board, mark preparing/ready/completed, payment reviews, menu & stock, pause toggle |
| Frontend | Tailwind, same dark/gold tokens; PWA manifest + SW |
| Ops | Releases + Docker, Caddy in front (as today), Postgres, Oban dashboard behind staff auth |

### Suggested milestones
1. Phoenix app, schema, seed menu from the captured `GET /api/menu` shape; menu + search + cart LiveViews (no payments).
2. Orders + state machine + stock reservation + expiry (Oban) + order status LiveView + pickup codes.
3. Daraja sandbox: STK push, callback, STK query, idempotency, cooldown/unresolved rules, payment reviews.
4. Staff app: queue board, ready action, pause ordering, stock/menu edit, refunds/review resolution.
5. Web Push + PWA polish, order-history cookie, offline banner.
6. Hardening: rate limits, CSP (match current), load test on a Friday-night burst, backups, runbook.

### Compatibility option
Keep the same JSON contract (section 5) in a Phoenix API so the existing Next
frontend can be pointed at it first, then replace the frontend with LiveView
later. Lower risk cut-over.
