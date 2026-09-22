#!/usr/bin/env bash
set -euo pipefail
umask 077

BACKUPABLE_BACKUP_DIR="${BACKUPABLE_BACKUP_DIR:-/var/lib/backupable/jobs}"
BACKUPABLE_STATE_DIR="${BACKUPABLE_STATE_DIR:-/var/lib/backupable/state}"
BACKUPABLE_SCHEDULER_MODE="${BACKUPABLE_SCHEDULER_MODE:-internal}"

export BACKUPABLE_BACKUP_DIR BACKUPABLE_STATE_DIR BACKUPABLE_SCHEDULER_MODE

mkdir -p "$BACKUPABLE_BACKUP_DIR" "$BACKUPABLE_STATE_DIR"
chmod 0700 "$BACKUPABLE_BACKUP_DIR" "$BACKUPABLE_STATE_DIR"

run_all_jobs() {
    local found=false
    local script

    shopt -s nullglob
    for script in "$BACKUPABLE_BACKUP_DIR"/*_backupable_script.sh; do
        found=true
        echo "[INFO] Running backup job now: $script"
        bash "$script"
    done
    shopt -u nullglob

    if [[ "$found" == false ]]; then
        echo "[WARN] No backup jobs are configured."
    fi
}

show_status() {
    local found=false
    local script remark state_file last_run schedule_type schedule_time schedule_tz schedule

    echo "Backupable container status"
    echo "  scheduler: $BACKUPABLE_SCHEDULER_MODE"
    echo "  jobs dir:  $BACKUPABLE_BACKUP_DIR"
    echo "  state dir: $BACKUPABLE_STATE_DIR"
    echo ""

    shopt -s nullglob
    for script in "$BACKUPABLE_BACKUP_DIR"/*_backupable_script.sh; do
        found=true
        remark="${script##*/_}"
        remark="${remark%_backupable_script.sh}"
        state_file="$BACKUPABLE_STATE_DIR/$remark.last-run"
        if [[ -f "$state_file" ]]; then
            last_run="$(cat "$state_file" 2>/dev/null || true)"
        else
            last_run="never"
        fi

        schedule_type="$(sed -n 's/^SCHEDULE_TYPE="\([^"]*\)"$/\1/p' "$script" | head -n 1)"
        case "$schedule_type" in
            daily)
                schedule_time="$(sed -n 's/^SCHEDULE_TIME="\([^"]*\)"$/\1/p' "$script" | head -n 1)"
                schedule_tz="$(sed -n 's/^SCHEDULE_TZ="\([^"]*\)"$/\1/p' "$script" | head -n 1)"
                schedule="daily@${schedule_time}[${schedule_tz}]"
                ;;
            interval)
                schedule="interval"
                ;;
            *)
                schedule="legacy"
                ;;
        esac

        printf '  %-24s schedule=%-30s state=%s\n' "$remark" "$schedule" "$last_run"
    done
    shopt -u nullglob

    [[ "$found" == true ]] || echo "  no jobs configured"
}

case "${1:-run}" in
    run)
        exec /app/docker/scheduler.sh
        ;;
    setup)
        shift || true
        exec /app/backupable.sh "$@"
        ;;
    backup-now)
        run_all_jobs
        ;;
    status)
        show_status
        ;;
    shell)
        exec /bin/bash
        ;;
    *)
        exec "$@"
        ;;
esac
