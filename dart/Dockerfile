# syntax=dexnore/dexfile:0
# Universal Production-Ready Dart Dexfile
# Pure Dart server (compile exe -> scratch) + Flutter web (nginx)

ARG DART_VERSION=3.5
ARG FLUTTER_VERSION=stable
ARG ENTRYPOINT=bin/server.dart
ARG BINARY_NAME=app
ARG PORT=8080
ARG APP_UID=10001
ARG APP_GID=10001
ARG APP_USER=dexfile
ARG TZ=UTC
ARG DART_COMPILE_ARGS="-O4"
ARG FLUTTER_WEB_RENDERER=canvaskit
ARG ENABLE_ANALYZE=0
ARG SKIP_PUB_GET=0
ARG BUILD_IMAGE
ARG RUN_IMAGE
ARG NGINX_VERSION=1.27

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN [ -f pubspec.yaml ] || (echo "pubspec.yaml required" >&2; exit 1)

FROM busybox:latest AS version-detector
WORKDIR /detect
COPY pubspec.yaml .dart-version .fvm/fvm_config.json ./
RUN <<'D'
#!/bin/sh
DV=""; FV="stable"
[ -f .dart-version ] && DV=$(cat .dart-version | tr -d 'v \t\r\n')
[ -z "$DV" ] && DV=$(grep -A5 'environment:' pubspec.yaml 2>/dev/null | grep -E 'sdk\s*:' | grep -oE '[0-9]+\.[0-9]+' | head -1)
[ -z "$DV" ] && DV="3.5"
[ -f .fvm/fvm_config.json ] && FV=$(grep -oE '"flutterSdkVersion"\s*:\s*"[^"]+' .fvm/fvm_config.json 2>/dev/null | sed 's/.*"//' || echo stable)
echo "$DV" > /dart-version
echo "$FV" > /flutter-version
D

FROM busybox:latest AS mode-detector
WORKDIR /detect
COPY pubspec.yaml ./
COPY lib/ ./lib/ 2>/dev/null || true
COPY web/ ./web/ 2>/dev/null || true
COPY bin/ ./bin/ 2>/dev/null || true
RUN <<'D'
#!/bin/sh
MODE="server"; FW="unknown"; ENTRY="bin/server.dart"
grep -qE 'flutter\s*:' pubspec.yaml 2>/dev/null || grep -qE 'sdk:\s*flutter' pubspec.yaml 2>/dev/null && MODE="flutter-web" && FW="flutter"
grep -qE 'shelf\s*:' pubspec.yaml 2>/dev/null && FW="shelf"
grep -qE 'dart_frog\s*:' pubspec.yaml 2>/dev/null && FW="dart_frog"
grep -qE 'serverpod\s*:' pubspec.yaml 2>/dev/null && FW="serverpod"
[ -f bin/server.dart ] && ENTRY="bin/server.dart"
[ -f bin/main.dart ] && ENTRY="bin/main.dart"
PKG=$(grep -E '^\s*name\s*:' pubspec.yaml | head -1 | sed 's/.*:\s*//' | tr -d ' \r')
echo "$MODE" > /mode
echo "$FW" > /framework
echo "$ENTRY" > /entrypoint
echo "${PKG:-app}" > /package-name
D

FROM alpine:3.20 AS static-assets
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile
RUN apk add --no-cache ca-certificates tzdata && \
    echo "${APP_USER}:x:${APP_UID}:${APP_GID}::/home/${APP_USER}:/" > /etc/passwd && \
    echo "${APP_USER}:x:${APP_GID}:" > /etc/group && \
    echo "passwd: files" > /etc/nsswitch.conf && echo "group: files" >> /etc/nsswitch.conf && \
    mkdir -p /home/${APP_USER} /tmp && chmod 1777 /tmp && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}

FROM ${BUILD_IMAGE:-dart:3.5} AS dart-base
WORKDIR /app
RUN apt-get update -qq && apt-get install --no-install-recommends -y git curl ca-certificates unzip && rm -rf /var/lib/apt/lists/*

FROM dart-base AS dart-deps
WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
ARG SKIP_PUB_GET
RUN --mount=type=cache,target=/root/.pub-cache,id=pub-cache \
    if [ "${SKIP_PUB_GET}" != "1" ]; then dart pub get; fi

FROM dart-deps AS dart-builder
WORKDIR /app
COPY . .
ARG ENTRYPOINT BINARY_NAME DART_COMPILE_ARGS ENABLE_ANALYZE
RUN if [ "${ENABLE_ANALYZE}" = "1" ]; then dart analyze || true; fi
RUN ENTRY="${ENTRYPOINT}"; \
    [ ! -f "$ENTRY" ] && { [ -f bin/server.dart ] && ENTRY=bin/server.dart; [ -f bin/main.dart ] && ENTRY=bin/main.dart; }; \
    dart compile exe ${DART_COMPILE_ARGS} -o /app/${BINARY_NAME} "$ENTRY" && chmod +x /app/${BINARY_NAME} && ls -lh /app/${BINARY_NAME}

FROM ${BUILD_IMAGE:-ghcr.io/cirruslabs/flutter:stable} AS flutter-base
WORKDIR /app
RUN flutter config --no-analytics && flutter precache --web 2>/dev/null || true

FROM flutter-base AS flutter-deps
WORKDIR /app
COPY pubspec.yaml pubspec.lock* ./
ARG SKIP_PUB_GET
RUN --mount=type=cache,target=/root/.pub-cache,id=pub-cache \
    if [ "${SKIP_PUB_GET}" != "1" ]; then flutter pub get; fi

FROM flutter-deps AS flutter-builder
WORKDIR /app
COPY . .
ARG FLUTTER_WEB_RENDERER
RUN --mount=type=cache,target=/root/.pub-cache,id=pub-cache \
    flutter build web --release --web-renderer ${FLUTTER_WEB_RENDERER}

FROM ${RUN_IMAGE:-scratch} AS prod-native
ARG BINARY_NAME=app APP_UID=10001 APP_GID=10001 PORT=8080 TZ=UTC
COPY --from=static-assets /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=static-assets /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=static-assets /etc/passwd /etc/passwd
COPY --from=static-assets /etc/group /etc/group
COPY --from=static-assets /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=static-assets --chmod=1777 /tmp /tmp
COPY --from=static-assets --chown=${APP_UID}:${APP_GID} /home/dexfile /home/dexfile
COPY --from=dart-builder --chown=${APP_UID}:${APP_GID} /app/${BINARY_NAME} /app
COPY --from=mode-detector /mode /etc/dexfile-mode
COPY --from=mode-detector /framework /etc/dexfile-framework
COPY --from=version-detector /dart-version /etc/dexfile-dart-version
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt PORT=${PORT}
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/app"]
EXPOSE ${PORT}

FROM nginx:${NGINX_VERSION}-alpine AS prod-flutter-web
COPY --from=flutter-builder /app/build/web /usr/share/nginx/html
RUN printf '%s\n' 'server {' '  listen 80;' '  root /usr/share/nginx/html;' '  index index.html;' \
  '  location / { try_files $uri $uri/ /index.html; }' '}' > /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]

FROM prod-native AS prod
FROM prod AS release
ARG PORT=8080 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="Dart Application" \
      security.non-root="true" security.uid="${APP_UID}" app.language="dart" app.port="${PORT}"

FROM prod-flutter-web AS release-flutter
LABEL app.language="dart" app.mode="flutter-web"

FROM release
