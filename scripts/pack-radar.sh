#!/usr/bin/env sh
# Pack the radar H5 dataset into a single zip ready to upload to Google Drive.
# Usage:
#   ./scripts/pack-radar.sh [SOURCE_DIR] [OUTPUT_ZIP]
# Defaults:
#   SOURCE_DIR  = ../tiles-processor/data/radar_h5  (sibling checkout)
#   OUTPUT_ZIP  = ./radar_h5.zip

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="${1:-$ROOT/../tiles-processor/data/radar_h5}"
OUTPUT_ZIP="${2:-$ROOT/radar_h5.zip}"

[ -d "$SOURCE_DIR" ] || { echo "source dir not found: $SOURCE_DIR" >&2; exit 1; }
command -v zip >/dev/null || { echo "zip not found — install via your package manager" >&2; exit 1; }

ABS_SRC="$(cd "$SOURCE_DIR" && pwd)"
PARENT="$(dirname "$ABS_SRC")"
LEAF="$(basename "$ABS_SRC")"

echo "Source:  $ABS_SRC"
echo "Output:  $OUTPUT_ZIP"
echo "(H5 files are typically already compressed internally, so we use store-only mode for speed)"
(cd "$PARENT" && zip -0 -r "$OUTPUT_ZIP" "$LEAF")

SIZE=$(du -h "$OUTPUT_ZIP" | cut -f1)
echo "Wrote $OUTPUT_ZIP ($SIZE)"
echo
echo "Next steps:"
echo "  1. Upload $OUTPUT_ZIP to Google Drive."
echo "  2. Share the file with link access (Anyone with the link → Viewer)."
echo "  3. Copy the share URL and hand it to the deploy team."
echo "  4. They run: make fetch-radar URL=<google-drive-share-url>"
