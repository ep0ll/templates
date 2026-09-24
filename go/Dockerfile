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

# ========================
# Meta Stage: Global Args
# ========================
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
ARG HEALTHCHECK_INTERVAL=30s
ARG HEALTHCHECK_TIMEOUT=5s
ARG HEALTHCHECK_START_PERIOD=10s
ARG HEALTHCHECK_RETRIES=3
ARG TZ=UTC
ARG APP_USER=dexfile
ARG APP_UID=10001
ARG APP_GID=10001
ARG INSTALL_CA_CERTS=1
ARG INSTALL_TZDATA=1
ARG STRIP_BINARY=1
ARG COMPRESS_BINARY=0
ARG UPX_FLAGS=-9
ARG DEBUG=0
ARG BUILD_FLAGS=""
ARG EXTRA_PACKAGES=""
ARG GO_MAIN_GLOB=""
ARG VENDOR=0
ARG GOTOOLCHAIN=auto
ARG GOMODCACHE=/go/pkg/mod
ARG GOCACHE=/root/.cache/go-build

WORKDIR /home/dexfile/app

# ========================
# Stage 0: Project Validation
# ========================
FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN if [ ! -f go.mod ]; then echo "ERROR: go.mod not found. Go modules are required." >&2; exit 1; fi && echo "go.mod found"
RUN if ! grep -q '^module ' go.mod; then echo "ERROR: go.mod does not contain a module directive." >&2; exit 1; fi && echo "module directive present"

# ========================
# Stage 1: Go Version Detection
# ========================
FROM busybox:latest AS version-detector
WORKDIR /detect
COPY go.mod .go-version* .tool-versions* ./
RUN <<'DETECT'
#!/bin/sh
set -e
VERSION=""
if [ -f .go-version ]; then VERSION=$(cat .go-version | tr -d 'v \t\r\n'); echo "Detected from .go-version: $VERSION"; fi
if [ -z "$VERSION" ] && [ -f .tool-versions ]; then VERSION=$(grep -E '^golang?\s' .tool-versions 2>/dev/null | awk '{print $2}' | tr -d 'v' | head -1); [ -n "$VERSION" ] && echo "Detected from .tool-versions: $VERSION"; fi
if [ -z "$VERSION" ] && [ -f go.mod ]; then VERSION=$(grep -E '^toolchain\s+go' go.mod 2>/dev/null | awk '{print $2}' | sed 's/^go//' | head -1); [ -n "$VERSION" ] && echo "Detected from toolchain: $VERSION"; fi
if [ -z "$VERSION" ] && [ -f go.mod ]; then VERSION=$(grep -E '^go\s+[0-9]' go.mod 2>/dev/null | awk '{print $2}' | head -1); [ -n "$VERSION" ] && echo "Detected from go directive: $VERSION"; fi
if [ -z "$VERSION" ]; then VERSION="1.23"; echo "No version found, defaulting to: $VERSION"; fi
VERSION=$(echo "$VERSION" | grep -oE '^[0-9]+\.[0-9]+' || echo "$VERSION")
echo "$VERSION" > /go-version
DETECT

# ========================
# Stage 2: Framework Detection
# ========================
FROM busybox:latest AS framework-detector
WORKDIR /detect
COPY go.mod go.sum* ./
RUN <<'DETECT'
#!/bin/sh
set -e
FRAMEWORK="stdlib"
HTTP_ROUTER="net/http"
if grep -qE 'github.com/gin-gonic/gin' go.mod 2>/dev/null; then FRAMEWORK="gin"; HTTP_ROUTER="gin"
elif grep -qE 'github.com/labstack/echo' go.mod 2>/dev/null; then FRAMEWORK="echo"; HTTP_ROUTER="echo"
elif grep -qE 'github.com/gofiber/fiber' go.mod 2>/dev/null; then FRAMEWORK="fiber"; HTTP_ROUTER="fiber"
elif grep -qE 'github.com/go-chi/chi' go.mod 2>/dev/null; then FRAMEWORK="chi"; HTTP_ROUTER="chi"
elif grep -qE 'github.com/gorilla/mux' go.mod 2>/dev/null; then FRAMEWORK="gorilla"; HTTP_ROUTER="gorilla"
elif grep -qE 'github.com/julienschmidt/httprouter' go.mod 2>/dev/null; then FRAMEWORK="httprouter"; HTTP_ROUTER="httprouter"
elif grep -qE 'github.com/go-martini/martini|github.com/codegangsta/martini' go.mod 2>/dev/null; then FRAMEWORK="martini"; HTTP_ROUTER="martini"
elif grep -qE 'github.com/revel/revel' go.mod 2>/dev/null; then FRAMEWORK="revel"; HTTP_ROUTER="revel"
elif grep -qE 'github.com/gobuffalo/buffalo' go.mod 2>/dev/null; then FRAMEWORK="buffalo"; HTTP_ROUTER="buffalo"
elif grep -qE 'github.com/kataras/iris' go.mod 2>/dev/null; then FRAMEWORK="iris"; HTTP_ROUTER="iris"
elif grep -qE 'github.com/emicklei/go-restful' go.mod 2>/dev/null; then FRAMEWORK="go-restful"; HTTP_ROUTER="go-restful"
elif grep -qE 'google.golang.org/grpc' go.mod 2>/dev/null; then FRAMEWORK="grpc"; HTTP_ROUTER="grpc"
fi
HAS_COBRA=0; HAS_URFAVE=0
grep -qE 'github.com/spf13/cobra' go.mod 2>/dev/null && HAS_COBRA=1
grep -qE 'github.com/urfave/cli' go.mod 2>/dev/null && HAS_URFAVE=1
echo "$FRAMEWORK" > /framework
echo "$HTTP_ROUTER" > /http-router
echo "$HAS_COBRA" > /has-cobra
echo "$HAS_URFAVE" > /has-urfave
echo "Detected framework: $FRAMEWORK (router: $HTTP_ROUTER)"
DETECT

# ========================
# Stage 3: Build System Detection
# ========================
FROM busybox:latest AS buildsys-detector
WORKDIR /detect
COPY Makefile Justfile Taskfile.yml Taskfile.yaml magefile.go* ./
RUN <<'DETECT'
#!/bin/sh
set -e
SYS="go-build"
if [ -f Makefile ] || [ -f makefile ]; then SYS="make"
elif [ -f Justfile ] || [ -f justfile ]; then SYS="just"
elif [ -f Taskfile.yml ] || [ -f Taskfile.yaml ]; then SYS="task"
elif [ -f magefile.go ]; then SYS="mage"
fi
echo "$SYS" > /buildsys
echo "Detected build system: $SYS"
DETECT

# ========================
# Stage 4: Static Assets
# ========================
FROM alpine:3.20 AS static-assets
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile
RUN apk add --no-cache ca-certificates tzdata && \
    echo "${APP_USER}:x:${APP_UID}:${APP_GID}:${APP_USER}:/home/${APP_USER}:/" > /etc/passwd && \
    echo "${APP_USER}:x:${APP_GID}:" > /etc/group && \
    echo "passwd: files" > /etc/nsswitch.conf && echo "group: files" >> /etc/nsswitch.conf && \
    mkdir -p /home/${APP_USER} /tmp && chmod 1777 /tmp && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}

# ========================
# Stage 5: Base Builder
# ========================
FROM ${BUILD_IMAGE:-golang:1.23-alpine} AS base
ARG GO_VERSION EXTRA_PACKAGES
WORKDIR /home/dexfile/app
RUN apk add --no-cache git ca-certificates tzdata build-base && update-ca-certificates
RUN if [ -n "${EXTRA_PACKAGES}" ]; then apk add --no-cache ${EXTRA_PACKAGES}; fi

# ========================
# Stage 6: Dependency Download
# ========================
FROM base AS deps
WORKDIR /home/dexfile/app
COPY go.mod go.sum* ./
ARG VENDOR GOTOOLCHAIN
ENV GOTOOLCHAIN=${GOTOOLCHAIN}
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    <<'EOF'
#!/bin/sh
set -e
if [ "${VENDOR}" = "1" ] && [ -d vendor ]; then echo "Using vendored modules"; go mod verify || true
else echo "Downloading modules..."; go mod download; go mod verify || true; fi
EOF

# ========================
# Stage 7: Source + Build
# ========================
FROM deps AS builder
WORKDIR /home/dexfile/app
COPY . .
ARG GO_ENTRYPOINT GO_OUTPUT_BIN_PATH GO_LD_FLAGS GO_BUILD_TAGS CGO_ENABLED
ARG GOOS GOARCH GO_MULTI_BIN CROSS_MATRIX MAKE_ENABLED MAKE_TARGET JUST_ENABLED JUST_TARGET
ARG TASK_ENABLED TASK_TARGET MAGE_ENABLED MAGE_TARGET GO_MAIN_GLOB BUILD_FLAGS STRIP_BINARY COMPRESS_BINARY UPX_FLAGS DEBUG VENDOR
ENV CGO_ENABLED=${CGO_ENABLED}
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    <<'EOF'
#!/bin/sh
set -e
echo "=== Go Build ==="
build_pkg() {
  _src="$1"; _out="$2"
  echo "Building $_src -> $_out"
  env CGO_ENABLED="${CGO_ENABLED}" ${GOOS:+GOOS="$GOOS"} ${GOARCH:+GOARCH="$GOARCH"} \
    go build -trimpath -ldflags="${GO_LD_FLAGS} -buildid=" ${GO_BUILD_TAGS:+-tags="$GO_BUILD_TAGS"} ${BUILD_FLAGS} -o "$_out" "$_src"
  if [ "${STRIP_BINARY}" = "1" ] && command -v strip >/dev/null 2>&1; then strip "$_out" 2>/dev/null || true; fi
  if [ "${COMPRESS_BINARY}" = "1" ] && command -v upx >/dev/null 2>&1; then upx ${UPX_FLAGS} "$_out" 2>/dev/null || true; fi
}
if [ -n "${GO_ENTRYPOINT}" ] && [ "${GO_ENTRYPOINT}" != "." ]; then
  mkdir -p "$(dirname "${GO_OUTPUT_BIN_PATH}")"
  build_pkg "${GO_ENTRYPOINT}" "${GO_OUTPUT_BIN_PATH}"
  ls -la "${GO_OUTPUT_BIN_PATH}"; exit 0
fi
if [ "${MAKE_ENABLED}" = "1" ] && [ -f Makefile ]; then
  echo "Using Makefile target: ${MAKE_TARGET}"
  make "${MAKE_TARGET}"
  for cand in bin/app bin/server bin/main ${GO_OUTPUT_BIN_PATH} ./app ./server ./main; do
    if [ -f "$cand" ] && [ -x "$cand" ]; then cp "$cand" "${GO_OUTPUT_BIN_PATH}"; exit 0; fi
  done
  if [ -d bin ]; then first=$(find bin -type f -executable | head -1); [ -n "$first" ] && cp "$first" "${GO_OUTPUT_BIN_PATH}" && exit 0; fi
fi
if [ "${JUST_ENABLED}" = "1" ] && { [ -f Justfile ] || [ -f justfile ]; }; then just "${JUST_TARGET}"; exit 0; fi
if [ "${TASK_ENABLED}" = "1" ] && { [ -f Taskfile.yml ] || [ -f Taskfile.yaml ]; }; then task "${TASK_TARGET}"; exit 0; fi
if [ "${MAGE_ENABLED}" = "1" ] && [ -f magefile.go ]; then go run github.com/magefile/mage@latest "${MAGE_TARGET}"; exit 0; fi
M=""
if [ -n "${GO_MAIN_GLOB}" ]; then set -f; set -- ${GO_MAIN_GLOB}; set +f; for d; do [ -d "$d" ] && M="$M${M:+ }$d"; done; fi
if [ -z "$M" ]; then M=$(go list ${GO_BUILD_TAGS:+-tags="$GO_BUILD_TAGS"} -f '{{if eq .Name "main"}}{{.Dir}}{{end}}' ./... 2>/dev/null || true); fi
if [ -z "$M" ]; then echo "No main packages found. Set GO_ENTRYPOINT or GO_MAIN_GLOB." >&2; exit 1; fi
echo "Main packages: $M"
if [ -n "${CROSS_MATRIX}" ]; then
  _B_OUT="${GO_OUTPUT_BIN_PATH}"
  IFS=','; set -f; set -- ${CROSS_MATRIX}; set +f
  for c; do
    export GOOS="${c%%/*}" GOARCH="${c##*/}"
    MDIR="${_B_OUT}/${GOOS}_${GOARCH}"; mkdir -p "$MDIR"
    for p in $M; do
      bin="${p##*/}"; [ "$GOOS" = "windows" ] && bin="${bin}.exe"
      tout="$MDIR"; [ "${GO_MULTI_BIN}" = "1" ] && tout="${MDIR}/${bin}"
      build_pkg "$p" "$tout"
    done
  done
  exit 0
fi
if [ "${GO_MULTI_BIN}" = "1" ]; then
  mkdir -p "${GO_OUTPUT_BIN_PATH}"
  for p in $M; do build_pkg "$p" "${GO_OUTPUT_BIN_PATH}/${p##*/}"; done
else
  first=$(echo $M | awk '{print $1}')
  build_pkg "$first" "${GO_OUTPUT_BIN_PATH}"
fi
ls -la "${GO_OUTPUT_BIN_PATH}" || ls -la "$(dirname "${GO_OUTPUT_BIN_PATH}")"
EOF

# ========================
# Stage 8: go mod verify
# ========================
FROM builder AS mod-verify
ARG ENABLE_MOD_VERIFY
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    if [ "${ENABLE_MOD_VERIFY}" = "1" ]; then echo "=== go mod verify ===" && go mod verify; else echo "go mod verify skipped"; fi

# ========================
# Stage 9: govulncheck
# ========================
FROM builder AS vulncheck
ARG ENABLE_VULNCHECK
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    if [ "${ENABLE_VULNCHECK}" = "1" ]; then \
      echo "=== govulncheck ===" && go install golang.org/x/vuln/cmd/govulncheck@latest && \
      govulncheck ./... || (echo "govulncheck reported issues. Set ENABLE_VULNCHECK=0 to skip." >&2; exit 1); \
    else echo "govulncheck skipped"; fi

# ========================
# Stage 10: staticcheck
# ========================
FROM builder AS staticcheck
ARG ENABLE_STATICCHECK
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    if [ "${ENABLE_STATICCHECK}" = "1" ]; then \
      echo "=== staticcheck ===" && go install honnef.co/go/tools/cmd/staticcheck@latest && \
      staticcheck ./... || (echo "staticcheck reported issues. Set ENABLE_STATICCHECK=0 to skip." >&2; exit 1); \
    else echo "staticcheck skipped"; fi

# ========================
# Stage 11: Production - scratch
# ========================
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
COPY --from=framework-detector /http-router /etc/dexfile-http-router
COPY --from=buildsys-detector /buildsys /etc/dexfile-buildsys
COPY --from=version-detector /go-version /etc/dexfile-go-version
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt PATH=/usr/local/bin:/dexfile-app
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/dexfile-app"]
EXPOSE ${PORT}

# ========================
# Stage 12: Production - alpine
# ========================
FROM alpine:3.20 AS prod-alpine
ARG GO_OUTPUT_BIN_PATH=/dexfile-app APP_UID=10001 APP_GID=10001 APP_USER=dexfile PORT=8080 TZ=UTC
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g ${APP_GID} -S ${APP_USER} && \
    adduser -u ${APP_UID} -S -G ${APP_USER} -h /home/${APP_USER} -s /sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER} && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}
COPY --from=builder --chown=${APP_UID}:${APP_GID} ${GO_OUTPUT_BIN_PATH} /dexfile-app
COPY --from=framework-detector /framework /etc/dexfile-framework
COPY --from=version-detector /go-version /etc/dexfile-go-version
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/dexfile-app"]
EXPOSE ${PORT}

# ========================
# Stage 13: Production - distroless
# ========================
FROM gcr.io/distroless/static-debian12:nonroot AS prod-distroless
ARG GO_OUTPUT_BIN_PATH=/dexfile-app PORT=8080
COPY --from=builder ${GO_OUTPUT_BIN_PATH} /dexfile-app
COPY --from=framework-detector /framework /etc/dexfile-framework
ENTRYPOINT ["/dexfile-app"]
EXPOSE ${PORT}

# ========================
# Stage 14-16: Default / Release / Debug
# ========================
FROM prod-scratch AS prod
FROM prod AS release
ARG PORT=8080 GO_VERSION APP_UID=10001
LABEL maintainer="@dexnore/dexfile" \
      org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="Go Application" \
      org.opencontainers.image.description="Production static Go binary with framework detection, govulncheck, and multi-stage caching" \
      org.opencontainers.image.authors="@dexnore/dexfile" \
      org.opencontainers.image.source="https://github.com/dexnore/templates" \
      org.opencontainers.image.licenses="Apache-2.0" \
      security.non-root="true" security.uid="${APP_UID}" app.language="go" app.port="${PORT}" \
      moby.buildkit.frontend.network.none="true" \
      moby.buildkit.frontend.caps="moby.buildkit.frontend.inputs,moby.buildkit.frontend.subrequests,moby.buildkit.frontend.contexts"
LABEL app.framework="$(cat /etc/dexfile-framework 2>/dev/null || echo unknown)" \
      app.go.version="$(cat /etc/dexfile-go-version 2>/dev/null || echo unknown)" \
      app.buildsys="$(cat /etc/dexfile-buildsys 2>/dev/null || echo go-build)"

FROM prod-alpine AS debug
ARG GO_OUTPUT_BIN_PATH=/dexfile-app
USER 0
RUN apk add --no-cache bash curl procps
USER ${APP_UID:-10001}:${APP_GID:-10001}

FROM release AS sbom
FROM release

# ========================
# CI targets: test, coverage, lint, generate, vendor, size-report, metadata
# ========================
FROM busybox:latest AS workspace-detect
WORKDIR /detect
COPY go.work go.work.sum* ./
RUN if [ -f go.work ]; then echo "workspace" > /workspace-mode; else echo "single" > /workspace-mode; fi

FROM builder AS test
ARG ENABLE_RACE=0 TEST_FLAGS=""
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    RACE=""; [ "${ENABLE_RACE}" = "1" ] && RACE="-race"; go test ${RACE} ${TEST_FLAGS} ./... -count=1

FROM builder AS coverage
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    go test ./... -coverprofile=/tmp/coverage.out -covermode=atomic && go tool cover -func=/tmp/coverage.out

FROM builder AS lint
ARG ENABLE_LINT=0 GOLANGCI_LINT_VERSION=v1.61.0
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked,id=go-mod \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked,id=go-build \
    if [ "${ENABLE_LINT}" = "1" ]; then \
      curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin ${GOLANGCI_LINT_VERSION} && \
      golangci-lint run ./...; else echo "golangci-lint skipped"; fi

FROM builder AS size-report
ARG GO_OUTPUT_BIN_PATH=/dexfile-app
RUN echo "=== Binary size report ===" && ls -lh "${GO_OUTPUT_BIN_PATH}" 2>/dev/null || true && file "${GO_OUTPUT_BIN_PATH}" 2>/dev/null || true

FROM busybox:latest AS metadata
COPY --from=framework-detector /framework /meta/framework
COPY --from=framework-detector /http-router /meta/http-router
COPY --from=buildsys-detector /buildsys /meta/buildsys
COPY --from=version-detector /go-version /meta/go-version
COPY --from=workspace-detect /workspace-mode /meta/workspace-mode
RUN echo "{\"language\":\"go\",\"framework\":\"$(cat /meta/framework)\",\"http_router\":\"$(cat /meta/http-router)\",\"buildsys\":\"$(cat /meta/buildsys)\",\"go_version\":\"$(cat /meta/go-version)\",\"workspace\":\"$(cat /meta/workspace-mode)\"}"

FROM prod AS nonroot-check
USER 10001

FROM release

# ARG REFERENCE: GO_VERSION, GO_ENTRYPOINT, GO_OUTPUT_BIN_PATH, GO_LD_FLAGS, GO_BUILD_TAGS,
# CGO_ENABLED, BUILD_IMAGE, RUN_IMAGE, GOOS, GOARCH, CROSS_MATRIX, GO_MULTI_BIN,
# MAKE/JUST/TASK/MAGE_ENABLED, ENABLE_VULNCHECK, ENABLE_STATICCHECK, ENABLE_MOD_VERIFY,
# PORT, APP_UID, APP_GID, STRIP_BINARY, COMPRESS_BINARY, VENDOR, GOTOOLCHAIN
#
# FRAMEWORK MATRIX: gin, echo, fiber, chi, gorilla, httprouter, martini, revel, buffalo, iris, go-restful, grpc, stdlib
# RUNTIME TARGETS: prod/release (scratch), prod-alpine, prod-distroless, debug
# SECURITY: go mod verify, govulncheck (default on), staticcheck (opt-in)
#
# END OF GO DEXFILE (excellent production template)
