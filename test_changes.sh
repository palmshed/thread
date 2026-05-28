#!/bin/bash

set -euo pipefail

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
	for candidate in "venv/bin/python" ".venv/bin/python" "python3"; do
		if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "import cv2, numpy" >/dev/null 2>&1; then
			PYTHON_BIN="$candidate"
			break
		fi
	done
fi

if [ -z "$PYTHON_BIN" ]; then
	echo "FAIL: Python with cv2 and numpy is required"
	exit 1
fi

ROOT_DIR="$(pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
	rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
	echo "PASS: $1"
}

fail() {
	echo "FAIL: $1"
	exit 1
}

mkdir -p "$TMP_DIR/tiles" "$TMP_DIR/out"

"$PYTHON_BIN" - <<PY
from pathlib import Path

import cv2
import numpy as np

tile_dir = Path("$TMP_DIR/tiles")
for index in range(4):
    image = np.full((32, 32, 3), (0, 0, 255), dtype=np.uint8)
    ok = cv2.imwrite(str(tile_dir / f"tile_{index}.jpg"), image)
    if not ok:
        raise SystemExit("failed to write test tile")
PY

"$PYTHON_BIN" scripts/stitch.py "$TMP_DIR/tiles" "$TMP_DIR/stitched.jpg" --rows 2 --cols 2 --pattern "tile_*.jpg" >/dev/null
[ -f "$TMP_DIR/stitched.jpg" ] || fail "stitch.py did not create output"
pass "stitch.py creates output with explicit grid"

if "$ROOT_DIR/scripts/batch_upscale.sh" "$TMP_DIR/missing" "$TMP_DIR/out" >/dev/null 2>&1; then
	fail "batch_upscale.sh accepted a missing input directory"
fi
pass "batch_upscale.sh rejects missing input directory"

if UPSCALER="$TMP_DIR/no-upscaler" "$ROOT_DIR/scripts/batch_upscale.sh" "$TMP_DIR/tiles" "$TMP_DIR/out" >/dev/null 2>&1; then
	fail "batch_upscale.sh accepted a missing upscaler"
fi
pass "batch_upscale.sh rejects missing upscaler"

cat > "$TMP_DIR/fake-upscaler" <<'SH'
#!/bin/bash
set -euo pipefail
cp "$1" "$2"
SH
chmod +x "$TMP_DIR/fake-upscaler"

UPSCALER="$TMP_DIR/fake-upscaler" "$ROOT_DIR/scripts/batch_upscale.sh" "$TMP_DIR/tiles" "$TMP_DIR/out" 2 >/dev/null
[ -f "$TMP_DIR/out/tile_0.jpg" ] || fail "batch_upscale.sh did not create output with fake upscaler"
pass "batch_upscale.sh processes files with an upscaler"

if CLOUD_IP="invalid;command" LOCAL_TILES_DIR="$TMP_DIR/tiles" "$ROOT_DIR/scripts/transfer_tiles.sh" >/dev/null 2>&1; then
	fail "transfer_tiles.sh accepted unsafe CLOUD_IP"
fi
pass "transfer_tiles.sh rejects unsafe CLOUD_IP"

if CLOUD_IP="192.168.1.1" LOCAL_TILES_DIR="$TMP_DIR/missing" "$ROOT_DIR/scripts/transfer_tiles.sh" >/dev/null 2>&1; then
	fail "transfer_tiles.sh accepted a missing local tile directory"
fi
pass "transfer_tiles.sh rejects missing local tile directory"

echo "PASS: script checks completed"
