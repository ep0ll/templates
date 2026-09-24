# syntax=dexnore/dexfile:0
# Universal Production-Ready C/C++ Dexfile
# CMake/Meson/Make/Autotools, static linking, scratch, C vs C++ detection

ARG CC=gcc
ARG CXX=g++
ARG CFLAGS="-O2 -pipe -fPIC"
ARG CXXFLAGS="-O2 -pipe -fPIC"
ARG LDFLAGS="-static -s"
ARG BUILD_TYPE=Release
ARG BUILD_SYSTEM=auto
ARG GENERATOR=Ninja
ARG BINARY_NAME=app
ARG BIN_PATH=/usr/local/bin/app
ARG BUILD_DIR=build
ARG STATIC=1
ARG ENABLE_STRIP=1
ARG PORT=8080
ARG APP_UID=10001
ARG APP_GID=10001
ARG APP_USER=dexfile
ARG TZ=UTC
ARG CMAKE_ARGS=""
ARG MESON_ARGS=""
ARG MAKE_ARGS="-j$(nproc)"
ARG BUILD_IMAGE
ARG RUN_IMAGE

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN find . -maxdepth 4 \( -name CMakeLists.txt -o -name meson.build -o -name Makefile -o -name "*.c" -o -name "*.cpp" \) | grep -q . || \
    (echo "No C/C++ project markers" >&2; exit 1)

FROM busybox:latest AS lang-detector
WORKDIR /detect
COPY . .
RUN <<'D'
#!/bin/sh
LANG="c"
CXX_N=$(find . -maxdepth 5 \( -name "*.cpp" -o -name "*.cc" -o -name "*.cxx" \) 2>/dev/null | wc -l)
C_N=$(find . -maxdepth 5 -name "*.c" 2>/dev/null | wc -l)
[ "$CXX_N" -gt 0 ] && LANG="cpp"
[ "$CXX_N" -eq 0 ] && [ "$C_N" -gt 0 ] && LANG="c"
echo "$LANG" > /language
D

FROM busybox:latest AS buildsys-detector
WORKDIR /detect
COPY . .
RUN <<'D'
#!/bin/sh
SYS="make"
[ -f CMakeLists.txt ] && SYS="cmake"
[ -f meson.build ] && SYS="meson"
[ -f configure ] || [ -f configure.ac ] && SYS="autotools"
[ -f Makefile ] || [ -f makefile ] && [ "$SYS" = "make" ] && SYS="make"
echo "$SYS" > /buildsys
D

FROM alpine:3.20 AS static-assets
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile
RUN apk add --no-cache ca-certificates tzdata && \
    echo "${APP_USER}:x:${APP_UID}:${APP_GID}::/home/${APP_USER}:/" > /etc/passwd && \
    echo "${APP_USER}:x:${APP_GID}:" > /etc/group && \
    echo "passwd: files" > /etc/nsswitch.conf && echo "group: files" >> /etc/nsswitch.conf && \
    mkdir -p /home/${APP_USER} /tmp && chmod 1777 /tmp && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER}

FROM ${BUILD_IMAGE:-debian:bookworm-slim} AS base
WORKDIR /src
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential cmake ninja-build meson pkg-config git curl ca-certificates \
    autoconf automake libtool file && rm -rf /var/lib/apt/lists/*

FROM alpine:3.20 AS base-musl
WORKDIR /src
RUN apk add --no-cache build-base cmake ninja meson pkgconf git curl ca-certificates \
    autoconf automake libtool linux-headers file

FROM base AS builder
WORKDIR /src
COPY . .
ARG CC CXX CFLAGS CXXFLAGS LDFLAGS BUILD_TYPE BUILD_SYSTEM GENERATOR
ARG BINARY_NAME BUILD_DIR STATIC CMAKE_ARGS MESON_ARGS MAKE_ARGS ENABLE_STRIP
ENV CC=${CC} CXX=${CXX} CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${LDFLAGS}"
RUN <<'EOF'
#!/bin/bash
set -e
SYS="${BUILD_SYSTEM}"
[ "$SYS" = "auto" ] && { [ -f CMakeLists.txt ] && SYS=cmake; [ -f meson.build ] && SYS=meson; [ -f configure ] || [ -f configure.ac ] && SYS=autotools; [ -f Makefile ] && SYS=make; }
mkdir -p "${BUILD_DIR}"
case "$SYS" in
  cmake)
    cmake -S . -B "${BUILD_DIR}" -G "${GENERATOR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
      $([ "$STATIC" = "1" ] && echo -DBUILD_SHARED_LIBS=OFF) ${CMAKE_ARGS}
    cmake --build "${BUILD_DIR}" -j"$(nproc)"
    DESTDIR=/opt/stage cmake --install "${BUILD_DIR}" 2>/dev/null || true
    ;;
  meson)
    meson setup "${BUILD_DIR}" --buildtype=$(echo ${BUILD_TYPE}|tr A-Z a-z) \
      $([ "$STATIC" = "1" ] && echo --default-library=static) ${MESON_ARGS}
    meson compile -C "${BUILD_DIR}"
    DESTDIR=/opt/stage meson install -C "${BUILD_DIR}"
    ;;
  make)
    make ${MAKE_ARGS}
    mkdir -p /opt/stage/usr/local/bin
    find . -maxdepth 3 -type f -executable ! -path './.git/*' | head -5 | while read f; do cp "$f" /opt/stage/usr/local/bin/; done
    ;;
  autotools)
    [ -f configure.ac ] && [ ! -f configure ] && autoreconf -fi || true
    ./configure --prefix=/usr/local
    make ${MAKE_ARGS} && make DESTDIR=/opt/stage install
    ;;
esac
mkdir -p /out
FOUND=$(find /opt/stage ${BUILD_DIR} . -maxdepth 4 -type f -executable ! -name "*.so*" ! -path '*/.git/*' 2>/dev/null | head -1)
[ -z "$FOUND" ] && { echo "No binary found" >&2; exit 1; }
cp "$FOUND" /out/app && chmod +x /out/app
[ "$ENABLE_STRIP" = "1" ] && strip /out/app 2>/dev/null || true
ls -lh /out/app; file /out/app 2>/dev/null || true
EOF

FROM base-musl AS builder-static
WORKDIR /src
COPY . .
ARG CC CXX CFLAGS CXXFLAGS BUILD_TYPE BUILD_SYSTEM GENERATOR BINARY_NAME BUILD_DIR CMAKE_ARGS MESON_ARGS MAKE_ARGS
ENV CC=${CC:-gcc} CXX=${CXX:-g++} CFLAGS="${CFLAGS} -static" CXXFLAGS="${CXXFLAGS} -static" LDFLAGS="-static"
RUN <<'EOF'
#!/bin/bash
set -e
SYS="${BUILD_SYSTEM}"
[ "$SYS" = "auto" ] && { [ -f CMakeLists.txt ] && SYS=cmake; [ -f meson.build ] && SYS=meson; [ -f Makefile ] && SYS=make; }
mkdir -p "${BUILD_DIR}"
case "$SYS" in
  cmake) cmake -S . -B "${BUILD_DIR}" -G "${GENERATOR}" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_EXE_LINKER_FLAGS="-static" ${CMAKE_ARGS}
         cmake --build "${BUILD_DIR}" -j"$(nproc)"; DESTDIR=/opt/stage cmake --install "${BUILD_DIR}" 2>/dev/null || true ;;
  meson) meson setup "${BUILD_DIR}" --buildtype=release --default-library=static ${MESON_ARGS}; meson compile -C "${BUILD_DIR}"; DESTDIR=/opt/stage meson install -C "${BUILD_DIR}" ;;
  make) make ${MAKE_ARGS} LDFLAGS="-static"; mkdir -p /opt/stage/usr/local/bin; find . -maxdepth 3 -type f -executable ! -path './.git/*' | head -3 | while read f; do cp "$f" /opt/stage/usr/local/bin/; done ;;
esac
mkdir -p /out
FOUND=$(find /opt/stage ${BUILD_DIR} . -maxdepth 4 -type f -executable ! -name "*.so*" ! -path '*/.git/*' 2>/dev/null | head -1)
cp "$FOUND" /out/app && chmod +x /out/app && strip /out/app 2>/dev/null || true
EOF

FROM ${RUN_IMAGE:-scratch} AS prod
ARG BIN_PATH=/usr/local/bin/app APP_UID=10001 APP_GID=10001 PORT=8080 TZ=UTC
COPY --from=static-assets /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=static-assets /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=static-assets /etc/passwd /etc/passwd
COPY --from=static-assets /etc/group /etc/group
COPY --from=static-assets /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=static-assets --chmod=1777 /tmp /tmp
COPY --from=static-assets --chown=${APP_UID}:${APP_GID} /home/dexfile /home/dexfile
COPY --from=builder --chown=${APP_UID}:${APP_GID} /out/app ${BIN_PATH}
COPY --from=lang-detector /language /etc/dexfile-language
COPY --from=buildsys-detector /buildsys /etc/dexfile-buildsys
ENV HOME=/home/dexfile TZ=${TZ} SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
USER ${APP_UID}:${APP_GID}
WORKDIR /home/dexfile
ENTRYPOINT ["/usr/local/bin/app"]
EXPOSE ${PORT}

FROM scratch AS prod-static
ARG BIN_PATH=/usr/local/bin/app APP_UID=10001 APP_GID=10001 PORT=8080 TZ=UTC
COPY --from=static-assets /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=static-assets /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=static-assets /etc/passwd /etc/passwd
COPY --from=static-assets /etc/group /etc/group
COPY --from=static-assets /etc/nsswitch.conf /etc/nsswitch.conf
COPY --from=static-assets --chmod=1777 /tmp /tmp
COPY --from=static-assets --chown=${APP_UID}:${APP_GID} /home/dexfile /home/dexfile
COPY --from=builder-static --chown=${APP_UID}:${APP_GID} /out/app ${BIN_PATH}
USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/usr/local/bin/app"]
EXPOSE ${PORT}

FROM prod AS release
ARG PORT=8080 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title="C/C++ Application" \
      security.non-root="true" security.uid="${APP_UID}" app.language="c-cpp" app.port="${PORT}"

FROM release
