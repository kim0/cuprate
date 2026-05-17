#!/usr/bin/env bash
set -euo pipefail

src_dir="$1"
mapfile -t candidates < <(find "$src_dir/vendor" -maxdepth 2 -type f -path '*/randomx-rs*/build.rs' | sort)
[[ ${#candidates[@]} -gt 0 ]] || { echo "no vendored randomx-rs build.rs found" >&2; exit 1; }

for build_rs in "${candidates[@]}"; do
  python3 - "$build_rs" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
# Upstream randomx-rs uses `.define("DARCH", "native")` which becomes `-DDARCH=native`
# at the CMake level — that's not the variable RandomX's CMakeLists actually consults.
# Replace either form with a Rust env-var driven `.define("ARCH", ...)` so the build can
# be steered to a non-`native` configuration for reproducible artifacts. An empty
# RANDOMX_ARCH is treated as unset so the RANDOMX_DARCH fallback (defaults to "default")
# actually fires.
replacement = ('''.define(
            "ARCH",
            std::env::var("RANDOMX_ARCH")
                .ok()
                .filter(|v| !v.is_empty())
                .or_else(|| std::env::var("RANDOMX_DARCH").ok().filter(|v| !v.is_empty()))
                .unwrap_or_else(|| "default".to_string()),
        )''')
changed = False
for needle in ('.define("ARCH", "native")', '.define("DARCH", "native")'):
    if needle in s:
        s = s.replace(needle, replacement, 1)
        changed = True
if not changed:
    print(f"randomx-rs build.rs at {p} has no ARCH/DARCH define to patch", file=sys.stderr)
    sys.exit(2)
p.write_text(s)
PY
  echo "patched $build_rs to honor RANDOMX_ARCH/RANDOMX_DARCH" >&2

  crate_dir="$(dirname "$build_rs")"
  checksum_file="$crate_dir/.cargo-checksum.json"
  if [[ -f "$checksum_file" ]]; then
    python3 - "$crate_dir" "$checksum_file" <<'PY'
import hashlib, json, sys
crate_dir, checksum_file = sys.argv[1], sys.argv[2]
with open(checksum_file) as f:
    data = json.load(f)
rel = "build.rs"
with open(f"{crate_dir}/{rel}", "rb") as f:
    new_sha = hashlib.sha256(f.read()).hexdigest()
data["files"][rel] = new_sha
with open(checksum_file, "w") as f:
    json.dump(data, f, separators=(",", ":"), sort_keys=True)
PY
    echo "updated $checksum_file (build.rs sha256 regenerated)" >&2
  else
    echo "warning: no .cargo-checksum.json next to $build_rs; cargo --frozen will fail" >&2
  fi
done
