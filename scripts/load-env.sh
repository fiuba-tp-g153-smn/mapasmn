# Sourced by setup-env.sh and the Makefile; ROOT_DIR is the repository root.
# Resolve configuration once for rendering and Compose interpolation.

set -a
. "$ROOT_DIR/.env.example"
. "$ROOT_DIR/.env"
set +a

# External databases are provisioned by the institution, never by this stack.
case "$MYSQL_BUNDLED_MODE" in
    true)
        export MYSQL_PASSWORD="$DEV_PASSWORD"
        ;;
    false)
        if [ -z "$MYSQL_HOST" ] || [ "$MYSQL_HOST" = mysql ]; then
            echo "MYSQL_BUNDLED_MODE=false requires MYSQL_HOST pointing to the external server" >&2
            exit 1
        fi
        : "${MYSQL_PASSWORD:?set MYSQL_PASSWORD for the external write connection}"
        : "${MYSQL_TAVISO_USER:?set MYSQL_TAVISO_USER for the external read connection}"
        : "${MYSQL_TAVISO_PASSWORD:?set MYSQL_TAVISO_PASSWORD for the external read connection}"
        if [ "$MANAGE_DB_SCHEMAS" != false ]; then
            echo "MYSQL_BUNDLED_MODE=false requires MANAGE_DB_SCHEMAS=false" >&2
            exit 1
        fi
        ;;
    *)
        echo "MYSQL_BUNDLED_MODE must be true or false" >&2
        exit 1
        ;;
esac

# Resolve defaults after both files so root overrides win.
export MYSQL_TAVISO_HOST="${MYSQL_TAVISO_HOST:-$MYSQL_HOST}"
export MYSQL_TAVISO_PORT="${MYSQL_TAVISO_PORT:-$MYSQL_PORT}"
export MYSQL_TAVISO_DATABASE="${MYSQL_TAVISO_DATABASE:-$MYSQL_DATABASE}"
export MYSQL_TAVISO_USER="${MYSQL_TAVISO_USER:-$MYSQL_READONLY_USER}"
export MYSQL_TAVISO_PASSWORD="${MYSQL_TAVISO_PASSWORD:-$DEV_PASSWORD}"

