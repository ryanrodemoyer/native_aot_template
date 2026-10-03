# Benchmark: .NET 10 Native AOT CLI + GUI Starter Template

> **Read [AGENTS.md](AGENTS.md) first.** It defines the rules of engagement (worktree, branch, integrity, process logs, submission). This document defines **what** to build and **how it is scored**.

## 1. Goal

Build an open-source, MIT-licensed, forkable starter template for a **.NET 10** solution that ships:

1. A **Native AOT CLI tool** for Windows x64, macOS Apple Silicon (arm64), and Linux x64.
2. A **Native AOT desktop GUI app** (Avalonia) for the same three platforms.
3. A **shared core library** used by both front ends.
4. **Automated tests**: unit tests, CLI end-to-end tests against the *published native binary*, and headless GUI tests.
5. **GitHub Actions** pipelines that build, test, publish, and package everything.
6. **Install scripts** (`install.sh`, `install.ps1`) that install the binaries from GitHub Release artifacts.
7. A **README** that explains every entry point and how to build, run, test, publish, install, and fork.

The template includes a specific sample application. This benchmark uses the **[Lockbox](products/lockbox/PRODUCT.md)** product spec. 

> [!IMPORTANT]
> The product spec ([`products/lockbox/PRODUCT.md`](products/lockbox/PRODUCT.md)) defines *what* the application does, including specific rules, test cases, and penalties. **You must satisfy both this infrastructure benchmark spec AND the chosen product spec.**

## 2. Platform Matrix

| Platform | RID | GitHub runner | CLI | GUI |
|---|---|---|---|---|
| Windows x64 | `win-x64` | `windows-latest` | ✅ | ✅ |
| macOS Apple Silicon | `osx-arm64` | `macos-latest` (arm64) | ✅ | ✅ |
| Linux x64 | `linux-x64` | `ubuntu-latest` | ✅ | ✅ |

Out of scope: `win-arm64`, `linux-arm64`, `osx-x64`, musl/Alpine, and browser/WASM.

> [!NOTE]
> Native AOT cannot compile for one OS while running on another. **Both** the CLI and the GUI must be published on a runner of the target OS (a matrix build).

## 3. Product Specification

Read the active product specification at **[`products/lockbox/PRODUCT.md`](products/lockbox/PRODUCT.md)** for detailed requirements regarding core logic, CLI interface, GUI features, and test vectors. 

Use the identifiers (namespaces, project names, artifact names) defined in the product spec. Throughout this document, placeholders like `<Product>`, `<product>`, and `<cli>` correspond to the values defined in the product spec.

## 4. Technical Requirements

### 4.1 Solution and Conventions

- `global.json` pins the .NET 10 SDK (`rollForward: latestFeature`).
- Solution file uses the **`.slnx`** format.
- `Directory.Build.props` holds shared settings: `TargetFramework=net10.0`, `Nullable=enable`, `ImplicitUsings=enable`, `TreatWarningsAsErrors=true`, `AnalysisLevel=latest`, deterministic builds.
- **Central Package Management** (`Directory.Packages.props`).
- `.editorconfig` and `.gitignore` (standard .NET). The root `LICENSE` (MIT) already exists; keep it.
- Suggested layout (you may deviate if you justify it in `SUBMISSION.md`):

```
src/<Product>.Core/              shared library
src/<Product>.Cli/               CLI (PublishAot)
src/<Product>.Gui/               Avalonia views + view models
src/<Product>.Desktop/           desktop host (PublishAot)
tests/<Product>.Core.Tests/
tests/<Product>.Cli.E2ETests/
tests/<Product>.Gui.Tests/       Avalonia.Headless
scripts/install.sh
scripts/install.ps1
.github/workflows/
submission/                    PLAN.md, THOUGHTS.md, SUBMISSION.md (see AGENTS.md)
```

### 4.2 Native AOT Verification

- Executables set `PublishAot=true`. Libraries set `IsAotCompatible=true`, which turns on the trim, single-file, and AOT analyzers.
- Running `dotnet publish -c Release -r <rid>` for the CLI and the desktop GUI must finish with **zero** warnings in the `IL2xxx` / `IL3xxx` ranges. CI must fail if any appear (`TreatWarningsAsErrors` must cover publish).
- Do **not** suppress trim/AOT warnings (`NoWarn`, `#pragma`, `UnconditionalSuppressMessage`, `TrimmerRootAssembly`, `rd.xml`) unless you justify each one in `SUBMISSION.md`. Unjustified suppressions are penalized.
- The published binaries must behave correctly under AOT, not just build. 
- CI must **run** each published binary on its native runner: `<cli> --version` and the CLI E2E suite for the CLI, and a launch smoke test for the GUI (for example a `--smoke-test` flag that starts the app, builds the main window, and exits 0).

### 4.3 Dependencies

- Use as few packages as possible. **Every** runtime dependency must be Native AOT compatible.
- Acceptable:
  - Avalonia packages (the latest stable release that supports .NET 10 and AOT)
  - `Avalonia.Headless` for tests
  - one test framework (and its runner/adapter)
  - optionally `System.CommandLine` and `CommunityToolkit.Mvvm` (source generator based)
  - any additional dependencies explicitly allowed in the product spec
- Not allowed: reflection-heavy libraries (for example ReactiveUI, Newtonsoft.Json, AutoMapper, or reflection-based DI scanning). See the product spec for additional disallowed dependencies.
- List every package and justify it in `SUBMISSION.md`.

### 4.4 Tests

- **Unit tests (Core):** Must cover generic functionality and all product-specific test requirements.
- **CLI E2E tests:** run the **published native binary**. Its path comes from an environment variable (e.g., `<PRODUCT>_CLI_PATH`); tests may fall back to `dotnet run` locally. Cover all commands, exit codes, and workflows specified in the product spec.
- **GUI headless tests** (`Avalonia.Headless`):
  - view model behavior and workflows specified in the product spec.
  - at least one test that renders the main window headlessly and works the real controls.
- All tests run in CI on all three OSes. No test may depend on wall-clock timing (`Thread.Sleep` and the like). Test time-dependent behavior deterministically if required by the product spec.

### 4.5 CI/CD (GitHub Actions)

**`ci.yml`**, triggered on `pull_request` and `push` to `main`:
- Matrix over the 3 platforms: restore, build, unit tests, GUI headless tests.
- Publish the CLI and the desktop GUI with Native AOT for each RID. Fail on any AOT/trim warning.
- Run CLI E2E tests against the published binary, and run the GUI smoke test.
- Test the install scripts in from-dir mode (§4.6).
- Upload artifacts named `<product>-cli-<rid>` and `<product>-gui-<rid>`.
- Use NuGet caching and least-privilege `permissions:`. Pin action versions to a major tag or SHA.

**`release.yml`**, triggered on tags matching `v*.*.*` **and** `workflow_dispatch`:
- Builds the same matrix and produces archives: `.zip` for Windows, `.tar.gz` for macOS/Linux, named `<product>-cli-<version>-<rid>.<ext>` and `<product>-gui-<version>-<rid>.<ext>`.
- Produces a `SHA256SUMS` file in GNU coreutils format (`<hex>  <filename>`).
- On a tag push, it creates a GitHub Release with all archives and `SHA256SUMS`.
- On `workflow_dispatch`, it has a `dry-run` input (default `true`) that uploads everything as workflow artifacts and **does not** create a release.
- The Avalonia GUI output includes native libraries (Skia, HarfBuzz) next to the executable. Archives must contain everything needed to run.

> [!IMPORTANT]
> Submissions must **not** push tags or create releases. Validate `release.yml` with a `workflow_dispatch` dry run on your branch.

### 4.6 Install Scripts

`scripts/install.sh` (macOS/Linux, POSIX sh or bash) and `scripts/install.ps1` (PowerShell 7+ and Windows PowerShell 5.1):

- Detect OS/arch and pick the matching RID. Exit with a clear error on unsupported platforms.
- Download from GitHub Releases. Defaults: latest release and the CLI component. Options: version, component (`cli`, `gui`, `all`), install directory, and repository (`owner/name`, so forks work without editing the script).
- **Verify the download against `SHA256SUMS`** before installing.
- Install to a user-local directory by default (`~/.local/bin` + `~/.local/share/<product>` or similar; `%LOCALAPPDATA%\Programs\<Product>` on Windows). Never require admin/sudo by default. Print PATH guidance if the directory is not on PATH.
- Support installing from a **local directory of archives** (e.g. `--from-dir` / `-FromDir`) so CI can test the scripts against freshly built artifacts without a release.
- CI runs both scripts (`install.sh` on macOS and Linux, `install.ps1` on Windows) in from-dir mode, then runs the installed `<cli> --version`.

### 4.7 README.md

Must cover:
- What the template is, and the sample application. See the product spec for required disclaimers.
- **Entry points**: CLI, desktop GUI, and the test projects. Include the exact `dotnet run` / published binary commands for each.
- Prerequisites per OS: .NET 10 SDK, and the native toolchains Native AOT needs (MSVC Build Tools on Windows, Xcode Command Line Tools on macOS, `clang` + `zlib1g-dev` on Linux).
- Build, test, publish (per RID), and install instructions.
- CLI reference: commands, options, input rules, JSON output, exit codes.
- CI/CD overview, and how to cut a release.
- Project layout and architecture: what goes in Core and what goes in the front ends.
- Native AOT notes and gotchas: compiled bindings, JSON source generation, analyzers, platform support, how to read IL2xxx/IL3xxx warnings.
- **Forking guide**: how to rename the project to your own product and what to delete (including `benchmark/` and `submission/`).
- Notes on unsigned binaries (Windows SmartScreen, macOS Gatekeeper) and that signing is out of scope.
- License.

### 4.8 Process Artifacts

`submission/PLAN.md`, `submission/THOUGHTS.md`, and `submission/SUBMISSION.md` are required, as defined in [AGENTS.md](AGENTS.md).

## 5. Scoring Rubric (100 points + up to 10 bonus)

### 5.1 Hard Gates (fail any of these and the submission is scored 0)

- [ ] A PR exists from the submission branch to `main`, and `submission/SUBMISSION.md` is present.
- [ ] `ci.yml` is green on the PR's latest commit on all three platforms.
- [ ] The CLI and the desktop GUI are both published with `PublishAot=true` (not merely self-contained or trimmed).
- [ ] Any **product-specific hard gates** defined in the product spec are met.
- [ ] No integrity violations (see AGENTS.md).

### 5.2 Weighted Score

| # | Category | Pts | What earns full marks |
|---|---|---|---|
| 1 | **Core product correctness** | 15 | Passes any hidden conformance suites. Correct implementation of product-specific domain logic, file formats, error handling, and performance rules defined in the product spec. |
| 2 | **Native AOT correctness** | 13 | Zero IL2xxx/IL3xxx warnings with analyzers on. No unjustified suppressions. JSON source gen. Compiled bindings. Published binaries behave correctly on every platform. |
| 3 | **Tests** | 13 | Covers §4.4 and the product spec. E2E tests run against the native binary. Headless UI tests use real controls. Deterministic, not flaky. |
| 4 | **CI/CD** | 12 | `ci.yml` and `release.yml` meet §4.5. The release dry run was executed and is green. Caching, least-privilege permissions, clear job names, artifacts named as specified. |
| 5 | **CLI functionality** | 10 | Every command, option, input rule, format, and exit code specified in the product spec. Clean cancellation. Works in scripts. |
| 6 | **GUI functionality** | 10 | Every feature specified in the product spec works. Responsive UI. Sensible layout on all three OSes. |
| 7 | **Distribution** | 7 | Install scripts meet §4.6, including checksum verification, fork-friendly repo option, and CI-tested from-dir mode. |
| 8 | **Documentation** | 6 | README covers §4.7 accurately (commands actually work). |
| 9 | **Shared architecture** | 5 | Core has no UI/console dependencies. No duplicated logic. Clean boundaries a template user can extend. |
| 10 | **Process** | 5 | `PLAN.md` was committed first and has a sound task diagram. `THOUGHTS.md` is a genuine, timestamped log of decisions, failures, and pivots. The plan-vs-actual reflection is honest. `SUBMISSION.md` is complete. |
| 11 | **Template hygiene** | 4 | Conventions in §4.1. Minimal, justified dependencies. No committed build output or secrets. Consistent naming and style. Easy to fork. |

### 5.3 Bonus (max +10)

| Bonus | Pts |
|---|---|
| **Product-specific bonus:** defined in the product spec | Up to +4 |
| Working rename script (`scripts/rename.*`) that rebrands the solution and leaves it building and passing tests (proved in CI) | +3 |
| macOS GUI packaged as a proper `.app` bundle (with `Info.plist` and icon) in the release archive | +3 |

### 5.4 Penalties

| Violation | Penalty |
|---|---|
| Integrity violation (see AGENTS.md) | **Disqualification** |
| Modifying anything under `benchmark/` or the root `AGENTS.md` | −10 |
| Skipped, disabled, or deleted tests to make CI pass, or `continue-on-error` on required steps | −10 |
| **Product-specific penalties:** defined in the product spec | Up to −15 |
| Unjustified AOT/trim warning suppression | −3 each (max −15) |
| Pushing tags, creating releases, deploying Pages, or changing repo settings | −10 |
| Timestamps in `THOUGHTS.md` not written by the provided logging script, or fabricated | −5 |
| README instructions that do not work as written | −2 each (max −10) |
| Claims in `SUBMISSION.md` contradicted by the code or CI | −5 each |

### 5.5 Efficiency (reported, not scored)

Evaluators record these alongside the score, for comparison between agents:
- Wall-clock time, from the `start` to the `end` entry in `THOUGHTS.md` (and checked against commit and CI timestamps).
- Number of CI runs triggered.
- Number of human interventions (target: **0**).
- Tokens / cost, if the harness exposes them.

## 6. How Evaluators Verify

1. Check out the submission branch in a clean environment.
2. Run `dotnet build`, `dotnet test`, and `dotnet publish -c Release -r <rid>` for the CLI and the GUI. Inspect the output for IL2xxx/IL3xxx warnings.
3. Validate against the product spec (including any hidden conformance suites).
4. Grep for suppressions and shortcuts: `NoWarn`, `#pragma warning disable IL`, `UnconditionalSuppressMessage`, `continue-on-error`, `Skip =`, `[Ignore]`, and any disallowed dependencies.
5. Review the CI runs for the PR head commit and the `release.yml` dry run.
6. Download the artifacts on each OS. Run the CLI and work through the GUI manually.
7. Follow the README literally from a fresh clone.
8. Check `PLAN.md` commit order, compare `THOUGHTS.md` timestamps with git and CI history, and compare `SUBMISSION.md` claims with the evidence.
