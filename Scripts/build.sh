#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
verify_tests=0
for arg in "$@"; do
    case "$arg" in
        --verify-tests) verify_tests=1 ;;
        *) printf '%s\n' "Unknown build option: $arg" >&2; exit 2 ;;
    esac
done
export PYTHONDONTWRITEBYTECODE=1
python3 Scripts/product_contract.py generate
run_dir="$project_dir/.build/development-$(uuidgen)"
mkdir -p "$run_dir/tmp" "$run_dir/cache" "$run_dir/config" "$run_dir/security" "$run_dir/module-cache" "$project_dir/dist"
export TMPDIR="$run_dir/tmp" CLANG_MODULE_CACHE_PATH="$run_dir/module-cache"
if [ -n "${JEV_SWIFT:-}" ]; then
    swift_bin="$JEV_SWIFT"
else
    swift_bin=$(xcrun --find swift)
fi
run_swift() {
    "$swift_bin" "$@" --cache-path "$run_dir/cache" --config-path "$run_dir/config" --security-path "$run_dir/security" -Xswiftc -module-cache-path -Xswiftc "$run_dir/module-cache"
}
record_inputs() {
    python3 - "$1" <<'PYINPUT'
import hashlib, json, sys
from pathlib import Path
root = Path.cwd()
files = [root / 'Product.json', root / 'Package.swift', root / 'Scripts/build.sh', root / 'Scripts/product_contract.py']
for folder in ['Sources', 'Tests', 'Assets', 'skill']:
    files.extend(p for p in (root / folder).rglob('*') if p.is_file())
Path(sys.argv[1]).write_text(json.dumps({str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}, sort_keys=True) + '\n')
PYINPUT
}
record_inputs "$run_dir/inputs-before.json"
run_swift build -c release --scratch-path "$run_dir/product" -Xswiftc -gnone
if [ "$verify_tests" = 1 ]; then
    run_swift test --scratch-path "$run_dir/tests"
fi
record_inputs "$run_dir/inputs-after.json"
cmp "$run_dir/inputs-before.json" "$run_dir/inputs-after.json"
python3 Scripts/product_contract.py check
bin_dir=$(run_swift build -c release --scratch-path "$run_dir/product" --show-bin-path)
app_dir="$project_dir/dist/development-$(uuidgen)/JevNative.app"
mkdir -p "$(dirname "$app_dir")"
python3 Scripts/product_contract.py assemble --candidate "$app_dir" --raw "$bin_dir/jev-native" --inputs "$run_dir/inputs-before.json"
printf '%s\n' "$app_dir/Contents/MacOS/jev-native"
