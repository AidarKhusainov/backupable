#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUPABLE_BACKUP_DIR:-/var/lib/backupable/jobs}"
STATE_DIR="${BACKUPABLE_STATE_DIR:-/var/lib/backupable/state}"
FAILURE_GRACE_SECONDS="${BACKUPABLE_HEALTH_FAILURE_GRACE_SECONDS:-300}"

[[ -d "$BACKUP_DIR" && -w "$BACKUP_DIR" ]]
[[ -d "$STATE_DIR" && -w "$STATE_DIR" ]]
[[ "$FAILURE_GRACE_SECONDS" =~ ^[0-9]+$ ]] || {
    echo "[ERROR] BACKUPABLE_HEALTH_FAILURE_GRACE_SECONDS must be a non-negative integer." >&2
    exit 1
}

now=$(date +%s)
shopt -s nullglob
for script in "$BACKUP_DIR"/*_backupable_script.sh; do
    remark="${script##*/_}"
    remark="${remark%_backupable_script.sh}"
    success_file="$STATE_DIR/$remark.last-success"
    failure_file="$STATE_DIR/$remark.last-failure"
    success_epoch=0
    failure_epoch=0

    [[ -f "$success_file" ]] && success_epoch=$(cat "$success_file" 2>/dev/null || echo 0)
    [[ -f "$failure_file" ]] && failure_epoch=$(cat "$failure_file" 2>/dev/null || echo 0)

    [[ "$success_epoch" =~ ^[0-9]+$ ]] || success_epoch=0
    [[ "$failure_epoch" =~ ^[0-9]+$ ]] || failure_epoch=0

    if (( failure_epoch > success_epoch && now - failure_epoch >= FAILURE_GRACE_SECONDS )); then
        echo "[ERROR] Backup job has an unresolved failure: $remark" >&2
        exit 1
    fi
done
shopt -u nullglob

docker version --format '{{.Client.Version}}' >/dev/null
