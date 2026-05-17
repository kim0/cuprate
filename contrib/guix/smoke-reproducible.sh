#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_once() {
  local src="$1"
  local commit distsrc artifact
  commit="$(git -C "$repo_root" rev-parse HEAD)"

  git clone --quiet --no-local "$repo_root" "$src" >&2
  git -C "$src" checkout --quiet --detach "$commit" >&2

  (
    cd "$src"
    distsrc="$(./contrib/guix/guix-mk-distsrc x86_64-linux 2>"$src/mk-distsrc.log" | tail -n1)"
    ./contrib/guix/guix-build \
      --guix-system x86_64-linux \
      --target x86_64-unknown-linux-gnu \
      --package cuprated \
      --distsrc "$distsrc" >"$src/build.log" 2>&1

    artifact="$({ find contrib/guix/out -maxdepth 1 -type f -name 'cuprated-*-x86_64-unknown-linux-gnu.tar.gz' | LC_ALL=C sort | tail -n1; })"
    sha256sum "$artifact" | awk '{print $1}'
  )
}

h1="$(run_once "$tmp/a")"
h2="$(run_once "$tmp/b")"

[[ "$h1" == "$h2" ]]
echo "reproducibility smoke test: PASS ($h1)"
