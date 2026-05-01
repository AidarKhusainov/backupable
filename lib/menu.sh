menu() {
    while true; do
        clear
        print "======== Backupable Menu [$VERSION] ========"
        print ""
        print "1) Create or update a backup job"
        print "2) Remove backup jobs and generated files"
        print "3) Run all existing backup jobs now"
        print "4) Exit"
        print ""
        input "Choose an option:" choice
        case $choice in
            1)
                start_backup
                ;;
            2)
                cleanup_backups
                ;;
            3)
                if compgen -G "/root/*${SCRIPT_SUFFIX}" > /dev/null; then
                    for script in /root/*${SCRIPT_SUFFIX}; do
                        log "Running backup script: $script"
                        bash "$script"
                    done
                else
                    warn "No backup scripts found in /root directory"
                fi
                confirm
                ;;
            4)
                print "Thank you for using this script. Goodbye!"
                exit 0
                ;;
            *)
                wrong "Invalid option, Please select a valid option!"
                ;;
        esac
    done
}

cleanup_backups() {
    print "Removing generated backup scripts, backup files, and matching cron entries..."

    rm -rf /root/*"$SCRIPT_SUFFIX" /root/*"$TAG"* /root/*_backupable.sh /root/ac-backup*.sh /root/*backupable*.sh

    if command -v crontab &>/dev/null; then
        crontab -l | grep -v "$SCRIPT_SUFFIX" | crontab -
    fi

    success "All backups and cron jobs have been removed."
    sleep 1
}

review_backup_configuration() {
    local answer

    clear
    print "Step 8/8: Review and create\n"
    print "Job name: ${REMARK}"
    print "Schedule: every ${minutes} minutes (${TIMER})"
    print "Template: ${TEMPLATE_NAME:-Custom}"
    print "Delivery: ${PLATFORM_NAME:-Unknown}"
    print "Proxy: ${PROXY_ENABLED:-disabled}"
    print "Archive password: ${PASSWORD_ENABLED:-disabled}"
    print "Database/log command: $([[ -n "$BACKUP_DB_COMMAND" ]] && echo configured || echo none)"
    print ""
    print "Included paths:"
    for dir in "${DIRECTORIES[@]}"; do
        [[ -n "$dir" ]] && print "  - $dir"
    done
    print ""

    input "Create this backup job and run the first backup now? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || error "Backup job creation cancelled."
}

start_backup() {
    generate_remark
    generate_timer
    generate_template
    toggle_directories
    configure_proxy
    generate_platform
    ensure_common_dependencies
    generate_password
    review_backup_configuration
    generate_script
}
