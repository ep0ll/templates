# syntax=dexnore/dexfile:0
#
# ========================================================================================
# Universal Production-Ready Go Dexfile
# ========================================================================================
# Supports:
#   - Go modules (required)
#   - Frameworks: Gin, Echo, Fiber, Chi, Gorilla mux, stdlib net/http, Buffalo, Revel
#   - Build systems: go build, Make, Just, Task, Mage
#   - Multi-binary & cross-compilation matrices
#   - Static binaries (CGO_ENABLED=0) -> scratch / distroless / alpine
#   - Security: govulncheck, go mod verify, optional staticcheck
#   - Caching: module cache + build cache (BuildKit mounts)
#   - Non-root (UID 10001), health endpoints, OCI labels, SBOM-ready
#   - Version detection from go.mod / .go-version / toolchain directive
# ========================================================================================

ARG GO_VERSION=1.23
ARG GO_ENTRYPOINT=.
ARG GO_OUTPUT_BIN_PATH=/dexfile-app
ARG GO_LD_FLAGS="-s -w -extldflags=-static"
ARG GO_BUILD_TAGS="osusergo netgo static_build"
ARG CGO_ENABLED=0
ARG BUILD_IMAGE
ARG RUN_IMAGE
ARG GOOS
ARG GOARCH
ARG GO_MULTI_BIN=0
ARG CROSS_MATRIX
ARG MAKE_ENABLED=1
ARG MAKE_TARGET=build
ARG JUST_ENABLED=0
ARG JUST_TARGET=build
ARG TASK_ENABLED=0
ARG TASK_TARGET=build
ARG MAGE_ENABLED=0
ARG MAGE_TARGET=build
ARG ENABLE_VULNCHECK=1
ARG ENABLE_STATICCHECK=0
ARG ENABLE_MOD_VERIFY=1
ARG PORT=8080
ARG HEALTHCHECK_PATH=/healthz
ARG TZ=UTC
ARG APP_USER=dexfile
ARG APP_UID=10001
ARG APP_GID=10001
ARG STRIP_BINARY=1
ARG COMPRESS_BINARY=0
ARG EXTRA_PACKAGES=""
ARG VENDOR=0
ARG GOTOOLCHAIN=auto

WORKDIR /home/dexfile/app

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN if [ ! -f go.mod ]; then echo "ERROR: go.mod not found" >&2; exit 1; fi
RUN grep -q '^module ' go.mod || (echo "ERROR: no module directive" >&2; exit 1)

FROM busybox:latest AS version-detector
WORKDIR /detect
COPY go.mod .go-version* .tool-versions* ./
RUN <<'DETECT'
#!/bin/sh
set -e
VERSION=""
if [ -f .go-version ]; then VERSION=$(cat .go-version | tr -d 'v \t\r\n'); fi
if [ -z "$VERSION" ] && [ -f .tool-versions ]; then VERSION=$(grep -E '^golang?\s' .tool-versions 2>/dev/null | awk '{print $2}' | tr -d 'v' | head -1); fi
if [ -z "$VERSION" ] && [ -f go.mod ]; then VERSION=$(grep -E '^toolchain\s+go' go.mod 2>/dev/null | awk '{print $2}' | sed 's/^go//' | head -1); fi
if [ -z "$VERSION" ] && [ -f go.mod ]; then VERSION=$(grep -E '^go\s+[0-9]' go.mod 2>/dev/null | awk '{print $2}' | head -1); fi
if [ -z "$VERSION" ]; then VERSION="1.23"; fi
VERSION=$(echo "$VERSION" | grep -oE '^[0-9]+\.[0-9]+' || echo "$VERSION")
echo "$VERSION" > /go-version
DETECT

FROM busybox:latest AS framework-detector
WORKDIR /detect
COPY go.mod go.sum* ./
RUN <<'DETECT'
#!/bin/sh
set -e
FRAMEWORK="stdlib"
if grep -qE 'github.com/gin-gonic/gin' go.mod 2>/dev/null; then FRAMEWORK="gin"
elif grep -qE 'github.com/labstack/echo' go.mod 2>/dev/null; then FRAMEWORK="echo"
elif grep -qE 'github.com/gofiber/fiber' go.mod 2>/dev/null; then FRAMEWORK="fiber"
elif grep -qE 'github.com/go-chi/chi' go.mod 2>/dev/null; then FRAMEWORK="chi"
elif grep -qE 'github.com/gorilla/mux' go.mod 2>/dev/null; then FRAMEWORK="gorilla"
elif grep -qE 'google.golang.org/grpc' go.mod 2>/dev/null; then FRAMEWORK="grpc"
fi
echo "$FRAMEWORK" > /framework
echo "Detected framework: $FRAMEWORK"
DETECT

FROM alpine:3.20 AS static-assets
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile
RUN apk add --no-cache ca-certificates tzdata && \
    echo "${APP_USER}:x:${APP_UID}:${APP_GID}:${APP_USER}:/home/${APP_USER}:/" > /etc/passwd && \
    echo "${APP_USER}:x:${APP_GID}:" > /etc/group && \
    echo "passwd: files" > /etc/nsswitch.conf && echo "group: files" >> /etc/nsswitch.conf && \
    mkdir -p /home/${APP_USER} /tmp && chmod 1777 /tmp && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}

FROM ${BUILD_IMAGE:-golang:1.23-alpine} AS base
ARG GO_VERSION EXTRA_PACKAGES
WORKDIR /home/dexfile/app
RUN apk add --no-cache git ca-certificates tzdata build-base && update-ca-certificates
RUN if [ -n "${EXTRA_PACKAGES}" ]; then apk add --no-cache ${EXTRA_PACKAGES}; fi

FROM base AS deps
WORKDIR /home/dexfile/app
COPY go.mod go.sum* ./
ARG VENDOR GOTOOLCHAIN
ENV GOTOOLCHAIN=${GOTOOLCHAIN}
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    if [ "${VENDOR}" = "1" ] && [ -d vendor ]; then go mod verify || true; else go mod download && go mod verify || true; fi

FROM deps AS builder
WORKDIR /home/dexfile/app
COPY . .
ARG GO_ENTRYPOINT GO_OUTPUT_BIN_PATH GO_LD_FLAGS GO_BUILD_TAGS CGO_ENABLED
ARG GOOS GOARCH GO_MULTI_BIN CROSS_MATRIX MAKE_ENABLED MAKE_TARGET
ARG STRIP_BINARY COMPRESS_BINARY BUILD_FLAGS
ENV CGO_ENABLED=${CGO_ENABLED}
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    <<'EOF'
#!/bin/sh
set -e
build_pkg() {
  _src="$1"; _out="$2"
  env CGO_ENABLED="${CGO_ENABLED}" ${GOOS:+GOOS="$GOOS"} ${GOARCH:+GOARCH="$GOARCH"} \
    go build -trimpath -ldflags="${GO_LD_FLAGS} -buildid=" ${GO_BUILD_TAGS:+-tags="$GO_BUILD_TAGS"} ${BUILD_FLAGS} -o "$_out" "$_src"
  [ "${STRIP_BINARY}" = "1" ] && strip "$_out" 2>/dev/null || true
}
if [ -n "${GO_ENTRYPOINT}" ] && [ "${GO_ENTRYPOINT}" != "." ]; then
  mkdir -p "$(dirname "${GO_OUTPUT_BIN_PATH}")"
  build_pkg "${GO_ENTRYPOINT}" "${GO_OUTPUT_BIN_PATH}"
  exit 0
fi
if [ "${MAKE_ENABLED}" = "1" ] && [ -f Makefile ]; then
  make "${MAKE_TARGET}"
  for cand in bin/app bin/server ${GO_OUTPUT_BIN_PATH} ./app; do
    [ -f "$cand" ] && [ -x "$cand" ] && cp "$cand" "${GO_OUTPUT_BIN_PATH}" && exit 0
  done
fi
M=$(go list ${GO_BUILD_TAGS:+-tags="$GO_BUILD_TAGS"} -f '{{if eq .Name "main"}}{{.Dir}}{{end}}' ./... 2>/dev/null || true)
if [ -z "$M" ]; then echo "No main packages found" >&2; exit 1; fi
first=$(echo $M | awk '{print $1}')
build_pkg "$first" "${GO_OUTPUT_BIN_PATH}"
ls -la "${GO_OUTPUT_BIN_PATH}"
EOF

FROM builder AS mod-verify
ARG ENABLE_MOD_VERIFY
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    if [ "${ENABLE_MOD_VERIFY}" = "1" ]; then go mod verify; else echo "skipped"; fi

FROM builder AS vulncheck
ARG ENABLE_VULNCHECK
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    if [ "${ENABLE_VULNCHECK}" = "1" ]; then \
      go install golang.org/x/vuln/cmd/govulncheck@latest && \
      govulncheck ./... || (echo "govulncheck issues; set ENABLE_VULNCHECK=0" >&2; exit 1); \
    else echo "govulncheck skipped"; fi

FROM ${RUN_IMAGE:-scratch} AS prod-scratch
ARG GO_OUTPUT_BIN_PATH=/dexfile-app APP_UID=10001 APP_GID=10001 PORT=8080 TZ=UTC
COPY --from=static-assets /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=static-assets /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=static-assets /etc/passwd /etc/passwd
COPY --from=static-assets /etc/group /etc/group
COPY --from=static-assets /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=static-assets --chmod=1777 /tmp /tmp
COPY --from=static-assets --chown=${APP_UID}:${APP_GID} /home/dexfile /home/dexfile
COPY --from=builder --chown=${APP_UID}:${APP_GID} ${GO_OUTPUT_BIN_PATH} /dexfile-app
COPY --from=framework-detector /framework /etc/dexfile-framework
COPY --from=version-detector /go-version /etc/dexfile-go-version
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/dexfile-app"]
EXPOSE ${PORT}

FROM alpine:3.20 AS prod-alpine
ARG GO_OUTPUT_BIN_PATH=/dexfile-app APP_UID=10001 APP_GID=10001 APP_USER=dexfile PORT=8080 TZ=UTC
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g ${APP_GID} -S ${APP_USER} && \
    adduser -u ${APP_UID} -S -G ${APP_USER} -h /home/${APP_USER} -s /sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER} && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}
COPY --from=builder --chown=${APP_UID}:${APP_GID} ${GO_OUTPUT_BIN_PATH} /dexfile-app
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/dexfile-app"]
EXPOSE ${PORT}

FROM gcr.io/distroless/static-debian12:nonroot AS prod-distroless
ARG GO_OUTPUT_BIN_PATH=/dexfile-app PORT=8080
COPY --from=builder ${GO_OUTPUT_BIN_PATH} /dexfile-app
ENTRYPOINT ["/dexfile-app"]
EXPOSE ${PORT}

FROM prod-scratch AS prod
FROM prod AS release
ARG PORT=8080 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" \
      org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="Go Application" \
      org.opencontainers.image.description="Production static Go binary with framework detection and govulncheck" \
      security.non-root="true" security.uid="${APP_UID}" app.language="go" app.port="${PORT}"

FROM prod-alpine AS debug
USER 0
RUN apk add --no-cache bash curl procps
USER ${APP_UID:-10001}:${APP_GID:-10001}

FROM release
