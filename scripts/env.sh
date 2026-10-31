# source scripts/env.sh : toolchain env for this container (Elixir 1.17 / OTP 25 / Postgres 16)
export PATH=/opt/elixir/bin:$PATH LANG=C.UTF-8 LC_ALL=C.UTF-8
service postgresql start >/dev/null 2>&1 || true
