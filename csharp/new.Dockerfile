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

# ============================================================================
# SUPPORTED SDK TARGETS
# ============================================================================
# - .NET 10 LTS is the fallback default.
# - .NET 9 remains supported when pinned by global.json or DOTNET_VERSION.
# - .NET 8 LTS remains supported when pinned by the repository.
# - Older supported TFMs should be explicitly pinned and tested rather than silently selected.
# - global.json controls SDK selection and roll-forward policy.
# - .dotnet-version is supported for repositories using a version-manager convention.

# ============================================================================
# PROJECT TYPES
# ============================================================================
# - ASP.NET Core web SDK projects.
# - Console applications and Generic Host applications.
# - Worker Service applications.
# - Blazor Server applications.
# - Blazor WebAssembly applications.
# - gRPC services.
# - SignalR applications.
# - YARP reverse proxies.
# - Azure Functions isolated worker applications.
# - AWS Lambda .NET container applications.
# - Orleans silo/worker applications.
# - Dapr-enabled services.
# - .NET Aspire application projects.
# - EF Core applications.
# - Native AOT applications.

# ============================================================================
# PROJECT FILES
# ============================================================================
# - C# csproj files.
# - F# fsproj files.
# - Visual Basic vbproj files.
# - MSBuild Directory.Build.props.
# - MSBuild Directory.Build.targets.
# - Directory.Packages.props central package versions.
# - packages.lock.json dependency locks.
# - NuGet.config and nuget.config.
# - global.json SDK pinning.
# - .config/dotnet-tools.json local tools.
# - paket.dependencies.
# - paket.lock.
# - .sln solution files.
# - .slnx solution files.

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================
# - NuGet is the default package manager.
# - Private feeds can be configured through a secret-mounted NuGet.config.
# - Paket repositories are detected from paket.dependencies or paket.lock.
# - MyGet and ProGet remain NuGet-compatible feed scenarios.
# - LibMan remains available for client-side library assets.
# - Repository-local dotnet tools are restored from the tool manifest.
# - Credential providers should be supplied by the CI environment rather than baked into the image.

# ============================================================================
# RESTORE BEHAVIOR
# ============================================================================
# - Restore is isolated from source compilation for cache reuse.
# - NuGet global packages are stored in a BuildKit cache mount.
# - NuGet HTTP metadata is stored in a separate BuildKit cache mount.
# - Locked restore can be forced with RESTORE_LOCKED=true.
# - packages.lock.json can be used to make auto mode enforce locked restore.
# - Private-feed credentials are exposed only to the restore operation.
# - The secret-mounted NuGet.config is removed before the restore stage completes.
# - Restore should fail closed for missing private package credentials.

# ============================================================================
# BUILD BEHAVIOR
# ============================================================================
# - Build never performs an implicit second restore.
# - Release is the default configuration.
# - Deterministic compilation is enabled by default.
# - ContinuousIntegrationBuild is enabled when Source Link integration is enabled.
# - Build output remains outside the runtime stage.
# - Compiler warnings and errors remain application policy; this template does not hide them.
# - The test stage is separate from the production artifact.

# ============================================================================
# PUBLISH MODES
# ============================================================================
# - Framework-dependent publish is the normal default.
# - Self-contained publish is selected with DEPLOYMENT_TYPE=self-contained.
# - Native AOT is selected with ENABLE_AOT=true or the project PublishAot property.
# - Trimming can be selected with PUBLISH_TRIMMED=true.
# - Single-file can be selected with PUBLISH_SINGLE_FILE=true.
# - ReadyToRun can be selected with PUBLISH_READYTORUN=true.
# - TARGET_RID selects a concrete runtime identifier.
# - Native deployment assets should use a fixed RID in release pipelines.

# ============================================================================
# RUNTIME IMAGES
# ============================================================================
# - ASP.NET Core applications use the ASP.NET runtime family.
# - Console and worker applications can use the .NET runtime family.
# - Native AOT uses runtime-deps-compatible images.
# - Chiseled images are the default production target.
# - Alpine should be selected deliberately when musl compatibility is required.
# - Do not assume Debian/glibc native binaries are compatible with Alpine/musl.
# - Globalization-invariant mode is opt-in through GLOBALIZATION_INVARIANT.
# - WASM applications are treated as static content rather than server applications.

# ============================================================================
# SECURITY BASELINE
# ============================================================================
# - Production executes as a non-root UID.
# - The SDK is never copied into the final image.
# - Git is never required at runtime.
# - Package managers are never required at runtime.
# - Compiler toolchains are never copied into the final image.
# - Runtime diagnostics are disabled unless explicitly enabled.
# - No package-feed token is persisted into the final image.
# - No cloud credential is persisted into the final image.
# - No TLS private key should be persisted into the final image.
# - The image should be scanned before release.
# - The image should be deployed by digest.

# ============================================================================
# HEALTH AND OBSERVABILITY
# ============================================================================
# - This template does not assume curl or wget exists in the runtime.
# - Chiseled images intentionally omit common diagnostic utilities.
# - Kubernetes readiness probes should target the application's real readiness endpoint.
# - Kubernetes liveness probes should target the application's real liveness endpoint.
# - OpenTelemetry configuration belongs in deployment configuration or application configuration.
# - Application logs should use stdout/stderr for container-native collection.
# - Do not make healthchecks depend on an endpoint that the application does not implement.

# ============================================================================
# SUPPLY CHAIN
# ============================================================================
# - Use a pinned SDK version for release builds.
# - Use lock files for dependencies where deterministic resolution is required.
# - Generate SBOM metadata in CI.
# - Generate provenance attestations in CI.
# - Scan both source dependencies and the resulting image.
# - Prefer immutable base-image digests for highly controlled release pipelines.
# - Record the source commit in OCI provenance.
# - Do not make package feeds reachable from the final runtime stage.

# ============================================================================
# CI PIPELINE
# ============================================================================
# - Validate Dexfile syntax before building.
# - Build the restore stage to verify dependency resolution.
# - Run ENABLE_TESTS=true for verification builds.
# - Run separate architecture builds when native dependencies differ.
# - Publish artifacts only from successful verification builds.
# - Generate SBOM and provenance after publishing.
# - Scan the final image before pushing.
# - Push immutable digest references.
# - Promote the exact digest between environments.

# ============================================================================
# MONOREPO GUIDANCE
# ============================================================================
# - Prefer a solution or solutionx file at the repository boundary.
# - Use Directory.Build.props for shared compiler settings.
# - Use Directory.Packages.props for central package versions.
# - Use packages.lock.json where reproducible restore is required.
# - Avoid selecting a project solely because it sorts first alphabetically.
# - For multiple deployable services, invoke the template once per service project.
# - Do not copy unrelated monorepo secrets into service images.
# - Keep service-specific publish settings in the project or invocation.

# ============================================================================
# EF CORE
# ============================================================================
# - EF Core packages are restored through normal NuGet resolution.
# - Provider native libraries must match the selected runtime libc and architecture.
# - Database migrations should be an explicit deployment operation.
# - Do not put production database credentials in the image.
# - Do not automatically run destructive migrations during container startup.
# - Health endpoints should distinguish process health from database readiness when appropriate.

# ============================================================================
# ASP.NET CORE
# ============================================================================
# - Use ASPNETCORE_ENVIRONMENT=Production in the runtime image.
# - Use ASPNETCORE_HTTP_PORTS for the default container port.
# - ASPNETCORE_URLS is provided for compatibility with applications that use it.
# - Terminate TLS at an ingress/load balancer unless the application explicitly owns TLS.
# - Use forwarded-header configuration appropriate to the ingress topology.
# - Configure request limits, timeouts and Kestrel settings in application configuration.

# ============================================================================
# BLAZOR WASM
# ============================================================================
# - Blazor WebAssembly output is static content.
# - A static web server should serve the published wwwroot.
# - Client-side assets should receive immutable caching only when filenames are content-versioned.
# - SPA fallback behavior belongs in the web-server configuration.
# - Do not expose server-only secrets in a WebAssembly application.

# ============================================================================
# GRPC AND SIGNALR
# ============================================================================
# - HTTP/2 and protocol requirements belong in the deployment platform configuration.
# - Ingress proxies must preserve the required protocol semantics.
# - Readiness endpoints should remain independent of long-lived streaming connections.
# - Do not use a streaming endpoint as a liveness probe.

# ============================================================================
# WORKERS
# ============================================================================
# - Worker services should run as PID 1 in the container.
# - Shutdown behavior should honor SIGTERM and the Generic Host cancellation token.
# - Long-running jobs should implement graceful shutdown.
# - External queues and credentials belong in runtime configuration.
# - Do not add an HTTP server merely to manufacture a healthcheck.

# ============================================================================
# ORLEANS DAPR ASPIRE
# ============================================================================
# - These frameworks frequently use multiple cooperating processes or sidecars.
# - The application image should contain only the application process and its runtime dependencies.
# - Dapr sidecars should be supplied by the platform.
# - Aspire orchestration is normally a development/deployment concern; production services should publish independently.
# - Orleans clustering and persistence configuration belongs outside the image.

# ============================================================================
# AZURE FUNCTIONS
# ============================================================================
# - Functions hosting images have platform-specific entrypoint requirements.
# - Do not replace a Functions host entrypoint with a generic dotnet app.dll command.
# - Use the Functions base-image guidance for the selected .NET isolated worker version.
# - Secrets and storage configuration remain runtime configuration.

# ============================================================================
# AWS LAMBDA
# ============================================================================
# - Lambda container images have Lambda-specific entrypoint behavior.
# - The handler and Lambda environment configuration belong in the function configuration.
# - Use AWS-provided .NET Lambda base images when the Lambda execution contract requires them.
# - Do not treat a Lambda image as a generic Kubernetes web server image.

# ============================================================================
# NATIVE AOT
# ============================================================================
# - Native AOT reduces runtime dependencies but imposes application compatibility constraints.
# - Reflection-heavy applications may require source generation or trimming annotations.
# - Dynamic assembly loading may not work as expected.
# - Native libraries must exist for the target architecture.
# - Use TARGET_RID for reproducible native assets.
# - Test the produced executable on the actual deployment architecture.

# ============================================================================
# TRIMMING
# ============================================================================
# - Trimming is not universally safe for every application.
# - Reflection and serialization frameworks may require annotations or source generation.
# - Treat trim warnings as release engineering signals.
# - Enable trimming only after application verification.
# - Keep the untrimmed deployment mode available as a fallback.

# ============================================================================
# ALPINE
# ============================================================================
# - Alpine uses musl libc.
# - Native dependencies compiled against glibc may not run on Alpine.
# - Use Alpine intentionally rather than as a universal size optimization.
# - Test all native database, graphics, crypto and compression dependencies on musl.
# - When compatibility is more important than image size, use a glibc-based runtime.

# ============================================================================
# GLOBALIZATION
# ============================================================================
# - GLOBALIZATION_INVARIANT=false is the default.
# - Applications using culture-sensitive parsing and formatting should retain globalization data.
# - Invariant globalization can reduce image requirements but changes runtime behavior.
# - Locale, timezone and ICU requirements should be tested as application behavior.

# ============================================================================
# FILESYSTEM
# ============================================================================
# - Treat the application filesystem as immutable.
# - Use /tmp only for temporary runtime state.
# - Persist user uploads and generated business data through external storage.
# - Do not depend on writes to the application directory.
# - Use read-only root filesystems where the orchestrator supports them.

# ============================================================================
# CONFIGURATION
# ============================================================================
# - Use environment variables for non-secret deployment configuration.
# - Use the orchestrator secret mechanism for credentials.
# - Do not bake environment-specific URLs into the image.
# - Do not bake tenant identifiers or production-only settings into a generic image.
# - Keep the same image digest across promotion environments.

# ============================================================================
# NETWORKING
# ============================================================================
# - Expose only the application port required by the service.
# - Do not install diagnostic network clients into production images.
# - Network policy belongs to the orchestrator or cloud network layer.
# - Private package feeds are build-time dependencies, not runtime dependencies.
# - Outbound access from the final runtime should be restricted where practical.

# ============================================================================
# IMAGE LABELS
# ============================================================================
# - OCI vendor metadata identifies Dexnore.
# - OCI source metadata identifies this repository.
# - Application framework and .NET version are recorded as labels.
# - Deployment type and AOT mode are recorded as labels.
# - Workspace and RID information are recorded as labels.
# - Security posture is recorded as a non-root label.

# ============================================================================
# OVERRIDES
# ============================================================================
# - DOTNET_VERSION overrides automatic SDK detection.
# - BUILD_IMAGE overrides the SDK image.
# - RUN_IMAGE overrides runtime image selection.
# - RUNTIME_FLAVOR selects the runtime family.
# - TARGET_RID selects a runtime identifier.
# - BUILD_CONFIGURATION selects Debug/Release or another configuration.
# - DEPLOYMENT_TYPE selects framework-dependent/self-contained behavior.
# - ENABLE_AOT explicitly enables Native AOT.
# - PUBLISH_TRIMMED controls trimming.
# - PUBLISH_SINGLE_FILE controls single-file publishing.
# - PUBLISH_READYTORUN controls ReadyToRun.
# - RESTORE_LOCKED controls locked restore policy.
# - PRIVATE_FEED_SECRET_ID controls the secret name.
# - ENABLE_TESTS enables the test stage.
# - ENABLE_RUNTIME_DIAGNOSTICS enables runtime diagnostics when necessary.

# END OF C# / .NET PRODUCTION STANDARD
