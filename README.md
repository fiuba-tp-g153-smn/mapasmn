# mapasmn

Master repo that bundles all services for the mapasmn project as git submodules and orchestrates them as a single Docker Compose project.

## What's in here

| Service | Stack | Port |
|---|---|---|
| [`data-service`](./data-service) | FastAPI | `6006` |
| [`alerts-service`](./alerts-service) | FastAPI + MySQL | `6007` |
| [`visualizer`](./visualizer) | Angular + nginx | `6010` |
| [`tiles-processor`](./tiles-processor) | Producer + workers, SeaweedFS, RabbitMQ | `9000` (S3), `5672` (AMQP), `15672` (RabbitMQ UI) |

## Prerequisites

- Docker Compose CLI **≥ 2.20.0** (for the root `compose.yaml`'s `include:` directive).
- `envsubst` (GNU gettext) — already on most Linux distros; install via `gettext-base` (Debian/Ubuntu) or `gettext` (Fedora/Arch).

## Quick start

```sh
git clone --recurse-submodules <this-repo-url>
cd mapasmn
make prod
```

If you cloned without `--recurse-submodules`, run `make update` once first to fetch the submodules. `make prod` itself never touches them, so your local submodule HEADs are always preserved.

After the first `make prod`, plain `docker compose up` from the repo root is enough — `make` is just a convenience that also runs the one-time env setup.

## What `make prod` does

1. Materializes the root `.env` from `.env.example` (replacing `REPLACE_WITH_SECURE_PASSWORD` with `devpassword`) and renders each submodule's `.env` from `scripts/env-templates/<service>.env` via `envsubst`.
2. Runs `docker compose up --build` from the root, which uses `compose.yaml`'s `include:` to bring up every submodule's prod container as one project on a shared network.

`make prod` does **not** initialize or update submodules — use `make update` for that.

## Configuration

**Edit `.env` at the repo root only.** Submodule `.env` files are generated artifacts — running `make setup` overwrites them with values derived from the root `.env`.

If you change the root `.env` (e.g. to set stronger passwords), re-run `make setup` to regenerate the submodule `.env` files, then `docker compose up`.

## Common targets

| Target | Action |
|---|---|
| `make prod` | Setup envs + `docker compose up --build` from root (single-compose, all services together) |
| `make down` | Stop and remove containers (keeps volumes/data) |
| `make clean` | Stop and remove containers **and volumes** — full reset |
| `make setup` | (Re)generate `.env` files from the root `.env` |
| `make update` | Pull each submodule to the latest commit on its upstream branch (`git submodule update --init --recursive --remote`) |
| `make up` | Per-submodule **dev** stack (each service's `docker-compose-dev.yaml` with hot reload) |
| `make data-service` / `make alerts-service` / `make tiles-processor` / `make visualizer` | Bring up just one submodule in dev mode |

## Service URLs after `make prod`

- Data service docs: <http://localhost:6006/docs>
- Alerts service docs: <http://localhost:6007/docs>
- Visualizer: <http://localhost:6010>
- RabbitMQ management UI: <http://localhost:15672> — user `tiles_processor`, password `devpassword`
