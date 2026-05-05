# mapasmn

Master repo that bundles all services for the mapasmn project as git submodules.

## What's in here

| Service | Stack | Dev port |
|---|---|---|
| [`data-service`](./data-service) | FastAPI | `6006` (HTTP) |
| [`alerts-service`](./alerts-service) | FastAPI + MySQL | `6007` (HTTP) |
| [`visualizer`](./visualizer) | Angular + nginx | `6010` (HTTP) |
| [`tiles-processor`](./tiles-processor) | Producer + workers, SeaweedFS, RabbitMQ | `9000` (S3), `5672` (AMQP), `15672` (RabbitMQ UI) |

## Quick start

```sh
git clone --recurse-submodules <this-repo-url>
cd mapasmn
make up
```

A non-recursive clone also works — `make up` runs `git submodule update --init --recursive` for you.

## What `make up` does

1. Initializes all git submodules.
2. Seeds each service's `.env` from its `.env.example` (only if `.env` doesn't already exist), replacing every `REPLACE_WITH_SECURE_PASSWORD` placeholder with `devpassword`.
3. Runs `make up` inside each service in parallel (each service brings up its own `docker compose -f docker-compose-dev.yaml`).

## Common targets

| Target | Action |
|---|---|
| `make up` | Setup + bring all services up (dev mode, hot reload) |
| `make down` | Stop all services |
| `make prod` | Setup + bring all services up in production mode |
| `make setup` | Init submodules and seed `.env` files. Idempotent — safe to re-run |
| `make data-service` | Bring up only the data-service |
| `make tiles-processor` | Bring up only the tiles-processor stack (SeaweedFS + RabbitMQ + workers) |
| `make alerts-service` | Bring up only the alerts-service |
| `make visualizer` | Bring up only the visualizer |

## Service URLs after `make up`

- Data service docs: <http://localhost:6006/docs>
- Alerts service docs: <http://localhost:6007/docs>
- Visualizer: <http://localhost:6010>
- RabbitMQ management UI: <http://localhost:15672> — user `tiles_processor`, password `devpassword`

## Customizing secrets

`.env` files are gitignored inside each submodule. After `make setup`, edit them in place if you want stronger passwords. Two notes:

- The shared S3 user passwords must stay in sync between `tiles-processor/.env` (where SeaweedFS provisions the users) and the consumer side: `data-service/.env` (`S3_TILES_DATA_SECRET_KEY`) and `alerts-service/.env` (`S3_SECRET_KEY`).
- `alerts-service/.env` ships with empty `S3_*` fields. The service still starts; layer backup/restore to S3 is simply skipped. Wire it to the SeaweedFS that `tiles-processor` stands up if you need it (`S3_ENDPOINT=host.docker.internal:9000`, `S3_ACCESS_KEY=alerts_service`, `S3_BUCKET_NAME=intersection-data`, `S3_SECURE=false`).
