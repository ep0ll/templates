# syntax=dexnore/dexfile:0
# Universal Production-Ready Ruby Dexfile
# Rails/Sinatra, Bootsnap, assets, bundler-audit, Puma, non-root slim

ARG RUBY_VERSION=3.3
ARG BUNDLE_WITHOUT="development:test"
ARG BUNDLE_PATH=/usr/local/bundle
ARG PORT=3000
ARG RAILS_ENV=production
ARG RACK_ENV=production
ARG ENABLE_BOOTSNAP=1
ARG ENABLE_ASSET_PRECOMPILE=1
ARG ENABLE_BUNDLE_AUDIT=1
ARG SECRET_KEY_BASE=dummy-for-assets-only
ARG SKIP_NODE=0
ARG NODE_VERSION=20
ARG APP_UID=10001
ARG APP_GID=10001
ARG APP_USER=dexfile
ARG TZ=UTC
ARG BUILD_IMAGE
ARG RUN_IMAGE

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN [ -f Gemfile ] || (echo "Gemfile required" >&2; exit 1)

FROM busybox:latest AS version-detector
WORKDIR /detect
COPY .ruby-version .tool-versions Gemfile Gemfile.lock* ./
RUN <<'D'
#!/bin/sh
V=""
[ -f .ruby-version ] && V=$(cat .ruby-version | tr -d 'v \t\r\n')
[ -z "$V" ] && [ -f .tool-versions ] && V=$(grep -E '^ruby\s' .tool-versions 2>/dev/null | awk '{print $2}' | tr -d 'v')
[ -z "$V" ] && V="3.3"
V=$(echo "$V" | grep -oE '^[0-9]+\.[0-9]+' || echo "$V")
echo "$V" > /ruby-version
D

FROM busybox:latest AS framework-detector
WORKDIR /detect
COPY Gemfile artisan* bin/rails* config/application.rb* config.ru* ./
RUN <<'D'
#!/bin/sh
FW="rack"
[ -f bin/rails ] || [ -f config/application.rb ] || grep -qE "gem ['\"]rails['\"]" Gemfile 2>/dev/null && FW="rails"
grep -qE "gem ['\"]sinatra['\"]" Gemfile 2>/dev/null && FW="sinatra"
grep -qE "gem ['\"]hanami['\"]" Gemfile 2>/dev/null && FW="hanami"
grep -qE "gem ['\"]roda['\"]" Gemfile 2>/dev/null && FW="roda"
echo "$FW" > /framework
D

FROM ${BUILD_IMAGE:-ruby:3.3-slim} AS base
WORKDIR /home/dexfile/app
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential libpq-dev libyaml-dev libffi-dev libssl-dev curl git \
    shared-mime-info libvips42 pkg-config && rm -rf /var/lib/apt/lists/*

FROM base AS gems
WORKDIR /home/dexfile/app
COPY Gemfile Gemfile.lock* ./
ARG BUNDLE_WITHOUT BUNDLE_PATH
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=${BUNDLE_WITHOUT} BUNDLE_PATH=${BUNDLE_PATH} BUNDLE_JOBS=4 BUNDLE_RETRY=3
RUN --mount=type=cache,target=/usr/local/bundle/cache,id=bundle-cache \
    bundle install && bundle clean --force 2>/dev/null || true

FROM base AS builder
WORKDIR /home/dexfile/app
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY . .
ARG RAILS_ENV RACK_ENV SECRET_KEY_BASE ENABLE_BOOTSNAP ENABLE_ASSET_PRECOMPILE BUNDLE_PATH
ENV RAILS_ENV=${RAILS_ENV} RACK_ENV=${RACK_ENV} SECRET_KEY_BASE=${SECRET_KEY_BASE} BUNDLE_PATH=${BUNDLE_PATH} BUNDLE_DEPLOYMENT=1
RUN if [ "${ENABLE_BOOTSNAP}" = "1" ] && bundle show bootsnap >/dev/null 2>&1; then \
      bundle exec bootsnap precompile --gemfile app/ lib/ config/ 2>/dev/null || \
      bundle exec bootsnap precompile app/ lib/ 2>/dev/null || true; fi
RUN if [ "${ENABLE_ASSET_PRECOMPILE}" = "1" ] && { [ -f bin/rails ] || [ -f config/application.rb ]; }; then \
      bundle exec rails assets:precompile 2>/dev/null || bundle exec rake assets:precompile 2>/dev/null || true; fi

FROM gems AS bundle-audit
ARG ENABLE_BUNDLE_AUDIT
RUN if [ "${ENABLE_BUNDLE_AUDIT}" = "1" ]; then \
      gem install bundler-audit --no-document && \
      bundle-audit check --update || (echo "audit issues; set ENABLE_BUNDLE_AUDIT=0" >&2; exit 1); \
    else echo "audit skipped"; fi

FROM ${RUN_IMAGE:-ruby:3.3-slim} AS prod
ARG PORT APP_UID APP_GID APP_USER TZ BUNDLE_PATH RAILS_ENV RACK_ENV
WORKDIR /home/dexfile/app
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    libpq5 libyaml-0-2 libffi8 libssl3 curl shared-mime-info libvips42 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid ${APP_GID} ${APP_USER} && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER}/app/tmp /home/${APP_USER}/app/log && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}
COPY --from=gems --chown=${APP_UID}:${APP_GID} /usr/local/bundle /usr/local/bundle
COPY --from=builder --chown=${APP_UID}:${APP_GID} /home/dexfile/app /home/dexfile/app
COPY --from=framework-detector /framework /etc/dexfile-framework
COPY --from=version-detector /ruby-version /etc/dexfile-ruby-version
ENV BUNDLE_PATH=${BUNDLE_PATH} BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test \
    RAILS_ENV=${RAILS_ENV} RACK_ENV=${RACK_ENV} RAILS_LOG_TO_STDOUT=1 \
    RAILS_SERVE_STATIC_FILES=true PORT=${PORT} HOME=/home/dexfile TZ=${TZ} MALLOC_ARENA_MAX=2
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile/app
EXPOSE ${PORT}
RUN printf '#!/bin/bash\nset -e\ncd /home/dexfile/app\nif [ -f bin/rails ]; then exec bundle exec puma -C config/puma.rb -b tcp://0.0.0.0:%s\nelif [ -f config.ru ]; then exec bundle exec puma -p %s -b tcp://0.0.0.0:%s config.ru\nelse exec bundle exec rackup -p %s -o 0.0.0.0\nfi\n' "$PORT" "$PORT" "$PORT" "$PORT" > /home/dexfile/app/entrypoint.sh && chmod +x /home/dexfile/app/entrypoint.sh
ENTRYPOINT ["/home/dexfile/app/entrypoint.sh"]

FROM prod AS release
ARG PORT=3000 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="Ruby Application" \
      security.non-root="true" security.uid="${APP_UID}" app.language="ruby" app.port="${PORT}"

FROM prod AS debug
USER 0
RUN apt-get update -qq && apt-get install --no-install-recommends -y bash curl procps && rm -rf /var/lib/apt/lists/*
USER ${APP_UID:-10001}:${APP_GID:-10001}

FROM release
