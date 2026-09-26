# PHP Windows Builds

Universal automated Windows builds of PHP — **any version, any [`php/php-src`](https://github.com/php/php-src) ref** — plus a patched Imagick extension that follows whichever PHP you build.

Thread Safe (ZTS) for Apache mod_php / XAMPP. x64 + x86, each also as an AVX2-optimized build.

> **History.** This repository started as `php86-windows-builds` and tracked the PHP **8.6.0-dev** master snapshots (see the [INIT 8.6](#changelog) section). On **2026-09-26**, `php/php-src` master bumped to **8.7.0-dev** after the `PHP-8.6` release branch was cut, so the repository was renamed to **`php-windows-builds`** and made version-agnostic end to end. Old URLs (git remote, releases, API) redirect automatically.

## 1. PHP distributions — any php/php-src ref

The [`build-php-dev-latest`](.github/workflows/build-php-dev-latest.yaml) workflow builds a complete PHP distribution from whatever ref you point it at:

| `php_ref` input | What you get |
|---|---|
| `master` *(default)* | the next dev version — currently **8.7.0-dev** |
| any release branch — e.g. `PHP-8.6` | that branch (dev snapshots + its release candidates) |
| any tag — e.g. `php-8.6.0RC2` | that exact release |
| any commit SHA | a reproducible snapshot |

The version label for artifacts and releases is **auto-detected from the source that is actually built** (`main/php_version.h`; the `php_version` input defaults to `auto`). A build can therefore never be mislabeled — the release job derives its tag, title and asset table from build metadata, not from a hardcoded string.

### Variants

| Architecture | Optimization |
|---|---|
| x64 | Standard |
| x86 | Standard |
| x64-AVX2 | AVX2 (Intel Haswell 2013+, AMD Ryzen 2017+) |
| x86-AVX2 | AVX2 |

### Each zip is a ready-to-use distribution

- `php.exe`, `php-cgi.exe` (CLI + FastCGI)
- `php8ts.dll` (Thread Safe engine), `php8apache2_4.dll` (Apache 2.4 module)
- `ext/*.dll` — 40+ extensions (mysqli, opcache, curl, gd, intl, mbstring, soap, xsl, sockets, …)
- dependency DLLs (libcrypto, libssl, icu, brotli)
- `php.ini-development` / `php.ini-production`
- **devel pack** (x64): headers, `.lib` files, `phpize.bat` — for building PECL extensions

**Compiler:** Visual Studio 2024 (VC18) on a `windows-2025` runner.
**Build type:** Thread Safe (ZTS) — Apache mod_php / XAMPP.

### XAMPP installation

1. Download `x64-AVX2.zip` for best performance on modern CPUs
2. Stop Apache
3. Replace `php8ts.dll`, `php8apache2_4.dll`, `php.exe`, `ext/` in `C:\xampp\php\`
4. Start Apache
5. Verify: `C:\xampp\php\php.exe -v`

**Trigger:** Actions → **Build PHP TS Windows VS18 (x86 + x64 + AVX2, any php/php-src ref)** → Run workflow.

---

## 2. Imagick extension — patched, follows any PHP ≥ 8.6

The [`build-imagick`](.github/workflows/build-imagick.yaml) workflow builds `php_imagick.dll` (x64, Thread Safe + Non-Thread Safe, each ± AVX2) against any PHP this repository provides:

- **TS variant** — compiled against a PHP release from this repository, selected by the `php_release` input:
  - `latest` *(default)* — the newest `php-*` release
  - a series, e.g. `8.6` or `8.7` — the newest release of that series
  - an exact tag, e.g. `php-8.6.0RC2`

  Artifact and release labels are derived from the release that was **actually used**, so they can never lie.
- **NTS variant** — compiled against the official [windows.php.net](https://windows.php.net) QA build selected by `qa_version` (default `8.6.0RC2`), labeled accordingly.

If the TS and NTS variants end up on different PHP series, the release is published as an explicit **multi-version** release and every asset carries its own version in the filename.

### Why the patch is needed

PHP 8.6 turned `zend_is_callable()` from an exported API function into a non-exported `static zend_always_inline` function. Every Imagick DLL built for PHP ≤ 8.5 imports `zend_is_callable` directly and dies on startup with:

> The procedure entry point `zend_is_callable` could not be located in the dynamic link library `php8ts.dll`.

The vendored, pre-patched Imagick source (`vendor/imagick-patched.zip`) switches the call to `zend_is_callable_ex`, which is still an exported `ZEND_API` function — **one fix for every PHP from 8.6 onward (8.6, 8.7, …)**. The workflow fail-fast-verifies the patch is present before building.

### How the TS variant stays ABI-correct

PHP checks `ZEND_MODULE_API_NO` when an extension is loaded, so headers, import libs and the runtime must all come from the same PHP build. The TS job therefore uses the official QA pack only as a tooling base (`script/`, `phpize.bat`, `win32/` extras) and overlays **both `include/` and `lib/`** from the selected own-repo devel pack — headers and `php8ts.lib` always match the exact binary being built against, for any series. The built-in load test (`php.exe -d extension=php_imagick.dll`) fails loudly if anything ever mismatches.

**Trigger:** Actions → **Build Imagick PHP VS18 x64 (from own releases)** → Run workflow.

---

## Workflows

| Workflow | Builds | Output |
|---|---|---|
| `build-php-dev-latest` | full PHP distro, any php/php-src ref, version auto-detected | GitHub Release (zips + devel pack) |
| `build-imagick` | patched `php_imagick.dll` — TS from own releases, NTS from official QA | GitHub Release (zips) |

## Source

- PHP source: [php/php-src](https://github.com/php/php-src) — any ref via `php_ref`
- PHP SDK: [php/php-sdk-binary-tools](https://github.com/php/php-sdk-binary-tools)
- Imagick source: [Imagick/imagick](https://github.com/Imagick/imagick) — patched, vendored
- Ubuntu .deb builds: [markusfoo/php-apt-builder](https://github.com/markusfoo/php-apt-builder)

## Changelog

### 2026-09-26 — universal builds (PHP 8.7.0-dev era) + repository renamed to `php-windows-builds`

- `php/php-src` master bumped to **8.7.0-dev** after the `PHP-8.6` release branch was cut, which made the old repository name (`php86-windows-builds`) and the version-coupled workflow inaccurate. The repository is renamed to **`php-windows-builds`**; all old URLs redirect automatically.
- `build-php-dev-latest.yaml` (renamed from `build-php86-dev-latest.yaml`) is fully version-agnostic:
  - new `php_ref` input — build **any** php/php-src ref: `master`, a release branch, a tag, or a SHA
  - new `php_version=auto` default — the version label is **auto-detected from `main/php_version.h`** of the checked-out source; the release job consumes build metadata via a `build-meta` artifact, so tag/title/asset table are all derived from what was actually built
  - validated by the first universal run: release **`php-8.7.0-dev-2026-09-26`** — correctly labeled 8.7.0-dev (the same-day `php-8.6.0-dev-2026-09-26` snapshot was 8.7.0-dev content under an 8.6 name and was removed in its favor)
- `build-imagick.yaml` — per-variant, honest versioning:
  - the `php_version` naming-only input was **removed**; the new `php_release` input (`latest` / a series like `8.6` / an exact tag) selects which own-repo release the TS variant builds against, and TS artifact names are derived from the release actually used
  - NTS artifact names derive from `qa_version` (default moved to the current php.net QA cycle: **`8.6.0RC2`**, previously `8.6.0beta2`)
  - the TS job now overlays the own devel pack's **`include/`** on the official QA base (in addition to `lib/`), because PHP checks `ZEND_MODULE_API_NO` at extension load (8.6 = `20260924`, 8.7.0-dev = `20260925`) — a DLL compiled against another series' headers would fail to load
  - the release tag/name/asset table/version line are generated from the assets that were actually built; mixed TS/NTS series produce an explicit multi-version release
  - own-releases API URL updated to the new repo name; vendored source renamed to `vendor/imagick-patched.zip`; job names and banners made version-agnostic
- README rewritten to be fully version-agnostic (version specifics now live only in this changelog); stale `php86-apt-builder` link fixed → [`php-apt-builder`](https://github.com/markusfoo/php-apt-builder)

### INIT 8.6 (2026-08 — 2026-09): repository history under the previous name (`php86-windows-builds`)

The repository was created to track the **PHP 8.6.0-dev** master snapshots:

- TS (ZTS) VS18 Windows builds on `windows-2025` runners — x64 + x86, each also as an AVX2 variant (`--enable-native-intrinsics=avx2`), XAMPP-ready (`php8ts.dll` + `php8apache2_4.dll`), with a devel pack (headers + `.lib` + `phpize.bat`) for building PECL extensions
- Releases: `v1.0.0-php8.6.0beta1`, `php-8.6.0-dev-2026-08-19`, `php-8.6.0-dev-2026-08-27`, plus `imagick-php8.6-vs18-x64-*` extension releases. A `php-8.6.0-dev-2026-09-26` snapshot was also published, but master had already moved to 8.7.0-dev by then — that mislabel is what triggered the universalization above (the release was later removed)
- Patched Imagick for the PHP 8.6 API change (`zend_is_callable` no longer exported → `zend_is_callable_ex`), with a hard fail-fast check that the patch is present in the vendored source before building
- Imagick build matrix extended to TS + NTS × ± AVX2, with the ImageMagick headers/libs layout fixed to match `config.w32` expectations and the official QA devel pack used as the `script/` source
