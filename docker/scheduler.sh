#!/usr/bin/env bash
set -euo pipefail
umask 077

BACKUP_DIR="${BACKUPABLE_BACKUP_DIR:-/var/lib/backupable/jobs}"
POLL_SECONDS="${BACKUPABLE_POLL_SECONDS:-60}"

if ! [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || (( POLL_SECONDS < 1 )); then
    echo "[ERROR] BACKUPABLE_POLL_SECONDS must be a positive integer." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

echo "[INFO] Backupable internal scheduler started. Poll interval: ${POLL_SECONDS}s"

while true; do
    shopt -s nullglob
    jobs=("$BACKUP_DIR"/*_backupable_script.sh)
    shopt -u nullglob

    for job in "${jobs[@]}"; do
        if ! bash "$job" --scheduled; then
            echo "[ERROR] Scheduled backup failed: $job" >&2
        fi
    done

    sleep "$POLL_SECONDS"
done
