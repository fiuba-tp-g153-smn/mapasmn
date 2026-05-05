#!/usr/bin/env sh
# Seed each submodule's .env from .env.example, replacing REPLACE_WITH_SECURE_PASSWORD
# with a fixed dev password. Idempotent: existing .env files are left untouched.

set -eu

DEV_PASSWORD="devpassword"
SERVICES="data-service tiles-processor visualizer alerts-service"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for service in $SERVICES; do
    example="$ROOT_DIR/$service/.env.example"
    target="$ROOT_DIR/$service/.env"

    if [ ! -f "$example" ]; then
        echo "skip $service: $example not found (submodule not initialized?)" >&2
        continue
    fi

    if [ -f "$target" ]; then
        echo "skip $service: .env already exists"
        continue
    fi

    cp "$example" "$target"
    sed -i "s/REPLACE_WITH_SECURE_PASSWORD/$DEV_PASSWORD/g" "$target"
    echo "wrote $service/.env"
done
