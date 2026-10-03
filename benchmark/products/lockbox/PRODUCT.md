# Product Spec: Lockbox (local encrypted password manager)

> This is a **product spec** for the benchmark in [../../BENCHMARK.md](../../BENCHMARK.md). It defines *what the sample app does*. The benchmark defines *how it is built, delivered, and scored*. If the two conflict, the benchmark's infrastructure rules win, and this spec's functional rules win.

**Why this product:** it tests precise reading of the spec (an exact vault format), correct use of cryptographic primitives, behavior that differs across platforms, and Native AOT pitfalls. It still stays small enough to serve as a template.

## 1. Identifiers

| Placeholder (used in BENCHMARK.md) | Value |
|---|---|
| `<Product>` (namespaces, projects, GUI title) | `Lockbox` |
| `<product>` (artifacts, install dir) | `lockbox` |
| `<cli>` (CLI executable) | `lockbox` (`lockbox.exe` on Windows) |
| `<PRODUCT>_CLI_PATH` (E2E env var) | `LOCKBOX_CLI_PATH` |

## 2. Shared Core (`Lockbox.Core`)

All vault, cryptography, entry, search, and password generation logic lives here. The CLI and GUI **must not** reimplement any of it.

### 2.1 Cryptography Rules

- Use **only** .NET base class library primitives (`System.Security.Cryptography`). Do not implement cryptography yourself, and do not add third-party crypto packages.
- Key derivation: **PBKDF2-HMAC-SHA256**, 32-byte key, with a 16-byte random salt.
  - The master password is normalized to **Unicode NFC** and then encoded as **UTF-8** before key derivation.
  - New vaults use **600,000** iterations by default. Readers accept 100,000–10,000,000 iterations. Anything outside that range is a format error.
- Encryption: **AES-256-GCM**, with a 12-byte nonce and a 16-byte tag.
  - Every save uses a **new random nonce**. Nonces must never be reused with the same key.
  - Changing the master password also generates a **new salt**.
- Random values come only from `RandomNumberGenerator`.
- Zero derived key buffers after use (`CryptographicOperations.ZeroMemory`). Never log secrets, and never put them in exception messages.

### 2.2 Vault File Format v1

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

**Saving** must be atomic and safe:
1. Write the new file to a temporary file in the same directory and flush it to disk.
2. Keep the previous version as `<vault>.bak`.
3. Atomically replace the vault.

On macOS and Linux, new vault files are created with mode `0600`.

**Errors** fall into distinct categories (they map to the CLI exit codes):
- **Authentication failure**: wrong password or tampered data. AES-GCM cannot tell these apart, so do not try.
- **Format error**: invalid JSON, wrong `format`/`version`/algorithm, bad base64, wrong salt/nonce/tag length, or iterations out of range.
- **I/O error.**

### 2.3 Password Generator

- Character classes:
  - lowercase `a-z`
  - uppercase `A-Z`
  - digits `0-9`
  - symbols `!#$%&*+-.:;=?@^_~` (exactly this set)
- Options: length (default 20, range 8–128); enable or disable each class (all enabled by default); exclude ambiguous characters `Il1O0o`.
- Each enabled class appears **at least once**. Use **unbiased** selection (`RandomNumberGenerator.GetInt32`) and a cryptographically secure Fisher–Yates shuffle.
- If every class is disabled, or the length is shorter than the number of enabled classes, raise a validation error.
- Report estimated entropy in bits: `length × log2(pool size)`, rounded down to an integer.

### 2.4 Search

Search matches case-insensitively (ordinal) on substrings of `name`, `username`, `url`, and `tags`. Passwords and notes are never searched.

### 2.5 Visible Test Vectors

| Vector | Value |
|---|---|
| PBKDF2-HMAC-SHA256, P=`passwd`, S=`salt`, c=1, dkLen=64 (RFC 7914) | `55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783` |
| Key: password `café` as U+00E9 (NFC), salt bytes `00..0f`, 100,000 iterations | `b094846c93dc080ae197c4152e428a30e72460df97b5b29861b25d0dd971ea84` |
| Key: password `café` as `e` + U+0301 (NFD), same salt and iterations | **same as above** (NFC normalization) |
| [`vectors/sample.lockbox`](vectors/sample.lockbox), master password `correct horse battery staple` | Derived key `49d49c25f597846209f0d92e7770ab64e1c75e94b4ce6c509265ee67175d2a1e`. Decrypts to one entry: name `example.com`, username `alice`, password `p@ssw0rd-éè`, tags `web`, `personal`. |

The sample vault's AAD is `lockbox-vault|1|pbkdf2-sha256|100000|AAECAwQFBgcICQoLDA0ODw==|aes-256-gcm|oKGio6Slpqeoqaqr`.

## 3. CLI (`lockbox`)

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

**Exit codes:**

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

## 4. GUI (`Lockbox` desktop app)

- **Start screen:** open an existing vault or create a new one, using the platform file picker. Remember recently used vault paths in a per-user settings file in the OS-appropriate application data folder. The settings file stores **no secrets**.
- **Unlock screen:** master password box. Key derivation (600k iterations) runs **off the UI thread** with a busy indicator. A wrong password shows an inline error.
- **Main screen:**
  - Searchable entry list (§2.4) and a detail pane.
  - Add, edit, and delete entries (delete asks for confirmation).
  - A toggle to show or hide the password.
  - **Copy username** and **Copy password** buttons.
  - A **password generator** dialog (§2.3) that can fill in the entry's password and shows the entropy.
  - **Change master password.**
- **Persistence:** every change is saved immediately and atomically. If a save fails, show the error, keep the change in memory, and allow a retry. Never lose data silently.
- **Clipboard:** clear copied secrets after **30 seconds**, but **only if** the clipboard still contains the value the app copied.
- **Locking:**
  - Auto-lock after inactivity: default 5 minutes, configurable in settings.
  - A manual **Lock** button.
  - Locking discards decrypted entries and key material from the view models and returns to the unlock screen.
- Inject time through `TimeProvider`, so auto-lock and clipboard clearing can be tested deterministically. Wrap the clipboard and file dialogs in abstractions so tests can replace them.

## 5. Product-Specific Test Requirements

These are in addition to the generic test requirements in BENCHMARK.md.

- **Core:**
  - every vector in §2.5, NFC equivalence, and proof that flipping any single byte of the ciphertext, tag, nonce, salt, or iteration count causes an authentication failure or format error
  - format error cases
  - nonce changes on every save, and salt changes on `passwd`
  - atomic save and `.bak` creation
  - Unix file mode (on Unix)
  - name uniqueness rules and search
  - generator guarantees (length, required classes, ambiguous exclusion, validation, entropy), and a statistical sanity check that the output is not obviously biased
  - Copy `sample.lockbox` into the test project. Do not reference `benchmark/` from the solution.
- **CLI E2E:**
  - opening `sample.lockbox`
  - password input through the environment variable and `--password-stdin`
  - a full lifecycle (`init` → `add` → `list` → `get` → `edit` → `passwd` → `get` → `remove`)
  - proof that `list` never leaks secrets
  - Use `--iterations 100000` to keep tests fast.
- **GUI headless:**
  - unlock (right and wrong password)
  - add/edit/delete persisted to disk (verify by reopening the vault)
  - search, generator, failed-save retry
  - auto-lock and clipboard clearing driven by a fake `TimeProvider`

## 6. Product-Specific Rules

- **Dependencies:** third-party crypto packages are not allowed.
- **AOT watch-list:** NFC normalization must work in the published binary (globalization settings), and AES-GCM must work on every OS.
- **README additions:**
  - a prominent **security disclaimer**: Lockbox is an unaudited educational sample and must not be used for real secrets
  - the master password input rules
  - a summary of the vault format
  - the exit code table
- **Product hard gate:** the published CLI decrypts `sample.lockbox` correctly on all three platforms.
- **Product penalties:**

| Violation | Penalty |
|---|---|
| Custom or third-party cryptography | −10 |
| Master password accepted as a CLI argument | −10 |
| Secrets in `list` output, logs, or error messages | −5 each (max −10) |

## 7. Bonus (max +10)

| Bonus | Pts |
|---|---|
| **TOTP** (RFC 6238): optional `totpSecret` (base32) field on entries. `lockbox totp <vault> <name>` prints the current 6-digit SHA-1 code. The GUI shows the code with a countdown. Tests include the RFC 6238 SHA-1 vectors (secret ASCII `12345678901234567890` = base32 `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`; 8-digit codes: T=59 → `94287082`, T=1111111109 → `07081804`, T=1234567890 → `89005924`, T=20000000000 → `65353130`), using `TimeProvider`. | +4 |
| Working rename script (`scripts/rename.*`) that rebrands the solution and leaves it building and passing tests (proved in CI) | +3 |
| macOS GUI packaged as a proper `.app` bundle (with `Info.plist` and icon) in the release archive | +3 |

## 8. Conformance Suite

Evaluators run a hidden conformance suite against the published `lockbox` binary on every platform. It covers the vault format (§2.2) and the CLI contract (§3) exactly as written, including vaults produced by an independent reference implementation, and decrypting vaults your CLI writes. The vectors above are a visible subset.
