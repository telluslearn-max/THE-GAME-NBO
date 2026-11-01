#!/usr/bin/env bash
# Release gate: boot the real `mix release` against a brand-new database and smoke-test it.
#   ./scripts/release_smoke.sh      (needs: MIX_ENV=prod mix assets.deploy && mix release first)
set -eu
source "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
REL=_build/prod/rel/the_game/bin
DB=the_game_release PORT=4200
su postgres -c "psql -q -c 'drop database if exists $DB' -c 'create database $DB'" >/dev/null
export DATABASE_URL=ecto://postgres:postgres@localhost/$DB PORT=$PORT PHX_HOST=localhost \
  SECRET_KEY_BASE=$(head -c 64 /dev/urandom | base64 | tr -d '\n=') \
  MPESA_ADAPTER=fake MPESA_FAKE_AUTO_MS=2000 MPESA_CALLBACK_TOKEN=smoke-token AUTO_PROMPT=true TILL_NUMBER=3308963
echo "== migrate + bootstrap from env (staff login + starter menu)"
ADMIN_EMAIL=admin@thegame.test ADMIN_PASSWORD="a long admin passphrase" STAFF_EMAIL=owner@thegame.test STAFF_PASSWORD="a long staff passphrase" SEED_MENU=true $REL/migrate
echo "== start";        ($REL/server > /tmp/release.log 2>&1 &)
for i in $(seq 1 40); do curl -fs "http://localhost:$PORT/healthz" >/dev/null 2>&1 && break; sleep 1; done
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
check "healthz answers ok"          '[ "$(curl -fs http://localhost:$PORT/healthz)" = ok ]'
check "menu renders seeded drinks"  'curl -fs http://localhost:$PORT/ | grep -q "KC Ginger"'
check "menu feed is JSON"           'curl -fs http://localhost:$PORT/menu.json | grep -q "\"paused\":false"'
check "staff area demands login"    '[ "$(curl -s -o /dev/null -w %{http_code} http://localhost:$PORT/staff)" = 302 ]'
check "security headers present"    'curl -sI http://localhost:$PORT/ | grep -qi "content-security-policy"'
login_dest() { J=$(mktemp); T=$(curl -s -c $J localhost:$PORT/staff/login | grep -o 'name="_csrf_token" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"//'); curl -s -b $J -c $J -o /dev/null -w "%{redirect_url}" --data-urlencode "_csrf_token=$T" --data-urlencode "email=$1" --data-urlencode "password=$2" localhost:$PORT/staff/login; }
check "admin login (created from env) lands on Insights" '[ "$(login_dest admin@thegame.test "a long admin passphrase")" = "http://localhost:$PORT/staff/insights" ]'
check "staff login lands on the board, not Insights"     '[ "$(login_dest owner@thegame.test "a long staff passphrase")" = "http://localhost:$PORT/staff" ]'
check "manifest served"             'curl -fs http://localhost:$PORT/manifest.webmanifest | grep -q standalone'
check "service worker served"       'curl -fs http://localhost:$PORT/sw.js | grep -q "push"'
URL=http://localhost:$PORT node scripts/budget.js >/tmp/budget.out 2>&1 && echo "PASS performance budgets" || { echo "FAIL performance budgets"; tail -5 /tmp/budget.out; fail=1; }
URL=http://localhost:$PORT node scripts/e2e_order.js >/tmp/e2e.out 2>&1 && echo "PASS browser: order + live payment" || { echo "FAIL browser order flow"; tail -8 /tmp/e2e.out; fail=1; }
URL=http://localhost:$PORT node scripts/e2e_staff.js >/tmp/e2e2.out 2>&1 && echo "PASS browser: staff board" || { echo "FAIL browser staff"; tail -8 /tmp/e2e2.out; fail=1; }
$REL/the_game stop >/dev/null 2>&1 || true
[ $fail -eq 0 ] && echo "RELEASE SMOKE PASSED" || { echo "RELEASE SMOKE FAILED (see /tmp/release.log)"; exit 1; }
