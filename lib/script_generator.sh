generate_script() {
    clear
    local BACKUP_PATH="${BACKUP_DIR}/_${REMARK}${SCRIPT_SUFFIX}"
    local STATE_FILE="${STATE_DIR}/${REMARK}.last-run"
    local LOCK_FILE="${STATE_DIR}/${REMARK}.lock"
    local backup_directories_quoted=""
    local selected_dirs=()
    local dir
    local log_file
    local cron_line

    for dir in "${DIRECTORIES[@]}"; do
        [[ -n "$dir" ]] && selected_dirs+=("$dir")
    done

    (( ${#selected_dirs[@]} > 0 )) || error "No files or directories selected for backup."
    printf -v backup_directories_quoted '%q ' "${selected_dirs[@]}"

    mkdir -p "$STATE_DIR" || error "Failed to create runtime state directory: $STATE_DIR"
    chmod 700 "$STATE_DIR" || error "Failed to secure runtime state directory: $STATE_DIR"

    log "Generating backup script: $BACKUP_PATH"

    cat <<EOL > "$BACKUP_PATH"
#!/bin/bash
set -euo pipefail
umask 077

BACKUP_DIR="$BACKUP_DIR"
STATE_FILE="$STATE_FILE"
LOCK_FILE="$LOCK_FILE"
INTERVAL_SECONDS=$((minutes * 60))

exec 9>"\$LOCK_FILE"
flock -n 9 || exit 0

if [[ "\${1:-}" == "--scheduled" ]]; then
    now=\$(date +%s)
    if [[ -f "\$STATE_FILE" ]]; then
        last_run=\$(cat "\$STATE_FILE" 2>/dev/null || echo 0)
        if [[ "\$last_run" =~ ^[0-9]+$ ]] && (( now - last_run < INTERVAL_SECONDS )); then
            exit 0
        fi
    fi
    printf '%s\n' "\$now" > "\$STATE_FILE"
fi

ip=\$(hostname -I | awk '{print \$1}')
timestamp=\$(date -u +%Y%m%d-%H%M%SZ)
CAPTION="${CAPTION}"
backup_name="$BACKUP_DIR/\${timestamp}_${REMARK}${BACKUP_SUFFIX}"
base_name="$BACKUP_DIR/\${timestamp}_${REMARK}${TAG}"

cleanup_generated_files() {
    rm -f "\$BACKUP_DIR"/*"${REMARK}${TAG}"* 2>/dev/null || true
}

cleanup_generated_files
trap cleanup_generated_files EXIT

$BACKUP_DB_COMMAND

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

date +%s > "\$STATE_FILE"
EOL

    chmod 700 "$BACKUP_PATH" || error "Failed to secure generated backup script: $BACKUP_PATH"
    success "Backup script created: $BACKUP_PATH"

    log_file=$(mktemp /tmp/backupable.XXXXXX.log) || error "Failed to create temporary log file."
    chmod 600 "$log_file"

    log "Running the backup script..."
    if bash "$BACKUP_PATH" 2>&1 | tee "$log_file"; then
        success "Backup script run successfully."

        cron_line="* * * * * $BACKUP_PATH --scheduled"
        log "Setting up cron job..."
        if (crontab -l 2>/dev/null | grep -Fv "$BACKUP_PATH" || true; echo "$cron_line") | crontab -; then
            success "Cron job set up successfully. Backups will run every $minutes minutes."
        else
            rm -f "$log_file"
            error "Failed to set up cron job. Set it up manually: $cron_line"
        fi

        rm -f "$log_file"
        success "Your backup system is set up and running."
        success "Backup script location: $BACKUP_PATH"
        success "Backup interval: every $minutes minutes"
        success "First backup created and sent."
        exit 0
    else
        warn "The first backup run failed. The cron job was not installed."
        cat "$log_file"
        rm -f "$log_file"
        error "Fix the reported error and create the backup job again."
    fi
}
