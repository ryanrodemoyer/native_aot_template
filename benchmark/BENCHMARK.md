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

The template includes a sample app, **Lockbox**, a local encrypted password manager. The sample is deliberately non-trivial. It tests precise reading of the spec (an exact vault format), correct use of cryptographic primitives, behavior that differs across platforms, and Native AOT pitfalls. It still stays small enough to serve as a template.

> [!IMPORTANT]
> Evaluators run a **hidden conformance suite** against your published CLI on every platform. It checks the vault format (§3.1) and the CLI contract (§3.2) exactly as written. The vectors in this document and in [`vectors/`](vectors/) are a visible subset. Follow the spec to the letter.

## 2. Platform Matrix

| Platform | RID | GitHub runner | CLI | GUI |
|---|---|---|---|---|
| Windows x64 | `win-x64` | `windows-latest` | ✅ | ✅ |
| macOS Apple Silicon | `osx-arm64` | `macos-latest` (arm64) | ✅ | ✅ |
| Linux x64 | `linux-x64` | `ubuntu-latest` | ✅ | ✅ |

Out of scope: `win-arm64`, `linux-arm64`, `osx-x64`, musl/Alpine, and browser/WASM (the browser does not support the required cryptography).

> [!NOTE]
> Native AOT cannot compile for one OS while running on another. **Both** the CLI and the GUI must be published on a runner of the target OS (a matrix build).

## 3. Sample App Specification: Lockbox

### 3.1 Shared Core (`Lockbox.Core`)

All vault, cryptography, entry, search, and password generation logic lives here. The CLI and GUI **must not** reimplement any of it. No UI or console dependencies are allowed. Set `IsAotCompatible=true`.

#### 3.1.1 Cryptography Rules

- Use **only** .NET base class library primitives (`System.Security.Cryptography`). Do not implement cryptography yourself, and do not add third-party crypto packages.
- Key derivation: **PBKDF2-HMAC-SHA256**, 32-byte key, with a 16-byte random salt.
  - The master password is normalized to **Unicode NFC** and then encoded as **UTF-8** before key derivation.
  - New vaults use **600,000** iterations by default. Readers accept 100,000–10,000,000 iterations. Anything outside that range is a format error.
- Encryption: **AES-256-GCM**, with a 12-byte nonce and a 16-byte tag.
  - Every save uses a **new random nonce**. Nonces must never be reused with the same key.
  - Changing the master password also generates a **new salt**.
- Random values come only from `RandomNumberGenerator`.
- Zero derived key buffers after use (`CryptographicOperations.ZeroMemory`). Never log secrets, and never put them in exception messages.

#### 3.1.2 Vault File Format v1

A vault is a UTF-8 JSON file (recommended extension: `.lockbox`):

```json
{
  "format": "lockbox-vault",
  "version": 1,
  "kdf":    { "algorithm": "pbkdf2-sha256", "iterations": 600000, "salt": "<base64, 16 bytes>" },
  "cipher": { "algorithm": "aes-256-gcm", "nonce": "<base64, 12 bytes>", "tag": "<base64, 16 bytes>" },
  "ciphertext": "<base64>"
}
```

- Base64 is standard RFC 4648 with padding (not URL-safe).
- **Associated data (AAD)** is the UTF-8 bytes of this exact string, with no trailing newline:
  `lockbox-vault|1|pbkdf2-sha256|<iterations>|<salt base64>|aes-256-gcm|<nonce base64>`
  The salt and nonce are written exactly as they appear in the file.
- The **plaintext** is UTF-8 JSON:

```json
{
  "entries": [
    {
      "id": "<uuid>",
      "name": "example.com",
      "username": "alice",
      "password": "…",
      "url": "https://example.com",
      "notes": "free text",
      "tags": ["web"],
      "createdUtc": "2026-01-01T00:00:00Z",
      "updatedUtc": "2026-01-02T03:04:05Z"
    }
  ]
}
```

- `id`, `name`, `password`, `createdUtc`, and `updatedUtc` are required. The other fields are optional; they may be omitted or `null`, and `tags` defaults to `[]`. Timestamps are ISO 8601 UTC with a `Z` suffix. Readers ignore unknown fields.
- Entry **names are unique, compared ordinally and case-insensitively**. Leading and trailing whitespace is trimmed.
- All JSON (vault, payload, settings, CLI output) uses **System.Text.Json source generation**. Reflection-based serialization is not allowed.

**Saving** must be atomic and safe:
1. Write the new file to a temporary file in the same directory and flush it to disk.
2. Keep the previous version as `<vault>.bak`.
3. Atomically replace the vault.

On macOS and Linux, new vault files are created with mode `0600`.

**Errors** fall into distinct categories (they map to the CLI exit codes):
- **Authentication failure**: wrong password or tampered data. AES-GCM cannot tell these apart, so do not try.
- **Format error**: invalid JSON, wrong `format`/`version`/algorithm, bad base64, wrong salt/nonce/tag length, or iterations out of range.
- **I/O error.**

#### 3.1.3 Password Generator

- Character classes:
  - lowercase `a-z`
  - uppercase `A-Z`
  - digits `0-9`
  - symbols `!#$%&*+-.:;=?@^_~` (exactly this set)
- Options: length (default 20, range 8–128); enable or disable each class (all enabled by default); exclude ambiguous characters `Il1O0o`.
- Each enabled class appears **at least once**. Use **unbiased** selection (`RandomNumberGenerator.GetInt32`) and a cryptographically secure Fisher–Yates shuffle.
- If every class is disabled, or the length is shorter than the number of enabled classes, raise a validation error.
- Report estimated entropy in bits: `length × log2(pool size)`, rounded down to an integer.

#### 3.1.4 Search

Search matches case-insensitively (ordinal) on substrings of `name`, `username`, `url`, and `tags`. Passwords and notes are never searched.

#### 3.1.5 Visible Test Vectors

| Vector | Value |
|---|---|
| PBKDF2-HMAC-SHA256, P=`passwd`, S=`salt`, c=1, dkLen=64 (RFC 7914) | `55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783` |
| Key: password `café` as U+00E9 (NFC), salt bytes `00..0f`, 100,000 iterations | `b094846c93dc080ae197c4152e428a30e72460df97b5b29861b25d0dd971ea84` |
| Key: password `café` as `e` + U+0301 (NFD), same salt and iterations | **same as above** (NFC normalization) |
| [`vectors/sample.lockbox`](vectors/sample.lockbox), master password `correct horse battery staple` | Derived key `49d49c25f597846209f0d92e7770ab64e1c75e94b4ce6c509265ee67175d2a1e`. Decrypts to one entry: name `example.com`, username `alice`, password `p@ssw0rd-éè`, tags `web`, `personal`. |

The sample vault's AAD is `lockbox-vault|1|pbkdf2-sha256|100000|AAECAwQFBgcICQoLDA0ODw==|aes-256-gcm|oKGio6Slpqeoqaqr`.

Your tests must include these vectors. Copy `sample.lockbox` into your test project; do not reference `benchmark/` from the solution. Your tests must also show that flipping any single byte of the ciphertext, tag, nonce, salt, or iteration count causes an authentication failure or format error.

### 3.2 CLI (`lockbox`)

The executable name is `lockbox` (`lockbox.exe` on Windows).

```
lockbox init     <vault> [--iterations <n>]
lockbox add      <vault> --name <name> [--username <u>] [--url <url>] [--notes <text>] [--tag <t>]...
                         [--generate [generator options]] [--password-stdin]
lockbox edit     <vault> <name> [--new-name <n>] [--username <u>] [--url <url>] [--notes <text>]
                         [--tag <t>]... [--clear-tags] [--generate [generator options]] [--password-stdin]
lockbox get      <vault> <name> [--field password|username|url|notes] [--format text|json]
lockbox list     <vault> [--search <q>] [--tag <t>] [--format text|json]
lockbox remove   <vault> <name>
lockbox passwd   <vault>
lockbox generate [--length <n>] [--no-lower] [--no-upper] [--no-digits] [--no-symbols]
                 [--exclude-ambiguous] [--count <n>] [--format text|json]
lockbox --version
lockbox --help
```

**Master password input:** the master password is **never** accepted as a command-line argument.
1. If the environment variable `LOCKBOX_MASTER_PASSWORD` is set, use it.
2. Otherwise, if stdin is a terminal, prompt without echoing. `init` and `passwd` ask for confirmation.
3. Otherwise, fail with a usage error.

For `passwd`, the new password comes from `LOCKBOX_NEW_MASTER_PASSWORD` or a confirmed prompt.

**Entry password input** (`add`, and `edit` when changing the password): use `--generate`, or `--password-stdin` (reads one line from stdin with the trailing newline stripped), or a no-echo prompt with confirmation. `add` requires one of these.

**Behavior:**
- `get` prints only the requested field (default `password`) followed by a newline, so it can be used in scripts. `--format json` prints the full entry.
- `list` **never** prints passwords or notes, in any format. Text output has one entry per line: `name`, `username`, and `url`, separated by tabs, sorted by name (ordinal, case-insensitive).
- `generate` needs no vault. It prints one password per line. JSON output: `{ "passwords": ["…"], "entropyBits": 119 }`.
- `--iterations` on `init` accepts 100,000–10,000,000 (default 600,000).
- Results go to **stdout**. Prompts, diagnostics, and errors go to **stderr**. Error messages never contain secrets.
- JSON output is exactly one document on stdout, uses camelCase, and follows the same entry shape as the vault payload (minus `password` and `notes` for `list`).

**Exit codes** (document them in the README):

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Entry not found |
| 2 | Usage or validation error (unknown option, missing password source, bad generator options, …) |
| 3 | I/O error (vault missing, unreadable, or unwritable) |
| 4 | Authentication failed (wrong master password or tampered vault) |
| 5 | Vault format error or unsupported version |
| 6 | Conflict (entry name already exists, or vault already exists on `init`) |
| 130 | Cancelled (Ctrl+C), with no stack trace |

### 3.3 GUI (`Lockbox` desktop app)

An Avalonia app, published with Native AOT.

- **Start screen:** open an existing vault or create a new one, using the platform file picker. Remember recently used vault paths in a per-user settings file in the OS-appropriate application data folder. The settings file stores **no secrets**.
- **Unlock screen:** master password box. Key derivation (600k iterations) runs **off the UI thread** with a busy indicator. A wrong password shows an inline error.
- **Main screen:**
  - Searchable entry list (§3.1.4) and a detail pane.
  - Add, edit, and delete entries (delete asks for confirmation).
  - A toggle to show or hide the password.
  - **Copy username** and **Copy password** buttons.
  - A **password generator** dialog (§3.1.3) that can fill in the entry's password and shows the entropy.
  - **Change master password.**
- **Persistence:** every change is saved immediately and atomically. If a save fails, show the error, keep the change in memory, and allow a retry. Never lose data silently.
- **Clipboard:** clear copied secrets after **30 seconds**, but **only if** the clipboard still contains the value the app copied.
- **Locking:**
  - Auto-lock after inactivity: default 5 minutes, configurable in settings.
  - A manual **Lock** button.
  - Locking discards decrypted entries and key material from the view models and returns to the unlock screen.
- **Architecture:**
  - MVVM, with view models testable without a window.
  - **Compiled bindings** (`AvaloniaUseCompiledBindingsByDefault=true`).
  - Inject time through **`TimeProvider`**, so auto-lock and clipboard clearing can be tested deterministically.
  - Wrap the clipboard and file dialogs in abstractions so tests can replace them.
- Unexpected exceptions are caught, shown to the user, and never crash the app.

## 4. Technical Requirements

### 4.1 Solution and Conventions

- `global.json` pins the .NET 10 SDK (`rollForward: latestFeature`).
- Solution file uses the **`.slnx`** format.
- `Directory.Build.props` holds shared settings: `TargetFramework=net10.0`, `Nullable=enable`, `ImplicitUsings=enable`, `TreatWarningsAsErrors=true`, `AnalysisLevel=latest`, deterministic builds.
- **Central Package Management** (`Directory.Packages.props`).
- `.editorconfig` and `.gitignore` (standard .NET). The root `LICENSE` (MIT) already exists; keep it.
- Suggested layout (you may deviate if you justify it in `SUBMISSION.md`):

```
src/Lockbox.Core/              shared library
src/Lockbox.Cli/               CLI (PublishAot)
src/Lockbox.Gui/               Avalonia views + view models
src/Lockbox.Desktop/           desktop host (PublishAot)
tests/Lockbox.Core.Tests/
tests/Lockbox.Cli.E2ETests/
tests/Lockbox.Gui.Tests/       Avalonia.Headless
scripts/install.sh
scripts/install.ps1
.github/workflows/
submission/                    PLAN.md, THOUGHTS.md, SUBMISSION.md (see AGENTS.md)
```

### 4.2 Native AOT Verification

- Executables set `PublishAot=true`. Libraries set `IsAotCompatible=true`, which turns on the trim, single-file, and AOT analyzers.
- Running `dotnet publish -c Release -r <rid>` for the CLI and the desktop GUI must finish with **zero** warnings in the `IL2xxx` / `IL3xxx` ranges. CI must fail if any appear (`TreatWarningsAsErrors` must cover publish).
- Do **not** suppress trim/AOT warnings (`NoWarn`, `#pragma`, `UnconditionalSuppressMessage`, `TrimmerRootAssembly`, `rd.xml`) unless you justify each one in `SUBMISSION.md`. Unjustified suppressions are penalized.
- The published binaries must behave correctly under AOT, not just build. Watch for globalization settings (NFC normalization must work in the published binary), platform crypto support (AES-GCM on every OS), and trimmed serialization.
- CI must **run** each published binary on its native runner: `lockbox --version` and the CLI E2E suite for the CLI, and a launch smoke test for the GUI (for example a `--smoke-test` flag that starts the app, builds the main window, and exits 0).

### 4.3 Dependencies

- Use as few packages as possible. **Every** runtime dependency must be Native AOT compatible.
- Acceptable:
  - Avalonia packages (the latest stable release that supports .NET 10 and AOT)
  - `Avalonia.Headless` for tests
  - one test framework (and its runner/adapter)
  - `Microsoft.Extensions.TimeProvider.Testing` (tests only)
  - optionally `System.CommandLine` and `CommunityToolkit.Mvvm` (source generator based)
- Not allowed: third-party crypto packages, and reflection-heavy libraries (for example ReactiveUI, Newtonsoft.Json, AutoMapper, or reflection-based DI scanning).
- List every package and justify it in `SUBMISSION.md`.

### 4.4 Tests

- **Unit tests (Core):**
  - every vector in §3.1.5, NFC equivalence, and single-byte tamper detection
  - format error cases
  - nonce changes on every save, and salt changes on `passwd`
  - atomic save and `.bak` creation
  - Unix file mode (on Unix)
  - name uniqueness rules and search
  - generator guarantees (length, required classes, ambiguous exclusion, validation, entropy), and a statistical sanity check that the output is not obviously biased
- **CLI E2E tests:** run the **published native binary**. Its path comes from an environment variable such as `LOCKBOX_CLI_PATH`; tests may fall back to `dotnet run` locally. Cover:
  - every command, both output formats, and every exit code
  - opening `sample.lockbox`
  - password input through the environment variable and `--password-stdin`
  - a full lifecycle (`init` → `add` → `list` → `get` → `edit` → `passwd` → `get` → `remove`)
  - proof that `list` never leaks secrets
  - Use low iteration counts (`--iterations 100000`) to keep tests fast.
- **GUI headless tests** (`Avalonia.Headless`):
  - view model behavior: unlock (right and wrong password), add/edit/delete persisted to disk (verify by reopening the vault), search, generator, failed-save retry
  - auto-lock and clipboard clearing driven by a fake `TimeProvider`
  - at least one test that renders the main window headlessly and works the real controls
- All tests run in CI on all three OSes. No test may depend on wall-clock timing (`Thread.Sleep` and the like).

### 4.5 CI/CD (GitHub Actions)

**`ci.yml`**, triggered on `pull_request` and `push` to `main`:
- Matrix over the 3 platforms: restore, build, unit tests, GUI headless tests.
- Publish the CLI and the desktop GUI with Native AOT for each RID. Fail on any AOT/trim warning.
- Run CLI E2E tests against the published binary, and run the GUI smoke test.
- Test the install scripts in from-dir mode (§4.6).
- Upload artifacts named `lockbox-cli-<rid>` and `lockbox-gui-<rid>`.
- Use NuGet caching and least-privilege `permissions:`. Pin action versions to a major tag or SHA.

**`release.yml`**, triggered on tags matching `v*.*.*` **and** `workflow_dispatch`:
- Builds the same matrix and produces archives: `.zip` for Windows, `.tar.gz` for macOS/Linux, named `lockbox-cli-<version>-<rid>.<ext>` and `lockbox-gui-<version>-<rid>.<ext>`.
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
- Install to a user-local directory by default (`~/.local/bin` + `~/.local/share/lockbox` or similar; `%LOCALAPPDATA%\Programs\Lockbox` on Windows). Never require admin/sudo by default. Print PATH guidance if the directory is not on PATH.
- Support installing from a **local directory of archives** (e.g. `--from-dir` / `-FromDir`) so CI can test the scripts against freshly built artifacts without a release.
- CI runs both scripts (`install.sh` on macOS and Linux, `install.ps1` on Windows) in from-dir mode, then runs the installed `lockbox --version`.

### 4.7 README.md

Must cover:
- What the template is, and the Lockbox sample. Include a prominent **security disclaimer**: Lockbox is an unaudited educational sample and must not be used for real secrets.
- **Entry points**: CLI, desktop GUI, and the test projects. Include the exact `dotnet run` / published binary commands for each.
- Prerequisites per OS: .NET 10 SDK, and the native toolchains Native AOT needs (MSVC Build Tools on Windows, Xcode Command Line Tools on macOS, `clang` + `zlib1g-dev` on Linux).
- Build, test, publish (per RID), and install instructions.
- CLI reference: commands, options, password input rules, JSON output, exit codes.
- The vault format, with a link to or summary of §3.1.2.
- CI/CD overview, and how to cut a release.
- Project layout and architecture: what goes in Core and what goes in the front ends.
- Native AOT notes and gotchas: compiled bindings, JSON source generation, analyzers, globalization, crypto platform support, how to read IL2xxx/IL3xxx warnings.
- **Forking guide**: how to rename `Lockbox` to your own product and what to delete (including `benchmark/` and `submission/`).
- Notes on unsigned binaries (Windows SmartScreen, macOS Gatekeeper) and that signing is out of scope.
- License.

### 4.8 Process Artifacts

`submission/PLAN.md`, `submission/THOUGHTS.md`, and `submission/SUBMISSION.md` are required, as defined in [AGENTS.md](AGENTS.md).

## 5. Scoring Rubric (100 points + up to 10 bonus)

### 5.1 Hard Gates (fail any of these and the submission is scored 0)

- [ ] A PR exists from the submission branch to `main`, and `submission/SUBMISSION.md` is present.
- [ ] `ci.yml` is green on the PR's latest commit on all three platforms.
- [ ] The CLI and the desktop GUI are both published with `PublishAot=true` (not merely self-contained or trimmed).
- [ ] The published CLI decrypts `sample.lockbox` correctly on all three platforms.
- [ ] No integrity violations (see AGENTS.md).

### 5.2 Weighted Score

| # | Category | Pts | What earns full marks |
|---|---|---|---|
| 1 | **Core & security correctness** | 15 | Passes the hidden conformance suite. Exact vault format and AAD, NFC handling, nonce/salt rules, unbiased generator, atomic saves, file permissions. No secrets leak through output, errors, or logs. |
| 2 | **Native AOT correctness** | 13 | Zero IL2xxx/IL3xxx warnings with analyzers on. No unjustified suppressions. JSON source gen. Compiled bindings. Published binaries behave correctly on every platform. |
| 3 | **Tests** | 13 | Covers §4.4. E2E tests run against the native binary. Headless UI tests use real controls. Time-dependent behavior is tested with `TimeProvider`. Deterministic, not flaky. |
| 4 | **CI/CD** | 12 | `ci.yml` and `release.yml` meet §4.5. The release dry run was executed and is green. Caching, least-privilege permissions, clear job names, artifacts named as specified. |
| 5 | **CLI functionality** | 10 | Every command, option, input rule, format, and exit code in §3.2. Clean cancellation. Works in scripts. |
| 6 | **GUI functionality** | 10 | Every feature in §3.3 works. The UI stays responsive during key derivation. Auto-lock and clipboard clearing work. Sensible layout on all three OSes. |
| 7 | **Distribution** | 7 | Install scripts meet §4.6, including checksum verification, fork-friendly repo option, and CI-tested from-dir mode. |
| 8 | **Documentation** | 6 | README covers §4.7 accurately (commands actually work). |
| 9 | **Shared architecture** | 5 | Core has no UI/console dependencies. No duplicated logic. Clean boundaries a template user can extend. |
| 10 | **Process** | 5 | `PLAN.md` was committed first and has a sound task diagram. `THOUGHTS.md` is a genuine, timestamped log of decisions, failures, and pivots. The plan-vs-actual reflection is honest. `SUBMISSION.md` is complete. |
| 11 | **Template hygiene** | 4 | Conventions in §4.1. Minimal, justified dependencies. No committed build output or secrets. Consistent naming and style. Easy to fork. |

### 5.3 Bonus (max +10)

| Bonus | Pts |
|---|---|
| **TOTP** (RFC 6238): optional `totpSecret` (base32) field on entries. `lockbox totp <vault> <name>` prints the current 6-digit SHA-1 code. The GUI shows the code with a countdown. Tests include the RFC 6238 SHA-1 vectors (secret ASCII `12345678901234567890` = base32 `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`; 8-digit codes: T=59 → `94287082`, T=1111111109 → `07081804`, T=1234567890 → `89005924`, T=20000000000 → `65353130`), using `TimeProvider`. | +4 |
| Working rename script (`scripts/rename.*`) that rebrands the solution and leaves it building and passing tests (proved in CI) | +3 |
| macOS GUI packaged as a proper `.app` bundle (with `Info.plist` and icon) in the release archive | +3 |

### 5.4 Penalties

| Violation | Penalty |
|---|---|
| Integrity violation (see AGENTS.md) | **Disqualification** |
| Modifying anything under `benchmark/` or the root `AGENTS.md` | −10 |
| Skipped, disabled, or deleted tests to make CI pass, or `continue-on-error` on required steps | −10 |
| Custom or third-party cryptography, or the master password accepted as a CLI argument | −10 |
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
3. Run the hidden conformance suite against the published CLI on each OS.
4. Grep for suppressions and shortcuts: `NoWarn`, `#pragma warning disable IL`, `UnconditionalSuppressMessage`, `continue-on-error`, `Skip =`, `[Ignore]`, third-party crypto packages.
5. Review the CI runs for the PR head commit and the `release.yml` dry run.
6. Download the artifacts on each OS. Run the CLI and work through the GUI manually.
7. Follow the README literally from a fresh clone.
8. Check `PLAN.md` commit order, compare `THOUGHTS.md` timestamps with git and CI history, and compare `SUBMISSION.md` claims with the evidence.
