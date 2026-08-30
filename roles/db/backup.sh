#!/usr/bin/env bash

set -euo pipefail

# Configuration
LOCK_FILE="${LOCK_FILE:-${RUNTIME_DIRECTORY:-/run/backup}/backup-db.lock}"
LOG_FILE="${LOG_FILE:-/var/log/backup.log}"

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

log "INFO" "Running as $(id)"
log "INFO" "SOURCE_FILE='$SOURCE_FILE'  realpath=$(realpath "$SOURCE_FILE" 2>/dev/null || echo 'realpath failed')"

if [[ -f "$LOCK_FILE" ]]; then
    log "ERROR" "Another backup is already running (lock: $LOCK_FILE)"
    exit 1
fi

# Ensure lock directory exists
mkdir -p "$(dirname "$LOCK_FILE")"
echo $$ > "$LOCK_FILE"

if [[ ! -d "$SOURCE_FILE" ]]; then
    log "ERROR" "Source directory does not exist: $SOURCE_FILE"
    exit 1
fi

if [[ ! -r "$SOURCE_FILE" ]]; then
    log "ERROR" "Source directory is not readable: $SOURCE_FILE"
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
DIR_NAME="${SOURCE_FILE##*/}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BASENAME="${DIR_NAME}_${TIMESTAMP}"
TMP_BACKUP="${BACKUP_DIR}/${BASENAME}.tmp"
FINAL_BACKUP="${BACKUP_DIR}/${BASENAME}.xz"

log "INFO" "Starting backup of $SOURCE_FILE (running as $(whoami))"

# Make sure destination exists
mkdir -p "$BACKUP_DIR"

# Create compressed archive directly
tar -cJf "$FINAL_BACKUP" -C "$(dirname "$SOURCE_FILE")" "$(basename "$SOURCE_FILE")"

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

find "$BACKUP_DIR" -type f -name "${DIR_NAME}_*.xz" -mtime +"${RETENTION_DAYS}" -print -delete | while read -r old; do
    log "INFO" "Deleted old backup: $old"
done

log "INFO" "Backup job finished successfully"
exit 0