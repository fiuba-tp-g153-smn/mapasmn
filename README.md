# mapasmn

Meta-repositorio que agrupa todos los servicios del proyecto mapasmn como submódulos de git y los orquesta como un único proyecto de Docker Compose.

## Tabla de contenidos

- [¿Qué es este repo?](#qué-es-este-repo)
- [Servicios en producción](#servicios-en-producción)
- [Servicios y puertos](#servicios-y-puertos)
- [Contenedores y puertos detallados](#contenedores-y-puertos-detallados)
  - [Resumen de puertos del host](#resumen-de-puertos-del-host)
  - [Detalle fino por submódulo](#detalle-fino-por-submódulo)
- [Prerrequisitos](#prerrequisitos)
  - [Instalación de `envsubst`](#instalación-de-envsubst)
- [Inicio rápido — con `make` (recomendado)](#inicio-rápido--con-make-recomendado)
- [Inicio rápido — sin `make` (sólo `docker compose`)](#inicio-rápido--sin-make-sólo-docker-compose)
- [Cómo funciona](#cómo-funciona)
- [Personalizar credenciales y puertos](#personalizar-credenciales-y-puertos)
- [URLs de los servicios después de levantar](#urls-de-los-servicios-después-de-levantar)
- [Comandos `make`](#comandos-make)
- [Variables de entorno](#variables-de-entorno)
  - [Compartidas](#compartidas)
  - [S3 / SeaweedFS (cross-service)](#s3--seaweedfs-cross-service)
  - [data-service](#data-service)
  - [alerts-service](#alerts-service)
  - [tiles-processor — SeaweedFS](#tiles-processor--seaweedfs)
  - [tiles-processor — RabbitMQ](#tiles-processor--rabbitmq)
  - [tiles-processor — workers](#tiles-processor--workers)
  - [visualizer](#visualizer)
- [Configuración avanzada por submódulo](#configuración-avanzada-por-submódulo)

## ¿Qué es este repo?

Este repositorio **no contiene código de aplicación propio**. Cada servicio vive en su propio repositorio de GitHub y se incorpora acá como un submódulo. La función del meta-repositorio es:

1. Levantar los cuatro servicios juntos con un solo `docker compose up`.
2. Centralizar la configuración de desarrollo en un único `.env` raíz.

## Servicios en producción

Estado en vivo de todos los servicios: <https://uptime.mapasmn.com/status/smn>

| Servicio | URL pública | Repositorio |
|---|---|---|
| Visualizer (mapa interactivo) | <https://mapasmn.com> | [github.com/fiuba-tp-g153-smn/visualizer](https://github.com/fiuba-tp-g153-smn/visualizer) |
| data-service | <https://data.mapasmn.com/docs> | [github.com/fiuba-tp-g153-smn/data-service](https://github.com/fiuba-tp-g153-smn/data-service) |
| alerts-service | <https://alerts.mapasmn.com/docs> | [github.com/fiuba-tp-g153-smn/alerts-service](https://github.com/fiuba-tp-g153-smn/alerts-service) |
| tiles-processor | *(sin endpoint público — pipeline de procesamiento)* | [github.com/fiuba-tp-g153-smn/tiles-processor](https://github.com/fiuba-tp-g153-smn/tiles-processor) |

## Servicios y puertos

| Servicio | Stack | Puertos |
|---|---|---|
| [`data-service`](./data-service) | FastAPI + Redis | `6006` (API), `6379` (Redis, interno) |
| [`alerts-service`](./alerts-service) | FastAPI + MySQL | `6007` (API), `3306` (MySQL) |
| [`visualizer`](./visualizer) | Angular + nginx | `6010` (frontend), `6011` (docs) |
| [`tiles-processor`](./tiles-processor) | Producer + workers, SeaweedFS, RabbitMQ | `9000` (S3), `5672` (AMQP), `15672` (RabbitMQ UI) |

## Contenedores y puertos detallados

`make prod` (o `docker compose up`) levanta **11 contenedores** distribuidos en los cuatro submódulos. Acá va primero el resumen plano de puertos expuestos al host, y después el drilldown por submódulo con cada contenedor y sus puertos internos.

### Resumen de puertos del host

| Puerto host | Contenedor | Servicio |
|---|---|---|
| `3306` | `alerts-mysql` | MySQL |
| `5672` | `tiles-processor-rabbitmq` | RabbitMQ AMQP |
| `6006` | `data-service-container` | data-service API |
| `6007` | `alerts-service-container` | alerts-service API |
| `6010` | `visualizer-container` | Frontend |
| `6011` | `docs-service-container` | Docs |
| `8888` | `tiles-processor-seaweedfs` | SeaweedFS Filer |
| `9000` | `tiles-processor-seaweedfs` | SeaweedFS S3 API |
| `9333` | `tiles-processor-seaweedfs` | SeaweedFS Master |
| `15672` | `tiles-processor-rabbitmq` | RabbitMQ Management UI |
| `23646` | `tiles-processor-seaweedfs` | SeaweedFS Admin |

Si alguno de estos puertos colisiona con algo que ya tenés en el host, cambialo en el `.env` raíz: `${RABBITMQ_PORT}`, `${RABBITMQ_MGMT_PORT}`, `${S3_TILES_DATA_PORT}`, los `*_APP_HOST_PORT` y `${DOCS_HOST_PORT}` son configurables. Los puertos `3306`, `8888`, `9333` y `23646` están hardcodeados en los compose de los submódulos.

### Detalle fino por submódulo

#### tiles-processor (4 contenedores)

**`tiles-processor-rabbitmq`** — imagen `rabbitmq:4.2.4-management`

| Host | → Contenedor | Descripción |
|---|---|---|
| `${RABBITMQ_PORT}` (`5672`) | `5672` | Protocolo AMQP — los workers/producer se conectan acá |
| `${RABBITMQ_MGMT_PORT}` (`15672`) | `15672` | UI web de management (login: `tiles_processor` / `devpassword`) |

**`tiles-processor-seaweedfs`** — imagen `chrislusf/seaweedfs:4.20`

| Host | → Contenedor | Descripción |
|---|---|---|
| `${S3_TILES_DATA_PORT}` (`9000`) | `8333` | API S3 — lo consumen `data-service` y `alerts-service` |
| `8888` | `8888` | Filer (TTL por archivo, navegación HTTP) |
| `9333` | `9333` | Master (cluster status, healthcheck) |
| `23646` | `23646` | UI de administración de SeaweedFS |

**`tiles-processor-producer`** — imagen local `tiles-processor` (build de `tiles-processor/Dockerfile`)

| Host | → Contenedor | Descripción |
|---|---|---|
| *(sin puerto en el host)* | `8080` | Endpoint `/health` interno (lo usa el healthcheck del contenedor) |

Job programado (cron + APScheduler) que descubre imágenes nuevas en NOAA S3 y publica trabajos a RabbitMQ.

**`tiles-processor-worker1`** y **`tiles-processor-worker2`** — imagen local `tiles-processor` (misma que producer, distinto comando)

| Host | → Contenedor | Descripción |
|---|---|---|
| *(sin puerto en el host)* | `8080` | Endpoint `/health` interno |

Consumen unidades de trabajo de RabbitMQ (`prefetch=1`, ack manual) y procesan tiles. La cantidad de workers está fija en 2 en este compose; se puede regenerar con [`tiles-processor/scripts/generate-compose.sh`](./tiles-processor/scripts/generate-compose.sh).

#### data-service (2 contenedores)

**`data-service-redis-dev`** — imagen `redis:8.6-alpine`

| Host | → Contenedor | Descripción |
|---|---|---|
| *(sin puerto en el host)* | `6379` | Redis — sólo accesible vía la red Compose como `redis:6379` |

**`data-service-container`** — imagen local `data-service`

| Host | → Contenedor | Descripción |
|---|---|---|
| `${APP_HOST_PORT}` (`6006`, controlado por `DATA_SERVICE_APP_HOST_PORT`) | `8080` | API FastAPI (docs en `/docs`) |

#### alerts-service (2 contenedores)

**`alerts-mysql`** — imagen `mysql:8.4`

| Host | → Contenedor | Descripción |
|---|---|---|
| `3306` | `3306` | MySQL — accesible desde el host (cliente externo) y desde la red Compose como `mysql:3306` |

**`alerts-service-container`** — imagen local `alerts-service`

| Host | → Contenedor | Descripción |
|---|---|---|
| `${APP_HOST_PORT}` (`6007`, controlado por `ALERTS_SERVICE_APP_HOST_PORT`) | `8080` | API FastAPI (docs en `/docs`) |

#### visualizer (2 contenedores)

**`docs-service-container`** — imagen local `mapasmn-docs-service` (build de `visualizer/docs-service/Dockerfile`)

| Host | → Contenedor | Descripción |
|---|---|---|
| `${DOCS_HOST_PORT}` (`6011`) | `80` | Sitio Docusaurus servido por nginx |

**`visualizer-container`** — imagen local `visualizer`

| Host | → Contenedor | Descripción |
|---|---|---|
| `${APP_HOST_PORT}` (`6010`, controlado por `VISUALIZER_APP_HOST_PORT`) | `80` | Frontend Angular servido por nginx |

## Prerrequisitos

| Dependencia | Versión mínima | Para qué se usa |
|---|---|---|
| Docker Engine | 20.10+ | Construir y correr los contenedores |
| Docker Compose CLI | **2.20.0** | Necesario para la directiva `include:` en `compose.yaml` |
| Git | 2.x | Clonar el repo y manejar submódulos |
| `envsubst` (GNU gettext) | cualquiera | Renderizar los `.env` de cada submódulo desde plantillas |
| Shell POSIX (`sh`/`bash`/`zsh`) | — | Ejecutar `scripts/setup-env.sh` |
| `make` *(opcional)* | cualquiera | Sólo si querés usar los targets del `Makefile` |

### Instalación de `envsubst`

- **Debian/Ubuntu**: `sudo apt-get install -y gettext-base`
- **Fedora/RHEL**: `sudo dnf install -y gettext`
- **Arch**: `sudo pacman -S gettext`
- **macOS**: `brew install gettext` (puede requerir `brew link --force gettext`)

Para verificar la versión de Docker Compose:

```sh
docker compose version
```

## Inicio rápido — con `make` (recomendado)

```sh
git clone --recurse-submodules git@github.com:fiuba-tp-g153-smn/mapasmn.git
cd mapasmn
make prod
```

Si clonaste sin `--recurse-submodules`, ejecutá `make update` antes para traer los submódulos. `make prod` no toca los punteros de submódulos, así que tu HEAD local nunca se pisa.

Después del primer `make prod`, ejecutar `docker compose up` desde la raíz alcanza — `make` es sólo una conveniencia que además regenera los `.env`.

## Inicio rápido — sin `make` (sólo `docker compose`)

Equivalente exacto a `make prod`, paso a paso:

```sh
# 1. Clonar el repo con submódulos
git clone --recurse-submodules git@github.com:fiuba-tp-g153-smn/mapasmn.git
cd mapasmn

# (Si ya clonaste sin submódulos, traerlos ahora:)
# git submodule update --init --recursive

# 2. Generar el .env raíz y los .env de cada submódulo
./scripts/setup-env.sh

# 3. Crear la red externa que data-service espera (idempotente)
docker network inspect data_service_network >/dev/null 2>&1 \
    || docker network create data_service_network

# 4. Levantar todo
docker compose up --build
```

Equivalentes sin `make` para el resto de las operaciones:

| Operación | Con `make` | Sin `make` |
|---|---|---|
| Levantar | `make prod` | Pasos 1–4 de arriba |
| Bajar (preserva volúmenes) | `make down` | `docker compose down --remove-orphans` |
| Reset total (borra volúmenes) | `make clean` | `docker compose down --remove-orphans --volumes && docker network rm data_service_network` |
| Actualizar submódulos | `make update` | `git submodule update --init --recursive --remote` |
| Regenerar `.env` | `make setup` | `./scripts/setup-env.sh` |

## Cómo funciona

El meta-repo se apoya en dos ideas para no tener que modificar los submódulos:

1. **Un único proyecto Compose vía `include:`.** El `compose.yaml` de la raíz es básicamente una lista de `include:` apuntando al `docker-compose.yaml` de cada submódulo. Compose ≥ 2.20 los unifica en un solo proyecto (`mapasmn`, derivado del nombre del directorio): red compartida, namespace de volúmenes común, ciclo de vida `up`/`down` único. **Los compose de los submódulos nunca se editan.**

2. **Un único `.env` raíz vía plantillas con fan-out.** Los compose de los submódulos referencian variables con nombres en conflicto (por ejemplo, `APP_HOST_PORT` vale 6006/6007/6010 en tres servicios distintos). Para mantener una única fuente de verdad en la raíz **sin** modificar los submódulos:
   - El `.env.example` raíz nombra las variables conflictivas con prefijo (`DATA_SERVICE_APP_HOST_PORT`, `ALERTS_SERVICE_APP_HOST_PORT`, etc.).
   - `scripts/env-templates/<servicio>.env` mapea cada variable raíz al nombre que el submódulo espera.
   - `scripts/setup-env.sh` copia `.env.example` → `.env` (reemplazando `REPLACE_WITH_SECURE_PASSWORD` por `devpassword`) y después corre `envsubst` sobre cada plantilla, escribiendo el `.env` de cada submódulo.

> **Nota:** los `.env` que aparecen dentro de cada submódulo son **artefactos generados**. No los edites a mano — se sobrescriben en cada `make setup` / `./scripts/setup-env.sh`. La única fuente de verdad es el `.env` raíz.

## Personalizar credenciales y puertos

**Regla única**: editá `.env` en la raíz, después regenerá los `.env` de los submódulos:

```sh
# con make
make setup

# sin make
./scripts/setup-env.sh
```

Y luego volvé a levantar (`make prod` o `docker compose up --build`).

> Los `.env` dentro de cada submódulo son archivos generados — **no los edites a mano**, se sobrescriben.

## URLs de los servicios después de levantar

- Docs de data-service: <http://localhost:6006/docs>
- Docs de alerts-service: <http://localhost:6007/docs>
- Visualizer: <http://localhost:6010>
- UI de management de RabbitMQ: <http://localhost:15672> — usuario `tiles_processor`, contraseña `devpassword`

## Comandos `make`

| Target | Descripción |
|---|---|
| `make prod` | Genera los `.env`, crea la red `data_service_network` si falta, y corre `docker compose up --build` desde la raíz |
| `make down` | Para y elimina los contenedores; **preserva volúmenes y datos** |
| `make clean` | Para y elimina contenedores **y volúmenes** — reset total |
| `make setup` | (Re)genera los `.env` desde el `.env` raíz |
| `make update` | Trae cada submódulo al último commit de su rama upstream (`git submodule update --init --recursive --remote`) |
| `make up` | Stack de **dev** por submódulo (cada uno corre su `docker-compose-dev.yaml` con hot reload) |
| `make data-service` / `make alerts-service` / `make tiles-processor` / `make visualizer` | Levanta un solo submódulo en modo dev |

## Variables de entorno

Todas las variables están definidas en [`.env.example`](./.env.example). El usuario edita **únicamente** ese archivo (o su copia generada `.env`); los `.env` de cada submódulo se rederivan automáticamente.

### Compartidas

| Variable | Default | Descripción |
|---|---|---|
| `APP_ENV` | `development` | Entorno de la app. `production` activa el formateo de logs estilo NewRelic en data-service y alerts-service |
| `LOG_LEVEL` | `INFO` | Nivel de logging Python (`DEBUG` / `INFO` / `WARNING` / `ERROR`) |
| `DEV_PASSWORD` | `REPLACE_WITH_SECURE_PASSWORD` (sustituido por `devpassword` al correr `setup-env.sh`) | Contraseña única usada en TODOS los servicios donde haga falta una credencial. Cambiar acá la propaga a SeaweedFS, MySQL, RabbitMQ, etc. |

### S3 / SeaweedFS (cross-service)

SeaweedFS lo levanta `tiles-processor` y lo consumen `data-service` y `alerts-service`. Los usuarios se aprovisionan al primer arranque de SeaweedFS.

| Variable | Default | Descripción |
|---|---|---|
| `S3_TILES_DATA_PORT` | `9000` | Puerto en el host donde SeaweedFS expone su API S3 |
| `S3_TILES_DATA_BUCKET_NAME` | `tiles-data` | Bucket donde se guardan los tiles satelitales / radar / ECMWF |
| `S3_ROOT_USER` | `root_admin` | Usuario administrador interno de SeaweedFS |
| `S3_TILES_DATA_TILES_PROCESSOR_USER` | `tiles_processor` | Usuario S3 para tiles-processor (escribe tiles) |
| `S3_TILES_DATA_DATA_SERVICE_USER` | `data_service` | Usuario S3 para data-service (lee tiles) |
| `S3_INTERSECTION_DATA_BUCKET_NAME` | `intersection-data` | Bucket de capas geojson para alerts-service |
| `S3_INTERSECTION_DATA_ALERTS_SERVICE_USER` | `alerts_service` | Usuario S3 para alerts-service |
| `S3_BASEMAP_BUCKET_NAME` | `basemap-tiles` | Bucket de tiles de mapa base (cacheados por data-service) |

### data-service

| Variable | Default | Descripción |
|---|---|---|
| `DATA_SERVICE_APP_HOST_PORT` | `6006` | Puerto en el host donde se expone la API |
| `DATA_SERVICE_WEB_CONCURRENCY` | `3` | Cantidad de workers de Uvicorn |
| `DATA_SERVICE_SYNC_INTERVAL_SECONDS` | `60` | Intervalo (segundos) del background sync que copia tiles desde S3 al disco local |
| `REDIS_URL` | `redis://redis:6379/0` | URL de conexión al Redis interno |

### alerts-service

| Variable | Default | Descripción |
|---|---|---|
| `ALERTS_SERVICE_APP_HOST_PORT` | `6007` | Puerto en el host donde se expone la API |
| `MYSQL_DATABASE` | `aviso_gempak` | Nombre de la base de datos MySQL |
| `MYSQL_HOST` | `mysql` | Hostname del contenedor MySQL (resuelto en la red Compose) |
| `MYSQL_PORT` | `3306` | Puerto MySQL |
| `MYSQL_ROOT_HOST` | `localhost` | Host desde el cual el usuario `root` de MySQL puede conectar |
| `MYSQL_USER` | `alerts_service` | Usuario de aplicación con permisos completos sobre la DB |
| `MYSQL_READONLY_USER` | `avisos` | Usuario de sólo-lectura para consultas externas |
| `MYSQL_READONLY_MAX_CONNECTIONS` | `50` | Límite de conexiones simultáneas para el usuario read-only |
| `MYSQL_READONLY_MAX_CONNECTIONS_PER_HOUR` | `10000` | Límite de conexiones por hora para el usuario read-only |

### tiles-processor — SeaweedFS

| Variable | Default | Descripción |
|---|---|---|
| `SEAWEEDFS_FILER_ENDPOINT` | `seaweedfs:8888` | Endpoint del filer (habilita TTL por tile) |
| `SEAWEEDFS_TILE_TTL` | `6h` | TTL para tiles satelitales |
| `SEAWEEDFS_RADAR_TILE_TTL` | `30d` | TTL para tiles de radar |
| `SEAWEEDFS_METRICS_ADDRESS` | *(vacío)* | Dirección del Prometheus Push Gateway (`<host>:<puerto>`). Vacío = métricas deshabilitadas |
| `PROMETHEUS_PUSHGATEWAY_HTTP_PROTO` | `http` | `http` o `https` para el push gateway |
| `PROMETHEUS_PUSHGATEWAY_USER` | `push_user` | Usuario de basic auth para el push gateway |

### tiles-processor — RabbitMQ

| Variable | Default | Descripción |
|---|---|---|
| `RABBITMQ_PORT` | `5672` | Puerto AMQP |
| `RABBITMQ_MGMT_PORT` | `15672` | Puerto de la UI de management |
| `RABBITMQ_USER` | `tiles_processor` | Usuario por defecto de RabbitMQ |
| `RABBITMQ_QUEUE` | `tiles_work_queue` | Cola principal de unidades de trabajo |
| `RABBITMQ_DLQ` | `tiles_dead_letter_queue` | Cola de mensajes rechazados |
| `RABBITMQ_DLX` | `tiles_dlx` | Exchange de mensajes muertos |

### tiles-processor — workers

| Variable | Default | Descripción |
|---|---|---|
| `JOB_TTL_MINUTES` | `20` | Tiempo máximo (minutos) que un job puede vivir antes de ser descartado |
| `GDAL_CACHEMAX` | `128` | Caché máximo de GDAL en MB |
| `CPL_VSIL_CURL_CACHE_SIZE` | `16777216` | Caché VSI/CURL de GDAL en bytes (16 MB) |

### visualizer

| Variable | Default | Descripción |
|---|---|---|
| `VISUALIZER_APP_HOST_PORT` | `6010` | Puerto en el host donde se sirve el frontend |
| `DOCS_HOST_PORT` | `6011` | Puerto en el host donde se sirven los docs (Docusaurus) |
| `DOCS_URL` | `http://localhost:6011` | URL pública del sitio de docs |
| `DATA_SERVICE_BASE_URL` | `http://localhost:6006` | URL base de data-service vista desde el navegador |
| `ALERTS_SERVICE_BASE_URL` | `http://localhost:6007` | URL base de alerts-service vista desde el navegador |
| `TILE_FORMAT` | `webp` | Formato de tiles que pide el visualizer (`webp` o `png`) |

## Configuración avanzada por submódulo

El `.env` raíz expone los parámetros que necesitás cambiar para correr el stack en local. Cada submódulo además tiene **su propia configuración interna** que **no** se surfacea acá: tunables de runtime, modos de sincronización, ventanas de cache, cron de tareas, etc.

| Submódulo | Configuración adicional | Documentación |
|---|---|---|
| [`data-service`](./data-service) | `data-service/settings.json` (`sync_mode`, `basemap_sync_mode`, `basemap_*`, `tile_ttl`, `s3_max_concurrent_downloads`, etc.) | [`data-service/README.md`](./data-service/README.md), [`data-service/CLAUDE.md`](./data-service/CLAUDE.md) |
| [`alerts-service`](./alerts-service) | `alerts-service/settings.json` (`layer_update_cron`, `simplify_tolerance`), `alerts-service/.env.example` (URLs WFS de IGN) | [`alerts-service/README.md`](./alerts-service/README.md), [`alerts-service/CLAUDE.md`](./alerts-service/CLAUDE.md) |
| [`tiles-processor`](./tiles-processor) | `tiles-processor/settings.json` (cantidad de workers, intervalo del producer, geographic bounds) | [`tiles-processor/README.md`](./tiles-processor/README.md), [`tiles-processor/CLAUDE.md`](./tiles-processor/CLAUDE.md) |
| [`visualizer`](./visualizer) | Configuración de Angular en `visualizer/src/environments/`, definición de capas en `visualizer/src/app/config/layers/` | [`visualizer/README.md`](./visualizer/README.md), [`visualizer/CLAUDE.md`](./visualizer/CLAUDE.md) |

Para detalles de cada submódulo, leé el `README.md` y el `CLAUDE.md` que viven dentro suyo.
