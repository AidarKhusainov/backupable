generate_script() {
    clear
    local BACKUP_PATH="/root/_${REMARK}${SCRIPT_SUFFIX}"
    log "Generating backup script: $BACKUP_PATH"
    DB_CLEANUP=""
    if [[ -n "$DB_PATH" ]]; then
        DB_CLEANUP="rm -rf "$DB_PATH" 2>/dev/null || true"
    fi

    # Create the backup script
    cat <<EOL > "$BACKUP_PATH"
#!/bin/bash
set -e

# Variables
ip=\$(hostname -I | awk '{print \$1}')
timestamp=\$(TZ='Asia/Tehran' date +%m%d-%H%M)
CAPTION="${CAPTION}"
backup_name="/root/\${timestamp}_${REMARK}${BACKUP_SUFFIX}"
base_name="/root/\${timestamp}_${REMARK}${TAG}"

# Clean up old backup files (only specific backup files)
rm -rf *"${REMARK}${TAG}"* 2>/dev/null || true
$DB_CLEANUP

# Backup database
$BACKUP_DB_COMMAND

# Compress files
if ! $COMPRESS "\$backup_name" ${BACKUP_DIRECTORIES[@]}; then
    message="Failed to compress ${REMARK} files. Please check the server."
    echo "\$message"
    exit 1
fi

# Send backup files
if ls \${base_name}* > /dev/null 2>&1; then
    for FILE in \${base_name}*; do
        echo "Sending file: \$FILE"
        if $PLATFORM_COMMAND; then
            echo "Backup part sent successfully: \$FILE"
        else
            message="Failed to send ${REMARK} backup part: \$FILE. Please check the server."
            echo "\$message"
            exit 1
        fi
    done
    echo "All backup parts sent successfully"
else
    message="Backup file not found: \$backup_name. Please check the server."
    echo "\$message"
    exit 1
fi

rm -rf *"${REMARK}${TAG}"* 2>/dev/null || true
EOL

    # Make the script executable
    chmod +x "$BACKUP_PATH"
    success "Backup script created: $BACKUP_PATH"

    # Run the backup script with realtime output
    log "Running the backup script..."
    if bash "$BACKUP_PATH" 2>&1 | tee /tmp/backup.log; then
        success "Backup script run successfully."

        # Set up cron job
        log "Setting up cron job..."
        if (crontab -l 2>/dev/null; echo "$TIMER $BACKUP_PATH") | crontab -; then
            success "Cron job set up successfully. Backups will run every $minutes minutes."
        else
            error "Failed to set up cron job. Set it up manually: $TIMER $BACKUP_PATH"
            exit 1
        fi

        # Final success message
        success "🎉 Your backup system is set up and running!"
        success "Backup script location: $BACKUP_PATH"
        success "Cron job: Every $minutes minutes"
        success "First backup created and sent."
        success "Thank you for using this backup script. Enjoy automated backups!"
        exit 0
    else
        error "Failed to run backup script. Full output:"
        cat /tmp/backup.log
        message="Backup script failed to run. Please check the server."
        eval "$PLATFORM_COMMAND"
        rm -f /tmp/backup.log
        exit 1
    fi
}
