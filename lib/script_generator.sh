generate_script() {
    clear
    local BACKUP_PATH="${BACKUP_DIR}/_${REMARK}${SCRIPT_SUFFIX}"
    local BACKUP_PATH_TMP="${BACKUP_PATH}.tmp"
    local STATE_FILE="${STATE_DIR}/${REMARK}.last-run"
    local SUCCESS_FILE="${STATE_DIR}/${REMARK}.last-success"
    local FAILURE_FILE="${STATE_DIR}/${REMARK}.last-failure"
    local LOCK_FILE="${STATE_DIR}/${REMARK}.lock"
    local schedule_type="${SCHEDULE_TYPE:-interval}"
    local schedule_time="${SCHEDULE_TIME:-}"
    local schedule_tz="${SCHEDULE_TZ:-UTC}"
    local interval_seconds=0
    local job_timeout_seconds="${BACKUPABLE_JOB_TIMEOUT_SECONDS:-7200}"
    local backup_directories_quoted=""
    local selected_dirs=()
    local dir
    local log_file
    local cron_line

    [[ "$job_timeout_seconds" =~ ^[0-9]+$ ]] && (( job_timeout_seconds >= 1 )) ||
        error "BACKUPABLE_JOB_TIMEOUT_SECONDS must be a positive integer."

    case "$schedule_type" in
        interval)
            [[ "${minutes:-}" =~ ^[0-9]+$ ]] || error "Interval schedule requires a numeric minute value."
            (( minutes >= 1 && minutes <= 1440 )) || error "Interval must be between 1 and 1440 minutes."
            interval_seconds=$((minutes * 60))
            ;;
        daily)
            [[ "$schedule_time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] ||
                error "Daily schedule time must use 24-hour HH:MM format."
            if [[ "$schedule_tz" != "UTC" && "$schedule_tz" != "Etc/UTC" && "$schedule_tz" != "GMT" ]]; then
                [[ "$schedule_tz" != /* && "$schedule_tz" != *".."* && -f "/usr/share/zoneinfo/$schedule_tz" ]] ||
                    error "Daily schedule timezone is not a valid IANA zone: $schedule_tz"
            fi
            ;;
        *)
            error "Unsupported schedule type: $schedule_type"
            ;;
    esac

    for dir in "${DIRECTORIES[@]}"; do
        [[ -n "$dir" ]] && selected_dirs+=("$dir")
    done

    (( ${#selected_dirs[@]} > 0 )) || error "No files or directories selected for backup."
    printf -v backup_directories_quoted '%q ' "${selected_dirs[@]}"

    mkdir -p "$STATE_DIR" || error "Failed to create runtime state directory: $STATE_DIR"
    chmod 700 "$STATE_DIR" || error "Failed to secure runtime state directory: $STATE_DIR"

    log "Generating backup script: $BACKUP_PATH"

    rm -f "$BACKUP_PATH_TMP"
    cat <<EOL > "$BACKUP_PATH_TMP"
#!/bin/bash
set -euo pipefail
umask 077

BACKUP_DIR="$BACKUP_DIR"
STATE_FILE="$STATE_FILE"
SUCCESS_FILE="$SUCCESS_FILE"
FAILURE_FILE="$FAILURE_FILE"
LOCK_FILE="$LOCK_FILE"
SCHEDULE_TYPE="$schedule_type"
INTERVAL_SECONDS=$interval_seconds
SCHEDULE_TIME="$schedule_time"
SCHEDULE_TZ="$schedule_tz"
BACKUP_INPUTS=($backup_directories_quoted)
DISK_SAFETY_BYTES="\${BACKUPABLE_DISK_SAFETY_BYTES:-67108864}"

atomic_write() {
    local target="\$1"
    local value="\$2"
    local tmp="\${target}.tmp.\$\$"

    printf '%s\n' "\$value" > "\$tmp"
    chmod 0600 "\$tmp"
    mv -f "\$tmp" "\$target"
}

mark_failure() {
    local success_epoch=0 failure_epoch=0 now_epoch

    [[ -f "\$SUCCESS_FILE" ]] && success_epoch=\$(cat "\$SUCCESS_FILE" 2>/dev/null || echo 0)
    [[ -f "\$FAILURE_FILE" ]] && failure_epoch=\$(cat "\$FAILURE_FILE" 2>/dev/null || echo 0)

    if [[ "\$success_epoch" =~ ^[0-9]+$ && "\$failure_epoch" =~ ^[0-9]+$ ]] && (( failure_epoch > success_epoch )); then
        return 0
    fi

    now_epoch=\$(date +%s)
    atomic_write "\$FAILURE_FILE" "\$now_epoch"
}

resolve_daily_slot_for_date() {
    local slot_date="\$1"
    local schedule_hour schedule_minute start_minute minute candidate candidate_epoch resolved

    IFS=: read -r schedule_hour schedule_minute <<< "\$SCHEDULE_TIME"
    start_minute=\$((10#\$schedule_hour * 60 + 10#\$schedule_minute))

    for ((minute = start_minute; minute < 1440; minute++)); do
        printf -v candidate '%02d:%02d' "\$((minute / 60))" "\$((minute % 60))"
        if candidate_epoch=\$(TZ="\$SCHEDULE_TZ" date -d "\$slot_date \$candidate:00" +%s 2>/dev/null); then
            resolved=\$(TZ="\$SCHEDULE_TZ" date -d "@\$candidate_epoch" '+%F %H:%M')
            if [[ "\$resolved" == "\$slot_date \$candidate" ]]; then
                printf '%s\n' "\$candidate_epoch"
                return 0
            fi
        fi
    done

    echo "Failed to resolve a valid daily schedule slot for \$slot_date \$SCHEDULE_TIME in \$SCHEDULE_TZ." >&2
    return 1
}

latest_daily_slot_epoch() {
    local now_epoch="${1:-\$(date +%s)}"
    local today slot_epoch previous_day

    today=\$(TZ="\$SCHEDULE_TZ" date -d "@\$now_epoch" +%F)

    if ! slot_epoch=\$(resolve_daily_slot_for_date "\$today"); then
        return 1
    fi

    if (( slot_epoch > now_epoch )); then
        previous_day=\$(TZ="\$SCHEDULE_TZ" date -d "\$today -1 day" +%F)
        if ! slot_epoch=\$(resolve_daily_slot_for_date "\$previous_day"); then
            return 1
        fi
    fi

    printf '%s\n' "\$slot_epoch"
}

exec 9>"\$LOCK_FILE"
flock -n 9 || exit 0

scheduled_slot=""
if [[ "\${1:-}" == "--scheduled" ]]; then
    now="\${BACKUPABLE_NOW_EPOCH:-\$(date +%s)}"
    if ! [[ "\$now" =~ ^[0-9]+$ ]]; then
        echo "BACKUPABLE_NOW_EPOCH must be a Unix epoch integer." >&2
        exit 1
    fi

    case "\$SCHEDULE_TYPE" in
        interval)
            if [[ -f "\$STATE_FILE" ]]; then
                last_run=\$(cat "\$STATE_FILE" 2>/dev/null || echo 0)
                if [[ "\$last_run" =~ ^[0-9]+$ ]] && (( last_run <= now && now - last_run < INTERVAL_SECONDS )); then
                    exit 0
                fi
            fi
            ;;
        daily)
            scheduled_slot=\$(latest_daily_slot_epoch "\$now")
            if [[ -f "\$STATE_FILE" ]]; then
                last_completed_slot=\$(cat "\$STATE_FILE" 2>/dev/null || echo 0)
                if [[ "\$last_completed_slot" =~ ^[0-9]+$ ]] && (( last_completed_slot >= scheduled_slot )); then
                    exit 0
                fi
            fi
            ;;
        *)
            echo "Unsupported schedule type: \$SCHEDULE_TYPE" >&2
            exit 1
            ;;
    esac
fi

ip="\${BACKUPABLE_SOURCE_LABEL:-}"
if [[ -z "\$ip" ]]; then
    ip=\$(hostname -I 2>/dev/null | awk '{print \$1}' || true)
fi
if [[ -z "\$ip" ]]; then
    ip=\$(hostname -i 2>/dev/null | awk '{print \$1}' || true)
fi
[[ -n "\$ip" ]] || ip="unknown"
timestamp=\$(date -u +%Y%m%d-%H%M%SZ)
CAPTION="${CAPTION}"
backup_name="$BACKUP_DIR/\${timestamp}_${REMARK}${BACKUP_SUFFIX}"
base_name="$BACKUP_DIR/\${timestamp}_${REMARK}${TAG}"

cleanup_generated_files() {
    rm -f "\$BACKUP_DIR"/*"${REMARK}${TAG}"* 2>/dev/null || true
}

preflight_disk_space() {
    local required_bytes=0 available_bytes input_size path

    if ! [[ "\$DISK_SAFETY_BYTES" =~ ^[0-9]+$ ]]; then
        echo "BACKUPABLE_DISK_SAFETY_BYTES must be a non-negative integer." >&2
        return 1
    fi

    for path in "\${BACKUP_INPUTS[@]}"; do
        [[ -e "\$path" ]] || { echo "Backup input not found: \$path" >&2; return 1; }
        input_size=\$(du -sb -- "\$path" | awk '{print \$1}')
        [[ "\$input_size" =~ ^[0-9]+$ ]] || { echo "Failed to determine backup input size: \$path" >&2; return 1; }
        required_bytes=\$((required_bytes + input_size))
    done

    available_bytes=\$(df -PB1 -- "\$BACKUP_DIR" | awk 'NR == 2 {print \$4}')
    [[ "\$available_bytes" =~ ^[0-9]+$ ]] || { echo "Failed to determine free space for \$BACKUP_DIR." >&2; return 1; }

    if (( available_bytes < required_bytes + DISK_SAFETY_BYTES )); then
        echo "Insufficient disk space for backup: available=\${available_bytes}B, inputs=\${required_bytes}B, safety=\${DISK_SAFETY_BYTES}B." >&2
        return 1
    fi
}

on_exit() {
    local rc=\$?
    trap - EXIT
    cleanup_generated_files
    if (( rc != 0 )); then
        mark_failure || true
    fi
    exit "\$rc"
}

cleanup_generated_files
trap on_exit EXIT

$BACKUP_DB_COMMAND
preflight_disk_space

if ! $COMPRESS "\$backup_name" $backup_directories_quoted; then
    echo "Failed to compress ${REMARK} files. Please check the server."
    exit 1
fi

if compgen -G "\${base_name}*" > /dev/null; then
    for FILE in "\${base_name}"*; do
        echo "Sending file: \$FILE"
        if $PLATFORM_COMMAND; then
            echo "Backup part sent successfully: \$FILE"
        else
            echo "Failed to send ${REMARK} backup part: \$FILE. Please check the server."
            exit 1
        fi
    done
    echo "All backup parts sent successfully"
else
    echo "Backup file not found: \$backup_name. Please check the server."
    exit 1
fi

state_value=""
case "\$SCHEDULE_TYPE" in
    interval)
        state_value=\$(date +%s)
        ;;
    daily)
        case "\${1:-}" in
            --scheduled)
                state_value="\$scheduled_slot"
                ;;
            --initial)
                state_value=\$(latest_daily_slot_epoch)
                ;;
        esac
        ;;
esac

if [[ -n "\$state_value" ]]; then
    atomic_write "\$STATE_FILE" "\$state_value"
fi
atomic_write "\$SUCCESS_FILE" "\$(date +%s)"
EOL

    chmod 700 "$BACKUP_PATH_TMP" || error "Failed to secure generated backup script: $BACKUP_PATH_TMP"
    success "Backup script prepared: $BACKUP_PATH"

    log_file=$(mktemp /tmp/backupable.XXXXXX.log) || error "Failed to create temporary log file."
    chmod 600 "$log_file"

    log "Running the backup script..."
    if bash "$BACKUP_PATH_TMP" --initial 2>&1 | tee "$log_file"; then
        success "Backup script run successfully."

        mv "$BACKUP_PATH_TMP" "$BACKUP_PATH" || {
            rm -f "$log_file"
            error "Failed to register generated backup script: $BACKUP_PATH"
        }

        case "$SCHEDULER_MODE" in
            cron)
                cron_line="* * * * * timeout --signal=TERM --kill-after=30s ${job_timeout_seconds}s $BACKUP_PATH --scheduled"
                log "Setting up cron job..."
                if (crontab -l 2>/dev/null | grep -Fv "$BACKUP_PATH" || true; echo "$cron_line") | crontab -; then
                    success "Cron polling job set up successfully."
                else
                    rm -f "$log_file"
                    error "Failed to set up cron job. Set it up manually: $cron_line"
                fi
                ;;
            internal)
                success "Backup job registered for the internal scheduler."
                ;;
            *)
                rm -f "$log_file"
                error "Unsupported scheduler mode: $SCHEDULER_MODE"
                ;;
        esac

        rm -f "$log_file"
        success "Your backup system is set up and running."
        success "Backup script location: $BACKUP_PATH"
        case "$schedule_type" in
            interval)
                success "Backup interval: every $minutes minutes"
                ;;
            daily)
                success "Backup schedule: daily at $schedule_time ($schedule_tz)"
                ;;
        esac
        success "First backup created and sent."
        exit 0
    else
        if [[ "$SCHEDULER_MODE" == "cron" ]]; then
            warn "The first backup run failed. The cron job was not installed."
        else
            warn "The first backup run failed. The job was not registered successfully."
        fi
        cat "$log_file"
        rm -f "$log_file" "$BACKUP_PATH_TMP"
        error "Fix the reported error and create the backup job again."
    fi
}
