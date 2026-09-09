# mapasmn

Meta-repositorio de Mapas SMN. Fija las revisiones de `tiles-processor`,
`data-service`, `alerts-service` y `visualizer`, genera su configuración desde
un único `.env` y puede levantarlos como un solo proyecto de Docker Compose.

La documentación funcional y técnica del sistema vive en `visualizer/docs` y
se publica dentro del visualizador. La guía detallada de este perfil está en
[Beta-1: un sistema completo y liviano](./visualizer/docs/tecnica/operacion/beta-1.md).

## Qué perfil elegir

| Perfil | Uso | Comando |
|---|---|---|
| **Beta-1** | Sistema completo en una VM de 8 GB, conectado a fuentes reales | `make beta-1` |
| Producción completa | Catálogo y concurrencia completos de `tiles-processor` | `make prod` |
| Desarrollo | Los cuatro entornos de desarrollo con recarga | `make up` |

**Beta-1 es el punto de entrada recomendado para una instalación nueva en una
sola VM.** Conserva los cuatro componentes y todos los flujos del sistema. La
reducción está en la cantidad de workers y en el catálogo de productos que
procesa, no en reemplazar datos reales por datos simulados.

## Requisitos

- Una VM Linux con 8 GB de RAM y espacio suficiente para los datos crudos y
  procesados.
- Docker Engine y Docker Compose 2.20 o posterior.
- Git, `make`, un shell POSIX y `envsubst` de GNU gettext.
- Acceso saliente a NOAA, ECMWF, NOMADS, IGN y la API del SMN.
- Feeds vivos de radar SINARAME, GLM y WRF-ARG4K, o un mecanismo que los copie
  al directorio de entrada del procesador.

En Debian o Ubuntu:

```sh
sudo apt-get install -y git make gettext-base
docker compose version
```

## Desplegar Beta-1

### 1. Clonar las revisiones fijadas

```sh
git clone --recurse-submodules git@github.com:fiuba-tp-g153-smn/mapasmn.git
cd mapasmn
```

Si el repositorio ya estaba clonado:

```sh
git submodule update --init --recursive
```

### 2. Crear y revisar la configuración

```sh
make setup
```

El comando crea `.env` la primera vez y genera los `.env` de los cuatro
submódulos. **Editar solamente el `.env` de la raíz**; los demás son artefactos
generados y se sobrescriben.

Antes de construir las imágenes, revisar como mínimo:

```dotenv
APP_ENV=production
DEV_PASSWORD=<una-clave-larga-y-aleatoria>

SMN_API_USERNAME=<usuario>
SMN_API_PASSWORD=<clave>
SMN_API_BASE_URL=<endpoint-asignado-por-el-SMN>

DATA_SERVICE_BASE_URL=https://data.example.org
ALERTS_SERVICE_BASE_URL=https://alerts.example.org
METRICS_SERVICE_BASE_URL=https://metrics.example.org
DOCS_URL=/docs-site
```

Las tres URL de servicios son las direcciones que abrirá **el navegador del
usuario**. No deben apuntar a `localhost` cuando el navegador y la VM son
máquinas distintas. En una red privada sin proxy pueden usar la IP o el nombre
DNS de la VM y los puertos `6006`, `6007` y `6020`.

Después de editar `.env`, ejecutar otra vez:

```sh
make setup
```

### 3. Conectar las fuentes vivas

Beta-1 descarga directamente GOES-19, ECMWF y GFS desde sus fuentes públicas.
Radar, GLM y WRF son feeds locales: el productor observa estos directorios del
host, montados como `/app/data` dentro de sus contenedores:

| Fuente | Directorio del host |
|---|---|
| GLM | `tiles-processor/data/glm_h5/` |
| Radar SINARAME | `tiles-processor/data/radar_h5/` |
| WRF-ARG4K | `tiles-processor/data/wrf_nc/` |

La integración esperada es que los procesos del organismo escriban allí cada
nuevo archivo con su nombre y marca temporal originales. Es preferible copiar a
un nombre temporal y renombrar al terminar, para que el productor nunca observe
un archivo parcial. No hace falta reiniciar contenedores: el productor descubre
nuevos ingresos cada cinco minutos.

El perfil habilita:

- GOES-19 bandas 13 y 9;
- GLM FED;
- seis productos de RMA1, RMA2 y RMA8;
- WRF Colmax y Ráfagas;
- precipitación ECMWF;
- presión a nivel del mar de GFS.

`data-simulator` existe para laboratorios sin feeds vivos. **No es parte del
despliegue Beta-1 previsto** y no debe interponerse cuando están disponibles las
fuentes reales.

### 4. Levantar el sistema

```sh
make beta-1
```

El proyecto inicia 12 contenedores:

| Componente | Contenedores |
|---|---:|
| `tiles-processor` | 6: broker, almacén, productor, worker normal, worker liviano y métricas |
| `data-service` | 3: Redis, API y sincronizador |
| `alerts-service` | 2: MySQL y aplicación |
| `visualizer` | 1: nginx con la aplicación y esta documentación |

La primera construcción tarda varios minutos. El primer arranque de
`alerts-service` también puede tardar hasta ocho minutos mientras prepara las
capas administrativas.

### 5. Verificar

Desde una máquina que tenga acceso a la VM:

```sh
curl -f http://<vm>:6006/health
curl -f http://<vm>:6006/sync/status
curl -f http://<vm>:6007/health
curl -f http://<vm>:6020/health
curl -f http://<vm>:6010/
```

El visualizador queda en `http://<vm>:6010` y la documentación compilada en
`http://<vm>:6010/docs-site/`. El panel de estado del visualizador es la
comprobación de extremo a extremo.

La ausencia inicial de una capa local no implica que el servicio esté roto:
primero comprobar que el feed esté dejando archivos nuevos en el directorio
correcto y luego esperar el siguiente ciclo de descubrimiento.

## Operación

```sh
make beta-1                 # construir y levantar en primer plano
make beta-1-down            # bajar; conserva los datos
docker compose -f compose.beta-1.yaml ps
docker compose -f compose.beta-1.yaml logs -f producer worker1 worker-light1
```

Para actualizar a las nuevas revisiones que haya fijado este repositorio:

```sh
git pull --ff-only
git submodule update --init --recursive
make beta-1
```

`make update` tiene otro propósito: mueve los submódulos a la punta de sus ramas
remotas para preparar una nueva revisión del meta-repositorio. No debe usarse en
una VM que necesite reproducir exactamente la versión fijada.

## Puertos

| Puerto | Servicio | Exposición recomendada |
|---:|---|---|
| `6010` | Visualizador y documentación | Usuarios |
| `6006` | API de datos | Usuarios, por proxy |
| `6007` | API de avisos | Usuarios autorizados, por proxy |
| `6020` | Métricas del procesador | Usuarios, por proxy |
| `9000` | API S3 de SeaweedFS | Sólo el host y los servicios |
| `3306` | MySQL | Sólo administración local |
| `5672` | RabbitMQ | Sólo servicios |
| `15672` | Administración de RabbitMQ | Sólo operación |
| `8888`, `9333`, `23646` | SeaweedFS interno/administración | Sólo operación local |

Las plantillas publican varios puertos en todas las interfaces. **Beta-1 puede
levantarse en una VM, pero no debe exponerse directamente a Internet.** Aplicar
firewall, TLS, proxy inverso y los controles de
[Endurecimiento](./visualizer/docs/tecnica/seguridad/endurecimiento.md) antes de
abrirlo a una red no confiable.

## Archivos que definen Beta-1

- `compose.beta-1.yaml`: une los cuatro componentes.
- `tiles-processor/docker-compose-beta-1.yaml`: topología liviana del procesador.
- `tiles-processor/docker-compose-beta-1.override.yaml`: monta la configuración
  congelada del perfil.
- `tiles-processor/settings-beta-1.json`: fuentes y productos habilitados.
- `.env`: única configuración local editable.
- `scripts/env-templates/`: traducción del `.env` raíz a cada submódulo.

Los submódulos son la fuente autoritativa del código de cada componente. Un
cambio de versión se publica actualizando explícitamente sus punteros en este
repositorio.

## Producción completa y desarrollo

`make prod` usa las plantillas de producción de los cuatro componentes y la
configuración completa de `tiles-processor`: dos workers normales y tres
livianos, 15 contenedores en total. Requiere más memoria que Beta-1.

`make up` inicia los cuatro stacks de desarrollo por separado, con recarga y
herramientas de desarrollo. No es un procedimiento de despliegue.

Los despliegues independientes y la entrega por Coolify siguen documentados en
[Despliegue y entrega continua](./visualizer/docs/tecnica/operacion/despliegue.md).
