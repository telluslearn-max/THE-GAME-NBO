#!/usr/bin/env bash
# The QC gate. Run before every merge:   ./scripts/qc.sh
# Static + unit gate always; browser/budget gate when a prod-mode server is up on :4100
# (start one with ./scripts/prodrun.sh).
set -u
source "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
fail=0
step() { printf '\n== %s\n' "$1"; shift; "$@" || { echo "FAILED: $*"; fail=1; }; }

step "format"          mix format --check-formatted
step "compile (warnings are errors)" mix compile --force --warnings-as-errors
step "tests"           mix test

if curl -fs -o /dev/null http://localhost:4100/; then
  step "performance budgets" node scripts/budget.js
  [ -f /tmp/axe.min.js ] && step "accessibility (axe-core)" node scripts/a11y.js || echo "(skipping a11y: npm i axe-core and copy axe.min.js to /tmp/axe.min.js)"
  for t in e2e_menu e2e_checkout e2e_order e2e_staff e2e_pwa; do
    step "browser: $t"  node scripts/$t.js
  done
else
  echo; echo "(skipping browser/budget gate: no server on :4100; run ./scripts/prodrun.sh)"
fi
echo; [ $fail -eq 0 ] && echo "QC PASSED" || { echo "QC FAILED"; exit 1; }
