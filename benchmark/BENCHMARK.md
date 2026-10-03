# Benchmark: .NET 10 Native AOT CLI + GUI Starter Template

> **Read [AGENTS.md](AGENTS.md) first.** It defines the rules of engagement (worktree, branch, integrity, submission). This document defines **what** to build and **how it is scored**.

## 1. Goal

Build an open-source, MIT-licensed, forkable starter template for a **.NET 10** solution that ships:

1. A **Native AOT CLI tool** for Windows x64, macOS Apple Silicon (arm64), and Linux x64.
2. A **Native AOT desktop GUI app** (Avalonia) for the same three platforms.
3. A **shared core library** used by both front ends.
4. **Automated tests**: unit, CLI end-to-end against the *published native binary*, and headless GUI tests.
5. **GitHub Actions** pipelines that build, test, publish, and package everything.
6. **Install scripts** (`install.sh`, `install.ps1`) that install the binaries from GitHub Release artifacts.
7. A **README** that explains every entry point and how to build, run, test, publish, install, and fork.

The template ships a small but real sample app, **HashKit**, a file checksum tool. The sample app shows the patterns. It is not meant to be a product. Keep the business logic small and focus on getting the template's infrastructure right.

## 2. Platform Matrix

| Platform | RID | GitHub runner | CLI | GUI |
|---|---|---|---|---|
| Windows x64 | `win-x64` | `windows-latest` | ✅ | ✅ |
| macOS Apple Silicon | `osx-arm64` | `macos-latest` (arm64) | ✅ | ✅ |
| Linux x64 | `linux-x64` | `ubuntu-latest` | ✅ | ✅ |

Out of scope: `win-arm64`, `linux-arm64`, `osx-x64`, musl/Alpine.

> [!NOTE]
> Native AOT does not support cross-OS compilation. **Both** the CLI and the GUI must be published on a runner of the target OS (a matrix build). Do not try to cross-compile.

## 3. Sample App Specification: HashKit

### 3.1 Shared Core (`HashKit.Core`)

All hashing, manifest parsing and formatting, and hash comparison logic lives here. The CLI and GUI **must not** reimplement any of it.

- Algorithms: `md5`, `sha1`, `sha256` (default), `sha384`, `sha512`.
- Hash a `Stream` asynchronously. Read in chunks (do not load whole files into memory). Support `IProgress<T>` (bytes processed) and `CancellationToken`.
- Output is lowercase hex.
- Parse and write manifests in **GNU coreutils format**, so they work with `sha256sum -c`:
  - `<hex><space><space><path>` (text mode), and accept `<hex><space>*<path>` (binary mode) when parsing.
  - Ignore blank lines and lines starting with `#`. Report malformed lines rather than throwing.
- Compare hashes ignoring case and surrounding whitespace.
- No UI or console dependencies. The library must set `IsAotCompatible=true`.

**Required test vectors** (input is the ASCII string `abc`, no trailing newline):

| Algorithm | Expected |
|---|---|
| md5 | `900150983cd24fb0d6963f7d28e17f72` |
| sha1 | `a9993e364706816aba3e25717850c26c9cd0d89d` |
| sha256 | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| sha384 | `cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7` |
| sha512 | `ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f` |

Empty input with sha256 must produce `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

### 3.2 CLI (`hashkit`)

The executable name is `hashkit` (`hashkit.exe` on Windows).

```
hashkit hash <path>... [--algorithm|-a <algo>] [--format|-f text|json]
hashkit verify <manifest> [--algorithm|-a <algo>] [--format|-f text|json] [--quiet|-q]
hashkit --version
hashkit --help
```

- `hash`: hashes one or more files. A path of `-` means stdin. Text output is coreutils format (`<hex>  <path>`), one line per file, so `hashkit hash a b > SUMS && sha256sum -c SUMS` works.
- `verify`: reads a manifest and checks each entry. File paths are relative to the manifest's directory. Text output is `<path>: OK` / `<path>: FAILED` / `<path>: MISSING`, followed by a summary line on stderr when anything fails. `--quiet` prints only failures.
- `--format json` writes exactly one JSON document to stdout, using **System.Text.Json source generation** (no reflection-based serialization):

```jsonc
// hash
{ "algorithm": "sha256", "results": [ { "path": "a.txt", "hash": "…", "bytes": 3 } ] }
// verify
{ "algorithm": "sha256",
  "results": [ { "path": "a.txt", "status": "ok" } ],   // status: ok | failed | missing
  "summary": { "ok": 1, "failed": 0, "missing": 0, "malformed": 0 } }
```

- Results go to **stdout**. Diagnostics and errors go to **stderr**.
- **Exit codes** (document them in the README):

| Code | Meaning |
|---|---|
| 0 | Success / all entries verified |
| 1 | Verification failed (any `failed`, `missing`, or `malformed` entry) |
| 2 | Usage error (unknown command or option, bad algorithm) |
| 3 | I/O error (input file not found or unreadable) |

- Ctrl+C cancels cleanly (no stack trace). Use exit code 130 or document the code you choose.

### 3.3 GUI (`HashKit` desktop app)

An Avalonia app, published with Native AOT.

- Pick a file with the platform file picker **or** drag and drop it onto the window.
- Choose an algorithm (default sha256).
- Compute the hash with a **progress bar** and a **Cancel** button. The UI must stay responsive while hashing a large file.
- Show the result as selectable text, with a **Copy** button that copies it to the clipboard.
- An optional **Expected hash** field shows a clear match or mismatch indicator (using the Core comparison).
- Errors (unreadable file, cancellation) show inline. The app never crashes because of them.
- Use MVVM. View models must be testable without a window. Use **compiled bindings** (`AvaloniaUseCompiledBindingsByDefault=true`). Reflection-based bindings are not allowed.

### 3.4 Bonus: Browser (WASM) Target

Optionally add `HashKit.Browser`, which runs the same Avalonia UI in the browser with `Avalonia.Browser`.

- Native AOT does not apply to WASM. Use the .NET WebAssembly runtime (optionally with `RunAOTCompilation` and the `wasm-tools` workload). Explain the choice in the README.
- The browser does not support `MD5` (`PlatformNotSupportedException`). The app must handle this gracefully, for example by hiding the option or showing a message, and the solution must be designed so that this platform difference is not hard-coded throughout the UI.
- CI builds and uploads the published static site as an artifact. Deploying to GitHub Pages is optional and **must not** be done from a submission branch.

## 4. Technical Requirements

### 4.1 Solution and Conventions

- `global.json` pins the .NET 10 SDK (`rollForward: latestFeature`).
- Solution file uses the **`.slnx`** format.
- `Directory.Build.props` holds shared settings: `TargetFramework=net10.0`, `Nullable=enable`, `ImplicitUsings=enable`, `TreatWarningsAsErrors=true`, `AnalysisLevel=latest`, deterministic builds.
- **Central Package Management** (`Directory.Packages.props`).
- `.editorconfig`, `.gitignore` (standard .NET), `LICENSE` (MIT).
- Suggested layout (you may deviate if you justify it in `SUBMISSION.md`):

```
src/HashKit.Core/            shared library
src/HashKit.Cli/             CLI (PublishAot)
src/HashKit.Gui/             Avalonia views + view models (shared by desktop/browser)
src/HashKit.Desktop/         desktop host (PublishAot)
src/HashKit.Browser/         (bonus) WASM host
tests/HashKit.Core.Tests/
tests/HashKit.Cli.E2ETests/
tests/HashKit.Gui.Tests/     Avalonia.Headless
scripts/install.sh
scripts/install.ps1
.github/workflows/
```

### 4.2 Native AOT Verification

- Executables set `PublishAot=true`. Libraries set `IsAotCompatible=true`, which turns on the trim, single-file, and AOT analyzers.
- Running `dotnet publish -c Release -r <rid>` for the CLI and the desktop GUI must finish with **zero** warnings in the `IL2xxx` / `IL3xxx` ranges. CI must fail if any appear (`TreatWarningsAsErrors` must cover publish).
- Do **not** suppress trim/AOT warnings (`NoWarn`, `#pragma`, `UnconditionalSuppressMessage`, `TrimmerRootAssembly`, `rd.xml`) unless you justify each one in `SUBMISSION.md`. Unjustified suppressions are penalized.
- CI must **run** each published binary on its native runner: `hashkit --version` and the CLI E2E suite for the CLI, and a launch smoke test for the GUI where feasible (headless or `--smoke-test` style flag that starts and exits).

### 4.3 Dependencies

- Use as few packages as possible. **Every** runtime dependency must be Native AOT compatible.
- Expected and acceptable: Avalonia packages (latest stable that supports .NET 10 and AOT), `Avalonia.Headless` for tests, one test framework (and its runner/adapter), and optionally `System.CommandLine` and `CommunityToolkit.Mvvm` (source generator based).
- Not allowed: reflection-heavy libraries (for example ReactiveUI, Newtonsoft.Json, AutoMapper, or reflection-based DI scanning).
- List every package and justify it in `SUBMISSION.md`.

### 4.4 Tests

- **Unit tests**: Core hashing (all test vectors, empty input, large streams, progress reporting, cancellation), manifest parse and format (including malformed lines and binary mode `*`), and comparison.
- **CLI E2E tests**: run the **published native binary** (path provided by an environment variable such as `HASHKIT_CLI_PATH`; may fall back to `dotnet run` locally). Cover every command, both output formats, stdin input, every exit code, and the coreutils round trip (`hash` → `verify`).
- **GUI headless tests** (`Avalonia.Headless`): view model behavior (compute, cancel, match/mismatch, error state) **and** at least one test that renders the main window headlessly and works the controls.
- All tests run in CI on all three OSes.

### 4.5 CI/CD (GitHub Actions)

**`ci.yml`**, triggered on `pull_request` and `push` to `main`:
- Matrix over the 3 platforms: restore, build, unit tests, GUI headless tests.
- Publish the CLI and the desktop GUI with Native AOT for each RID. Fail on any AOT/trim warning.
- Run CLI E2E tests against the published binary, and run the GUI smoke test.
- Upload artifacts named `hashkit-cli-<rid>` and `hashkit-gui-<rid>`.
- Use NuGet caching and least-privilege `permissions:`. Pin action versions to a major tag or SHA.

**`release.yml`**, triggered on tags matching `v*.*.*` **and** `workflow_dispatch`:
- Builds the same matrix and produces archives: `.zip` for Windows, `.tar.gz` for macOS/Linux, named `hashkit-cli-<version>-<rid>.<ext>` and `hashkit-gui-<version>-<rid>.<ext>`.
- Produces a `SHA256SUMS` file in coreutils format. Generating it with `hashkit` itself is encouraged.
- On a tag push, it creates a GitHub Release with all archives and `SHA256SUMS`.
- On `workflow_dispatch`, it has a `dry-run` input (default `true`) that uploads the archives as workflow artifacts and **does not** create a release.
- The Avalonia GUI output includes native libraries (Skia, HarfBuzz) next to the executable. Archives must contain everything needed to run.

> [!IMPORTANT]
> Submissions must **not** push tags or create releases. Validate `release.yml` with a `workflow_dispatch` dry run on your branch.

### 4.6 Install Scripts

`scripts/install.sh` (macOS/Linux, POSIX sh or bash) and `scripts/install.ps1` (PowerShell 7+ and Windows PowerShell 5.1):

- Detect OS/arch and pick the matching RID. Exit with a clear error on unsupported platforms.
- Download from GitHub Releases. Defaults: latest release and the CLI component. Options: version, component (`cli`, `gui`, `all`), install directory, and repository (`owner/name`, so forks work without editing the script).
- **Verify the download against `SHA256SUMS`** before installing.
- Install to a user-local directory by default (`~/.local/bin` + `~/.local/share/hashkit` or similar; `%LOCALAPPDATA%\Programs\HashKit` on Windows). Never require admin/sudo by default. Print PATH guidance if the directory is not on PATH.
- Support installing from a **local directory of archives** (e.g. `--from-dir` / `-FromDir`) so CI can test the scripts against freshly built artifacts without a release.
- CI runs both scripts (`install.sh` on macOS and Linux, `install.ps1` on Windows) in from-dir mode, then runs the installed `hashkit --version`.

### 4.7 README.md

Must cover:
- What the template is, and the HashKit sample.
- **Entry points**: CLI, desktop GUI, browser (if done), test projects. Include the exact `dotnet run` / published binary commands for each.
- Prerequisites per OS: .NET 10 SDK, and the native toolchains Native AOT needs (MSVC Build Tools on Windows, Xcode Command Line Tools on macOS, `clang` + `zlib1g-dev` on Linux).
- Build, test, publish (per RID), and install instructions.
- CLI reference: commands, options, JSON schema, exit codes.
- CI/CD overview, and how to cut a release.
- Project layout and architecture: what goes in Core and what goes in the front ends.
- Native AOT notes and gotchas: compiled bindings, JSON source generation, analyzers, how to read IL2xxx/IL3xxx warnings.
- **Forking guide**: how to rename `HashKit` to your own product (a rename script is a bonus) and what to delete.
- Notes on unsigned binaries (Windows SmartScreen, macOS Gatekeeper) and that signing is out of scope.
- License.

### 4.8 SUBMISSION.md

Required. Use the template in [AGENTS.md](AGENTS.md#submissionmd-template).

## 5. Scoring Rubric (100 points + up to 10 bonus)

### 5.1 Hard Gates (fail any of these and the submission is scored 0)

- [ ] A PR exists from the submission branch to `main`, and `SUBMISSION.md` is present.
- [ ] `ci.yml` is green on the PR's latest commit on all three platforms.
- [ ] The CLI and the desktop GUI are both published with `PublishAot=true` (not merely self-contained or trimmed).
- [ ] No integrity violations (see AGENTS.md).

### 5.2 Weighted Score

| # | Category | Pts | What earns full marks |
|---|---|---|---|
| 1 | **Native AOT correctness** | 15 | Zero IL2xxx/IL3xxx warnings with analyzers on. No unjustified suppressions. JSON source gen. Compiled bindings. Published binaries execute in CI on every platform. |
| 2 | **CI/CD** | 15 | `ci.yml` and `release.yml` meet §4.5. The release dry run was executed and is green. Caching, least-privilege permissions, clear job names, artifacts named as specified. |
| 3 | **CLI functionality** | 12 | Every command, option, format, and exit code in §3.2. Coreutils interoperability. stdin. Clean cancellation. |
| 4 | **GUI functionality** | 10 | Every feature in §3.3 works. The UI stays responsive. Errors are handled. Layout is sensible on all three OSes. |
| 5 | **Tests** | 15 | Covers §4.4. E2E tests run against the native binary. Headless UI tests use real controls. Tests are deterministic and not flaky. |
| 6 | **Shared architecture** | 8 | Core has no UI/console dependencies. No duplicated logic. Clean, readable boundaries a template user can extend. |
| 7 | **Distribution** | 8 | Install scripts meet §4.6, including checksum verification, fork-friendly repo option, and CI-tested from-dir mode. |
| 8 | **Documentation** | 10 | README covers §4.7 accurately (commands actually work). `SUBMISSION.md` is honest and complete. |
| 9 | **Template hygiene** | 7 | Conventions in §4.1. Minimal, justified dependencies. No committed build output or secrets. Consistent naming and style. Easy to fork. |

### 5.3 Bonus (max +10)

| Bonus | Pts |
|---|---|
| Browser/WASM target per §3.4, built and uploaded in CI | +5 |
| Working rename script (`scripts/rename.*`) that rebrands the solution and keeps it building | +3 |
| macOS GUI packaged as a proper `.app` bundle in the release archive | +2 |

### 5.4 Penalties

| Violation | Penalty |
|---|---|
| Integrity violation (see AGENTS.md) | **Disqualification** |
| Modifying anything under `benchmark/` or the root `AGENTS.md` | −10 |
| Skipped, disabled, or deleted tests to make CI pass, or `continue-on-error` on required steps | −10 |
| Unjustified AOT/trim warning suppression | −3 each (max −15) |
| Pushing tags, creating releases, deploying Pages, or changing repo settings | −10 |
| README instructions that do not work as written | −2 each (max −10) |
| Claims in `SUBMISSION.md` contradicted by the code or CI | −5 each |

### 5.5 Efficiency (reported, not scored)

Evaluators record these alongside the score, for comparison between agents:
- Wall-clock time from first action to final push.
- Number of CI runs triggered.
- Number of human interventions (target: **0**).
- Tokens / cost, if the harness exposes them.

## 6. How Evaluators Verify

1. Check out the submission branch in a clean environment.
2. Run `dotnet build`, `dotnet test`, and `dotnet publish -c Release -r <rid>` for the CLI and the GUI. Inspect the output for IL2xxx/IL3xxx warnings.
3. Grep for suppressions: `NoWarn`, `#pragma warning disable IL`, `UnconditionalSuppressMessage`, `continue-on-error`, `Skip =`, `[Ignore]`.
4. Review the CI runs for the PR head commit and the `release.yml` dry run.
5. Download the artifacts on each OS. Run the CLI round trip against `sha256sum -c` and launch the GUI.
6. Follow the README literally from a fresh clone.
7. Compare `SUBMISSION.md` claims against the evidence.
