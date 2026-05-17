# Guix reproducible build flow (cuprated)

This directory provides an initial Guix-first reproducible release pipeline for
`cuprated` focused on Linux artifacts.

## Goals

- Pin the Guix environment (`channels.scm`, `manifest.scm`).
- Build from a deterministic source archive (`mk-distsrc`) in an isolated, no-network container.
- Set deterministic build environment values.
- Produce deterministic `tar.gz` archives, checksums, provenance metadata, and optional signatures.

## Build flow

1) Create deterministic source archive with vendored Cargo dependencies (Guix-pinned):

```bash
./contrib/guix/guix-mk-distsrc x86_64-linux
```

2) Build from that archive using Guix time-machine:

```bash
./contrib/guix/guix-build \
  --guix-system x86_64-linux \
  --target x86_64-unknown-linux-gnu \
  --package cuprated \
  --distsrc contrib/guix/out/cuprate-<version>-<commit>-src.tar.gz
```

3) Create aggregate checksums and signed attestation bundle:

```bash
./contrib/guix/guix-checksums contrib/guix/out
./contrib/guix/guix-attest contrib/guix/out <builder-id> <version>
```

4) Verify artifact checksum:

```bash
./contrib/guix/guix-verify contrib/guix/out/cuprated-<version>-x86_64-unknown-linux-gnu.tar.gz
```

5) Optional reproducibility smoke test:

```bash
./contrib/guix/smoke-reproducible.sh
```

## Output files

`contrib/guix/out/` includes:

- `cuprate-<version>-<commit>-src.tar.gz` (+ `.SHA256SUM`)
- `cuprated-<version>-<rust-target>.tar.gz` (+ `.SHA256SUM`)
- `SHA256SUMS` (from `guix-checksums`)
- `build-metadata.json` (includes `distsrc_sha256`)
- `guix-describe.json`
- `rustc-version.txt`
- `cargo-version.txt`
- `ldd-<rust-target>.txt`

## RandomX note

- Current flow temporarily patches vendored `randomx-rs` during distsrc creation to force `ARCH` default behavior via `RANDOMX_ARCH`/`RANDOMX_DARCH`.
- Long-term fix should update Cuprate to a `randomx-rs` revision with this behavior upstream.
