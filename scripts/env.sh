# source scripts/env.sh : toolchain env for this container (Elixir 1.18 / OTP 27 / Postgres 16)
export PATH=/opt/otp27/OTP-27.3.4.9/bin:/opt/elixir18/bin:$PATH LANG=C.UTF-8 LC_ALL=C.UTF-8
service postgresql start >/dev/null 2>&1 || true
