# Local haqor-core development

Released app builds use the exact `haqor-core` version declared in
`native/hub/Cargo.toml`. To use a sibling local checkout from the app
repository root, run:

```sh
nix run .#update-local-core-lock
```

Pass a checkout path as an argument if it is elsewhere:
`nix run .#update-local-core-lock -- /path/to/haqor-core`. The command writes
the ignored `.cargo/config.toml` patch and updates `Cargo.lock`. To configure
it by hand instead, add this file at the app repository root:

```toml
# .cargo/config.toml
[patch.crates-io]
haqor-core = { path = "/path/to/haqor-core/crates/haqor-core" }
```

Cargo, Rinf, and Flutter's Rust build then use the local crate automatically.
The checkout's package version must satisfy the exact version in
`native/hub/Cargo.toml`.

Keep the local `Cargo.lock` change local; `cargo --locked` will reject a
path-patched build until the lockfile has been updated. After rebuilding the
runtime database in `haqor-core`, run `bash tool/sync-dbs.sh` here so the app
bundles the new database.

Remove that patch before validating the released dependency:

```sh
rm .cargo/config.toml
cargo update -p haqor-core --precise 0.9.19
```
