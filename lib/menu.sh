menu() {
    update_os
    install_dependencies
    install_yq
    while true; do
        clear
        print "======== Backupable Menu [$VERSION] ========"
        print ""
        print "1️) Install Backupable"
        print "2) Remove All Backup Jobs"
        print "3) Run All Backup Scripts"
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
    print "Removing all backups and cron jobs..."

    rm -rf /root/*"$SCRIPT_SUFFIX" /root/*"$TAG"* /root/*_backupable.sh /root/ac-backup*.sh /root/*backupable*.sh

    crontab -l | grep -v "$SCRIPT_SUFFIX" | crontab -

    success "All backups and cron jobs have been removed."
    sleep 1
}

start_backup() {
    generate_remark
    generate_timer
    generate_template
    toggle_directories
    generate_platform
    generate_password
    generate_script
}
