# syntax=dexnore/dexfile:0
# Universal Production-Ready PHP Dexfile
# FrankenPHP (default), RoadRunner, FPM; Laravel/Symfony/WordPress; composer audit

ARG PHP_VERSION=8.3
ARG COMPOSER_VERSION=2
ARG APP_ENV=production
ARG APP_DEBUG=false
ARG PORT=8080
ARG ENABLE_COMPOSER_AUDIT=1
ARG ENABLE_OPCACHE=1
ARG ENABLE_JIT=1
ARG JIT_BUFFER_SIZE=128M
ARG MEMORY_LIMIT=256M
ARG DOCUMENT_ROOT=/app/public
ARG SKIP_NODE=0
ARG NODE_VERSION=20
ARG APP_UID=10001
ARG APP_GID=10001
ARG APP_USER=dexfile
ARG TZ=UTC
ARG ROADRUNNER_VERSION=2024.2
ARG BUILD_IMAGE
ARG RUN_IMAGE

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN [ -f composer.json ] || [ -f index.php ] || [ -f public/index.php ] || [ -f artisan ] || [ -f wp-config.php ] || \
    (echo "No PHP project markers" >&2; exit 1)

FROM busybox:latest AS version-detector
WORKDIR /detect
COPY .php-version .tool-versions composer.json ./
RUN <<'D'
#!/bin/sh
V=""
[ -f .php-version ] && V=$(cat .php-version | tr -d 'v \t\r\n')
[ -z "$V" ] && [ -f composer.json ] && V=$(grep -oE '"php"\s*:\s*"[^"]+' composer.json 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+')
[ -z "$V" ] && V="8.3"
echo "$V" > /php-version
D

FROM busybox:latest AS framework-detector
WORKDIR /detect
COPY composer.json artisan* bin/console* wp-config.php* config/application.rb* ./
RUN <<'D'
#!/bin/sh
FW="plain"; DOCROOT="public"
[ -f artisan ] || grep -qE '"laravel/framework"' composer.json 2>/dev/null && FW="laravel"
[ -f bin/console ] || grep -qE '"symfony/framework-bundle"' composer.json 2>/dev/null && FW="symfony"
[ -f wp-config.php ] && FW="wordpress" && DOCROOT="."
grep -qE '"drupal/core"' composer.json 2>/dev/null && FW="drupal"
grep -qE '"slim/slim"' composer.json 2>/dev/null && FW="slim"
[ -d public ] && DOCROOT="public"
[ -d web ] && DOCROOT="web"
echo "$FW" > /framework
echo "$DOCROOT" > /document-root
D

FROM composer:${COMPOSER_VERSION} AS composer-base
WORKDIR /app
COPY composer.json composer.lock* ./
ARG COMPOSER_ARGS="--no-dev --optimize-autoloader --classmap-authoritative --no-interaction"
ENV COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_HOME=/tmp/composer
RUN --mount=type=cache,target=/tmp/composer/cache,id=composer-cache \
    if [ -f composer.lock ]; then composer install ${COMPOSER_ARGS} --no-scripts; else composer update ${COMPOSER_ARGS} --no-scripts; fi

FROM composer-base AS builder
WORKDIR /app
COPY --from=composer-base /app/vendor /app/vendor
COPY . .
ARG APP_ENV
ENV APP_ENV=${APP_ENV} COMPOSER_ALLOW_SUPERUSER=1
RUN composer dump-autoload --optimize --classmap-authoritative 2>/dev/null || true
RUN if [ -f artisan ]; then \
      php artisan package:discover --ansi 2>/dev/null || true; \
      php artisan config:cache 2>/dev/null || true; \
      php artisan route:cache 2>/dev/null || true; \
      php artisan view:cache 2>/dev/null || true; \
    fi
RUN if [ -f bin/console ]; then php bin/console cache:warmup --env=prod 2>/dev/null || true; fi

FROM composer-base AS composer-audit
ARG ENABLE_COMPOSER_AUDIT
COPY composer.json composer.lock* ./
RUN if [ "${ENABLE_COMPOSER_AUDIT}" = "1" ]; then \
      composer audit --no-interaction || (echo "audit issues; set ENABLE_COMPOSER_AUDIT=0" >&2; exit 1); \
    else echo "audit skipped"; fi

FROM ${RUN_IMAGE:-dunglas/frankenphp:1-php8.3} AS prod-frankenphp
ARG PHP_VERSION PORT APP_UID APP_GID APP_USER TZ
ARG ENABLE_OPCACHE ENABLE_JIT JIT_BUFFER_SIZE MEMORY_LIMIT APP_ENV APP_DEBUG
WORKDIR /app
USER root
RUN install-php-extensions opcache pdo_mysql pdo_pgsql redis intl bcmath gd zip 2>/dev/null || \
    docker-php-ext-install opcache pdo_mysql 2>/dev/null || true
RUN printf '%s\n' "memory_limit=${MEMORY_LIMIT}" "expose_php=Off" "display_errors=Off" \
    "log_errors=On" "error_log=/dev/stderr" "date.timezone=${TZ}" > /usr/local/etc/php/conf.d/zz-production.ini
RUN if [ "${ENABLE_OPCACHE}" = "1" ]; then \
      printf '%s\n' "opcache.enable=1" "opcache.memory_consumption=256" "opcache.validate_timestamps=0" \
        "opcache.jit=1255" "opcache.jit_buffer_size=${JIT_BUFFER_SIZE}" > /usr/local/etc/php/conf.d/zz-opcache.ini; fi
RUN groupadd --system --gid ${APP_GID} ${APP_USER} 2>/dev/null || true && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} 2>/dev/null || true && \
    mkdir -p /home/${APP_USER} /app /data/caddy && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER} /app /data/caddy 2>/dev/null || true
COPY --from=builder --chown=${APP_UID}:${APP_GID} /app /app
COPY --from=framework-detector /framework /etc/dexfile-framework
COPY --from=version-detector /php-version /etc/dexfile-php-version
ENV APP_ENV=${APP_ENV} APP_DEBUG=${APP_DEBUG} SERVER_NAME=":${PORT}" HOME=/home/dexfile TZ=${TZ}
WORKDIR /app
USER ${APP_UID}:${APP_GID}
EXPOSE ${PORT}
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]

FROM php:${PHP_VERSION}-cli-bookworm AS prod-roadrunner
ARG PORT APP_UID APP_GID APP_USER TZ ROADRUNNER_VERSION APP_ENV
WORKDIR /app
RUN apt-get update -qq && apt-get install --no-install-recommends -y git unzip libzip-dev libpq-dev curl && \
    docker-php-ext-install pdo_mysql pdo_pgsql opcache zip && rm -rf /var/lib/apt/lists/*
RUN curl -sSL "https://github.com/roadrunner-server/roadrunner/releases/download/v${ROADRUNNER_VERSION}/roadrunner-${ROADRUNNER_VERSION}-linux-amd64.tar.gz" \
      | tar -xz -C /usr/local/bin --strip-components=1 2>/dev/null || \
    (curl -sSL https://github.com/roadrunner-server/roadrunner/releases/latest/download/roadrunner-linux-amd64 -o /usr/local/bin/rr && chmod +x /usr/local/bin/rr)
RUN groupadd --system --gid ${APP_GID} ${APP_USER} && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER} /app && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER} /app
COPY --from=builder --chown=${APP_UID}:${APP_GID} /app /app
RUN if [ ! -f /app/.rr.yaml ] && [ ! -f /app/.rr.yml ]; then \
      printf '%s\n' 'version: "3"' 'server:' '  command: "php public/index.php"' 'http:' '  address: 0.0.0.0:8080' \
        '  pool:' '    num_workers: 4' > /app/.rr.yaml; fi
ENV APP_ENV=${APP_ENV} HOME=/home/dexfile TZ=${TZ}
USER ${APP_UID}:${APP_GID}
WORKDIR /app
EXPOSE ${PORT}
CMD ["rr", "serve", "-c", ".rr.yaml"]

FROM php:${PHP_VERSION}-fpm-bookworm AS prod-fpm
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile APP_ENV=production MEMORY_LIMIT=256M TZ=UTC ENABLE_OPCACHE=1
RUN apt-get update -qq && apt-get install --no-install-recommends -y libzip-dev libpq-dev libpng-dev libicu-dev && \
    docker-php-ext-install pdo_mysql pdo_pgsql opcache zip bcmath intl gd && rm -rf /var/lib/apt/lists/*
RUN printf '%s\n' "memory_limit=${MEMORY_LIMIT}" "expose_php=Off" "display_errors=Off" "date.timezone=${TZ}" > /usr/local/etc/php/conf.d/zz-production.ini
RUN groupadd --system --gid ${APP_GID} ${APP_USER} 2>/dev/null || true && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} 2>/dev/null || true && \
    mkdir -p /home/${APP_USER} /app && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER} /app
COPY --from=builder --chown=${APP_UID}:${APP_GID} /app /app
ENV APP_ENV=${APP_ENV} HOME=/home/dexfile
WORKDIR /app
USER ${APP_UID}:${APP_GID}
EXPOSE 9000
CMD ["php-fpm", "-F"]

FROM prod-frankenphp AS prod
FROM prod AS release
ARG PORT=8080 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="PHP Application" \
      security.non-root="true" security.uid="${APP_UID}" app.language="php" app.port="${PORT}"

FROM prod AS artisan
ENTRYPOINT ["php", "artisan"]
CMD ["list"]

FROM prod AS migrate
CMD ["php", "artisan", "migrate", "--force"]

FROM release
