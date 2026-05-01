# Utility functions
check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        error "Unsupported package manager"
    fi
}

package_for_command() {
    local command_name="$1"
    local package_manager="$2"

    case "$command_name" in
        crontab)
            case "$package_manager" in
                apt) echo "cron" ;;
                dnf|yum|pacman) echo "cronie" ;;
            esac
            ;;
        pg_dump)
            case "$package_manager" in
                apt) echo "postgresql-client" ;;
                dnf|yum|pacman) echo "postgresql" ;;
            esac
            ;;
        mysqldump|mysqlshow)
            case "$package_manager" in
                apt) echo "default-mysql-client" ;;
                dnf|yum|pacman) echo "mariadb" ;;
            esac
            ;;
        *) echo "$command_name" ;;
    esac
}

install_package() {
    local package_manager=$(detect_package_manager)
    local package_name="$1"

    log "Installing package: $package_name"

    case $package_manager in
        apt)
            apt-get update || error "Failed to update package index"
            if [[ "$package_name" == "default-mysql-client" ]]; then
                apt-get install -y default-mysql-client || apt-get install -y mariadb-client || error "Failed to install MySQL/MariaDB client"
            else
                apt-get install -y "$package_name" || error "Failed to install package: $package_name"
            fi
            ;;
        dnf|yum)
            $package_manager install -y "$package_name" || error "Failed to install package: $package_name"
            ;;
        pacman)
            pacman -Sy --noconfirm "$package_name" || error "Failed to install package: $package_name"
            ;;
    esac
    success "Package installed: $package_name"
}

install_yq() {
    if command -v yq &>/dev/null; then
        success "yq is already installed."
        return
    fi

    log "Installing yq..."
    local ARCH=$(uname -m)
    local YQ_BINARY="yq_linux_amd64"

    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && YQ_BINARY="yq_linux_arm64"

    wget -q "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -O /usr/bin/yq || error "Failed to download yq."
    chmod +x /usr/bin/yq || error "Failed to set execute permissions on yq."

    success "yq installed successfully."
}

ask_install_package() {
    local command_name="$1"
    local package_name="$2"
    local answer

    warn "Missing required command: $command_name"
    input "Install package '$package_name'? [y/N]: " answer

    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

ensure_command() {
    local command_name="$1"
    local manual_message="${2:-}"
    local package_manager package_name

    if command -v "$command_name" &>/dev/null; then
        return
    fi

    if [[ -n "$manual_message" ]]; then
        error "$manual_message"
    fi

    if [[ "$command_name" == "yq" ]]; then
        ensure_command wget
        ask_install_package yq "yq" || error "Missing required command: yq"
        install_yq
    else
        package_manager=$(detect_package_manager)
        package_name=$(package_for_command "$command_name" "$package_manager")
        ask_install_package "$command_name" "$package_name" || error "Missing required command: $command_name"
        install_package "$package_name"
    fi

    command -v "$command_name" &>/dev/null || error "Command is still unavailable after installation: $command_name"
}

ensure_common_dependencies() {
    ensure_command zip
    ensure_command crontab
}
