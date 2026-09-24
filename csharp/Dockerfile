# syntax=dexnore/dexfile:0
# Universal Production-Ready .NET / C# Dexfile
# Web/Minimal/MVC/Blazor/Worker/gRPC, PublishAot, NuGet audit, non-root

ARG DOTNET_VERSION=8.0
ARG PROJECT_FILE=""
ARG SOLUTION_FILE=""
ARG CONFIGURATION=Release
ARG PUBLISH_AOT=false
ARG PUBLISH_TRIMMED=false
ARG PUBLISH_SINGLE_FILE=false
ARG SELF_CONTAINED=false
ARG RUNTIME_ID=""
ARG ENTRY_DLL=""
ARG PORT=8080
ARG ASPNETCORE_URLS=http://+:8080
ARG ASPNETCORE_ENVIRONMENT=Production
ARG APP_UID=10001
ARG APP_GID=10001
ARG APP_USER=dexfile
ARG TZ=UTC
ARG ENABLE_VULN_CHECK=1
ARG BUILD_IMAGE
ARG RUN_IMAGE

FROM busybox:latest AS validator
WORKDIR /validate
COPY . .
RUN find . -maxdepth 5 \( -name "*.csproj" -o -name "*.fsproj" \) | grep -q . || (echo "No .NET project" >&2; exit 1)

FROM busybox:latest AS version-detector
WORKDIR /detect
COPY global.json Directory.Build.props *.csproj *.fsproj ./
RUN <<'D'
#!/bin/sh
V=""
[ -f global.json ] && V=$(grep -oE '"version"\s*:\s*"[0-9.]+' global.json 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+')
[ -z "$V" ] && for f in *.csproj; do [ -f "$f" ] && V=$(grep -oE 'net[0-9]+\.[0-9]+' "$f" 2>/dev/null | head -1 | sed 's/net//') && [ -n "$V" ] && break; done
[ -z "$V" ] && V="8.0"
echo "$V" > /dotnet-version
D

FROM busybox:latest AS project-detector
WORKDIR /detect
COPY . .
RUN <<'D'
#!/bin/sh
TYPE="console"; SDK="Microsoft.NET.Sdk"; ENTRY="App.dll"
PROJ=$(find . -maxdepth 4 \( -name "*.csproj" -o -name "*.fsproj" \) | head -1)
if [ -n "$PROJ" ]; then
  NAME=$(basename "$PROJ" | sed 's/\.csproj$//;s/\.fsproj$//')
  ENTRY="${NAME}.dll"
  grep -q "Microsoft.NET.Sdk.Web" "$PROJ" 2>/dev/null && { SDK="Microsoft.NET.Sdk.Web"; TYPE="web"; }
  grep -q "Microsoft.NET.Sdk.Worker" "$PROJ" 2>/dev/null && { SDK="Microsoft.NET.Sdk.Worker"; TYPE="worker"; }
  grep -rq "MapGet\|WebApplication.CreateBuilder" --include="*.cs" . 2>/dev/null && TYPE="minimal-api"
  grep -rq "AddControllers" --include="*.cs" . 2>/dev/null && TYPE="mvc"
  grep -rq "AddServerSideBlazor\|MapBlazorHub" --include="*.cs" . 2>/dev/null && TYPE="blazor-server"
  grep -rq "AddGrpc\|MapGrpcService" --include="*.cs" . 2>/dev/null && TYPE="grpc"
fi
echo "$TYPE" > /project-type
echo "$ENTRY" > /entry-dll
echo "$SDK" > /sdk
D

FROM ${BUILD_IMAGE:-mcr.microsoft.com/dotnet/sdk:8.0} AS base
WORKDIR /src
RUN apt-get update -qq && apt-get install --no-install-recommends -y curl git ca-certificates && rm -rf /var/lib/apt/lists/*

FROM base AS restore
WORKDIR /src
COPY . .
ARG SOLUTION_FILE PROJECT_FILE ENABLE_VULN_CHECK
RUN --mount=type=cache,target=/root/.nuget/packages,id=nuget-packages \
    --mount=type=cache,target=/root/.local/share/NuGet,id=nuget-http \
    <<'EOF'
#!/bin/bash
set -e
TARGET="${SOLUTION_FILE:-${PROJECT_FILE}}"
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && TARGET=$(find . -maxdepth 3 -name "*.sln" | head -1)
[ -z "$TARGET" ] && TARGET=$(find . -maxdepth 4 -name "*.csproj" | head -1)
echo "Restoring $TARGET"
dotnet restore "$TARGET"
[ "${ENABLE_VULN_CHECK}" = "1" ] && dotnet list "$TARGET" package --vulnerable --include-transitive 2>/dev/null || true
EOF

FROM restore AS build
WORKDIR /src
ARG CONFIGURATION PROJECT_FILE SOLUTION_FILE
RUN --mount=type=cache,target=/root/.nuget/packages,id=nuget-packages \
    <<'EOF'
#!/bin/bash
set -e
TARGET="${SOLUTION_FILE:-${PROJECT_FILE}}"
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && TARGET=$(find . -maxdepth 3 -name "*.sln" | head -1)
[ -z "$TARGET" ] && TARGET=$(find . -maxdepth 4 -name "*.csproj" | head -1)
dotnet build "$TARGET" -c "${CONFIGURATION}" --no-restore
EOF

FROM build AS publish
WORKDIR /src
ARG CONFIGURATION PROJECT_FILE PUBLISH_AOT PUBLISH_TRIMMED PUBLISH_SINGLE_FILE SELF_CONTAINED RUNTIME_ID ENTRY_DLL
RUN --mount=type=cache,target=/root/.nuget/packages,id=nuget-packages \
    <<'EOF'
#!/bin/bash
set -e
PROJ="${PROJECT_FILE}"
[ -z "$PROJ" ] || [ ! -f "$PROJ" ] && PROJ=$(find . -maxdepth 4 -name "*.csproj" | while read p; do grep -q "Sdk.Web\|Sdk.Worker" "$p" 2>/dev/null && echo "$p" && break; done)
[ -z "$PROJ" ] && PROJ=$(find . -maxdepth 4 -name "*.csproj" | head -1)
EXTRA=""
[ "${PUBLISH_AOT}" = "true" ] && EXTRA="$EXTRA -p:PublishAot=true"
[ "${PUBLISH_TRIMMED}" = "true" ] && EXTRA="$EXTRA -p:PublishTrimmed=true"
[ "${PUBLISH_SINGLE_FILE}" = "true" ] && EXTRA="$EXTRA -p:PublishSingleFile=true"
[ "${SELF_CONTAINED}" = "true" ] && EXTRA="$EXTRA --self-contained true"
[ "${SELF_CONTAINED}" = "false" ] && EXTRA="$EXTRA --self-contained false"
[ -n "${RUNTIME_ID}" ] && EXTRA="$EXTRA -r ${RUNTIME_ID}"
dotnet publish "$PROJ" -c "${CONFIGURATION}" -o /app/publish --no-restore $EXTRA
NAME=$(basename "$PROJ" | sed 's/\.csproj$//')
if [ -n "${ENTRY_DLL}" ]; then echo "${ENTRY_DLL}" > /app/publish/entry.dll.name
elif [ -f "/app/publish/${NAME}.dll" ]; then echo "${NAME}.dll" > /app/publish/entry.dll.name
else ls /app/publish/*.dll | grep -v -E 'Microsoft.|System.' | head -1 | xargs basename > /app/publish/entry.dll.name || echo App.dll > /app/publish/entry.dll.name
fi
ls -la /app/publish
EOF

FROM ${RUN_IMAGE:-mcr.microsoft.com/dotnet/aspnet:8.0} AS prod
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile PORT=8080
ARG ASPNETCORE_URLS ASPNETCORE_ENVIRONMENT TZ ENTRY_DLL
WORKDIR /app
RUN groupadd --system --gid ${APP_GID} ${APP_USER} && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER} /app && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER} /app
COPY --from=publish --chown=${APP_UID}:${APP_GID} /app/publish .
COPY --from=project-detector /project-type /etc/dexfile-project-type
COPY --from=project-detector /entry-dll /etc/dexfile-entry-dll
COPY --from=version-detector /dotnet-version /etc/dexfile-dotnet-version
RUN DLL=$(cat /app/entry.dll.name 2>/dev/null || cat /etc/dexfile-entry-dll || echo App.dll); \
    [ -n "${ENTRY_DLL}" ] && DLL="${ENTRY_DLL}"; \
    echo "#!/bin/sh" > /app/entrypoint.sh && echo "exec dotnet \"$DLL\" \"\$@\"" >> /app/entrypoint.sh && chmod +x /app/entrypoint.sh
ENV ASPNETCORE_URLS=${ASPNETCORE_URLS} ASPNETCORE_ENVIRONMENT=${ASPNETCORE_ENVIRONMENT} \
    DOTNET_RUNNING_IN_CONTAINER=true HOME=/home/dexfile TZ=${TZ}
USER ${APP_UID}:${APP_GID}
EXPOSE ${PORT}
ENTRYPOINT ["/app/entrypoint.sh"]

FROM mcr.microsoft.com/dotnet/runtime:8.0 AS prod-runtime
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile ENTRY_DLL TZ
WORKDIR /app
RUN groupadd --system --gid ${APP_GID} ${APP_USER} && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER} /app && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER} /app
COPY --from=publish --chown=${APP_UID}:${APP_GID} /app/publish .
RUN DLL=$(cat /app/entry.dll.name 2>/dev/null || echo App.dll); \
    echo "#!/bin/sh" > /app/entrypoint.sh && echo "exec dotnet \"$DLL\" \"\$@\"" >> /app/entrypoint.sh && chmod +x /app/entrypoint.sh
USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/app/entrypoint.sh"]

FROM mcr.microsoft.com/dotnet/runtime-deps:8.0 AS prod-aot
ARG APP_UID=10001 APP_GID=10001 APP_USER=dexfile PORT=8080 TZ
WORKDIR /app
RUN groupadd --system --gid ${APP_GID} ${APP_USER} && \
    useradd --system --uid ${APP_UID} --gid ${APP_GID} --home /home/${APP_USER} --shell /usr/sbin/nologin ${APP_USER} && \
    mkdir -p /home/${APP_USER} /app && chown -R ${APP_UID}:${APP_GID} /home/${APP_USER} /app
COPY --from=publish --chown=${APP_UID}:${APP_GID} /app/publish .
RUN NAME=$(cat /app/entry.dll.name 2>/dev/null | sed 's/\.dll$//'); \
    if [ -x "/app/${NAME}" ]; then echo "#!/bin/sh" > /app/entrypoint.sh && echo "exec /app/${NAME} \"\$@\"" >> /app/entrypoint.sh; \
    else echo "#!/bin/sh" > /app/entrypoint.sh && echo "exec dotnet ${NAME}.dll \"\$@\"" >> /app/entrypoint.sh; fi && chmod +x /app/entrypoint.sh
USER ${APP_UID}:${APP_GID}
EXPOSE ${PORT}
ENTRYPOINT ["/app/entrypoint.sh"]

FROM prod AS release
ARG PORT=8080 APP_UID=10001
LABEL maintainer="@dexnore/dexfile" org.opencontainers.image.vendor="Dexnore" \
      org.opencontainers.image.title=".NET Application" \
      security.non-root="true" security.uid="${APP_UID}" app.language="csharp" app.port="${PORT}"

FROM release
