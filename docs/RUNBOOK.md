# Runbook

## Admin login and Insights
Set `ADMIN_EMAIL` and `ADMIN_PASSWORD` (a strong one) to create the owner's login on boot; it lands on **Insights**
(revenue, busiest hours, top drinks, till vs prompt, delivery speed, orders per waiter, low stock, unsold items).
Waiters and bar staff keep the shared staff login and never see Insights. Staff can add menu items on the **Menu** page,
including a new category. `STAFF_RESET_PASSWORD=true` also re-applies `ADMIN_PASSWORD` on boot; remove the flag afterwards.

## Till payments (the main way to pay)
Set `TILL_NUMBER` to the Buy Goods till number clients pay. With no Safaricom API credentials, set
`MPESA_ADAPTER=none` (no `MPESA_CALLBACK_TOKEN` needed); the prompt button then disappears and the till is the only way to pay.
Flow at the bar: client pays the till → waiter writes the M-Pesa code (last 4) and time → counter matches it on the POS →
waiter taps **Confirmed at counter** → bar prepares → waiter delivers. Orders held 30 minutes while unpaid.
`AUTO_PROMPT=true` additionally sends an M-Pesa prompt automatically (needs a working gateway).

## Deploy (one venue, one box)
1. `cd deploy && cp .env.example .env` and fill it in (`SECRET_KEY_BASE`, `MPESA_CALLBACK_TOKEN`, DB password, hostname).
2. Point DNS for `PHX_HOST` at the server. `docker compose up -d`. Caddy gets the certificate; the app migrates on boot.
3. Create the first staff login:
   `docker compose exec app /app/bin/the_game eval 'TheGame.Release.create_staff("owner@bar.com", "a long passphrase")'`
4. Optional starter menu: `... eval "TheGame.Release.seed()"`, then edit everything in **/staff/menu**.
5. M-Pesa: register the callback `https://<host>/mpesa/callback/<MPESA_CALLBACK_TOKEN>` in the Daraja portal. **Test in the Daraja sandbox first** (`MPESA_BASE_URL=https://sandbox.safaricom.co.ke`), then switch to `https://api.safaricom.co.ke`.
6. Verify: `curl https://<host>/healthz` returns `ok`; place a real KES 10 order and watch it on /staff.

## During service
- **Pause ordering** (stock count): the switch top right on any staff screen. Customers see why and are told not to pay at the till.
- **Board**: new paid orders ring; Start, Ready, Collected. Customers' phones follow live.
- **Lost phone / lost cookie**: find the order on the Board by its 4-character code.

## Money problems (`/staff` → Payments)
Anything that did not cleanly settle an order lands here and flags the order. Nothing is automatic.
- *Paid after expiry / cancel*: **Honour** sends it to the bar; otherwise refund and **Refunded / dismiss**.
- *Short* (paid less): collect the difference or refund.
- *Extra* (double / over): refund the excess in M-Pesa, then dismiss.
- Refunds are a manual M-Pesa reversal; the app records the decision, it does not move money.
- A customer who says "I paid but have no code": ask for the M-Pesa SMS. Search the receipt in Payments, or find the order by code.
- A prompt stuck "unresolved": the customer taps **Check payment** (asks Safaricom directly); the sweeper also reconciles every 10 s.

## Operations
- Backups: `docker compose exec db pg_dump -U the_game the_game > backup.sql` nightly; test a restore.
- Rotate the callback token: change `MPESA_CALLBACK_TOKEN`, restart, update the Daraja portal in the same minute.
- Staff accounts: create via `TheGame.Release.create_staff/2`; deactivate by setting `active=false` (access ends immediately).
- Logs: `docker compose logs app`; Caddy access log in the `caddy_data` volume.
- Load check before a big night: `node scripts/load.js https://<host>/ 200 10`.
