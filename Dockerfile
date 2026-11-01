# THE GAME: multi-stage build. Final image is ~100 MB, runs as an unprivileged user.
ARG ELIXIR_VERSION=1.18.6
ARG OTP_VERSION=27.3.4.9
ARG DEBIAN_VERSION=bookworm-20260202-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION} AS build
RUN apt-get update -y && apt-get install -y build-essential git && apt-get clean && rm -f /var/lib/apt/lists/*_*
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

FROM debian:bookworm-20260202-slim AS app
RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 MIX_ENV=prod
WORKDIR /app
RUN useradd --system --home /app app && chown app /app
COPY --from=build --chown=app:root /app/_build/prod/rel/the_game ./
USER app
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s CMD curl -fsS http://localhost:4000/healthz || exit 1
EXPOSE 4000
CMD ["/app/bin/server"]
