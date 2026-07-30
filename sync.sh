#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────────────────────────────────────────────
# Configuracion
#
# Todo es sobrescribible por variables de entorno; los valores de aqui
# son los recomendados por defecto. Ver .env.example.
#
# Obligatorias: SOURCE_USER, DEST_USER.
# ───────────────────────────────────────────────────────────────────────

# Buzon de origen
SOURCE_HOST="${SOURCE_HOST:-imap.juntadeandalucia.es}"
SOURCE_USER="${SOURCE_USER:-}"
SOURCE_PORT="${SOURCE_PORT:-993}"
SOURCE_PASSFILE="${SOURCE_PASSFILE:-/run/secrets/password_corporativo_junta}"

# Buzon de destino
DEST_HOST="${DEST_HOST:-imap.gmail.com}"
DEST_USER="${DEST_USER:-}"
DEST_PORT="${DEST_PORT:-993}"
DEST_PASSFILE="${DEST_PASSFILE:-/run/secrets/password_geducaand}"
DEST_IS_GMAIL="${DEST_IS_GMAIL:-true}"

# Sincronizacion
SYNC_FOLDER="${SYNC_FOLDER:-INBOX}"
MAX_AGE="${MAX_AGE:-7}"
SLEEP_INTERVAL="${SLEEP_INTERVAL:-600}"

# Los mensajes se identifican por Message-Id. Los que no la traen se ignoran
# y, como nunca se transfieren, --delete1 tampoco los borra: se quedarian en
# origen para siempre. ADD_HEADER hace que imapsync les genere una Message-Id
# sintetica a partir del UID de origen.
ADD_HEADER="${ADD_HEADER:-true}"

# DELETE_SOURCE=true borra en origen lo ya transferido (mover, no copiar).
# DRY_RUN=true simula sin escribir nada: recomendable en la primera puesta
# en marcha para comprobar el filtrado antes de tocar el buzon real.
DELETE_SOURCE="${DELETE_SOURCE:-true}"
DRY_RUN="${DRY_RUN:-false}"

# Segunda pasada: correo cuyo asunto contiene SPAM_SUBJECT va a SPAM_FOLDER.
# Con SPAM_SUBJECT vacio se desactiva y solo se hace la pasada normal.
# Sin ':' en la expansion: asi un SPAM_SUBJECT= explicito se respeta como
# vacio (desactiva la pasada) en vez de recaer en el valor por defecto.
SPAM_SUBJECT="${SPAM_SUBJECT-Publicidad}"
SPAM_FOLDER="${SPAM_FOLDER:-[Gmail]/Spam}"

# Logs. Al superar LOG_MAX_BYTES el log se comprime y se empieza uno nuevo,
# conservando LOG_KEEP comprimidos.
LOG_DIR="${LOG_DIR:-/var/log/imapsync}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-$((100 * 1024 * 1024))}"
LOG_KEEP="${LOG_KEEP:-3}"

# Tope por pasada. Sin esto, una conexion IMAP colgada bloquea el bucle
# indefinidamente sin que el proceso llegue a morir, asi que Docker nunca
# reinicia el contenedor y la sincronizacion se detiene en silencio.
PASS_TIMEOUT="${PASS_TIMEOUT:-480}"
PASS_KILL_AFTER="${PASS_KILL_AFTER:-30}"

# RUN_ONCE=true ejecuta un unico ciclo y termina, en vez de bucle infinito.
# VERBOSE=true vuelca ademas la salida de imapsync por pantalla.
# Los usa 'make test' para comprobar la configuracion sin dejar nada corriendo.
RUN_ONCE="${RUN_ONCE:-false}"
VERBOSE="${VERBOSE:-false}"

# ───────────────────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sync-$(date +%Y-%m).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Falla al arrancar y no en mitad del bucle, con un mensaje accionable.
check_config() {
    local faltan=()
    [[ -n "$SOURCE_USER" ]] || faltan+=("SOURCE_USER")
    [[ -n "$DEST_USER" ]]   || faltan+=("DEST_USER")

    if (( ${#faltan[@]} > 0 )); then
        log "ERROR: faltan variables obligatorias: ${faltan[*]}"
        log "Defínelas en .env (ver .env.example)."
        exit 1
    fi

    local fichero
    for fichero in "$SOURCE_PASSFILE" "$DEST_PASSFILE"; do
        if [[ ! -r "$fichero" ]]; then
            log "ERROR: no se puede leer el fichero de contraseña: $fichero"
            log "Comprueba la sección 'secrets' de docker-compose.yml."
            exit 1
        fi
        if [[ ! -s "$fichero" ]]; then
            log "ERROR: el fichero de contraseña está vacío: $fichero"
            log "Rellénalo ejecutando 'make install'."
            exit 1
        fi
    done

    if ! [[ "$SLEEP_INTERVAL" =~ ^[0-9]+$ ]] || (( SLEEP_INTERVAL < 60 )); then
        log "ERROR: SLEEP_INTERVAL debe ser un entero >= 60 (valor: $SLEEP_INTERVAL)"
        exit 1
    fi
}

# El contenedor corre indefinidamente, asi que el nombre mensual debe
# recalcularse en cada ciclo y no solo al arrancar.
update_log_file() {
    LOG_FILE="$LOG_DIR/sync-$(date +%Y-%m).log"
}

rotate_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi

    local size
    size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    if (( size < LOG_MAX_BYTES )); then
        return 0
    fi

    log "Log en $((size / 1024 / 1024)) MB, rotando..."

    local i
    for (( i = LOG_KEEP - 1; i >= 1; i-- )); do
        if [[ -f "$LOG_FILE.$i.gz" ]]; then
            mv -f "$LOG_FILE.$i.gz" "$LOG_FILE.$((i + 1)).gz"
        fi
    done

    mv -f "$LOG_FILE" "$LOG_FILE.1"
    gzip -f "$LOG_FILE.1"
    rm -f "$LOG_FILE.$((LOG_KEEP + 1)).gz"

    : > "$LOG_FILE"
    log "Rotación completada (se conservan $LOG_KEEP ficheros comprimidos)"
}

check_config

COMMON_ARGS=(
    --host1      "$SOURCE_HOST"
    --user1      "$SOURCE_USER"
    --passfile1  "$SOURCE_PASSFILE"
    --port1      "$SOURCE_PORT"
    --ssl1

    --host2      "$DEST_HOST"
    --user2      "$DEST_USER"
    --passfile2  "$DEST_PASSFILE"
    --port2      "$DEST_PORT"
    --ssl2

    --syncinternaldates
    --useheader  "Message-Id"
    --maxage     "$MAX_AGE"
    --folder     "$SYNC_FOLDER"

    # imapsync crea por defecto un fichero propio por ejecucion en
    # LOG_imapsync/; con un ciclo cada 10 min eso son ~288 ficheros al dia.
    --nolog
    --noreleasecheck
    --nofoldersizes
    --nofoldersizesatend
)

if [[ "$DEST_IS_GMAIL" == "true" ]]; then
    COMMON_ARGS+=(--gmail2)
fi

if [[ "$ADD_HEADER" == "true" ]]; then
    COMMON_ARGS+=(--addheader)
fi

if [[ "$DELETE_SOURCE" == "true" ]]; then
    COMMON_ARGS+=(--delete1)
fi

if [[ "$DRY_RUN" == "true" ]]; then
    COMMON_ARGS+=(--dry)
fi

# Ejecuta una pasada de imapsync acotada por PASS_TIMEOUT y deja el resultado
# en PASS_STATUS. timeout envia primero SIGTERM y, si no muere, SIGKILL.
run_pass() {
    local etiqueta="$1"
    shift

    local rc=0
    if [[ "$VERBOSE" == "true" ]]; then
        # pipefail hace que rc recoja el fallo de imapsync, no el de tee.
        timeout -k "$PASS_KILL_AFTER" "$PASS_TIMEOUT" \
            imapsync "${COMMON_ARGS[@]}" "$@" 2>&1 | tee -a "$LOG_FILE" || rc=$?
    else
        timeout -k "$PASS_KILL_AFTER" "$PASS_TIMEOUT" \
            imapsync "${COMMON_ARGS[@]}" "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    fi

    case "$rc" in
        0)
            PASS_STATUS="OK"
            ;;
        124|137)
            PASS_STATUS="TIMEOUT (${PASS_TIMEOUT}s)"
            log "$etiqueta abortada: superó ${PASS_TIMEOUT}s sin terminar"
            ;;
        *)
            PASS_STATUS="WARN (exit $rc)"
            ;;
    esac
}

log "=== Iniciando bucle de sincronización ==="
log "Origen:  $SOURCE_USER en $SOURCE_HOST:$SOURCE_PORT (carpeta $SYNC_FOLDER)"
log "Destino: $DEST_USER en $DEST_HOST:$DEST_PORT"
log "Intervalo: ${SLEEP_INTERVAL}s | Antigüedad máxima: ${MAX_AGE}d | Borrar origen: $DELETE_SOURCE"

if [[ "$DRY_RUN" == "true" ]]; then
    log "MODO SIMULACIÓN (DRY_RUN=true): no se escribirá ni se borrará nada"
fi

while true; do
    START=$(date +%s)
    update_log_file
    rotate_log
    log "── Inicio de ciclo ──"

    log "Pasada 1: emails normales..."
    if [[ -n "$SPAM_SUBJECT" ]]; then
        run_pass "Pasada 1" --search "NOT SUBJECT \"$SPAM_SUBJECT\""
    else
        run_pass "Pasada 1"
    fi
    STATUS1="$PASS_STATUS"

    if [[ -n "$SPAM_SUBJECT" ]]; then
        log "Pasada 2: $SPAM_SUBJECT → $SPAM_FOLDER..."
        # --f1f2 toma un unico argumento con la forma origen=destino. Pasarlo
        # como dos argumentos hace que imapsync salga con 64 (EX_USAGE).
        run_pass "Pasada 2" \
            --search "SUBJECT \"$SPAM_SUBJECT\"" \
            --f1f2   "$SYNC_FOLDER=$SPAM_FOLDER"
        STATUS2="$PASS_STATUS"
    else
        STATUS2="omitida (SPAM_SUBJECT vacío)"
    fi

    END=$(date +%s)
    log "Ciclo completado en $((END - START))s — Normal: $STATUS1 | Publicidad: $STATUS2"

    if [[ "$RUN_ONCE" == "true" ]]; then
        log "RUN_ONCE=true: fin tras un único ciclo"
        break
    fi

    sleep "$SLEEP_INTERVAL"
done
