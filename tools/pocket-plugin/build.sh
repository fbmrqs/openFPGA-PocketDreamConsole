#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$plugin_dir/../.." && pwd)"
cargo_cache="${CARGO_HOME:-$HOME/.cargo}"
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$project_dir=. --remap-path-prefix=$cargo_cache=.cargo"
cargo build --manifest-path "$plugin_dir/Cargo.toml" --release --locked --target wasm32-wasip1 -j 2
asset_dir="$plugin_dir/target/release-assets"
mkdir -p "$asset_dir"
cp "$plugin_dir/target/wasm32-wasip1/release/plugin.wasm" "$asset_dir/plugin.wasm"
cp "$plugin_dir/plugin.json" "$asset_dir/plugin.json"
cp "$plugin_dir/LICENSE" "$asset_dir/LICENSE"
"${PYTHON:-python3}" "$plugin_dir/notices.py" "$asset_dir/THIRD_PARTY_NOTICES.txt"
"${PYTHON:-python3}" - "$asset_dir" <<'PY'
import hashlib
from pathlib import Path
import sys
folder = Path(sys.argv[1])
files = [folder / name for name in ('plugin.wasm', 'plugin.json', 'LICENSE', 'THIRD_PARTY_NOTICES.txt')]
(folder / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files))
print(f'Release assets: {folder}')
PY
