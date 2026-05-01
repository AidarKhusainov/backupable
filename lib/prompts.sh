generate_remark() {
    clear
    print "Step 1/8: Backup job name\n"
    print "This name is used in generated files and the cron entry (e.g., main_server, panel_1).\n"

    while true; do
        input "Enter a remark: " REMARK

        if ! [[ "$REMARK" =~ ^[a-zA-Z0-9_]+$ ]]; then
            wrong "Remark must contain only letters, numbers, or underscores."
        elif [ ${#REMARK} -lt 3 ]; then
            wrong "Remark must be at least 3 characters long."
        elif [ -e "${REMARK}${SCRIPT_SUFFIX}" ]; then
            wrong "File ${REMARK}${SCRIPT_SUFFIX} already exists. Choose a different remark."
        else
            success "Backup remark: $REMARK"
            break
        fi
    done
    sleep 1
}

generate_caption() {
    clear
    print "Additional caption\n"
    print "You can add a caption for your backup file (e.g., 'The main server of the company').\n"

    input "Enter your caption (Press Enter to skip): " CAPTION

    if [ -z "$CAPTION" ]; then
        success "No caption provided. Skipping..."
        CAPTION=""
    else
        CAPTION+='\n'
        success "Caption set: $CAPTION"
    fi

    sleep 1
}

generate_timer() {
    clear
    print "Step 2/8: Schedule\n"
    print "Choose how often the backup job should run."
    print "For example, '10' means every 10 minutes.\n"

    while true; do
        input "Enter the number of minutes (1-1440): " minutes

        if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
            wrong "Please enter a valid number."
        elif [ "$minutes" -lt 1 ] || [ "$minutes" -gt 1440 ]; then
            wrong "Number must be between 1 and 1440."
        else
            break
        fi
    done

    if [ "$minutes" -le 59 ]; then
        TIMER="*/$minutes * * * *"
    elif [ "$minutes" -le 1439 ]; then
        hours=$((minutes / 60))
        remaining_minutes=$((minutes % 60))
        if [ "$remaining_minutes" -eq 0 ]; then
            TIMER="0 */$hours * * *"
        else
            TIMER="*/$remaining_minutes */$hours * * *"
        fi
    else
        TIMER="0 0 * * *"
    fi
    success "Cron job set to run every $minutes minutes: $TIMER"
    sleep 1
}

generate_template() {
    clear
    print "Step 3/8: Backup template\n"
    print "Select the app/service whose data should be backed up."
    print "You can add or remove paths in the next step.\n"
    print "1) X-ui"
    print "2) S-ui"
    print "3) Hiddify"
    print "4) Remnawave"
    print "5) Rebecca"
    print "6) Marzneshin"
    print "7) Marzneshin Logs"
    print "8) Marzban"
    print "9) Marzban Logs"
    print "10) MirzaBot"
    print "11) Walpanel"
    print "12) HolderBot"
    print "13) MarzHelp + Marzban"
    print "14) Phantom"
    print "15) OvPanel"
    print "16) OvNode"
    print "17) MarzGozir"
    print "18) PasarGuard"
    print "0) Custom"
    print ""
    while true; do
        input "Enter your template number: " TEMPLATE
        case $TEMPLATE in
            1)
                TEMPLATE_NAME="X-ui"
                xui_template
                break
                ;;
            2)
                TEMPLATE_NAME="S-ui"
                sui_template
                break
                ;;
            3)
                TEMPLATE_NAME="Hiddify"
                hiddify_template
                break
                ;;
            4)
                TEMPLATE_NAME="Remnawave"
                remnawave_template
                break
                ;;
            5)
                TEMPLATE_NAME="Rebecca"
                rebecca_template
                break
                ;;
            6)
                TEMPLATE_NAME="Marzneshin"
                marzneshin_template
                break
                ;;
            7)
                TEMPLATE_NAME="Marzneshin Logs"
                marzneshin_logs_template
                break
                ;;
            8)
                TEMPLATE_NAME="Marzban"
                marzban_template
                break
                ;;
            9)
                TEMPLATE_NAME="Marzban Logs"
                marzban_logs_template
                break
                ;;
            10)
                TEMPLATE_NAME="MirzaBot"
                mirzabot_template
                break
                ;;
            11)
                TEMPLATE_NAME="Walpanel"
                walpanel_template
                break
                ;;
            12)
                TEMPLATE_NAME="HolderBot"
                holderbot_template
                break
                ;;
            13)
                TEMPLATE_NAME="MarzHelp + Marzban"
                marzhelp_template
                break
                ;;
            14)
                TEMPLATE_NAME="Phantom"
                phantom_template
                break
                ;;
            15)
                TEMPLATE_NAME="OvPanel"
                ovpanel_template
                break
                ;;
            16)
                TEMPLATE_NAME="OvNode"
                ovnode_template
                break
                ;;
            17)
                TEMPLATE_NAME="MarzGozir"
                marzgozir_template
                break
                ;;
            18)
                TEMPLATE_NAME="PasarGuard"
                pasarguard_template
                break
                ;;
            0)
                TEMPLATE_NAME="Custom"
                break
                ;;
            *)
                wrong "Invalid option. Please choose a valid number!"
                ;;
        esac
    done
}

add_directories() {
    local base_dir="$1"

    # Check if base directory exists
    [[ ! -d "$base_dir" ]] && { warn "Directory not found: $base_dir"; return; }

    # Find directories and filter based on exclude patterns
    mapfile -t items < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d \( -name "*mysql*" -prune -o -name "*mariadb*" -prune \) -o -print)

    for item in "${items[@]}"; do
        local exclude_item=false

        # Check if item matches any exclude pattern
        for pattern in "${exclude_patterns[@]}"; do
            if [[ "$item" =~ $pattern ]]; then
                exclude_item=true
                break
            fi
        done

        # Add item to backup list if it doesn't match any exclude pattern
        if ! $exclude_item; then
            success "Added to backup: $item"
            DIRECTORIES+=("$item")
        fi
    done
}

toggle_directories() {
    clear
    print "Step 4/8: Included paths\n"
    print "Review auto-detected paths. Enter a path to add/remove it, or type 'done' when finished.\n"

    while true; do
        print "\nCurrent directories:"
        for dir in "${DIRECTORIES[@]}"; do
            [[ -n "$dir" ]] && success "\t- $dir"
        done
        print ""

        input "Enter a path (or 'done' to finish): " path

        if [[ "$path" == "done" ]]; then
            break
        elif [[ ! -e "$path" ]]; then
            wrong "Path does not exist: $path"
        elif [[ " ${DIRECTORIES[*]} " =~ " ${path} " ]]; then
            DIRECTORIES=("${DIRECTORIES[@]/$path}")
            success "Removed from list: $path"
        else
            DIRECTORIES+=("$path")
            success "Added to list: $path"
        fi
    done
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
}
