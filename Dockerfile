# THE GAME. Build on the official Elixir image, run the release on slim Debian (same glibc).
FROM elixir:1.18 AS build
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile
COPY priv priv
COPY lib lib
COPY assets assets
RUN mix assets.setup && mix assets.deploy
RUN mix compile
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

FROM debian:bookworm-slim AS app
RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 MIX_ENV=prod
WORKDIR /app
RUN useradd --system --home /app app && chown app /app
COPY --from=build --chown=app:root /app/_build/prod/rel/the_game ./
USER app
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s CMD curl -fsS http://localhost:${PORT:-4000}/healthz || exit 1
# Migrate (and bootstrap staff/menu from env on first boot), then serve. Render provides PORT.
CMD ["sh", "-c", "/app/bin/migrate && /app/bin/server"]
