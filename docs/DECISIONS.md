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
| 16 | **The claim code has two halves, and the waiter proves both from the client's phone.** First 4 characters: system pickup code on the client's page. After paying, the client also gets an M-Pesa SMS. The waiter reads it off the client's phone and types the **last 4 characters of the M-Pesa code and the time paid**, then taps "I've got this one". Both must match the payment Safaricom reported (time within 3 minutes; 24h or AM/PM accepted), so a faked or old SMS cannot be claimed. Her slip then shows the **actual** values from the system: `CODE·LAST4`, payment time (Safaricom's TransactionDate, EAT), amount, order, waiter name. Waiters never see the full M-Pesa code before claiming. What she typed is kept on screen after a mistake. | `Orders.claim/4`, `orders.mpesa_paid_at`. |
