#!/usr/bin/env bash
set -euo pipefail

src_dir="$1"
mapfile -t candidates < <(find "$src_dir/vendor" -maxdepth 2 -type f -path '*/randomx-rs*/build.rs' | sort)
[[ ${#candidates[@]} -gt 0 ]] || { echo "no vendored randomx-rs build.rs found" >&2; exit 1; }

for build_rs in "${candidates[@]}"; do
  crate_dir="$(dirname "$build_rs")"

  # ----- patch 1: build.rs, ARCH/DARCH define -----
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

  # ----- patch 2: RandomX/src/instructions_portable.cpp -----
  # GCC 15+ rejects the bare `fesetround(mode)` call: <cfenv> only brings the
  # function into std::, and including <fenv.h> doesn't reliably backport it
  # to the global namespace under libstdc++. Qualify the call as
  # std::fesetround(mode) instead — works on every supported toolchain.
  ip_cpp="$crate_dir/RandomX/src/instructions_portable.cpp"
  if [[ -f "$ip_cpp" ]]; then
    python3 - "$ip_cpp" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
if 'std::fesetround(' in s:
    print(f"{p} already calls std::fesetround", file=sys.stderr)
elif '\tfesetround(' in s or '\t\tfesetround(' in s or ' fesetround(' in s:
    # The call is currently `fesetround(mode);` somewhere; qualify it.
    import re
    new_s = re.sub(r'(?<![:\w])fesetround\(', 'std::fesetround(', s, count=1)
    if new_s == s:
        print(f"warning: failed to qualify fesetround in {p}", file=sys.stderr)
        sys.exit(3)
    p.write_text(new_s)
    print(f"qualified fesetround as std::fesetround in {p}", file=sys.stderr)
else:
    print(f"warning: {p} has no fesetround call to patch", file=sys.stderr)
    sys.exit(3)
PY
  fi

  # ----- regenerate .cargo-checksum.json for every modified file -----
  checksum_file="$crate_dir/.cargo-checksum.json"
  if [[ -f "$checksum_file" ]]; then
    python3 - "$crate_dir" "$checksum_file" <<'PY'
import hashlib, json, sys, os
crate_dir, checksum_file = sys.argv[1], sys.argv[2]
with open(checksum_file) as f:
    data = json.load(f)
# Only refresh entries for files we touch — leaves the rest of the
# upstream-provided manifest intact and keeps the diff small.
touched = ["build.rs", "RandomX/src/instructions_portable.cpp"]
for rel in touched:
    abs_path = os.path.join(crate_dir, rel)
    if rel not in data["files"]:
        continue
    if not os.path.exists(abs_path):
        continue
    with open(abs_path, "rb") as f:
        data["files"][rel] = hashlib.sha256(f.read()).hexdigest()
with open(checksum_file, "w") as f:
    json.dump(data, f, separators=(",", ":"), sort_keys=True)
PY
    echo "refreshed $checksum_file for patched files" >&2
  else
    echo "warning: no .cargo-checksum.json next to $build_rs; cargo --frozen will fail" >&2
  fi
done
