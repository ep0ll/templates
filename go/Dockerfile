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
#   - Static binaries (CGO_ENABLED=0) → scratch / distroless / alpine
#   - Security: govulncheck, go mod verify, optional staticcheck
#   - Caching: module cache + build cache (BuildKit mounts)
#   - Non-root (UID 10001), health endpoints, OCI labels, SBOM-ready
#   - Version detection from go.mod / .go-version / toolchain directive
# ========================================================================================

# See full template in repository after push; content truncated for tool transport test.
ARG GO_VERSION=1.23
WORKDIR /home/dexfile/app
FROM golang:1.23-alpine AS builder
WORKDIR /home/dexfile/app
COPY go.mod go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /dexfile-app .
FROM scratch AS release
COPY --from=builder /dexfile-app /dexfile-app
USER 10001
ENTRYPOINT ["/dexfile-app"]
