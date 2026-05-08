#!/usr/bin/env sh
# Materialize the root .env from .env.example (idempotent), then regenerate
# each submodule's .env from scripts/env-templates/<service>.env using envsubst.
# The root .env is the only file users edit; per-submodule .env files are
# generated artifacts and overwritten on every run.

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_PASSWORD_DEFAULT="devpassword"

# 1. Materialize root .env if missing.
if [ ! -f "$ROOT_DIR/.env" ]; then
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
    sed -i "s/REPLACE_WITH_SECURE_PASSWORD/$DEV_PASSWORD_DEFAULT/g" "$ROOT_DIR/.env"
    echo "wrote .env"
else
    echo "skip .env: already exists"
fi

# 2. Always regenerate per-submodule .env files from root .env via envsubst.
command -v envsubst >/dev/null || {
    echo "envsubst not found — install GNU gettext (apt: gettext-base, fedora/arch: gettext)" >&2
    exit 1
}

set -a
. "$ROOT_DIR/.env"
set +a

for service in data-service tiles-processor alerts-service visualizer; do
    tpl="$ROOT_DIR/scripts/env-templates/$service.env"
    out="$ROOT_DIR/$service/.env"
    if [ ! -f "$tpl" ]; then
        echo "skip $service: no template at $tpl" >&2
        continue
    fi
    if [ ! -d "$ROOT_DIR/$service" ]; then
        echo "skip $service: submodule directory missing (run git submodule update --init)" >&2
        continue
    fi
    envsubst < "$tpl" > "$out"
    echo "rendered $service/.env"
done
