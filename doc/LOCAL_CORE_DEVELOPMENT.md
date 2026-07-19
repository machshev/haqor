# Local haqor-core development

Released app builds use the exact `haqor-core` version declared in
`native/hub/Cargo.toml`. To develop a paired change against a local
`haqor-core` checkout, add this ignored Cargo configuration at the app
repository root:

```toml
# .cargo/config.toml
[patch.crates-io]
haqor-core = { path = "/path/to/haqor-core/crates/haqor-core" }
```

Cargo, Rinf, and Flutter's Rust build then use the local crate automatically.
The checkout's package version must satisfy the exact version in
`native/hub/Cargo.toml`.

Cargo may update `Cargo.lock` to record the local path while this patch is
active. Keep that lockfile change local; it is expected that `cargo --locked`
will reject a path-patched build.

Remove that patch before validating the released dependency:

```sh
rm .cargo/config.toml
cargo update -p haqor-core --precise 0.7.1
```
