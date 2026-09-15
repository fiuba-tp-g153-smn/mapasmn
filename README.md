# mapasmn

Este repositorio reúne los cuatro componentes de MapaSMN y fija la versión de
cada uno mediante submódulos de Git. Su función es permitir que una instalación
completa se configure desde un solo archivo y se ejecute como un proyecto de
Docker Compose. El código de aplicación continúa en los repositorios de
`tiles-processor`, `data-service`, `alerts-service` y `visualizer`.

El perfil recomendado para una primera instalación es Beta-1. Fue preparado
para una máquina virtual con 8 GB de memoria y mantiene el circuito completo del
sistema. Recibe datos meteorológicos reales, los procesa, los publica mediante
las API y permite generar avisos desde el visualizador. Para reducir el consumo,
utiliza dos workers y habilita una selección acotada de productos.

La documentación técnica completa se publica con el visualizador. La sección
[Beta-1, el sistema completo y liviano](./visualizer/docs/tecnica/operacion/beta-1.md)
explica el criterio con el que se armó este perfil.

## Contenidos

- [Requisitos](#requisitos)
- [Primera puesta en marcha de Beta-1](#primera-puesta-en-marcha-de-beta-1)
  - [Clonar la versión](#clonar-la-versión)
  - [Preparar la configuración](#preparar-la-configuración)
  - [Definir las entradas meteorológicas](#definir-las-entradas-meteorológicas)
  - [Iniciar el sistema](#iniciar-el-sistema)
- [Verificación](#verificación)
- [Cambio de nombres de septiembre de 2026](#cambio-de-nombres-de-septiembre-de-2026)
- [Coolify y las rutas de entrada](#coolify-y-las-rutas-de-entrada)
- [Operación habitual](#operación-habitual)
- [Datos históricos de radar](#datos-históricos-de-radar)
- [Puertos y exposición](#puertos-y-exposición)
- [Producción completa y desarrollo](#producción-completa-y-desarrollo)

## Requisitos

La máquina debe tener Docker Engine, Docker Compose 2.20 o posterior, Git,
`make`, un shell POSIX y `envsubst`, incluido en GNU gettext. También necesita
espacio para los datos crudos, el almacén de objetos, Redis y MySQL.

En Debian o Ubuntu, las herramientas auxiliares se instalan con:

```sh
sudo apt-get install -y git make gettext-base
docker compose version
```

## Primera puesta en marcha de Beta-1

### Clonar la versión

Cada commit de este repositorio apunta a una revisión determinada de los cuatro
componentes. Por este motivo, el clon debe incluir los submódulos.

```sh
git clone --recurse-submodules git@github.com:fiuba-tp-g153-smn/mapasmn.git
cd mapasmn
```

Si el repositorio ya había sido clonado sin ellos:

```sh
git submodule update --init --recursive
```

### Preparar la configuración

El siguiente comando crea el `.env` de la raíz y deriva los archivos que espera
cada componente:

```sh
make setup
```

El operador sólo debe editar el `.env` de la raíz. Los archivos `.env` de los
submódulos se generan de nuevo con cada ejecución de `make setup`.

Antes de iniciar el sistema se deben reemplazar la contraseña de desarrollo, las
credenciales del SMN y las direcciones que utilizará el navegador. Un ejemplo
mínimo es el siguiente:

```dotenv
APP_ENV=production
DEV_PASSWORD=<una-clave-larga-y-aleatoria>

SMN_API_BASE_URL=<endpoint-asignado-por-el-SMN>
SMN_API_USERNAME=<usuario>
SMN_API_PASSWORD=<clave>

DATA_SERVICE_BASE_URL=https://data.example.org
ALERTS_SERVICE_BASE_URL=https://alerts.example.org
METRICS_SERVICE_BASE_URL=https://metrics.example.org
DOCS_URL=/docs-site
```

Las tres direcciones de servicios quedan incorporadas al visualizador durante
la construcción. Deben ser accesibles desde la computadora del usuario. Si el
mapa se abre desde otra máquina, `localhost` apunta a esa máquina y no al
servidor donde corre MapaSMN.

### Definir las entradas meteorológicas

El `tiles-processor` admite cuatro modos de entrada. El modo `local` lee una
carpeta. El modo `s3` lee un bucket con la misma organización. ECMWF IFS y GFS
pueden utilizar además sus proveedores públicos mediante
`external-provider-opendata` y `external-provider-nomads`.

Beta-1 utiliza S3 público para GOES-19 ABI, carpetas locales para GOES-19 GLM,
radar SINARAME y WRF-ARG4K, y los proveedores públicos para ECMWF IFS y GFS.
Docker Compose exige una ruta de host para las seis fuentes, aunque el modo
elegido no lea esa carpeta. Las rutas deben ser absolutas y los directorios
deben existir.

```dotenv
GOES19_ABI_INPUT_DIR=/srv/mapasmn/input/goes19-abi
GOES19_GLM_INPUT_DIR=/srv/mapasmn/input/goes19-glm
RADAR_SINARAME_INPUT_DIR=/srv/mapasmn/input/radar-sinarame
WRF_ARG4K_INPUT_DIR=/srv/mapasmn/input/wrf-arg4k
ECMWF_IFS_INPUT_DIR=/srv/mapasmn/input/ecmwf-ifs
GFS_INPUT_DIR=/srv/mapasmn/input/gfs
```

Una forma de crear la estructura inicial es:

```sh
sudo mkdir -p /srv/mapasmn/input/goes19-abi
sudo mkdir -p /srv/mapasmn/input/goes19-glm
sudo mkdir -p /srv/mapasmn/input/radar-sinarame
sudo mkdir -p /srv/mapasmn/input/wrf-arg4k
sudo mkdir -p /srv/mapasmn/input/ecmwf-ifs
sudo mkdir -p /srv/mapasmn/input/gfs
```

Los procesos del SMN que reciben GLM, radar y WRF deben copiar cada archivo en
la carpeta correspondiente. El productor revisa las fuentes cada cinco minutos,
por lo que no es necesario reiniciar los contenedores cuando ingresa un archivo.
Conviene completar la copia con un nombre temporal y renombrarlo al final. De
esta forma, el productor no puede abrir un archivo incompleto.

Las carpetas físicas pueden conservar sus nombres anteriores durante una
actualización. Por ejemplo, la nueva variable `RADAR_SINARAME_INPUT_DIR` puede
apuntar a una carpeta existente llamada `radar_h5`. Lo que cambió es el nombre
con el que el procesador reconoce la fuente dentro del contenedor.

Una fuente configurada en modo `s3` puede usar credenciales propias. Cada par se
deja vacío para acceso anónimo o se completa en su totalidad:

```dotenv
GOES19_ABI_S3_ACCESS_KEY=
GOES19_ABI_S3_SECRET_KEY=
GOES19_GLM_S3_ACCESS_KEY=
GOES19_GLM_S3_SECRET_KEY=
RADAR_SINARAME_S3_ACCESS_KEY=
RADAR_SINARAME_S3_SECRET_KEY=
WRF_ARG4K_S3_ACCESS_KEY=
WRF_ARG4K_S3_SECRET_KEY=
ECMWF_IFS_S3_ACCESS_KEY=
ECMWF_IFS_S3_SECRET_KEY=
GFS_S3_ACCESS_KEY=
GFS_S3_SECRET_KEY=
```

Después de completar el `.env`, se deben regenerar las configuraciones:

```sh
make setup
```

### Iniciar el sistema

Beta-1 se inicia con:

```sh
make beta1
```

El comando construye las imágenes y levanta doce contenedores. El procesador
aporta RabbitMQ, SeaweedFS, el productor, un worker normal, un worker liviano y
la API de métricas. `data-service` aporta Redis, la API y el sincronizador.
`alerts-service` aporta MySQL y la aplicación. El último contenedor sirve el
visualizador junto con esta documentación.

El primer arranque demora varios minutos. `alerts-service` puede tardar hasta
ocho minutos mientras descarga y simplifica las capas administrativas.

## Verificación

Con los puertos del archivo de ejemplo, las comprobaciones iniciales son:

```sh
curl -f http://<vm>:6006/health
curl -f http://<vm>:6006/sync/status
curl -f http://<vm>:6007/health
curl -f http://<vm>:6020/health
curl -f http://<vm>:6010/
```

El visualizador queda disponible en `http://<vm>:6010` y la documentación en
`http://<vm>:6010/docs-site/`. Luego del arranque conviene revisar los registros
del productor:

```sh
docker compose -f compose.beta-1.yaml logs -f producer
```

Cada fuente informa su modo, el directorio interno y si encontró archivos. Un
tick sano que sólo publica ABI no demuestra que las entradas locales estén bien
montadas. GLM, radar y WRF deben aparecer en ese resumen cuando sus carpetas
contienen datos.

## Cambio de nombres de septiembre de 2026

La versión actual adoptó un mismo criterio para los identificadores, las rutas
HTTP y el almacenamiento. Los nombres distinguen la plataforma, el instrumento
y el producto. Esta distinción evita que `goes19` represente al mismo tiempo un
satélite y una familia de imágenes, y deja lugar para incorporar otros radares o
modelos sin volver a modificar los contratos existentes.

Algunos ejemplos del cambio son:

| Familia | Nombre anterior | Nombre actual |
|---|---|---|
| GOES-19 ABI | `band_13` | `goes19/abi/c13` |
| GOES-19 GLM | `glm_folder_fed` | `goes19/glm/fed` |
| Radar | `tiles/radar` | `tiles/radar/sinarame` |
| WRF | `tiles/wrf` | `tiles/wrf-arg4k` |
| ECMWF | `tiles/models/ecmwf` | `tiles/ecmwf-ifs` |
| GFS 500 hPa | `tiles/models/gfs/500hpa` | `tiles/gfs/geopotential-500hpa` |

La actualización es un corte coordinado. `tiles-processor` escribe las nuevas
rutas, `data-service` las lee y `visualizer` solicita las nuevas rutas HTTP. No
se deben desplegar revisiones incompatibles de estos componentes.

Los objetos que ya estaban almacenados no requieren migración ni borrado.
SeaweedFS conserva el vencimiento asignado en el momento de la escritura y los
elimina según la retención original. Como consecuencia visible, el historial de
animación queda vacío durante el cambio y vuelve a completarse con los productos
nuevos. GOES-19 necesita cerca de cuatro horas para reconstruir sus 24 capturas.

También cambiaron las variables de credenciales y los nombres internos de las
carpetas. Un despliegue anterior debe revisar scripts, tareas programadas y
montajes que todavía mencionen `GOES19_S3`, `GLM_FOLDER_S3`, `RADAR_S3`,
`WRF_S3`, `glm_h5`, `radar_h5` o `wrf_nc`.

## Coolify y las rutas de entrada

Docker Compose permite utilizar una variable como origen de un bind mount.
Coolify analiza ese campo antes de sustituir la variable y puede convertirlo en
un volumen administrado vacío. El despliegue de producción de `tiles-processor`
usa por este motivo rutas absolutas literales. Esas rutas pertenecen al servidor
actual y deben revisarse antes de reutilizar su Compose en otra máquina.

Beta-1 no utiliza ese archivo. Su Compose conserva las variables de entrada,
porque Docker Compose las sustituye correctamente y permite que cada instalación
elija dónde guarda los datos. La validación con `docker compose config` comprueba
la sintaxis, pero no reproduce el analizador de Coolify.

## Operación habitual

```sh
make beta1
make beta1-down
docker compose -f compose.beta-1.yaml ps
docker compose -f compose.beta-1.yaml logs -f producer worker1 worker-light1
```

`make beta1-down` elimina los contenedores y las redes del proyecto, pero
conserva los datos. `make down` detiene tanto la composición completa como
Beta-1.

Para instalar una nueva revisión fijada por este repositorio:

```sh
git pull --ff-only
git submodule update --init --recursive
make beta1
```

`make update` tiene un propósito diferente. Avanza los submódulos a la punta de
sus ramas remotas y se utiliza al preparar una nueva versión de `mapasmn`. Una
VM operativa debe respetar los commits fijados por el repositorio.

## Datos históricos de radar

El sistema está pensado para recibir fuentes vivas. Para una prueba sin acceso
al feed de radar se puede cargar un archivo ZIP en la ruta configurada por
`RADAR_SINARAME_INPUT_DIR`:

```sh
make fetch-radar URL=<url-de-google-drive>
```

El script acepta archivos con contenido en la raíz y archivos que todavía usen
los directorios `radar-sinarame` o `radar_h5`. El productor encontrará los H5 en
el siguiente ciclo. Esta herramienta no reemplaza al feed operativo.

Para preparar un archivo de prueba:

```sh
make pack-radar SOURCE=/ruta/al/directorio/radar-sinarame
```

`data-simulator` también puede reproducir muestras históricas de GLM, radar y
WRF. Es un proyecto opcional y no forma parte de esta composición.

## Puertos y exposición

| Puerto | Uso previsto |
|---:|---|
| `6010` | Visualizador y documentación |
| `6006` | API de datos |
| `6007` | API de avisos |
| `6020` | Métricas del procesador |
| `9000` | API S3 para los servicios |
| `3306` | Administración local de MySQL |
| `5672`, `15672` | RabbitMQ y su panel |
| `8888`, `9333`, `23646` | Servicios internos de SeaweedFS |

Las plantillas publican varios de estos puertos en todas las interfaces. Antes
de exponer la VM se deben cambiar las contraseñas de ejemplo, cerrar los puertos
internos, configurar el proxy inverso y habilitar TLS. La guía de
[endurecimiento](./visualizer/docs/tecnica/seguridad/endurecimiento.md) contiene
el detalle de estas tareas.

## Producción completa y desarrollo

`make prod` incluye los Compose de producción de los cuatro componentes. El
archivo de producción de `tiles-processor` contiene rutas literales del servidor
actual para evitar el problema de Coolify descrito antes. No debe utilizarse en
otra máquina sin revisar esos montajes.

`make up` inicia los cuatro entornos de desarrollo. Cada componente conserva su
propio Compose y sus herramientas de recarga. Este comando sirve para trabajar
sobre el código y no constituye un procedimiento de despliegue.
