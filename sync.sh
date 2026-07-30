#!/usr/bin/env bash
set -euo pipefail

SOURCE_HOST="imap.juntadeandalucia.es"
SOURCE_USER="angel.cardiel.edu@juntadeandalucia.es"
SOURCE_PORT=993

DEST_USER="acarfer940@g.educaand.es"

LOG_DIR="/var/log/imapsync"
SLEEP_INTERVAL=600

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sync-$(date +%Y-%m).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

COMMON_ARGS=(
    --host1      "$SOURCE_HOST"
    --user1      "$SOURCE_USER"
    --passfile1  /run/secrets/password_corporativo_junta
    --port1      "$SOURCE_PORT"
    --ssl1

    --host2      imap.gmail.com
    --user2      "$DEST_USER"
    --passfile2  /run/secrets/password_geducaand
    --port2      993
    --ssl2

    --gmail2
    --syncinternaldates
    --useheader  "Message-Id"
    --maxage     7
    --delete1
    --folder     INBOX
    --nofoldersizes
    --nofoldersizesatend
)

log "=== Iniciando bucle de sincronizacion ==="

while true; do
    START=$(date +%s)
    log "── Inicio de ciclo ──"

    log "Pasada 1: emails normales..."
    imapsync \
        "${COMMON_ARGS[@]}" \
        --search 'NOT SUBJECT "Publicidad"' \
        >> "$LOG_FILE" 2>&1 && STATUS1="OK" || STATUS1="WARN (exit $?)"

    log "Pasada 2: publicidad → Spam..."
    imapsync \
        "${COMMON_ARGS[@]}" \
        --search 'SUBJECT "Publicidad"' \
        --f1f2   "INBOX" "[Gmail]/Spam" \
        >> "$LOG_FILE" 2>&1 && STATUS2="OK" || STATUS2="WARN (exit $?)"

    END=$(date +%s)
    log "Ciclo completado en $((END - START))s — Normal: $STATUS1 | Publicidad: $STATUS2"

    sleep "$SLEEP_INTERVAL"
done
