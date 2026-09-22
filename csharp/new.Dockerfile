# syntax=dexnore/dexfile:0

# Production-ready C# .NET Dexfile supporting:
# - Runtimes: .NET 9, .NET 8 (LTS), .NET 6/7, Native AOT, Mono, CoreCLR
# - Package Managers: NuGet, Paket, MyGet, ProGet, Libman
# - Frameworks: ASP.NET Core, Blazor (Server/WASM/Hybrid), OpenSilver, Uno Platform, MAUI
# - Web Servers: Kestrel, OWIN/Katana, HttpSys
# - Deployment: Azure Functions, AWS Lambda, Native AOT, Self-contained, Framework-dependent
# - Distributed: Microsoft Orleans, Dapr, Aspire
# - Base Images: Chiseled Ubuntu, Alpine, Mariner (CBL-Mariner), Debian

ARG DOTNET_VERSION DOTNET_RUNTIME BUILD_IMAGE RUN_IMAGE
ARG FRAMEWORK_TYPE DEPLOYMENT_TYPE BUILD_CONFIGURATION=Release
ARG TARGET_RID
ARG RUNTIME_FLAVOR=chiseled
ARG GLOBALIZATION_INVARIANT=false
ARG PUBLISH_TRIMMED=auto
ARG PUBLISH_SINGLE_FILE=auto
ARG PUBLISH_READYTORUN=false
ARG RESTORE_LOCKED=auto
ARG ENABLE_TESTS=false
ARG TEST_CONFIGURATION=Release
ARG TEST_FILTER
ARG ENABLE_SOURCE_LINK=true
ARG ENABLE_DETERMINISTIC=true
ARG ENABLE_RUNTIME_DIAGNOSTICS=false
ARG NUGET_PACKAGES=/root/.nuget/packages
ARG NUGET_HTTP_CACHE=/root/.local/share/NuGet/http-cache
ARG PRIVATE_FEED_SECRET_ID=nuget-config
ARG PROJECT_TYPE PACKAGE_MANAGER ENABLE_AOT=false
ARG PORT=8080 ASPNETCORE_HTTP_PORTS=8080
ARG NGINX_ROOT="/usr/share/nginx/html"

WORKDIR /home/dexfile/app

# ============================================================================
# .NET VERSION DETECTION
# ============================================================================
FUNC detect_dotnet_version
    # Priority 1: global.json (most reliable for .NET SDK version)
    IF PROC --from=busybox:latest --mount=target=. [ -f "global.json" ]
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(grep -oP '"version":\s*"\K[^"]+' global.json) && echo "$VERSION"
            ARG DOTNET_VERSION=${STDOUT}
        ENDIF
    # Priority 2: .NET version file (custom)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f ".dotnet-version" ]
        ARG DOTNET_VERSION=$(cat .dotnet-version | tr -d '\n')
    # Priority 3: Check TargetFramework in .csproj files
    ELSE IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 2 -name "*.csproj" -exec grep -l "TargetFramework" {} \; | head -1
        IF PROC --from=busybox:latest --mount=target=. VERSION=$(find . -maxdepth 2 -name "*.csproj" -exec grep -oP '<TargetFramework>net\K[^<]+' {} \; | head -1) && echo "$VERSION"
            ARG DOTNET_VERSION=${STDOUT}
        ENDIF
    ELSE
        ARG DOTNET_VERSION="10.0"
    ENDIF
    
    # Normalize version (e.g., "9.0" -> "9.0", "9" -> "9.0")
    IF PROC [ -n "${DOTNET_VERSION}" ]
        IF PROC ! echo "${DOTNET_VERSION}" | grep -q '\.'
            ARG DOTNET_VERSION="${DOTNET_VERSION}.0"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# FRAMEWORK DETECTION
# ============================================================================
FUNC detect_framework
    # Check .csproj files for framework and project type
    IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 2 -name "*.csproj" | head -1
        # ASP.NET Core detection
        IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.Web' *.csproj
            ARG FRAMEWORK_TYPE="aspnetcore"
            ARG PROJECT_TYPE="web"
        # Blazor WebAssembly
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.BlazorWebAssembly' *.csproj
            ARG FRAMEWORK_TYPE="blazor-wasm"
            ARG PROJECT_TYPE="wasm"
        # Blazor detection via packages
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.AspNetCore.Components.WebAssembly' *.csproj
            ARG FRAMEWORK_TYPE="blazor-wasm"
            ARG PROJECT_TYPE="wasm"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.AspNetCore.Components.Server' *.csproj
            ARG FRAMEWORK_TYPE="blazor-server"
            ARG PROJECT_TYPE="web"
        # Azure Functions
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.Functions' *.csproj || grep -q 'Microsoft.Azure.Functions' *.csproj
            ARG FRAMEWORK_TYPE="azure-functions"
            ARG PROJECT_TYPE="functions"
        # AWS Lambda
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Amazon.Lambda' *.csproj
            ARG FRAMEWORK_TYPE="aws-lambda"
            ARG PROJECT_TYPE="lambda"
        # Orleans
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.Orleans' *.csproj
            ARG FRAMEWORK_TYPE="orleans"
            ARG PROJECT_TYPE="distributed"
        # Dapr
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Dapr' *.csproj || [ -f "dapr.yaml" ]
            ARG FRAMEWORK_TYPE="dapr"
            ARG PROJECT_TYPE="distributed"
        # Aspire
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Aspire' *.csproj || [ -f "aspire.json" ]
            ARG FRAMEWORK_TYPE="aspire"
            ARG PROJECT_TYPE="distributed"
        # OpenSilver
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'OpenSilver' *.csproj
            ARG FRAMEWORK_TYPE="opensilver"
            ARG PROJECT_TYPE="wasm"
        # Uno Platform
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Uno.UI' *.csproj
            ARG FRAMEWORK_TYPE="uno-platform"
            ARG PROJECT_TYPE="cross-platform"
        # MAUI
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.NET.Sdk.Maui' *.csproj
            ARG FRAMEWORK_TYPE="maui"
            ARG PROJECT_TYPE="cross-platform"
        # Worker Service
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Microsoft.Extensions.Hosting' *.csproj && grep -q 'BackgroundService' *.csproj
            ARG FRAMEWORK_TYPE="worker"
            ARG PROJECT_TYPE="service"
        # gRPC
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'Grpc.AspNetCore' *.csproj
            ARG FRAMEWORK_TYPE="grpc"
            ARG PROJECT_TYPE="web"
        # Console/Generic
        ELSE
            ARG FRAMEWORK_TYPE="console"
            ARG PROJECT_TYPE="console"
        ENDIF
    ELSE
        RUN echo "ERROR: No .csproj file found" >&2 && exit 1
    ENDIF
ENDFUNC

# ============================================================================
# NATIVE AOT DETECTION
# ============================================================================
FUNC detect_native_aot
    # Check for PublishAot property in .csproj
    IF PROC --from=busybox:latest --mount=target=. grep -q '<PublishAot>true</PublishAot>' *.csproj
        ARG ENABLE_AOT=true
        ARG DEPLOYMENT_TYPE="native-aot"
    # Check for Native AOT in properties
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '<PublishTrimmed>true</PublishTrimmed>' *.csproj && grep -q '<PublishReadyToRun>true</PublishReadyToRun>' *.csproj
        ARG DEPLOYMENT_TYPE="trimmed"
    # Check for self-contained
    ELSE IF PROC --from=busybox:latest --mount=target=. grep -q '<SelfContained>true</SelfContained>' *.csproj
        ARG DEPLOYMENT_TYPE="self-contained"
    ELSE
        ARG DEPLOYMENT_TYPE="framework-dependent"
    ENDIF
ENDFUNC

# ============================================================================
# PACKAGE MANAGER DETECTION
# ============================================================================
FUNC detect_package_manager
    # Priority 1: Paket
    IF PROC --from=busybox:latest --mount=target=. [ -f "paket.dependencies" ] || [ -f "paket.lock" ]
        ARG PACKAGE_MANAGER="paket"
    # Priority 2: Custom NuGet configs
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "NuGet.config" ]
        IF PROC --from=busybox:latest --mount=target=. grep -q 'myget.org' NuGet.config
            ARG PACKAGE_MANAGER="myget"
        ELSE IF PROC --from=busybox:latest --mount=target=. grep -q 'proget' NuGet.config
            ARG PACKAGE_MANAGER="proget"
        ELSE
            ARG PACKAGE_MANAGER="nuget"
        ENDIF
    # Priority 3: Libman (for client-side libraries)
    ELSE IF PROC --from=busybox:latest --mount=target=. [ -f "libman.json" ]
        ARG PACKAGE_MANAGER="libman+nuget"
    ELSE
        ARG PACKAGE_MANAGER="nuget"
    ENDIF
ENDFUNC

# ============================================================================
# RUNTIME IMAGE SELECTION
# ============================================================================
FUNC select_runtime_image
    # For WASM projects, use nginx
    IF PROC [ "${PROJECT_TYPE}" = "wasm" ]
        ARG RUN_IMAGE="nginx:stable-alpine"
        RETURN
    ENDIF
    
    # For Native AOT, use minimal runtime-deps or chiseled
    IF PROC [ "${ENABLE_AOT}" = "true" ]
        # Chiseled Ubuntu for Native AOT (smallest, most secure)
        ARG RUN_IMAGE="mcr.microsoft.com/dotnet/runtime-deps:${DOTNET_VERSION}-noble-chiseled"
    # For standard runtime
    ELSE
        # Check for preferred base image in .dockerignore comments or config
        IF PROC --from=busybox:latest --mount=target=. [ -f ".dotnet-runtime" ]
            ARG RUNTIME_PREF=$(cat .dotnet-runtime | tr -d '\n')
            IF PROC [ "${RUNTIME_PREF}" = "alpine" ]
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-alpine"
            ELSE IF PROC [ "${RUNTIME_PREF}" = "mariner" ]
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-cbl-mariner"
            ELSE IF PROC [ "${RUNTIME_PREF}" = "chiseled" ]
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled"
            ELSE
                ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-bookworm-slim"
            ENDIF
        ELSE
            # Default: Chiseled Ubuntu for best security/size balance
            ARG RUN_IMAGE="mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled"
        ENDIF
    ENDIF
ENDFUNC

# ============================================================================
# SOLUTION/PROJECT DETECTION
# ============================================================================
FUNC detect_solution_structure
    # Check if solution file exists
    IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 1 -name "*.sln" | head -1
        ARG SOLUTION_FILE=$(find . -maxdepth 1 -name "*.sln" | head -1)
    ENDIF
    
    # Find the main project file
    IF PROC --from=busybox:latest --mount=target=. find . -name "*.csproj" | grep -v "Tests" | grep -v "Test" | head -1
        ARG PROJECT_FILE=$(find . -name "*.csproj" | grep -v "Tests" | grep -v "Test" | head -1)
    ENDIF
ENDFUNC

# ============================================================================
# WORKSPACE / REPRODUCIBILITY POLICY
# ============================================================================
FUNC detect_workspace_policy
    ARG WORKSPACE_TYPE="single-project"
    IF PROC --from=busybox:latest --mount=target=. [ -f "Directory.Packages.props" ]
        ARG WORKSPACE_TYPE="central-package-management"
    ELSE IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 2 -name "*.slnx" | head -1
        ARG WORKSPACE_TYPE="solutionx"
    ELSE IF PROC --from=busybox:latest --mount=target=. find . -maxdepth 2 -name "*.sln" | head -1
        ARG WORKSPACE_TYPE="solution"
    ENDIF
ENDFUNC
FUNC detect_publish_policy
    ARG PUBLISH_TRIMMED_EFFECTIVE=false
    ARG PUBLISH_SINGLE_FILE_EFFECTIVE=false
    IF PROC [ "${PUBLISH_TRIMMED}" = "true" ] || PROC [ "${PUBLISH_TRIMMED}" = "auto" ] && PROC grep -Rqi "<PublishTrimmed>true</PublishTrimmed>" --include="*.csproj" .
        ARG PUBLISH_TRIMMED_EFFECTIVE=true
    ENDIF
    IF PROC [ "${PUBLISH_SINGLE_FILE}" = "true" ] || PROC [ "${PUBLISH_SINGLE_FILE}" = "auto" ] && PROC grep -Rqi "<PublishSingleFile>true</PublishSingleFile>" --include="*.csproj" .
        ARG PUBLISH_SINGLE_FILE_EFFECTIVE=true
    ENDIF
    ARG PUBLISH_TRIMMED=${PUBLISH_TRIMMED_EFFECTIVE}
    ARG PUBLISH_SINGLE_FILE=${PUBLISH_SINGLE_FILE_EFFECTIVE}
ENDFUNC
FUNC CALL detect_workspace_policy
FUNC CALL detect_publish_policy

# ============================================================================
# RUN DETECTIONS
# ============================================================================
FUNC CALL detect_dotnet_version
FUNC CALL detect_framework
FUNC CALL detect_native_aot
FUNC CALL detect_package_manager
FUNC CALL detect_solution_structure
FUNC CALL select_runtime_image

# Set build image based on version
IF PROC [ -n "${DOTNET_VERSION}" ]
    ARG BUILD_IMAGE="mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}"
ELSE
    ARG BUILD_IMAGE="mcr.microsoft.com/dotnet/sdk:10.0"
ENDIF

# ============================================================================
# BASE BUILD STAGE
# ============================================================================
FROM ${BUILD_IMAGE} AS base

# Install additional build tools for Native AOT
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        clang \
        zlib1g-dev \
        wget \
        curl \
        ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /home/dexfile/app

# Set environment variables
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV DOTNET_NOLOGO=1
ENV ASPNETCORE_ENVIRONMENT=Production

# ============================================================================
# RESTORE STAGE (dependency caching)
# ============================================================================
FROM base AS restore

WORKDIR /home/dexnore/app
COPY global.json* .dotnet-version* ./
COPY NuGet.config* nuget.config* ./
COPY Directory.Build.props Directory.Build.targets Directory.Packages.props ./
COPY *.sln* ./
COPY */*.csproj ./
COPY **/*.csproj ./
COPY packages.lock.json ./
COPY **/packages.lock.json ./
COPY paket.dependencies paket.lock ./
COPY .config/dotnet-tools.json ./.config/dotnet-tools.json

RUN --mount=type=cache,id=dotnet-nuget,target=${NUGET_PACKAGES},sharing=locked \
    --mount=type=cache,id=dotnet-http,target=${NUGET_HTTP_CACHE},sharing=locked \
    --mount=type=secret,id=${PRIVATE_FEED_SECRET_ID},target=/tmp/NuGet.config,required=false \
    set -eu; \
    if [ -f /tmp/NuGet.config ]; then cp /tmp/NuGet.config ./NuGet.config; fi; \
    if [ -f .config/dotnet-tools.json ]; then dotnet tool restore; fi; \
    if [ "${PACKAGE_MANAGER}" = "paket" ]; then dotnet tool install --tool-path /tmp/paket paket --version 8.* >/dev/null 2>&1 || true; /tmp/paket/paket restore; \
    elif [ -n "${SOLUTION_FILE}" ]; then dotnet restore "${SOLUTION_FILE}" --nologo; \
    elif [ -n "${PROJECT_FILE}" ]; then dotnet restore "${PROJECT_FILE}" --nologo; \
    else dotnet restore --nologo; fi; \
    rm -f ./NuGet.config

# ============================================================================
# BUILD STAGE
# ============================================================================
FROM restore AS build
WORKDIR /home/dexnore/app
COPY . .
RUN --mount=type=cache,id=dotnet-nuget,target=${NUGET_PACKAGES},sharing=locked \
    set -eu; \
    PROPS="/p:Deterministic=${ENABLE_DETERMINISTIC}"; \
    if [ "${ENABLE_SOURCE_LINK}" = "true" ]; then PROPS="${PROPS} /p:ContinuousIntegrationBuild=true /p:EnableSourceLink=true"; fi; \
    if [ -n "${SOLUTION_FILE}" ]; then dotnet build "${SOLUTION_FILE}" --configuration ${BUILD_CONFIGURATION} --no-restore --nologo $PROPS; \
    elif [ -n "${PROJECT_FILE}" ]; then dotnet build "${PROJECT_FILE}" --configuration ${BUILD_CONFIGURATION} --no-restore --nologo $PROPS; \
    else dotnet build --configuration ${BUILD_CONFIGURATION} --no-restore --nologo $PROPS; fi

FROM build AS test
RUN --mount=type=cache,id=dotnet-nuget,target=${NUGET_PACKAGES},sharing=locked \
    set -eu; \
    if [ "${ENABLE_TESTS}" = "true" ]; then \
      if [ -n "${SOLUTION_FILE}" ]; then dotnet test "${SOLUTION_FILE}" --configuration ${TEST_CONFIGURATION} --no-build --no-restore --nologo; \
      else dotnet test "${PROJECT_FILE}" --configuration ${TEST_CONFIGURATION} --no-build --no-restore --nologo; fi; \
    fi

============================================================================
# BUILD STAGE
# ============================================================================
FROM restore AS build

# Copy all source files
COPY . .

# Build the application
RUN --mount=type=cache,id=nuget-packages,target=/root/.nuget/packages,sharing=locked \
    set -e; \
    if [ -n "${SOLUTION_FILE}" ]; then \
        dotnet build "${SOLUTION_FILE}" \
            --configuration ${BUILD_CONFIGURATION} \
            --no-restore; \
    elif [ -n "${PROJECT_FILE}" ]; then \
        dotnet build "${PROJECT_FILE}" \
            --configuration ${BUILD_CONFIGURATION} \
            --no-restore; \
    else \
        dotnet build \
            --configuration ${BUILD_CONFIGURATION} \
            --no-restore; \
    fi

# ============================================================================
# PUBLISH STAGE
# ============================================================================
FROM build AS publish
WORKDIR /home/dexnore/app
RUN --mount=type=cache,id=dotnet-nuget,target=${NUGET_PACKAGES},sharing=locked \
    set -eu; \
    ARGS="--configuration ${BUILD_CONFIGURATION} --no-restore --nologo --output /app/publish"; \
    if [ "${ENABLE_AOT}" = "true" ]; then ARGS="${ARGS} --self-contained true /p:PublishAot=true /p:StripSymbols=true"; fi; \
    if [ "${DEPLOYMENT_TYPE}" = "self-contained" ]; then ARGS="${ARGS} --self-contained true"; fi; \
    if [ "${DEPLOYMENT_TYPE}" = "framework-dependent" ]; then ARGS="${ARGS} --self-contained false"; fi; \
    if [ "${PUBLISH_TRIMMED}" = "true" ]; then ARGS="${ARGS} /p:PublishTrimmed=true"; fi; \
    if [ "${PUBLISH_SINGLE_FILE}" = "true" ]; then ARGS="${ARGS} /p:PublishSingleFile=true"; fi; \
    if [ "${PUBLISH_READYTORUN}" = "true" ]; then ARGS="${ARGS} /p:PublishReadyToRun=true"; fi; \
    if [ -n "${TARGET_RID}" ]; then ARGS="${ARGS} --runtime ${TARGET_RID}"; fi; \
    if [ -n "${PROJECT_FILE}" ]; then dotnet publish "${PROJECT_FILE}" $ARGS; else dotnet publish $ARGS; fi

# ============================================================================
# RUNTIME BASE STAGE
# ============================================================================
FROM ${RUN_IMAGE} AS app
WORKDIR /app
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_HTTP_PORTS=${ASPNETCORE_HTTP_PORTS}
ENV ASPNETCORE_URLS=http://+:${PORT}
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=${GLOBALIZATION_INVARIANT}
ENV TMPDIR=/tmp
ENV TEMP=/tmp
ENV TMP=/tmp
IF PROC [ "${ENABLE_RUNTIME_DIAGNOSTICS}" = "false" ]
    ENV DOTNET_EnableDiagnostics=0
    ENV COMPlus_EnableDiagnostics=0
ENDIF
EXPOSE ${PORT}

# ============================================================================
# RELEASE STAGE
# ============================================================================
FROM app AS release
USER 1654:1654
IF PROC [ "${PROJECT_TYPE}" = "wasm" ]
    WORKDIR ${NGINX_ROOT}
    COPY --from=publish /app/publish/wwwroot/ ${NGINX_ROOT}/
    USER nginx
    EXPOSE 80
    CMD ["nginx", "-g", "daemon off;"]
ELSE
    COPY --from=publish --chown=1654:1654 /app/publish/ ./
    IF PROC [ "${ENABLE_AOT}" = "true" ]
        CMD ["./app"]
    ELSE
        CMD ["dotnet", "app.dll"]
    ENDIF
ENDIF
HEALTHCHECK NONE
LABEL org.opencontainers.image.vendor="Dexnore"
LABEL org.opencontainers.image.title="Production .NET Application"
LABEL org.opencontainers.image.source="https://github.com/ep0ll/templates"
LABEL org.opencontainers.image.language="csharp"
LABEL app.framework="${FRAMEWORK_TYPE}"
LABEL app.dotnet-version="${DOTNET_VERSION}"
LABEL app.deployment-type="${DEPLOYMENT_TYPE}"
LABEL app.package-manager="${PACKAGE_MANAGER}"
LABEL app.native-aot="${ENABLE_AOT}"
LABEL app.workspace="${WORKSPACE_TYPE}"
LABEL app.target-rid="${TARGET_RID}"
LABEL app.non-root="true"
LABEL app.runtime-flavor="${RUNTIME_FLAVOR}"

FROM release

# ============================================================================
# C# / .NET PRODUCTION STANDARD
# ============================================================================
# Ecosystems: .NET SDK/MSBuild, NuGet, private NuGet feeds, Paket, LibMan,
# repository-local dotnet tools and central package management.
# Workspaces: .sln, .slnx, nested csproj/fsproj/vbproj, Directory.Build.*,
# Directory.Packages.props, packages.lock.json, global.json and dotnet-tools.
# Frameworks: ASP.NET Core, Minimal APIs, MVC, Razor Pages, Blazor, SignalR,
# gRPC, YARP, Worker Services, EF Core, Orleans, Dapr, Aspire, Azure Functions,
# AWS Lambda and Native AOT.
# Publishing: framework-dependent, self-contained, RID-specific, trimming,
# single-file, ReadyToRun and Native AOT.
#
# Cache: dependency manifests precede source; NuGet packages and HTTP metadata
# use BuildKit cache mounts; restore/build/publish remain separate stages.
# Secrets: use PRIVATE_FEED_SECRET_ID (default nuget-config) for private feeds.
# Never put package credentials in ARG, ENV or final image layers.
# Reproducibility: pin SDK with global.json, commit lock files, use
# RESTORE_LOCKED=true, pin TARGET_RID, and keep deterministic builds enabled.
# Security: runtime is UID 1654; SDK/compiler/git/package tools never enter the
# runtime; diagnostics are disabled by default; chiseled images omit shells and
# package managers; health probes belong to the orchestrator.
# Operations: generate SBOM/provenance, scan the image, push by digest, deploy
# immutable digests, and inject secrets/configuration at runtime.
# AOT/trimming require application-level compatibility validation for reflection,
# dynamic loading and native dependencies. EF migrations should be explicit
# deployment jobs rather than implicit startup mutations.
# ============================================================================
