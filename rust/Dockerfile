# syntax=dexnore/dexfile:0
# Universal Production-Ready Rust Dexfile
# cargo-chef style, Axum/Actix/Rocket detection, cargo-audit, static musl -> scratch

ARG RUST_VERSION=1.82
ARG FEATURES=""
ARG BINARY_NAME=""
ARG BIN_PATH=/usr/local/bin/app
ARG CARGO_FLAGS="--release"
ARG ENABLE_AUDIT=1
ARG PORT=8080
ARG APP_UID=10001
ARG APP_GID=10001
ARG USE_MUSL=1
ARG STRIP_BINARY=1
ARG BUILD_IMAGE
ARG RUN_IMAGE

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN [ -f Cargo.toml ] || (echo "Cargo.toml required" >&2; exit 1)

FROM busybox:latest AS version-detector
WORKDIR /detect
COPY rust-toolchain.toml rust-toolchain Cargo.toml ./
RUN <<'D'
#!/bin/sh
V=""
[ -f rust-toolchain.toml ] && V=$(grep -E 'channel\s*=' rust-toolchain.toml 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' | head -1)
[ -z "$V" ] && [ -f rust-toolchain ] && V=$(cat rust-toolchain | tr -d ' \t\r\n')
[ -z "$V" ] && V="1.82"
echo "$V" > /rust-version
D

FROM busybox:latest AS framework-detector
WORKDIR /detect
COPY Cargo.toml ./
RUN <<'D'
#!/bin/sh
FW="unknown"
grep -qE 'axum\s*=' Cargo.toml 2>/dev/null && FW="axum"
grep -qE 'actix-web\s*=' Cargo.toml 2>/dev/null && FW="actix-web"
grep -qE 'rocket\s*=' Cargo.toml 2>/dev/null && FW="rocket"
grep -qE 'warp\s*=' Cargo.toml 2>/dev/null && FW="warp"
grep -qE 'poem\s*=' Cargo.toml 2>/dev/null && FW="poem"
BIN=$(grep -m1 -E '^\s*name\s*=' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/' || echo app)
echo "$FW" > /framework
echo "$BIN" > /package-name
D

FROM alpine:3.20 AS static-assets
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile
RUN apk add --no-cache ca-certificates tzdata && \
    echo "${APP_USER}:x:${APP_UID}:${APP_GID}::/home/${APP_USER}:/" > /etc/passwd && \
    echo "${APP_USER}:x:${APP_GID}:" > /etc/group && \
    echo "passwd: files" > /etc/nsswitch.conf && echo "group: files" >> /etc/nsswitch.conf && \
    mkdir -p /home/${APP_USER} /tmp && chmod 1777 /tmp && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}

FROM ${BUILD_IMAGE:-rust:1.82-alpine} AS base
WORKDIR /home/dexfile/app
RUN apk add --no-cache musl-dev openssl-dev openssl-libs-static pkgconfig git curl build-base ca-certificates

FROM base AS planner
WORKDIR /home/dexfile/app
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo "fn main() {}" > src/main.rs
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry \
    --mount=type=cache,target=/usr/local/cargo/git,id=cargo-git \
    cargo fetch

FROM base AS cacher
WORKDIR /home/dexfile/app
COPY --from=planner /usr/local/cargo /usr/local/cargo
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo "fn main() {}" > src/main.rs
ARG FEATURES
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry \
    --mount=type=cache,target=/usr/local/cargo/git,id=cargo-git \
    --mount=type=cache,target=/home/dexfile/app/target,id=cargo-target \
    cargo build --release ${FEATURES:+--features $FEATURES} || true

FROM base AS builder
WORKDIR /home/dexfile/app
COPY --from=cacher /usr/local/cargo /usr/local/cargo
COPY --from=cacher /home/dexfile/app/target /home/dexfile/app/target
COPY . .
ARG FEATURES BINARY_NAME USE_MUSL STRIP_BINARY
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry \
    --mount=type=cache,target=/usr/local/cargo/git,id=cargo-git \
    --mount=type=cache,target=/home/dexfile/app/target,id=cargo-target \
    <<'EOF'
#!/bin/sh
set -e
[ -z "$BINARY_NAME" ] && BINARY_NAME=$(grep -m1 -E '^\s*name\s*=' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/' || echo app)
FEAT=""; [ -n "$FEATURES" ] && FEAT="--features $FEATURES"
TARGET_FLAG=""
if [ "$USE_MUSL" = "1" ]; then
  HOST=$(rustc -vV | sed -n 's/^host: //p')
  MUSL=$(echo "$HOST" | sed 's/unknown-linux-gnu/unknown-linux-musl/')
  if [ "$MUSL" != "$HOST" ]; then rustup target add "$MUSL" 2>/dev/null || true; TARGET_FLAG="--target $MUSL"; fi
fi
cargo build --release $FEAT $TARGET_FLAG
OUT="target/release/$BINARY_NAME"
[ -n "$TARGET_FLAG" ] && T=$(echo $TARGET_FLAG | sed 's/--target //') && OUT="target/$T/release/$BINARY_NAME"
[ ! -f "$OUT" ] && OUT=$(find target -type f -executable -name "$BINARY_NAME" | head -1)
cp "$OUT" /tmp/app && chmod +x /tmp/app
[ "$STRIP_BINARY" = "1" ] && strip /tmp/app 2>/dev/null || true
ls -lh /tmp/app
EOF

FROM builder AS audit
ARG ENABLE_AUDIT
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=cargo-registry \
    if [ "$ENABLE_AUDIT" = "1" ]; then \
      cargo install cargo-audit --locked 2>/dev/null || true; \
      cargo audit || (echo "audit issues; set ENABLE_AUDIT=0" >&2; exit 1); \
    else echo "audit skipped"; fi

FROM ${RUN_IMAGE:-scratch} AS prod
ARG BIN_PATH=/usr/local/bin/app APP_UID=10001 APP_GID=10001 PORT=8080 TZ=UTC
COPY --from=static-assets /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=static-assets /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=static-assets /etc/passwd /etc/passwd
COPY --from=static-assets /etc/group /etc/group
COPY --from=static-assets /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=static-assets --chmod=1777 /tmp /tmp
COPY --from=static-assets --chown=${APP_UID}:${APP_GID} /home/dexfile /home/dexfile
COPY --from=builder --chown=${APP_UID}:${APP_GID} /tmp/app ${BIN_PATH}
COPY --from=framework-detector /framework /etc/dexfile-framework
COPY --from=version-detector /rust-version /etc/dexfile-rust-version
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/usr/local/bin/app"]
EXPOSE ${PORT}

FROM alpine:3.20 AS debug
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile
RUN apk add --no-cache ca-certificates tzdata libgcc bash curl && \
    addgroup -g ${APP_GID} -S ${APP_USER} && \
    adduser -u ${APP_UID} -S -G ${APP_USER} -h /home/${APP_USER} -s /sbin/nologin ${APP_USER}
COPY --from=builder --chown=${APP_UID}:${APP_GID} /tmp/app /usr/local/bin/app
USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/usr/local/bin/app"]

FROM prod AS release
ARG PORT=8080 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="Rust Application" \
      security.non-root="true" security.uid="${APP_UID}" app.language="rust" app.port="${PORT}"

FROM release
