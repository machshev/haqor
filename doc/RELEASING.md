# Releasing

Pushing a tag matching `v*` runs `.github/workflows/release.yml`, which builds
binaries for Android, Windows, macOS, Linux, iOS, and a WebAssembly PWA. It
attaches all of them to a GitHub Release. Both repos are public, so all runners
(including macOS and Windows) are free.

## Cutting a release

1. Bump `pubspec.yaml` with `./tool/bump-version.sh patch` (or `minor`,
   `major`, or an explicit `X.Y.Z`). It advances Flutter's build number for
   Android/iOS and the release tag must match the semantic version with a
   leading `v` (for example `version: 1.2.3+4` requires `v1.2.3`).
2. If the databases changed since the last release, bump the installed-DB
   version so existing installs refresh their local copy on next launch:
   `tool/sync-dbs.sh --bump` (commits a `_dbVersion` increment in
   `lib/src/db_installer.dart`).
3. Commit any other release changes, then create the version commit and tag:

   ```sh
   ./tool/bump-version.sh patch --tag
   git push origin v1.2.3
   ```

   To recreate a local release tag after correcting it, append `--force` to
   the bump command. It replaces only the local tag; force-pushing a remote
   tag remains a deliberate separate action.

4. The workflow creates the release with all binaries plus `SHA256SUMS`.
   The web bundle is published as `haqor-<version>-web-wasm.zip`, and that
   same version is deployed to GitHub Pages at
   `https://machshev.github.io/haqor/`. Review and edit the release notes on
   GitHub afterwards.

The workflow can also be run without a tag via *Actions → Release → Run
workflow* to check that all platforms still build (no release is published in
that case). It also runs automatically on PRs that modify a release-critical
workflow, setup action, native hub, Android signing configuration, lockfile,
or package manifest.

## One-time setup: Android release keystore

Tagged releases fail without these secrets. Non-publishing validation builds
use debug keys; such APKs must never be distributed. Generate a keystore once:

```sh
keytool -genkey -v -keystore haqor-release.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias haqor
```

**Back this file and its passwords up somewhere safe.** All future releases
must be signed with the same key — if it is lost, existing installs can never
upgrade to a new release.

Then add these repository secrets (*Settings → Secrets and variables →
Actions*):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 haqor-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `haqor` |
| `ANDROID_KEY_PASSWORD` | the key password |

## One-time GitHub Pages setup

In *Settings → Pages*, set **Source** to **GitHub Actions**. The release
workflow deploys the tagged WebAssembly PWA to the repository's Pages URL.
The first browser visit registers a service worker so GitHub Pages can serve
the cross-origin-isolation headers needed by the threaded Rust WebAssembly
runtime; it then reloads once automatically.

## One-time release protection

Protect the `v*` tag namespace so only trusted maintainers can create release
tags. Also configure the GitHub `release` environment with a required reviewer
before the first publication. Build jobs only receive read access; the publish
job pauses at that environment approval boundary before it receives permission
to create a GitHub Release.

## Platform signing caveats (no paid developer accounts)

- **Windows** — unsigned; SmartScreen warns on first run. Fixable later with a
  code-signing certificate (e.g. Azure Trusted Signing).
- **macOS** — ad-hoc signed, not notarized; users right-click → Open the first
  time. Proper signing/notarization needs an Apple Developer account
  ($99/year) — with one, add certificate secrets and replace the ad-hoc
  `codesign` step with Developer ID signing + `notarytool`.
- **iOS** — the IPA is unsigned and cannot be installed directly. Users
  sideload it with [AltStore](https://altstore.io/) or Sideloadly using a free
  Apple ID (apps re-sign every 7 days). TestFlight/App Store distribution
  needs the same Apple Developer account.

## How the build is wired

- `.github/workflows/databases.yml` regenerates the four bundled SQLite
  databases from `haqor-core` (cached per haqor-core commit) via `cargo run`
  inside haqor-core's devshell, and shares them with all platform jobs as the
  `assets-db` artifact. It uses `cargo run` rather than the nix-built binary
  because gen-lexicon resolves `data/lexicon_overrides.json` through a
  compile-time `CARGO_MANIFEST_DIR` path that a relocated binary cannot
  satisfy.
- Linux-hosted jobs (databases, Android, CI checks) build inside the Nix
  devshell (`.github/actions/setup-nix-build`) so the toolchain is pinned by
  `flake.lock`.
- Windows/macOS/iOS and the portable Linux tarball use
  `.github/actions/setup-build` instead: Windows has no native Nix, macOS
  needs the runner's Xcode, and Linux binaries linked inside the devshell
  would carry `/nix/store` paths and only run on Nix systems. The pinned
  `flutter-version` there must be kept in lockstep with the flake's Flutter.
- `native/hub` uses the exact published `haqor-core` version declared in its
  `Cargo.toml`. Database generation checks out the matching `v0.7.1` core tag,
  so the released code and bundled databases come from the same core release.
  See `doc/LOCAL_CORE_DEVELOPMENT.md` when developing against a local core
  checkout.
