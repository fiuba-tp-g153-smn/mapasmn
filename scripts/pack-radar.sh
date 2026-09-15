#!/usr/bin/env sh
# Pack the radar H5 dataset into a single zip ready to upload to Google Drive.
# Usage:
#   ./scripts/pack-radar.sh SOURCE_DIR [OUTPUT_ZIP]
# Defaults:
#   OUTPUT_ZIP = ./radar-sinarame.zip

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ $# -ge 1 ] || {
    echo "Usage: $0 SOURCE_DIR [OUTPUT_ZIP]" >&2
    exit 1
}

SOURCE_DIR="$1"
OUTPUT_ZIP="${2:-$ROOT/radar-sinarame.zip}"

[ -d "$SOURCE_DIR" ] || { echo "source dir not found: $SOURCE_DIR" >&2; exit 1; }
command -v zip >/dev/null || { echo "zip not found. Install it with your package manager" >&2; exit 1; }

ABS_SRC="$(cd "$SOURCE_DIR" && pwd)"
PARENT="$(dirname "$ABS_SRC")"
LEAF="$(basename "$ABS_SRC")"

echo "Source:  $ABS_SRC"
echo "Output:  $OUTPUT_ZIP"
echo "H5 files are already compressed internally; using store-only mode"
(cd "$PARENT" && zip -0 -r "$OUTPUT_ZIP" "$LEAF")

SIZE=$(du -h "$OUTPUT_ZIP" | cut -f1)
echo "Wrote $OUTPUT_ZIP ($SIZE)"
echo
echo "Next steps:"
echo "  1. Upload $OUTPUT_ZIP to Google Drive."
echo "  2. Share the file with link access."
echo "  3. Copy the share URL and hand it to the deploy team."
echo "  4. They run: make fetch-radar URL=<google-drive-share-url>"
