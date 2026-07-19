# Releasing

Pushing a tag matching `v*` runs `.github/workflows/release.yml`, which builds
binaries for Android, Windows, macOS, Linux, and iOS and attaches them to a
GitHub Release. Both repos are public, so all runners (including macOS and
Windows) are free.

## Cutting a release

1. Update `version:` in `pubspec.yaml`.
2. If the databases changed since the last release, bump the installed-DB
   version so existing installs refresh their local copy on next launch:
   `tool/sync-dbs.sh --bump` (commits a `_dbVersion` increment in
   `lib/src/db_installer.dart`).
3. Commit, then tag and push:

   ```sh
   git tag v1.2.3
   git push origin v1.2.3
   ```

4. The workflow creates the release with all binaries plus `SHA256SUMS`.
   Review and edit the release notes on GitHub afterwards.

The workflow can also be run without a tag via *Actions → Release → Run
workflow* to check that all platforms still build (no release is published in
that case). It also runs automatically on PRs that modify the workflow file.

## One-time setup: Android release keystore

Without this, release APKs are signed with debug keys (installable, but users
cannot upgrade in place across differently-keyed builds, and the Play Store
would reject them). Generate a keystore once:

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
- `haqor-core` is checked out as a sibling directory in every job because
  `native/hub/Cargo.toml` depends on it by relative path.
- CI builds against haqor-core `main` by default. When local development
  tracks a haqor-core branch instead, set the repository variable
  `HAQOR_CORE_REF` (*Settings → Secrets and variables → Actions → Variables*)
  to that branch name, and delete the variable once the branch is merged.
  A `workflow_dispatch` run of Release can also override the ref one-off via
  its `core-ref` input.
