#!/usr/bin/env sh
# Fetch the radar H5 dataset from Google Drive and load it into the
# `mapasmn_tiles_data` named docker volume (which the prod compose mounts as
# /app/data in the producer/workers).
#
# - Downloads the zip into ./.cache/radar_h5.zip; subsequent runs reuse the
#   cached file (rm it to force a fresh download).
# - Always extracts from the cache into the named volume.
# - Uses ephemeral python:3.12-slim containers so the host needs only Docker.

set -eu

usage() {
    cat >&2 <<EOF
Usage: $0 <google-drive-url-or-file-id>

Examples:
  $0 https://drive.google.com/file/d/1AbCdEf_xxxxx/view?usp=sharing
  $0 1AbCdEf_xxxxx
EOF
    exit 1
}

[ $# -eq 1 ] || usage
URL_OR_ID="$1"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$ROOT/.cache"
CACHE_ZIP="$CACHE_DIR/radar_h5.zip"
VOLUME="mapasmn_tiles_data"

command -v docker >/dev/null || { echo "docker not found — required to run the gdown container" >&2; exit 1; }

mkdir -p "$CACHE_DIR"

if [ -f "$CACHE_ZIP" ]; then
    echo "Found cached zip: $CACHE_ZIP ($(du -h "$CACHE_ZIP" | cut -f1)). Skipping download."
    echo "(delete $CACHE_ZIP to force a fresh download)"
else
    echo "Downloading from Google Drive into $CACHE_ZIP..."
    docker run --rm -i \
        --user "$(id -u):$(id -g)" \
        -v "$CACHE_DIR:/cache" \
        -e HOME=/tmp \
        -e PYTHONUSERBASE=/tmp/pip \
        python:3.12-slim \
        sh -s "$URL_OR_ID" <<'EOF'
set -eu
pip install --quiet --user --no-warn-script-location 'gdown>=5'
export PATH="/tmp/pip/bin:$PATH"
gdown "$1" -O /cache/radar_h5.zip
size=$(stat -c%s /cache/radar_h5.zip)
echo "Downloaded $size bytes"
if [ "$size" -lt 10000 ]; then
    rm -f /cache/radar_h5.zip
    echo "ERROR: download too small — Drive likely returned an HTML error page" >&2
    echo "Check that the file is shared with 'Anyone with the link → Viewer'" >&2
    exit 1
fi
EOF
fi

echo "Extracting into docker volume '$VOLUME'..."
docker run --rm \
    -v "$CACHE_DIR:/cache:ro" \
    -v "$VOLUME:/out" \
    python:3.12-slim \
    sh -c '
set -eu
python -m zipfile -e /cache/radar_h5.zip /out
H5_COUNT=$(find /out/radar_h5 -type f -name "*.H5" 2>/dev/null | wc -l)
DATA_SIZE=$(du -sh /out/radar_h5 2>/dev/null | cut -f1)
echo "Volume now has $H5_COUNT .H5 files ($DATA_SIZE) at /out/radar_h5/"
'

echo
echo "Cached zip preserved at: $CACHE_ZIP"
echo "If the stack is already running, restart the producer/workers so they pick it up:"
echo "  docker compose restart producer worker1 worker2"
