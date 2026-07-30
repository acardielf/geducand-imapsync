# geducand-imapsync

Sincronización periódica y unidireccional de correo IMAP desde el buzón corporativo
de la Junta de Andalucía hacia una cuenta de Gmail de `g.educaand.es`, ejecutada en
un contenedor Docker que corre de forma continua.

## 📑 Índice

- 🚀 [Inicio rápido](#-inicio-rápido)
- 📬 [Qué hace](#-qué-hace)
- 📂 [Estructura](#-estructura)
- 🔧 [Configuración](#-configuración)
  - [Obligatorias](#obligatorias)
  - [Conexión](#conexión)
  - [Sincronización](#sincronización)
  - [Logs y tolerancia a fallos](#logs-y-tolerancia-a-fallos)
- 🔐 [Secretos](#-secretos)
  - [Cómo generar `password_geducaand`](#cómo-generar-password_geducaand)
- 🧰 [Uso](#-uso)
  - [Comandos](#comandos)
  - [`make test`](#make-test)
  - [Sin `make`](#sin-make)
- 📄 [Logs](#-logs)
  - [Rotación](#rotación)
- 🚨 [Tolerancia a fallos](#-tolerancia-a-fallos)
- 📌 [Pendiente](#-pendiente)

## 🚀 Inicio rápido

Necesitas **Docker** (con Compose v2), **make** y **git**.

```bash
git clone https://github.com/acardielf/geducand-imapsync.git
cd geducand-imapsync
make install
nano .env
make test
make up
```

1. `make install` crea `.env` y los dos ficheros de contraseña.
2. En `.env` sólo hace falta poner `SOURCE_USER` y `DEST_USER`; el resto de valores
   traen defaults razonables.
3. `make test` ejecuta un ciclo en simulación: no toca ningún buzón.
4. `make up` arranca en segundo plano.

Además de editar `.env`, escribe las dos contraseñas:

```bash
printf '%s' 'CONTRASEÑA_JUNTA' > password_corporativo_junta
printf '%s' 'APP_PASSWORD_GOOGLE' > password_geducaand
```

🔑 La segunda **no** es la contraseña normal de Google, sino una App Password de 16
caracteres: cómo obtenerla está en [Cómo generar `password_geducaand`](#cómo-generar-password_geducaand).

A partir de ahí, `make logs` para ver qué está haciendo y `make down` para pararlo.

> ⚠️ Por defecto la sincronización **mueve** el correo: borra en origen lo que ya ha
> transferido. Ejecuta siempre `make test` antes de `make up` para ver qué haría, y
> usa `DELETE_SOURCE=false` si prefieres copiar en vez de mover.

## 📬 Qué hace

Un contenedor Debian con [imapsync](https://imapsync.lamiral.info/) ejecuta un bucle
infinito que, cada 10 minutos, realiza **dos pasadas** sobre el `INBOX` de origen:

| Pasada | Filtro IMAP | Destino |
|---|---|---|
| 1 — Correo normal | `NOT SUBJECT "Publicidad"` | `INBOX` de Gmail |
| 2 — Publicidad | `SUBJECT "Publicidad"` | `[Gmail]/Spam` |

Características del sincronizado (con los valores por defecto de `sync.sh`):

- **Sólo los últimos 7 días** (`MAX_AGE`).
- **Movimiento, no copia**: `DELETE_SOURCE=true` borra en origen los mensajes ya
  transferidos.
- **Modo Gmail** (`DEST_IS_GMAIL`) y conservación de fechas internas.
- Deduplicación por cabecera `Message-Id`.
- Sólo se procesa la carpeta `INBOX`; el resto se ignora.

Tanto el intervalo como los filtros y las carpetas son configurables: ver
[Configuración](#-configuración).

## 📂 Estructura

```
.
├── Makefile            # Atajos de gestión (make help)
├── Dockerfile          # Imagen Debian bullseye + dependencias Perl + imapsync oficial
├── docker-compose.yml  # Servicio, volumen de logs y secretos
├── .env.example        # Plantilla de configuración (copiar a .env)
├── sync.sh             # Bucle de sincronización (copiado a /usr/local/bin en la imagen)
└── logs/               # Salida montada desde el contenedor (ignorada por git)
```

La imagen no instala imapsync desde `apt`, sino que descarga el script original del
autor en `/usr/local/bin/imapsync`; las dependencias Perl sí vienen de los paquetes
Debian.

## 🔧 Configuración

Todo se configura por **variables de entorno**, con valores por defecto recomendados
en `sync.sh`. `make install` copia la plantilla por ti; a mano sería:

```bash
cp .env.example .env
```

`.env` está excluido en `.gitignore`; `.env.example` sí se versiona y documenta cada
variable.

### Obligatorias

Sin estas dos el contenedor se detiene al arrancar con un mensaje explícito:

| Variable | Descripción |
|---|---|
| `SOURCE_USER` | Dirección completa del buzón de origen |
| `DEST_USER` | Dirección completa del buzón de destino |

### Conexión

| Variable | Por defecto | Descripción |
|---|---|---|
| `SOURCE_HOST` | `imap.juntadeandalucia.es` | Servidor IMAP de origen |
| `SOURCE_PORT` | `993` | Puerto de origen (siempre SSL) |
| `DEST_HOST` | `imap.gmail.com` | Servidor IMAP de destino |
| `DEST_PORT` | `993` | Puerto de destino (siempre SSL) |
| `DEST_IS_GMAIL` | `true` | Activa `--gmail2`; ponlo a `false` si el destino no es Gmail |
| `SOURCE_PASSFILE` | `/run/secrets/password_corporativo_junta` | Ruta al secreto de origen |
| `DEST_PASSFILE` | `/run/secrets/password_geducaand` | Ruta al secreto de destino |

### Sincronización

| Variable | Por defecto | Descripción |
|---|---|---|
| `SYNC_FOLDER` | `INBOX` | Carpeta a sincronizar |
| `MAX_AGE` | `7` | Sólo correo de los últimos N días |
| `SLEEP_INTERVAL` | `600` | Segundos entre ciclos (mínimo 60) |
| `DELETE_SOURCE` | `true` | `true` mueve (borra en origen); `false` copia |
| `DRY_RUN` | `false` | `true` simula sin escribir ni borrar nada |
| `SPAM_SUBJECT` | `Publicidad` | Asunto que se desvía a `SPAM_FOLDER`; **vacío desactiva la segunda pasada** |
| `SPAM_FOLDER` | `[Gmail]/Spam` | Carpeta destino de la publicidad |

### Logs y tolerancia a fallos

| Variable | Por defecto | Descripción |
|---|---|---|
| `LOG_DIR` | `/var/log/imapsync` | Directorio de logs dentro del contenedor |
| `LOG_MAX_BYTES` | `104857600` (100 MB) | Tamaño a partir del cual se rota |
| `LOG_KEEP` | `3` | Comprimidos que se conservan |
| `PASS_TIMEOUT` | `480` | Segundos máximos por pasada |
| `PASS_KILL_AFTER` | `30` | Margen antes del `SIGKILL` |
| `TZ` | `Europe/Madrid` | Zona horaria del contenedor |

## 🔐 Secretos

Las contraseñas no van en `.env`: se pasan como *Docker secrets* y se leen desde
`/run/secrets/password_corporativo_junta` y `/run/secrets/password_geducaand`.

`make install` crea ambos ficheros vacíos con permisos `600`; sólo hay que escribir
la contraseña dentro, sin salto de línea final:

```bash
printf '%s' 'CONTRASEÑA_JUNTA' > password_corporativo_junta
printf '%s' 'APP_PASSWORD_GOOGLE' > password_geducaand
```

| Fichero | Contenido |
|---|---|
| `password_corporativo_junta` | Contraseña del buzón corporativo `@juntadeandalucia.es` |
| `password_geducaand` | App Password de la cuenta `@g.educaand.es` (**no** la contraseña normal) |

> 🔒 Ambos ficheros están excluidos en `.gitignore`, así que no se suben al repositorio.

### Cómo generar `password_geducaand`

La cuenta de Gmail **no** acepta la contraseña habitual por IMAP: hay que crear una
*App Password*, y para que Google ofrezca esa opción es **imprescindible tener activada
la verificación en dos pasos (2FA)** en la cuenta `usuario@g.educaand.es`.

1. Activa la verificación en dos pasos en la cuenta `usuario@g.educaand.es`.
   Sin este paso, el generador de App Passwords no aparece.
2. Entra en <https://myaccount.google.com/apppasswords>.
3. Crea una contraseña de aplicación nueva (por ejemplo, con el nombre `imapsync`).
4. Copia los 16 caracteres que genera Google y guárdalos en `password_geducaand`,
   sin espacios y sin salto de línea final.

`g.educaand.es` está gestionado por Google Workspace, así que el administrador del
dominio debe tener habilitadas tanto la 2FA como las App Passwords. Si no lo están,
la opción no aparecerá aunque actives la verificación en dos pasos en tu cuenta.

## 🧰 Uso

La gestión se hace con `make`. Ejecuta `make` sin argumentos para ver la lista
completa de comandos.

`make install` es idempotente: si `.env` o los ficheros de contraseña ya existen,
los deja intactos.

### Comandos

| Comando | Qué hace |
|---|---|
| `make help` | Lista los comandos disponibles (opción por defecto) |
| `make install` | Crea `.env` y los ficheros de contraseña sin sobrescribir |
| `make up` | Construye y levanta el contenedor en segundo plano |
| `make down` | Para y elimina el contenedor |
| `make restart` | Reinicia el contenedor |
| `make build` | Sólo construye la imagen |
| `make test` | Ejecución única, verbosa y **en simulación** |
| `make sync-once` | Una única sincronización **real** (pide confirmación) |
| `make logs` | Sigue el log del contenedor |
| `make status` | Estado del contenedor y tamaño de los logs |
| `make shell` | Abre una shell dentro del contenedor |
| `make clean` | Borra contenedor, imagen y logs (pide confirmación) |

`make up`, `make test` y `make sync-once` comprueban antes que exista `.env` y que
los ficheros de contraseña no estén vacíos, y fallan con un mensaje claro si no.

### `make test`

Ejecuta un único ciclo con `DRY_RUN=true`, `RUN_ONCE=true` y `VERBOSE=true`: hace
login real en ambos servidores y muestra por pantalla qué mensajes movería, pero no
escribe ni borra nada. Es la forma de validar credenciales y filtrado antes de
arrancar en serio. Al usar `docker compose run --rm` no interfiere con el contenedor
que ya esté levantado ni deja nada atrás.

### Sin `make`

Los comandos equivalentes con Docker directamente:

```bash
cp .env.example .env
docker compose up -d --build   # Construir y arrancar
docker compose logs -f         # Seguir la salida
docker compose down            # Parar
```

El servicio está configurado con `restart: always`, por lo que vuelve a levantarse
tras un reinicio del host.

## 📄 Logs

Se escriben en `./logs/` (montado sobre `/var/log/imapsync`), en un fichero mensual
`sync-AAAA-MM.log`. Contiene tanto las marcas de inicio/fin de ciclo del script como
la salida completa de imapsync.

```bash
tail -f logs/sync-$(date +%Y-%m).log
```

### Rotación

Al inicio de cada ciclo se comprueba el tamaño del log activo. Si supera
`LOG_MAX_BYTES` (100 MB por defecto), se comprime como `sync-AAAA-MM.log.1.gz`,
los comprimidos anteriores se desplazan un número, y se empieza un log nuevo.
Se conservan `LOG_KEEP` ficheros comprimidos (3 por defecto); el más antiguo
se descarta.

El consumo máximo en disco es por tanto ~100 MB del log activo más los 3 comprimidos,
que al ser texto muy repetitivo bajan a una fracción de su tamaño original.

Además se pasa `--nolog` a imapsync para que no genere su propio directorio
`LOG_imapsync/` con un fichero por ejecución (serían ~288 al día), y
`--noreleasecheck` para evitar la consulta de versión en cada pasada.

La zona horaria del contenedor es `Europe/Madrid`.

## 🚨 Tolerancia a fallos

Cada pasada se ejecuta bajo `timeout`, con un tope de `PASS_TIMEOUT` segundos
(480 por defecto) y `SIGKILL` 30 segundos después si no atiende al `SIGTERM`.

Esto cubre el modo de fallo que `restart: always` **no** detecta: si una conexión IMAP
se queda colgada, el proceso sigue vivo, Docker considera el contenedor sano y el bucle
se detendría en silencio para siempre. Con el timeout, la pasada se aborta, queda
registrada como `TIMEOUT` en el log y el ciclo continúa.

Estados posibles de cada pasada:

| Estado | Significado |
|---|---|
| ✅ `OK` | La pasada terminó correctamente |
| ⚠️ `WARN (exit N)` | imapsync terminó con error; el código `N` queda en el log |
| ⏱️ `TIMEOUT (480s)` | La pasada se abortó por exceder el tope |

Como las pasadas son secuenciales, en el peor caso un ciclo tarda
`2 × PASS_TIMEOUT + SLEEP_INTERVAL`. No hay riesgo de solapamiento.

## 📌 Pendiente

- No hay reintento ni alerta externa si una pasada falla: el estado sólo queda
  registrado en el log.
