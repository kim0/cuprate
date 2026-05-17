#!/usr/bin/env bash
set -euo pipefail

src_dir="$1"
mapfile -t candidates < <(find "$src_dir/vendor" -maxdepth 2 -type f -path '*/randomx-rs*/build.rs' | sort)
[[ ${#candidates[@]} -gt 0 ]] || { echo "no vendored randomx-rs build.rs found" >&2; exit 1; }

for build_rs in "${candidates[@]}"; do
  python3 - "$build_rs" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
if '.define("ARCH", "native")' in s:
    s=s.replace('.define("ARCH", "native")','''.define(
            "ARCH",
            std::env::var("RANDOMX_ARCH")
                .or_else(|_| std::env::var("RANDOMX_DARCH"))
                .unwrap_or_else(|_| "default".to_string()),
        )''',1)
if '.define("DARCH", "native")' in s:
    s=s.replace('.define("DARCH", "native")','''.define(
            "ARCH",
            std::env::var("RANDOMX_ARCH")
                .or_else(|_| std::env::var("RANDOMX_DARCH"))
                .unwrap_or_else(|_| "default".to_string()),
        )''',1)
p.write_text(s)
PY
  echo "patched $build_rs to honor RANDOMX_ARCH/RANDOMX_DARCH" >&2
done
