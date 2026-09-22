# syntax=dexnore/dexfile:0
#
# ========================================================================================
# C++ Convenience Dexfile
# ========================================================================================
# Thin wrapper around the unified C/C++ template with C++-oriented defaults.
# For full documentation and stages, see ../c/Dockerfile
#
# Usage is identical – language is auto-detected. This file exists so that
# repositories that only contain C++ can IMPORT cpp/Dockerfile explicitly.
# ========================================================================================
#
# Recommended:
#   docker buildx build -f c/Dockerfile -t myapp:latest .
#
# C++-leaning defaults:
#   --build-arg CXX=g++
#   --build-arg CXXFLAGS="-O2 -pipe -fPIC -std=c++20"
#   --build-arg BUILD_SYSTEM=cmake
#   --build-arg STATIC=1
#   --target prod-static
#
# All stages, ARG surface, Conan/vcpkg, CMake/Meson/Make/Autotools/Bazel,
# scratch/alpine/distroless runtimes, and security hardening are defined in:
#   c/Dockerfile
#
ARG CXX=g++
ARG CXXFLAGS="-O2 -pipe -fPIC -std=c++17"
ARG BINARY_NAME=app
ARG BUILD_SYSTEM=auto
ARG STATIC=1
ARG PORT=8080
ARG APP_UID=10001

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN find . -maxdepth 5 \( -name "*.cpp" -o -name "*.cc" -o -name "CMakeLists.txt" -o -name "meson.build" \) | grep -q . || \
    (echo "No C++ project markers" >&2; exit 1)

FROM debian:bookworm-slim AS release
LABEL app.language="cpp" \
      org.opencontainers.image.description="C++ projects: use c/Dockerfile for full production build"
WORKDIR /app
COPY . .
CMD ["echo", "Build with -f c/Dockerfile for the full C/C++ production image"]

FROM release
