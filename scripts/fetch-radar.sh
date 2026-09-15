#!/usr/bin/env sh
# Fetch a radar H5 dataset from Google Drive and load it into the host directory
# configured as RADAR_SINARAME_INPUT_DIR.
#
# - Downloads the zip into ./.cache/radar-sinarame.zip; subsequent runs reuse the
#   cached file (rm it to force a fresh download).
# - Accepts archives whose files are at the root, under radar-sinarame/, or under
#   the former radar_h5/ name.
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
CACHE_ZIP="$CACHE_DIR/radar-sinarame.zip"

[ -f "$ROOT/.env" ] || {
    echo ".env not found; run 'make setup' and configure RADAR_SINARAME_INPUT_DIR" >&2
    exit 1
}

set -a
. "$ROOT/.env"
set +a

: "${RADAR_SINARAME_INPUT_DIR:?set RADAR_SINARAME_INPUT_DIR in the root .env}"
case "$RADAR_SINARAME_INPUT_DIR" in
    /*) ;;
    *) echo "RADAR_SINARAME_INPUT_DIR must be an absolute path" >&2; exit 1 ;;
esac

command -v docker >/dev/null || { echo "docker not found. It is required to run the gdown container" >&2; exit 1; }

mkdir -p "$CACHE_DIR" "$RADAR_SINARAME_INPUT_DIR"

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
gdown "$1" -O /cache/radar-sinarame.zip
size=$(stat -c%s /cache/radar-sinarame.zip)
echo "Downloaded $size bytes"
if [ "$size" -lt 10000 ]; then
    rm -f /cache/radar-sinarame.zip
    echo "ERROR: download too small. Drive likely returned an HTML error page" >&2
    echo "Check that the file is shared with 'Anyone with the link, Viewer'" >&2
    exit 1
fi
EOF
fi

echo "Extracting into $RADAR_SINARAME_INPUT_DIR..."
docker run --rm \
    -v "$CACHE_DIR:/cache:ro" \
    -v "$RADAR_SINARAME_INPUT_DIR:/out" \
    python:3.12-slim \
    sh -c '
set -eu
rm -rf /tmp/radar-extract
mkdir -p /tmp/radar-extract
python -m zipfile -e /cache/radar-sinarame.zip /tmp/radar-extract
if [ -d /tmp/radar-extract/radar-sinarame ]; then
    cp -a /tmp/radar-extract/radar-sinarame/. /out/
elif [ -d /tmp/radar-extract/radar_h5 ]; then
    cp -a /tmp/radar-extract/radar_h5/. /out/
else
    cp -a /tmp/radar-extract/. /out/
fi
H5_COUNT=$(find /out -type f \( -name "*.H5" -o -name "*.h5" \) | wc -l)
DATA_SIZE=$(du -sh /out | cut -f1)
echo "Input directory now has $H5_COUNT H5 files ($DATA_SIZE)"
'

echo
echo "Cached zip preserved at: $CACHE_ZIP"
echo "The producer will inspect the files on its next discovery tick."
