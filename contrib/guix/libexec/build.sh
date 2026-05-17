#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
out_dir="$repo_root/contrib/guix/out"
mkdir -p "$out_dir"

export LC_ALL=C
export TZ=UTC

dist_src="${GUIX_DIST_SRC:-}"
if [[ -z "$dist_src" || ! -f "$dist_src" ]]; then
  echo "GUIX_DIST_SRC must point to a source archive produced by contrib/guix/mk-distsrc" >&2
  exit 1
fi

build_root="$repo_root/target/guix-build-src"
export CARGO_HOME="$build_root/cargo-home"
rm -rf "$build_root"
mkdir -p "$build_root/src" "$CARGO_HOME"
# See mk-distsrc: guix shell --container runs as a mapped non-root user that
# cannot honor the archive's stored uid/gid; pass --no-same-owner so tar
# accepts the unprivileged extraction.
tar -xf "$dist_src" --no-same-owner --no-same-permissions -C "$build_root/src"

src_dir="$build_root/src"
cd "$src_dir"

version="$({ cargo metadata --locked --format-version=1 --no-deps | python3 -c 'import json,sys; print(next(p["version"] for p in json.load(sys.stdin)["packages"] if p["name"]=="cuprated"))'; })"
: "${version:?unable to parse version}"

SOURCE_DATE_EPOCH="$(python3 -c 'import json; print(json.load(open(".cuprate-distsrc.json"))["source_date_epoch"])')"
git_commit="$(python3 -c 'import json; print(json.load(open(".cuprate-distsrc.json"))["git_commit"])')"
distsrc_sha256="$(sha256sum "$dist_src" | awk '{print $1}')"
outer_commit="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$outer_commit" != "$git_commit" && "${GUIX_ALLOW_COMMIT_MISMATCH:-0}" != "1" ]]; then
  echo "outer checkout $outer_commit differs from distsrc commit $git_commit" >&2
  exit 1
fi
export SOURCE_DATE_EPOCH
export CARGO_INCREMENTAL=0
export CARGO_NET_OFFLINE=true
export RANDOMX_ARCH="${RANDOMX_ARCH:-}"
export RANDOMX_DARCH="${RANDOMX_DARCH:-default}"
export RUSTFLAGS="--remap-path-prefix=$src_dir=/cuprate -C codegen-units=1"
export CFLAGS="-ffile-prefix-map=$src_dir=/cuprate"
# libstdc++ in Guix's gcc-15.2 toolchain ships with _GLIBCXX_HAVE_FENV_H and
# _GLIBCXX_USE_C99_FENV undefined (c++config.h emits `/* #undef ... */` for
# both), so <cfenv> doesn't pull in glibc's fenv.h and std::fesetround / the
# global ::fesetround are both absent. Force-enable them so RandomX (and any
# other C++ caller of <cfenv>) builds. This is a libstdc++ packaging gap;
# defining these is consistent with what every other Linux distribution does.
export CXXFLAGS="-ffile-prefix-map=$src_dir=/cuprate -D_GLIBCXX_HAVE_FENV_H=1 -D_GLIBCXX_USE_C99_FENV=1"
# Guix's gcc-toolchain profile only provides `gcc`/`g++`, not the legacy `cc`
# alias; cc-rs (used by -sys crates such as libsqlite3-sys, openssl-sys,
# randomx-rs, ring, etc.) defaults to `cc` and fails with
#   ToolNotFound: failed to find tool "cc": No such file or directory
# Pointing CC/CXX/AR/AS at the actual binaries fixes every -sys crate.
export CC=gcc
export CXX=g++
export AR=ar
export AS=as
export LD=ld
export RANLIB=ranlib
export STRIP=strip
# Force openssl-sys to use the system openssl provided by the manifest via
# pkg-config rather than building it from source via openssl-src (which would
# also need `make`, but is wasteful when we already ship openssl).
export OPENSSL_NO_VENDOR=1
# Some -sys crates use $GUIX_ENVIRONMENT to find headers/libs when pkg-config
# is not available; provide explicit hints.
if [[ -n "${GUIX_ENVIRONMENT:-}" ]]; then
  export OPENSSL_DIR="$GUIX_ENVIRONMENT"
  export PKG_CONFIG_PATH="$GUIX_ENVIRONMENT/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi

rust_target="${GUIX_RUST_TARGET:-x86_64-unknown-linux-gnu}"

cargo build --frozen --release --package cuprated --target "$rust_target"

bash "$repo_root/contrib/guix/libexec/package.sh" "$version" "$rust_target" "$SOURCE_DATE_EPOCH" "$out_dir" "$src_dir"

binary="$src_dir/target/${rust_target}/release/cuprated"
if command -v ldd >/dev/null 2>&1; then
  ldd "$binary" > "$out_dir/ldd-${rust_target}.txt" 2>&1 || true
fi

guix describe --format=json > "$out_dir/guix-describe.json"
rustc --version --verbose > "$out_dir/rustc-version.txt"
cargo --version --verbose > "$out_dir/cargo-version.txt"

cat > "$out_dir/build-metadata.json" <<META
{
  "package": "cuprated",
  "version": "$version",
  "guix_system": "${GUIX_BUILD_SYSTEM:-x86_64-linux}",
  "rust_target": "$rust_target",
  "source_date_epoch": $SOURCE_DATE_EPOCH,
  "git_commit": "$git_commit",
  "randomx_arch": "$RANDOMX_ARCH",
  "randomx_darch": "$RANDOMX_DARCH",
  "distsrc": "$(basename "$dist_src")",
  "distsrc_sha256": "$distsrc_sha256"
}
META
