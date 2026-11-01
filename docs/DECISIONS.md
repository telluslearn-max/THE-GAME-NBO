# Decisions

Defaults chosen where `STUDY.md` section 7 left unknowns. All are config or one function to change.

| # | Decision | Why / how to change |
|---|---|---|
| 1 | Reservation TTL 10 min | `:order_ttl_seconds` |
| 2 | STK cooldown 60 s; an older unresolved prompt must be checked (STK query) before another is sent | `:stk_cooldown_seconds`; mirrors the old site's "don't pay twice" rules |
| 3 | Pickup code: 4 chars from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0/O/1/I/L), unique among live orders | `Orders.gen_code/0` |
| 4 | Prices are whole shillings (`price_cents` multiple of 100); Daraja only charges whole KES | enforced in `Product.changeset` |
| 5 | **No Oban.** A 10 s `Sweeper` GenServer expires orders and reconciles prompts. State is all in Postgres with row locks, so restarts and extra nodes are safe | One fewer dependency and migration set, smaller release. Revisit if job volume grows |
| 6 | **No Tailwind / no UI framework.** ~9 KB hand-written CSS | byte budget, distinctive look |
| 7 | Order history is a signed HttpOnly cookie (max 30 ids) + unguessable order URLs. No accounts | matches the incumbent; staff can look up by pickup code |
| 8 | Orders are never revealed by phone number: a stranger typing a number learns nothing | tested |
| 9 | Callbacks are authenticated by a secret path token (`MPESA_CALLBACK_TOKEN`), matched to a payment we created, and idempotent. Safaricom does not sign callbacks | also reconcile by STK query |
| 10 | Late / short / extra / unmatched money becomes a `payment_review` and the order is `flagged`; staff resolve it. Nothing is auto-refunded | refunds are a manual M-Pesa reversal for now |
| 11 | Production refuses to boot without Daraja credentials unless `MPESA_ADAPTER=fake` is set explicitly | no silent fake in prod |
| 12 | C2B (customer pays the till/paybill by hand) matching is **not** built in v1 | would create `:unmatched` reviews; add when the owner wants it |
| 13 | Menu seed uses only items observed on the incumbent menu | owner must supply the real menu |
| 14 | Storefront JS is vanilla (no LiveView) on menu and cart; LiveView loads only on order status and staff pages | data budget |
| 15 | **The app blends into the existing floor routine; it does not replace the POS or retrain anyone.** The app does menu, payment (STK) and fast service. Waiters still take the customer's M-Pesa code and go to the POS counter, and the counter person still confirms on the POS before dispatch. The app only adds: "I've got this one" (a typed waiter name, no accounts), "Delivered" (replaces "Collected"), and the M-Pesa code, amount and time shown on every order card. No roles, no counter screen, no app-side gate on the POS step. | Deliberately rejected: counter confirmation gated in the app, per-waiter logins, hiding the receipt from staff. Revisit only if the owner asks. |
| 16 | **The pickup/claim code has two halves.** The first 4 characters are system-generated (the code on the client's page). The last 4 are the end of the M-Pesa code, which the waiter reads from the client's phone and types once when she taps "I've got this one". The 4 characters must match the payment Safaricom reported, so a faked SMS cannot be claimed. Waiters do not see the full M-Pesa code before claiming. Her slip then shows `CODE·LAST4`, time paid (from Safaricom, not typed), amount and the order. | `Orders.claim/3`. The typed timestamp is not collected: the system already holds the authoritative one. |
| 17 | **Bookings are requests, not held tables.** One `bookings` table and one form per kind: table (1 to 9), large group (10 to 300), event (birthday, corporate party, afterparty, graduation, other), collab (brand or creator), VIP. Staff confirm by phone or WhatsApp; the customer is told it is not confirmed until then. Studied from tsukutsukunairobi.com, whose reservation is request-then-deposit. | `TheGame.Bookings`. No availability engine, because capacity and tables are not known to the app. Add when the owner supplies them |
| 18 | **No deposit or minimum spend in the app.** The competitor charges a deposit online and quotes a KES 2,500 per head minimum. We state no number: the owner has not given any, and groups, events and VIP are quoted by a person. A deposit, once agreed, goes through the existing M-Pesa routine | add a payment kind to bookings if the owner wants it online |
| 19 | **VIP copy is a placeholder.** Four perks (reserved table, a host, bottle service, priority) and three options live in `BookingHTML.vip_perks/0` and `Booking.vip_options/0`. The owner must replace them with what the venue really offers | one function and one enum |
| 20 | **Spam and double taps:** a hidden "website" field (a filled one gets the normal thanks page and nothing is stored), the same phone, kind and date inside 10 minutes returns the earlier request, and a phone is capped at 5 requests an hour. No captcha, no third party. Dates are EAT, not in the past, within a year | `Bookings.create/2` |
| 21 | **Staff see requests at `/staff/bookings`**, live, with a count on the nav of every staff page, Call and WhatsApp buttons, and Contacted / Confirm / Decline / Done. The thank-you page offers WhatsApp only if `VENUE_WHATSAPP` is set. Customers get no email or SMS in v1 | email/SMS needs a provider the owner has not chosen |
