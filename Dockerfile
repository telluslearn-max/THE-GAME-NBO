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

# Run on the very image we built on: the release bundles its own Erlang runtime, which must
# match the host libc exactly (a different Debian here fails with "GLIBC not found").
FROM elixir:1.18 AS app
ENV LANG=C.UTF-8 MIX_ENV=prod
WORKDIR /app
RUN useradd --system --home /app app && chown app /app
COPY --from=build --chown=app:root /app/_build/prod/rel/the_game ./
USER app
EXPOSE 4000
# Migrate (and bootstrap staff/menu from env on first boot), then serve. Render provides PORT.
CMD ["sh", "-c", "/app/bin/migrate && /app/bin/server"]
