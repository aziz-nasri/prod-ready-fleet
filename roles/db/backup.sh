#!/usr/bin/env bash

set -euo pipefail

# Configuration
LOCK_FILE="${LOCK_FILE:-/run/user/$(id -u)/backup-db.lock}"

# Helpers
log() {
    local level="$1"
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT


if [[ -f "$LOCK_FILE" ]]; then
    log "ERROR" "Another backup is already running (lock: $LOCK_FILE)"
    exit 1
fi

# Ensure lock directory exists
mkdir -p "$(dirname "$LOCK_FILE")"
echo $$ > "$LOCK_FILE"

if [[ ! -f "$SOURCE_FILE" ]]; then
    log "ERROR" "Source file does not exist: $SOURCE_FILE"
    exit 1
fi

if [[ ! -r "$SOURCE_FILE" ]]; then
    log "ERROR" "Source file is not readable: $SOURCE_FILE"
    exit 1
fi

# Create backup directory if needed
if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    chmod 750 "$BACKUP_DIR"
fi

if [[ ! -w "$BACKUP_DIR" ]]; then
    log "ERROR" "Backup directory is not writable: $BACKUP_DIR"
    exit 1
fi


# Create backup
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BASENAME="${PREFIX}_${TIMESTAMP}"
TMP_BACKUP="${BACKUP_DIR}/${BASENAME}.tmp"

log "INFO" "Starting backup of $SOURCE_FILE (running as $(whoami))"

# Copy the database file
cp --preserve=timestamps "$SOURCE_FILE" "$TMP_BACKUP"

if [[ "$COMPRESS" == "true" ]]; then
    gzip -9 "$TMP_BACKUP"
    FINAL_BACKUP="${BACKUP_DIR}/${BASENAME}.db.gz"
    mv "${TMP_BACKUP}.gz" "$FINAL_BACKUP"
else
    FINAL_BACKUP="${BACKUP_DIR}/${BASENAME}.db"
    mv "$TMP_BACKUP" "$FINAL_BACKUP"
fi

# Basic integrity: file must not be empty
if [[ ! -s "$FINAL_BACKUP" ]]; then
    log "ERROR" "Backup file is empty: $FINAL_BACKUP"
    rm -f "$FINAL_BACKUP"
    exit 1
fi

SIZE=$(du -h "$FINAL_BACKUP" | cut -f1)
log "INFO" "Backup created successfully: $FINAL_BACKUP ($SIZE)"


# Retention delete backups older than RETENTION_DAYS
log "INFO" "Applying retention policy (keep last ${RETENTION_DAYS} days)"

find "$BACKUP_DIR" -type f \( -name "${PREFIX}_*.db" -o -name "${PREFIX}_*.db.gz" \) \
    -mtime +"${RETENTION_DAYS}" -print -delete | while read -r old; do
    log "INFO" "Deleted old backup: $old"
done

log "INFO" "Backup job finished successfully"
exit 0