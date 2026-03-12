# Build stage
FROM elixir:1.17-alpine AS build

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files for dependency caching
COPY mix.exs mix.lock ./
COPY config/config.exs config/prod.exs config/runtime.exs config/

# Copy each app's mix.exs
COPY apps/readaloud_library/mix.exs apps/readaloud_library/
COPY apps/readaloud_reader/mix.exs apps/readaloud_reader/
COPY apps/readaloud_tts/mix.exs apps/readaloud_tts/
COPY apps/readaloud_importer/mix.exs apps/readaloud_importer/
COPY apps/readaloud_audiobook/mix.exs apps/readaloud_audiobook/
COPY apps/readaloud_web/mix.exs apps/readaloud_web/

RUN mix deps.get --only prod
RUN mix deps.compile

# Copy all source
COPY apps/ apps/

# Build assets
RUN cd apps/readaloud_web && mix assets.deploy

# Compile and create release
RUN mix compile
RUN mix release readaloud

# Runtime stage
FROM alpine:3.20

RUN apk add --no-cache \
    libstdc++ openssl ncurses-libs \
    calibre poppler-utils

WORKDIR /app

COPY --from=build /app/_build/prod/rel/readaloud ./

ENV DATABASE_PATH=/data/readaloud.db
ENV STORAGE_PATH=/data/files

EXPOSE 4000

CMD ["bin/readaloud", "start"]
