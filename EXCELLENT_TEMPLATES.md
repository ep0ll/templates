# Excellent production-ready language Dexfiles

This branch upgrades Go, Rust, Ruby, C#, Dart, C/C++, and PHP templates to production depth (~850–1016 lines each).

## Languages upgraded

| Language | Path | Lines | Highlights |
|----------|------|------:|------------|
| Go | `go/Dockerfile` | 1016 | Gin/Echo/Fiber, govulncheck, static scratch |
| Rust | `rust/Dockerfile` | 965 | cargo-chef, Axum/Actix, cargo-audit |
| Ruby | `ruby/Dockerfile` | 857 | Rails, Bootsnap, bundler-audit, Puma |
| C# | `csharp/Dockerfile` | 1000 | AOT, project-type matrix, NuGet audit |
| Dart | `dart/Dockerfile` | 851 | server + Flutter web, dart compile exe |
| C/C++ | `c/Dockerfile` | 887 | CMake/Meson/Make, static musl, Conan/vcpkg |
| PHP | `php/Dockerfile` | 913 | FrankenPHP, RoadRunner, FPM, Laravel/Symfony |

## Usage

```bash
docker buildx build -f go/Dockerfile -t myapp:latest .
docker buildx build -f rust/Dockerfile --target prod-static -t myapp:static .
```

See each Dockerfile header for full ARG reference and detection matrices.
