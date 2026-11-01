# THE GAME

Order drinks from your table, pay with M-Pesa, collect with a code. Elixir / Phoenix LiveView,
built to be small on the wire, fast on a cheap phone and safe with money.

| | |
|---|---|
| First visit, menu | **8.3 KB** (brotli): HTML 1.9 + CSS 2.7 + JS 1.4 + logo 2.2 (cached forever) |
| Repeat visit | 1 request (menu HTML revalidating); CSS/JS from the service worker |
| Works offline | menu, cart; money pages deliberately never cached |
| Live order page | 39 KB (includes the LiveView client, loaded only there) |
| Stack | Phoenix 1.7, LiveView, Ecto/Postgres, no UI framework, no Oban, no Tailwind |

## Run it

```bash
source scripts/env.sh            # this container's toolchain; elsewhere: Elixir 1.18 / OTP 27
mix setup                        # deps, db, migrations, seed menu, assets
mix the_game.staff.create you@bar.test "a long passphrase"
mix phx.server                   # http://localhost:4000  (staff: /staff)
```
Dev uses a fake M-Pesa that approves every prompt after 4 s, through the real callback code path.

## Quality gate

```bash
./scripts/prodrun.sh &           # prod-mode server on :4100 (fake gateway)
./scripts/qc.sh                  # format, warnings-as-errors, tests, byte budgets, axe a11y, 5 browser flows
./scripts/release_smoke.sh       # real `mix release` booted against a brand-new database
```

## Future features
Bookings (`/book`) ship as requests that staff confirm by phone or WhatsApp. Next:
- **Deposit and minimum spend online.** Take a deposit by M-Pesa when a booking is agreed, and show a minimum spend once the owner sets one. Today no figures are stated and any deposit goes through the existing M-Pesa routine.
- **Real VIP offering.** Replace the placeholder perks and options (`BookingHTML.vip_perks/0`, `Booking.vip_options/0`) with what the venue actually offers.
- **Stronger spam protection.** Today: a hidden field, a 10-minute duplicate return and a 5-per-hour cap per phone. Add a captcha or similar only if abuse appears.
- **Customer notifications.** Email or SMS when a request is received and when it is confirmed (needs a provider). Staff-side alerts beyond the live count on `/staff/bookings`.
- **Table availability.** Check requests against capacity once tables and limits are known.

## Docs
- `docs/STUDY.md` the incumbent site, reverse-engineered
- `docs/BRIEF.md`, `docs/PHASES.md` the brief and the phase gates
- `docs/DECISIONS.md` every default chosen and why
- `docs/RUNBOOK.md` deploy and operate
- `docs/QC_REPORT.md` what was verified, and what was not
