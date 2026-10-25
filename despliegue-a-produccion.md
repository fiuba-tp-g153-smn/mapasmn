# Despliegue productivo

El perfil de producción ejecuta los cuatro componentes de MapaSMN con el catálogo completo de productos y cinco workers de procesamiento. La instalación se configura desde el `.env` de la raíz y se inicia con `make prod`, siguiendo el mismo esquema de trabajo que Beta-1.

## Contenidos

- [Requisitos](#requisitos)
- [1. Obtener el sistema](#1-obtener-el-sistema)
- [2. Preparar la configuración](#2-preparar-la-configuración)
  - [MySQL incluido](#mysql-incluido)
  - [MySQL del SMN](#mysql-del-smn)
- [3. Indicar dónde están los datos meteorológicos](#3-indicar-dónde-están-los-datos-meteorológicos)
  - [Rutas del despliegue original](#rutas-del-despliegue-original)
- [4. Iniciar el sistema](#4-iniciar-el-sistema)
- [5. Verificar la instalación](#5-verificar-la-instalación)
- [Operación habitual](#operación-habitual)
- [Respaldo y documentación técnica](#respaldo-y-documentación-técnica)

## Requisitos

El servidor necesita Linux, Docker Engine, Git, `make` y `envsubst`, incluido en GNU gettext.

Además, la instalación requiere:

- Al menos 8 cores y 24 GB de RAM para ejecutar todos los servicios con caché, además de almacenamiento suficiente para entradas, productos y bases de datos.
- Acceso a NOAA, ECMWF, NOMADS, IGN y la API del SMN. Los archivos de GLM, SINARAME, INTA y WRF deben estar disponibles según se describe en el paso 3.

En Debian o Ubuntu, las herramientas auxiliares se instalan con:

```sh
sudo apt-get install -y git make gettext-base
docker compose version
```

## 1. Obtener el sistema

```sh
git clone --recurse-submodules git@github.com:fiuba-tp-g153-smn/mapasmn.git
cd mapasmn
```

Los submódulos fijan las versiones de los cuatro componentes. Si el repositorio ya se había clonado sin ellos, se inicializan con `git submodule update --init --recursive`.

## 2. Preparar la configuración

```sh
make setup
```

Este comando crea el `.env` de la raíz y genera los archivos de cada componente. El operador edita únicamente el archivo de la raíz. La configuración mínima comprende las credenciales, las direcciones del navegador y las rutas de entrada:

```dotenv
APP_ENV=production
DEV_PASSWORD=<una-clave-larga-y-aleatoria>

SMN_API_BASE_URL=<endpoint-asignado-por-el-SMN>
SMN_API_USERNAME=<usuario>
SMN_API_PASSWORD=<clave>

DATA_SERVICE_BASE_URL=http://mapasmn.example.org:6006
ALERTS_SERVICE_BASE_URL=http://mapasmn.example.org:6007
METRICS_SERVICE_BASE_URL=http://mapasmn.example.org:6020
DOCS_URL=/docs-site

GOES19_GLM_INPUT_DIR=/srv/mapasmn/input/goes19-glm
RADAR_SINARAME_INPUT_DIR=/srv/mapasmn/input/radar-sinarame
RADAR_INTA_INPUT_DIR=/srv/mapasmn/input/radar-inta
WRF_ARG4K_INPUT_DIR=/srv/mapasmn/input/wrf-arg4k
```

`DEV_PASSWORD` conserva un nombre heredado, pero su función en producción es configurar la contraseña compartida de los servicios internos: las cuentas de SeaweedFS, RabbitMQ, Redis, el Pushgateway cuando se utiliza, la administración de estaciones y el MySQL incluido. Se reemplaza por una clave propia de la instalación. No corresponde a las credenciales de la API del SMN ni del MySQL externo, que utilizan sus variables específicas. Como se interpola en comandos y SQL, no admite espacios, comillas ni `$`.

Las direcciones de las API deben ser accesibles desde los puestos de los usuarios y se incorporan al visualizador durante la construcción. En el ejemplo, `mapasmn.example.org` se reemplaza por el nombre o la IP del servidor. `make prod` reconstruye las imágenes para aplicar sus cambios.

Con los puertos predeterminados, los servicios se acceden directamente desde el navegador mediante las siguientes direcciones:

| Servicio | Dirección |
|---|---|
| Visualizador y documentación | `http://<servidor>:6010` |
| API de datos | `http://<servidor>:6006` |
| API de avisos | `http://<servidor>:6007` |
| API de métricas del procesador | `http://<servidor>:6020` |

La instalación puede incorporar un proxy inverso y HTTPS según su infraestructura. `make prod` no requiere esos componentes.

### MySQL incluido

La opción predeterminada utiliza la instancia MySQL de la composición y conserva sus datos en `mysql_data`. No requiere configurar otra conexión:

```dotenv
MYSQL_BUNDLED_MODE=true
```

En este modo, la contraseña de MySQL sigue siendo `DEV_PASSWORD` y `MANAGE_DB_SCHEMAS=true` permite preparar el esquema local. Beta-1 conserva esta configuración predeterminada. Editar una contraseña en el `.env` no cambia las cuentas que ya existen en MySQL; su rotación se realiza sobre la base y sus consumidores.

### MySQL del SMN

Para utilizar el servidor del organismo, se selecciona el modo externo y se completan las conexiones de escritura y lectura con las credenciales asignadas:

```dotenv
MYSQL_BUNDLED_MODE=false
MYSQL_HOST=mysql.smn.example.org
MYSQL_PORT=3306
MYSQL_DATABASE=<base-de-avisos>
MYSQL_USER=<usuario-de-escritura>
MYSQL_PASSWORD='<clave-de-escritura>'
MYSQL_TAVISO_USER=<usuario-de-lectura>
MYSQL_TAVISO_PASSWORD='<clave-de-lectura>'
MANAGE_DB_SCHEMAS=false
```

Si MySQL se ejecuta en el mismo servidor, fuera de Docker, puede utilizarse `MYSQL_HOST=host.docker.internal`; la base debe admitir conexiones desde la red de los contenedores.

La lectura de `taviso` utiliza por defecto el mismo host, puerto y base. Si el organismo dispone otra ubicación, se completan `MYSQL_TAVISO_HOST`, `MYSQL_TAVISO_PORT` y `MYSQL_TAVISO_DATABASE`. Las cuentas requieren los permisos de operación correspondientes, sin DDL, y un esquema acordado con el administrador de la base.

En ambos casos se ejecuta `make prod`. El modo externo excluye el contenedor MySQL y su volumen del despliegue y no ejecuta migraciones sobre la base institucional. El cambio de instancia no traslada los datos existentes: se realiza con la instalación detenida, un respaldo y el procedimiento de transferencia acordado con el administrador de la base.

## 3. Indicar dónde están los datos meteorológicos

Para generar las capas del mapa, MapaSMN necesita acceder a los archivos meteorológicos originales. Con la configuración incluida, obtiene automáticamente GOES-19 ABI desde NOAA, ECMWF desde Open Data y GFS desde NOMADS.

Los datos de GLM, SINARAME, INTA y WRF deben estar disponibles en el servidor donde se instala el sistema. Los aporta el SMN mediante sus procesos de recepción o generación de datos. Las cuatro variables del `.env` indican en qué carpeta debe buscarlos MapaSMN:

| Fuente | Variable del `.env` | Archivos que debe contener la carpeta |
|---|---|---|
| Descargas eléctricas GLM | `GOES19_GLM_INPUT_DIR` | NetCDF pregrillados con nombres `CG_GLM-L2-GLMF-*.nc`. |
| Radares SINARAME | `RADAR_SINARAME_INPUT_DIR` | Volúmenes de radar en archivos `.H5` o `.h5`. |
| Radares INTA | `RADAR_INTA_INPUT_DIR` | Volúmenes Rainbow5 en archivos `.vol` o `.VOL`. |
| Modelo WRF-ARG4K | `WRF_ARG4K_INPUT_DIR` | Archivos `WRF_ARG4K.FCST_L0_FIELD2D.*.nc` y sus `FIELD3D` correspondientes para los productos que los requieren. |

Si esos archivos ya se reciben en carpetas del servidor, se utilizan sus rutas absolutas en el `.env`. Por ejemplo, si los datos SINARAME están en `/datos/radares/sinarame`, se configura:

```dotenv
RADAR_SINARAME_INPUT_DIR=/datos/radares/sinarame
```

Las rutas `/srv/mapasmn/input/...` del ejemplo son una propuesta de organización. Si se decide utilizarlas, se crean antes del arranque:

```sh
sudo mkdir -p /srv/mapasmn/input/goes19-glm
sudo mkdir -p /srv/mapasmn/input/radar-sinarame
sudo mkdir -p /srv/mapasmn/input/radar-inta
sudo mkdir -p /srv/mapasmn/input/wrf-arg4k
```

Crear las carpetas no descarga ni genera esos datos. El proceso que los recibe debe dejarlos en la ubicación elegida y mantenerlos actualizados. Los archivos se conservan con sus nombres originales y pueden estar directamente en la carpeta o en subcarpetas de un nivel. La copia debe finalizar antes de que el archivo quede disponible para su lectura.

Una vez iniciado, MapaSMN revisa las fuentes cada cinco minutos y procesa los archivos recientes que encuentra. Si una carpeta permanece vacía, las capas de esa fuente no tendrán datos. La recepción y el descubrimiento se comprueban en los registros del productor:

```sh
docker compose logs -f producer
```

Esta sección describe la entrada mediante carpetas. Si los datos del organismo están en buckets S3, el perfil debe configurarse para leerlos desde allí. Los formatos y las opciones de entrada se detallan en la [configuración del procesador](./tiles-processor/README.md#settings-configuration-settingsjson).

### Rutas del despliegue original

Durante el desarrollo y la validación, el equipo desplegó el sistema en un servidor virtual privado (VPS) administrado con Coolify. El archivo `tiles-processor/docker-compose.yaml` conserva rutas absolutas de ese servidor para localizar los datos meteorológicos de entrada.

`mapasmn` reutiliza ese archivo, pero `make prod` aplica `scripts/compose-production.yaml` para sustituir esas ubicaciones por las cuatro carpetas configuradas en el `.env` de la instalación. Por eso la documentación menciona el reemplazo de las rutas del VPS: el operador configura sus propias carpetas, sin reproducir la estructura del servidor original ni editar el Compose del componente.

## 4. Iniciar el sistema

```sh
make prod
```

El comando regenera la configuración, valida la composición, crea la red compartida y construye las imágenes. Primero inicia la infraestructura, las API y los workers; después habilita el productor y el visualizador. Los contenedores quedan ejecutándose en segundo plano: quince con MySQL incluido o catorce con MySQL externo.

Este orden permite que los workers completen su inicialización antes de recibir nuevos trabajos. La primera construcción y la preparación de las capas administrativas pueden demorar varios minutos. Si un servicio no alcanza su estado de salud, el comando informa el error. Su estado y sus registros se consultan con:

```sh
docker compose ps
docker compose logs --tail=100
```

`make prod` aplica la configuración de producción automáticamente. No requiere definir funciones de shell, editar rutas del VPS ni combinar archivos Compose manualmente. RabbitMQ, SeaweedFS y el MySQL incluido no publican puertos en el servidor. La conexión al MySQL externo utiliza la dirección configurada por el organismo.

## 5. Verificar la instalación

Desde el servidor, con los puertos predeterminados:

```sh
curl -f http://127.0.0.1:6006/health
curl -f http://127.0.0.1:6006/sync/status
curl -f http://127.0.0.1:6007/health
curl -f http://127.0.0.1:6020/api/summary
curl -f http://127.0.0.1:6020/api/live
curl -f http://127.0.0.1:6010/
curl -f http://127.0.0.1:6010/docs-site/
```

Desde un puesto de operación se abre `http://<servidor>:6010` y se comprueba:

1. La visualización y animación de productos recientes de cada fuente conectada.
2. La actualización de las estaciones meteorológicas y de las pestañas del panel de estado.
3. La intersección de un polígono y la generación de un aviso de ensayo, con sus imágenes y persistencia, antes de habilitar su integración al circuito oficial.

Las rutas `/health` indican que los procesos responden. La disponibilidad de datos se verifica con `/sync/status`, los trabajos terminados y las capas del mapa. `alerts-service` puede responder HTTP mientras recupera capas faltantes, por lo que la prueba de intersección forma parte de esta verificación.

## Operación habitual

```sh
docker compose ps
docker compose logs -f --tail=100 producer worker1 worker2 worker-light1 worker-light2 worker-light3
make down
```

`make down` detiene los servicios y conserva los datos. `make clean` elimina volúmenes y no se utiliza durante una actualización ni como procedimiento de mantenimiento habitual.

Para actualizar una instalación, primero se suspende el ingreso de nuevos avisos y se detiene el productor:

```sh
docker compose stop producer
```

Luego se espera que finalicen los trabajos activos de procesamiento y avisos. Las colas y unidades en curso se consultan en el panel de estado y en `/api/live`. Cada worker limpia el directorio temporal compartido al arrancar; por ese motivo, la actualización se realiza con todos los trabajos finalizados y los workers detenidos en conjunto.

Con el estado respaldado, la actualización continúa con:

```sh
make down
git pull --ff-only
git submodule update --init --recursive
make prod
```

El servidor conserva las revisiones fijadas por `mapasmn`; `make update` se reserva para preparar una nueva versión. La recuperación de una versión anterior también requiere comprobar la compatibilidad de MySQL y SQLite y conservar las imágenes correspondientes.

## Respaldo y documentación técnica

Los respaldos operativos incluyen MySQL, los datos e índice de SeaweedFS, las bases locales de los servicios y los GIF de avisos. Se almacenan fuera del servidor y se comprueba su restauración. La configuración de acceso, los recursos y el monitoreo se desarrollan en las guías de [endurecimiento](./visualizer/docs/tecnica/seguridad/endurecimiento.md), [dimensionamiento](./visualizer/docs/tecnica/operacion/capacidad.md) y [observabilidad](./visualizer/docs/tecnica/operacion/observabilidad.md).
