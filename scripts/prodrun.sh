#!/usr/bin/env bash
# Local prod-mode server for measurement: ./scripts/prodrun.sh  (port 4100)
source "$(dirname "$0")/env.sh"
export MIX_ENV=prod PHX_SERVER=true PORT=4100 PHX_HOST=localhost \
  SECRET_KEY_BASE=$(printf 'x%.0s' {1..64}) \
  DATABASE_URL=ecto://postgres:postgres@localhost/the_game_dev
cd "$(dirname "$0")/.."
mix deps.get --only prod >/dev/null && mix assets.deploy >/dev/null && exec mix phx.server
