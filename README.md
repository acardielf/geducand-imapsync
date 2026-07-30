# geducand-imapsync

Sincronización periódica y unidireccional de correo IMAP desde el buzón corporativo
de la Junta de Andalucía hacia una cuenta de Gmail de `g.educaand.es`, ejecutada en
un contenedor Docker que corre de forma continua.

## Qué hace

Un contenedor Debian con [imapsync](https://imapsync.lamiral.info/) ejecuta un bucle
infinito que, cada 10 minutos, realiza **dos pasadas** sobre el `INBOX` de origen:

| Pasada | Filtro IMAP | Destino |
|---|---|---|
| 1 — Correo normal | `NOT SUBJECT "Publicidad"` | `INBOX` de Gmail |
| 2 — Publicidad | `SUBJECT "Publicidad"` | `[Gmail]/Spam` |

Características del sincronizado (definidas en `sync.sh`):

- **Sólo los últimos 7 días** (`--maxage 7`).
- **Movimiento, no copia**: `--delete1` borra en origen los mensajes ya transferidos.
- **Modo Gmail** (`--gmail2`) y conservación de fechas internas (`--syncinternaldates`).
- Deduplicación por cabecera `Message-Id`.
- Sólo se procesa la carpeta `INBOX`; el resto se ignora.

> ⚠️ `--delete1` es destructivo sobre el buzón de origen. Conviene probar primero
> añadiendo `--dry` a `COMMON_ARGS` antes de dejarlo en marcha.

## Estructura

```
.
├── Dockerfile          # Imagen Debian bullseye + dependencias Perl + imapsync oficial
├── docker-compose.yml  # Servicio, volumen de logs y secretos
├── sync.sh             # Bucle de sincronización (copiado a /usr/local/bin en la imagen)
└── logs/               # Salida montada desde el contenedor (ignorada por git)
```

La imagen no instala imapsync desde `apt`, sino que descarga el script original del
autor en `/usr/local/bin/imapsync`; las dependencias Perl sí vienen de los paquetes
Debian.

## Configuración

Los valores de conexión están **codificados en `sync.sh`**:

| Variable | Valor actual |
|---|---|
| `SOURCE_HOST` | `imap.juntadeandalucia.es` (puerto 993, SSL) |
| `SOURCE_USER` | `angel.cardiel.edu@juntadeandalucia.es` |
| `DEST_USER` | `acarfer940@g.educaand.es` (`imap.gmail.com:993`, SSL) |
| `SLEEP_INTERVAL` | `600` segundos entre ciclos |
| `LOG_DIR` | `/var/log/imapsync` |

Las contraseñas se pasan como *Docker secrets* y se leen desde
`/run/secrets/password_corporativo_junta` y `/run/secrets/password_geducaand`.

### Secretos

Antes del primer arranque hay que crear los dos ficheros en la raíz del repositorio,
sin salto de línea final:

```bash
printf '%s' 'CONTRASEÑA_JUNTA' > password_corporativo_junta
printf '%s' 'APP_PASSWORD_GEDUCAAND' > password_geducaand
chmod 600 password_corporativo_junta password_geducaand
```

| Fichero | Contenido |
|---|---|
| `password_corporativo_junta` | Contraseña del buzón corporativo `@juntadeandalucia.es` |
| `password_geducaand` | App Password de la cuenta `@g.educaand.es` (**no** la contraseña normal) |

#### Cómo generar `password_geducaand`

La cuenta de Gmail **no** acepta la contraseña habitual por IMAP: hay que crear una
*App Password*, y para que Google ofrezca esa opción es **imprescindible tener activada
la verificación en dos pasos (2FA)** en la cuenta `usuario@g.educaand.es`.

1. Activa la verificación en dos pasos en la cuenta `usuario@g.educaand.es`.
   Sin este paso, el generador de App Passwords no aparece.
2. Entra en <https://myaccount.google.com/apppasswords>.
3. Crea una contraseña de aplicación nueva (por ejemplo, con el nombre `imapsync`).
4. Copia los 16 caracteres que genera Google y guárdalos en `password_geducaand`,
   sin espacios y sin salto de línea final.

Si el dominio `g.educaand.es` está gestionado por Google Workspace, el administrador
debe permitir tanto la 2FA como las App Passwords; en caso contrario la opción no
estará disponible aunque la 2FA esté activa.

Ambos ficheros están excluidos en `.gitignore`, así que no se suben al repositorio.

## Uso

```bash
docker compose up -d --build   # Construir y arrancar
docker compose logs -f         # Seguir la salida del contenedor
docker compose down            # Parar
```

El servicio está configurado con `restart: always`, por lo que vuelve a levantarse
tras un reinicio del host.

## Logs

Se escriben en `./logs/` (montado sobre `/var/log/imapsync`), con un fichero mensual
por rotación natural del nombre: `sync-AAAA-MM.log`. Contiene tanto las marcas de
inicio/fin de ciclo del script como la salida completa de imapsync.

```bash
tail -f logs/sync-$(date +%Y-%m).log
```

La zona horaria del contenedor es `Europe/Madrid`.

## Pendiente

- Los datos de conexión están fijos en el script; convendría moverlos a variables de
  entorno del `docker-compose.yml`.
- No hay reintento ni alerta si una pasada falla: sólo se registra `WARN (exit N)`
  en el log.
