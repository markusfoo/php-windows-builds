# PHP Windows Builds

Universal automated Windows builds of PHP — **any version, any ref** — plus a patched Imagick extension. Thread Safe (ZTS) for Apache mod_php / XAMPP, x86 and x64, with optional AVX2-optimized binaries.

> This repository was originally named `php86-windows-builds` and tracked the PHP 8.6.0-dev master snapshots. It was renamed and universalized on **2026-09-26**, when `php/php-src` master bumped to **8.7.0-dev** after the `PHP-8.6` release branch was cut. Old URLs redirect automatically. See the [Changelog](#changelog) for the full history.

## What This Repository Provides

### 1. PHP Windows Builds (any php/php-src ref)

Pre-built **complete PHP distributions** for Windows, built from whatever `php/php-src` ref you point the workflow at:

| `php_ref` input | What you get |
|---|---|
| `master` *(default)* | Next dev version — currently **8.7.0-dev** (was 8.6.0-dev until the `PHP-8.6` branch was cut) |
| `PHP-8.6` | The 8.6 release branch (8.6.0-dev + release candidates) |
| `php-8.6.0RC1` (any tag) | That exact release |
| any commit SHA | A reproducible snapshot |

The version label for artifacts and releases is **auto-detected from the built source** (`main/php_version.h`) — the `php_version` input defaults to `auto`, so a build can never be mislabeled again (the 2026-09-26 snapshot was labeled `8.6.0-dev` while master had already moved to `8.7.0-dev`; auto-detection closes that gap).

| Variant | Architecture | Optimization |
|---------|-------------|--------------|
| x64 | 64-bit | Standard |
| x86 | 32-bit | Standard |
| x64-AVX2 | 64-bit | AVX2 (Intel Haswell 2013+, AMD Ryzen 2017+) |
| x86-AVX2 | 32-bit | AVX2 |

Each zip is a ready-to-use PHP distribution:
- `php.exe`, `php-cgi.exe` (CLI + FastCGI)
- `php8ts.dll` (Thread Safe engine)
- `php8apache2_4.dll` (Apache 2.4 module)
- `ext/*.dll` — 40+ extensions (mysqli, opcache, curl, gd, intl, mbstring, soap, xsl, sockets, etc.)
- Dependency DLLs (libcrypto, libssl, icu, brotli)
- `php.ini-development`, `php.ini-production`
- **Devel pack** (x64): headers, `.lib` files, `phpize.bat` — for building PECL extensions

**Compiler:** Visual Studio 2024 (VC18) on `windows-2025` runner.
**Build type:** Thread Safe (ZTS) — for Apache mod_php and XAMPP.

**XAMPP Installation:**
1. Download `x64-AVX2.zip` for best performance on modern CPUs
2. Stop Apache
3. Replace `php8ts.dll`, `php8apache2_4.dll`, `php.exe`, `ext/` in `C:\xampp\php\`
4. Start Apache
5. Verify: `C:\xampp\php\php.exe -v`

Trigger via **Actions** → **Build PHP TS Windows VS18 (x86 + x64 + AVX2, any php/php-src ref)** → **Run workflow**.

---

### 2. Imagick Extension for PHP 8.6+ (Windows)

Pre-built `php_imagick.dll` for PHP on Windows (x64, Thread Safe + Non-Thread Safe, ± AVX2).

#### The Problem

Starting with PHP 8.6, the Zend Engine changed `zend_is_callable()` from an exported API function to a `static zend_always_inline` function. It is no longer exported by `php8ts.dll`.

Older Imagick DLLs (compiled for PHP 8.5 and earlier) import `zend_is_callable` directly, causing a fatal error on startup:

> The procedure entry point `zend_is_callable` could not be located in the dynamic link library `php8ts.dll`.

This applies to **every PHP version from 8.6 onwards**, including 8.7 — the fix below is not version-specific.

#### The Fix

A patched version of [Imagick/imagick](https://github.com/Imagick/imagick) (vendored as `vendor/imagick-patched.zip`) that replaces the call to the inlined `zend_is_callable` with `zend_is_callable_ex`, which remains an exported `ZEND_API` function in PHP 8.6+:

```c
// Before (PHP 8.5):
if (!user_callback || !zend_is_callable(user_callback, 0, NULL TSRMLS_CC)) {

// After (PHP 8.6+):
if (!user_callback || !zend_is_callable_ex(user_callback, NULL, 0, NULL, NULL, NULL)) {
```

The TS variant builds against the **latest PHP release from this repository**; the NTS variant builds against the **official php.net QA build** (configurable via the `qa_version` input). Artifact and release naming uses the `php_version` input (default `8.6`).

Trigger via **Actions** → **Build Imagick PHP VS18 x64 (from own releases)** → **Run workflow**.

---

## Workflows

| Workflow | What it builds | Output |
|----------|---------------|--------|
| `build-php-dev-latest` | Full PHP distro (any php/php-src ref, version auto-detected) | GitHub Release (zip) |
| `build-imagick` | php_imagick.dll (patched, PHP 8.6+) | GitHub Release (zip) |

## Source

- PHP source: [php/php-src](https://github.com/php/php-src) (any ref via `php_ref`)
- PHP SDK: [php/php-sdk-binary-tools](https://github.com/php/php-sdk-binary-tools)
- Imagick source: [Imagick/imagick](https://github.com/Imagick/imagick) (patched, vendored)
- Ubuntu .deb builds: [markusfoo/php-apt-builder](https://github.com/markusfoo/php-apt-builder)

## Changelog

### 2026-09-26 — Universal builds (PHP 8.7.0-dev era) + repository renamed to `php-windows-builds`

- `php/php-src` master bumped to **8.7.0-dev** after the `PHP-8.6` release branch was
  cut, which made the old repository name (`php86-windows-builds`) and the
  version-coupled workflow inaccurate. The repository is renamed to
  **`php-windows-builds`**; all old URLs (git remote, releases, API) redirect
  automatically
- `build-php-dev-latest.yaml` (renamed from `build-php86-dev-latest.yaml`) is now
  fully version-agnostic:
  - new `php_ref` input — build **any** php/php-src ref: `master` (next dev
    version), a release branch (`PHP-8.6`), a tag (`php-8.6.0RC1`) or a SHA
  - new `php_version=auto` default — the version label is **auto-detected from
    `main/php_version.h` of the checked-out source**, so artifacts and releases
    can never be mislabeled (the 2026-09-26 snapshot was labeled `8.6.0-dev`
    while master had already moved to `8.7.0-dev`)
  - the release job now consumes build metadata (detected version + built ref)
    via a `build-meta` artifact: tag, title, asset table and the linked source
    commit are all derived from what was actually built
  - the hardcoded "PHP 8.6 features" release-notes section was replaced with a
    generic pointer to the built ref/commit
- `build-imagick.yaml` parameterized: new `php_version` input (artifact/release
  naming, default `8.6`) and `qa_version` input (official php.net QA build used
  for NTS binaries/devel packs and the `script/` fallback, default
  `8.6.0beta2`); own-release API URL updated to the new repo name; the dead
  workflow-level `PHP_VERSION: "8.6.0"` env was removed; the vendored source
  was renamed to `vendor/imagick-patched.zip`
- README rewritten to be version-agnostic; the stale `php86-apt-builder` link
  was corrected to [`php-apt-builder`](https://github.com/markusfoo/php-apt-builder)
- Validation: both workflows parse as valid YAML; job/step structure unchanged
  apart from the additions above

### INIT 8.6 (2026-08 — 2026-09): repository history under the previous name (`php86-windows-builds`)

The repository was created to track the **PHP 8.6.0-dev** master snapshots:

- TS (ZTS) VS18 Windows builds on `windows-2025` runners — x64 + x86, each
  also as an AVX2 variant (`--enable-native-intrinsics=avx2`), XAMPP-ready
  (`php8ts.dll` + `php8apache2_4.dll`), with a devel pack (headers + `.lib` +
  `phpize.bat`) for building PECL extensions
- Releases: `v1.0.0-php8.6.0beta1`, `php-8.6.0-dev-2026-08-19`,
  `php-8.6.0-dev-2026-08-27`, `php-8.6.0-dev-2026-09-26` (the last one
  actually built from master = 8.7.0-dev, which triggered the
  universalization), plus `imagick-php8.6-vs18-x64-*` extension releases
- Patched Imagick for the PHP 8.6 API change (`zend_is_callable` no longer
  exported → `zend_is_callable_ex`), with a hard fail-fast check that the
  patch is present in the vendored source before building
- Imagick build matrix extended to TS + NTS × ± AVX2, with the ImageMagick
  headers/libs layout fixed to match `config.w32` expectations and the
  official QA devel pack used as the `script/` source
