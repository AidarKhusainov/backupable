ovnode_template() {
    log "Checking OvNode configuration..."

    local OPENVPN_DB_FOLDER="/etc/openvpn"
    local OVNODE_DB_FOLDER="/opt/ov-node"

    # Check if the database file exists
    if [ ! -f "$OPENVPN_DB_FOLDER" ]; then
        error "OpenVPN file not found: $OPENVPN_DB_FOLDER"
        return 1
    fi
    if [ ! -f "$OVNODE_DB_FOLDER" ]; then
        error "Database file not found: $OVNODE_DB_FOLDER"
        return 1
    fi

    # Add the database file to BACKUP_DIRECTORIES
    add_directories "$OPENVPN_DB_FOLDER"
    add_directories "$OVNODE_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete OvNode"
    confirm
}

pasarguard_template() {
    log "Checking PasarGuard configuration..."
    local env_file="/opt/pasarguard/.env"

    [[ -f "$env_file" ]] || { error "Environment file not found: $env_file"; return 1; }

    local db_type db_name db_user db_password db_host db_port
    local BACKUP_DIRECTORIES=("/var/lib/pasarguard")

    local DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")
    log "Detected DATABASE_URL: $DATABASE_URL"
    if [[ -z "$DATABASE_URL" || "$DATABASE_URL" == *"sqlite"* ]]; then
        db_type="sqlite"
        db_name=""
        db_user=""
        db_password=""
        db_host=""
        db_port=""
    else
        if [[ "$DATABASE_URL" =~ ^(postgresql|postgres|timescaledb)(\+[a-z0-9]+)?://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]}"
            [[ "$db_type" == "postgres" ]] && db_type="postgresql"
            [[ "$db_type" == "timescaledb" ]] && db_type="postgresql"
            db_user="${BASH_REMATCH[3]}"
            db_password="${BASH_REMATCH[4]}"
            db_host="${BASH_REMATCH[5]}"
            db_port="${BASH_REMATCH[6]}"
            db_name="${BASH_REMATCH[7]}"
        elif [[ "$DATABASE_URL" =~ ^(postgresql|postgres|timescaledb)(\+[a-z0-9]+)?://([^:]+):([^@]+)@([^/]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]}"
            [[ "$db_type" == "postgres" ]] && db_type="postgresql"
            [[ "$db_type" == "timescaledb" ]] && db_type="postgresql"
            db_user="${BASH_REMATCH[3]}"
            db_password="${BASH_REMATCH[4]}"
            db_host="${BASH_REMATCH[5]}"
            db_port="5432"
            db_name="${BASH_REMATCH[6]}"
        elif [[ "$DATABASE_URL" =~ ^(mysql|mariadb)(\+[a-z0-9]+)?://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]}"
            db_user="${BASH_REMATCH[3]}"
            db_password="${BASH_REMATCH[4]}"
            db_host="${BASH_REMATCH[5]}"
            db_port="${BASH_REMATCH[6]}"
            db_name="${BASH_REMATCH[7]}"
        elif [[ "$DATABASE_URL" =~ ^(mysql|mariadb)(\+[a-z0-9]+)?://([^:]+):([^@]+)@([^/]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]}"
            db_user="${BASH_REMATCH[3]}"
            db_password="${BASH_REMATCH[4]}"
            db_host="${BASH_REMATCH[5]}"
            db_port="3306"
            db_name="${BASH_REMATCH[6]}"
        else
            error "Invalid DATABASE_URL format in $env_file."
            return 1
        fi
    fi

    add_directories "/opt/pasarguard"
    add_directories "/var/lib/pasarguard"

    success "Database type: $db_type"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database host: $db_host"
    success "Database port: $db_port"
    success "Database name: $db_name"

    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"

    if [[ "$db_type" == "postgresql" ]]; then
        ensure_command docker "Docker is required for PasarGuard PostgreSQL backup and must be installed manually."
        local pg_container=$(docker ps --filter "ancestor=postgres" --filter "ancestor=timescaledb/timescaledb" --format "{{.Names}}" | head -n 1)
        if [[ -z "$pg_container" ]]; then
            pg_container=$(docker ps --filter "publish=$db_port" --format "{{.Names}}" | head -n 1)
        fi
        BACKUP_DB_COMMAND="docker exec -e PGPASSWORD='$db_password' $pg_container pg_dump -U $db_user -d '$db_name' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    elif [[ "$db_type" == "mysql" || "$db_type" == "mariadb" ]]; then
        ensure_command mysqldump
        BACKUP_DB_COMMAND="mysqldump --column-statistics=0 -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete PasarGuard"
    confirm
}


marzgozir_template() {
    log "Checking MarzGozir configuration..."

    local MARZGOZIR_DB_FOLDER="/opt/marzgozir/data"

    # Check if the database file exists
    if [ ! -f "$MARZGOZIR_DB_FOLDER" ]; then
        error "Database file not found: $MARZGOZIR_DB_FOLDER"
        return 1
    fi

    # Add the database file to BACKUP_DIRECTORIES
    add_directories "$MARZGOZIR_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete MarzGozir"
    confirm
}

remnawave_template() {
    log "Checking Remnawave configuration..."

    local REMNAWAVE_DR="/opt/remnawave"
    if [ ! -d "$REMNAWAVE_DR" ]; then
        error "Directory not found: $REMNAWAVE_DR"
        return 1
    fi

    env_file="/opt/remnawave/.env"
    if [ ! -f "$env_file" ]; then
        error "Environment file not found: $env_file"
        return 1
    fi

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^postgresql://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
        db_user="${BASH_REMATCH[1]}"
        db_password="${BASH_REMATCH[2]}"
        db_name="${BASH_REMATCH[5]}"
    else
        error "Invalid DATABASE_URL format in $env_file."
        return 1
    fi

    add_directories "$REMNAWAVE_DR"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database name: $db_name"

    local DB_PATH="/root/_${REMARK}_${db_name}.sql"

    ensure_command docker "Docker is required for Remnawave database backup and must be installed manually."
    BACKUP_DB_COMMAND="docker exec -e PGPASSWORD='$db_password' \$(docker ps --filter 'publish=6767' --format '{{.Names}}' | head -n 1) pg_dump -U $db_user '$db_name' > $DB_PATH"
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Remnawave"
    confirm

}


ovpanel_template() {
    log "Checking OvPanel configuration..."

    local OVPANEL_DB_FOLDER="/opt/ov-panel"

    # Check if the database file exists
    if [ ! -f "$OVPANEL_DB_FOLDER" ]; then
        error "Database file not found: $OVPANEL_DB_FOLDER"
        return 1
    fi


    # Add the database file to BACKUP_DIRECTORIES
    add_directories "$OVPANEL_DB_FOLDER/data"
    add_directories "$OVPANEL_DB_FOLDER/.env"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete OvPanel"
    confirm
}

holderbot_template() {
    log "Checking HolderBot configuration..."

    # Set default value for HOLDER_FOLDER if not set
    local HOLDER_FOLDER="${HOLDER_FOLDER:-/opt/holderbot/}"

    # Check if the directory exists
    if [ ! -d "$HOLDER_FOLDER" ]; then
        error "Directory not found: $HOLDER_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$HOLDER_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete HolderBot"
    confirm
}

walpanel_template() {
    log "Checking WalPanel configuration..."

    # Set default value for WALDB_FOLDER if not set
    local WALDB_FOLDER="/opt/walpanel/app/data"

    # Check if the directory exists
    if [ ! -d "$WALDB_FOLDER" ]; then
        error "Directory not found: $WALDB_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$WALDB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete WalPanel"
    confirm
}

phantom_template() {
    log "Checking Phantom configuration..."

    # Set default value for PHANTOM_FOLDER if not set
    local PHANTOM_FOLDER="/etc/phantom/config.db"

    # Check if the directory exists
    if [ ! -d "$PHANTOM_FOLDER" ]; then
        error "Directory not found: $PHANTOM_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$PHANTOM_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Phantom"
    confirm
}


xui_template() {
    log "Checking X-ui configuration..."

    # Set default value for XUI_DB_FOLDER if not set
    local XUI_DB_FOLDER="${XUI_DB_FOLDER:-/etc/x-ui}"

    # Check if the directory exists
    if [ ! -d "$XUI_DB_FOLDER" ]; then
        error "Directory not found: $XUI_DB_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$XUI_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete X-ui"
    confirm
}

sui_template() {
    log "Checking S-ui configuration..."

    # Set default value for XUI_DB_FOLDER if not set
    local SUI_DB_FOLDER="${SUI_DB_FOLDER:-/usr/local/s-ui/db}"

    # Check if the directory exists
    if [ ! -d "$SUI_DB_FOLDER" ]; then
        error "Directory not found: $SUI_DB_FOLDER"
        return 1
    fi

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$SUI_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete S-ui"
    confirm
}

marzneshin_logs_template() {
    log "Checking Marzneshin configuration..."
    local docker_compose_file="/etc/opt/marzneshin/docker-compose.yml"

    # Check if docker-compose file exists
    if [[ ! -f "$docker_compose_file" ]]; then
        error "Docker compose file not found: $docker_compose_file"
        return 1
    fi

    # Define log file path
    local DB_PATH="/root/_${REMARK}${LOGS_SUFFIX}"

    # Check if marzneshin command exists
    ensure_command marzneshin "marzneshin command is required for Marzneshin logs backup and must be installed manually."
    if ! command -v marzneshin &> /dev/null; then
        error "marzneshin command not found. Please ensure it is installed."
        return 1
    fi

    # Run marzneshin logs command
    if ! marzneshin logs --no-follow > "$DB_PATH"; then
        error "Failed to export Marzneshin logs to $DB_PATH"
        return 1
    fi

    # Add log file path to DIRECTORIES
    DIRECTORIES=()
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Marzneshin logs backup completed successfully."
    confirm
}

marzneshin_template() {
    log "Checking Marzneshin configuration..."
    local docker_compose_file="/etc/opt/marzneshin/docker-compose.yml"

    # Check if docker-compose file exists
    [[ -f "$docker_compose_file" ]] || { error "Docker compose file not found: $docker_compose_file"; return 1; }

    # Extract database configuration
    local db_type db_name db_password db_port
    ensure_command yq
    DB_TYPE=$(yq eval '.services.db.image' "$docker_compose_file")
    DB_NAME=$(yq eval '.services.db.environment.MARIADB_DATABASE // .services.db.environment.MYSQL_DATABASE' "$docker_compose_file")
    DB_PASSWORD=$(yq eval '.services.db.environment.MARIADB_ROOT_PASSWORD // .services.db.environment.MYSQL_ROOT_PASSWORD' "$docker_compose_file")
    DB_PORT=$(yq eval '.services.db.ports[0]' "$docker_compose_file" | cut -d':' -f2)

    # Determine database type
    if [[ "$DB_TYPE" == *"mariadb"* ]]; then
        DB_TYPE="mariadb"
    elif [[ "$DB_TYPE" == *"mysql"* ]]; then
        DB_TYPE="mysql"
    else
        DB_TYPE="sqlite"
    fi

    # Validate database password for non-sqlite databases
    if [[ "$DB_TYPE" != "sqlite" && -z "$DB_PASSWORD" ]]; then
        error "Database password not found"
        return 1
    fi

    # Setup backup configuration
    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    DIRECTORIES=()

    # Scan default DIRECTORIES
    log "Scanning DIRECTORIES..."
    add_directories "/etc/opt/marzneshin"

    # Extract volumes from docker-compose
    log "Extracting volumes from docker-compose..."
    for service in $(yq eval '.services | keys | .[]' "$docker_compose_file"); do
        for volume in $(yq eval ".services.$service.volumes | .[]" "$docker_compose_file" 2>/dev/null | awk -F ':' '{print $1}'); do
            [[ -d "$volume" && ! "$volume" =~ /(mysql|mariadb)$ ]] && add_directories "$volume"
        done
    done

    # Generate backup command for non-sqlite databases
    if [[ "$DB_TYPE" != "sqlite" ]]; then
        ensure_command mysqldump
        BACKUP_DB_COMMAND="mysqldump -h 127.0.0.1 --column-statistics=0 -P $DB_PORT -u root -p'$DB_PASSWORD' '$DB_NAME' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Marzneshin"
    confirm
}

marzban_logs_template() {
    log "Checking Marzban configuration..."
    local docker_compose_file="/opt/marzban/docker-compose.yml"

    # Check if docker-compose file exists
    if [[ ! -f "$docker_compose_file" ]]; then
        error "Docker compose file not found: $docker_compose_file"
        return 1
    fi

    # Define log file path
    local DB_PATH="/root/_${REMARK}${LOGS_SUFFIX}"

    # Check if marzban command exists
    ensure_command marzban "marzban command is required for Marzban logs backup and must be installed manually."
    if ! command -v marzban &> /dev/null; then
        error "marzban command not found. Please ensure it is installed."
        return 1
    fi

    # Run marzban logs command
    if ! marzban logs --no-follow > "$DB_PATH"; then
        error "Failed to export marzban logs to $DB_PATH"
        return 1
    fi

    # Add log file path to DIRECTORIES
    DIRECTORIES=()
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "marzban logs backup completed successfully."
    confirm
}

marzban_template() {
    log "Checking environment file..."
    local env_file="/opt/marzban/.env"

    [[ -f "$env_file" ]] || { error "Environment file not found: $env_file"; return 1; }

    local db_type db_name db_user db_password db_host db_port
    local BACKUP_DIRECTORIES=("/var/lib/marzban")  # Add default volume

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ -z "$SQLALCHEMY_DATABASE_URL" || "$SQLALCHEMY_DATABASE_URL" == *"sqlite3"* ]]; then
        db_type="sqlite3"
        db_name=""
        db_user=""
        db_password=""
        db_host=""
        db_port=""
    else
        # Parse SQLALCHEMY_DATABASE_URL to extract database details
        if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
            db_user="${BASH_REMATCH[2]}"
            db_password="${BASH_REMATCH[3]}"
            db_host="${BASH_REMATCH[4]}"
            db_port="${BASH_REMATCH[5]}"
            db_name="${BASH_REMATCH[6]}"
        elif [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([0-9.]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
            db_user="${BASH_REMATCH[2]}"
            db_password="${BASH_REMATCH[3]}"
            db_host="${BASH_REMATCH[4]}"
            db_port="3306"  # Default MySQL/MariaDB port
            db_name="${BASH_REMATCH[5]}"
        else
            error "Invalid SQLALCHEMY_DATABASE_URL format in $env_file."
            return 1
        fi
    fi
    add_directories "/opt/marzban"
    add_directories "/var/lib/marzban"
    success "Database type: $db_type"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database host: $db_host"
    success "Database port: $db_port"
    success "Database name: $db_name"

    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    # Generate backup command for MySQL/MariaDB
    if [[ "$db_type" != "sqlite3" ]]; then
        ensure_command mysqldump
        BACKUP_DB_COMMAND="mysqldump --column-statistics=0 -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Marzban"
    confirm
}


rebecca_template() {
    log "Checking environment file..."
    local env_file="/opt/rebecca/.env"

    [[ -f "$env_file" ]] || { error "Environment file not found: $env_file"; return 1; }

    local db_type db_name db_user db_password db_host db_port
    local BACKUP_DIRECTORIES=("/var/lib/rebecca")  # Add default volume

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ -z "$SQLALCHEMY_DATABASE_URL" || "$SQLALCHEMY_DATABASE_URL" == *"sqlite3"* ]]; then
        db_type="sqlite3"
        db_name=""
        db_user=""
        db_password=""
        db_host=""
        db_port=""
    else
        # Parse SQLALCHEMY_DATABASE_URL to extract database details
        if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
            db_user="${BASH_REMATCH[2]}"
            db_password="${BASH_REMATCH[3]}"
            db_host="${BASH_REMATCH[4]}"
            db_port="${BASH_REMATCH[5]}"
            db_name="${BASH_REMATCH[6]}"
        elif [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([0-9.]+)/(.+)$ ]]; then
            db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
            db_user="${BASH_REMATCH[2]}"
            db_password="${BASH_REMATCH[3]}"
            db_host="${BASH_REMATCH[4]}"
            db_port="3306"  # Default MySQL/MariaDB port
            db_name="${BASH_REMATCH[5]}"
        else
            error "Invalid SQLALCHEMY_DATABASE_URL format in $env_file."
            return 1
        fi
    fi
    add_directories "/opt/rebecca"
    add_directories "/var/lib/rebecca"
    success "Database type: $db_type"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database host: $db_host"
    success "Database port: $db_port"
    success "Database name: $db_name"

    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    # Generate backup command for MySQL/MariaDB
    if [[ "$db_type" != "sqlite3" ]]; then
        ensure_command mysqldump
        BACKUP_DB_COMMAND="mysqldump --column-statistics=0 -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
        DIRECTORIES+=($DB_PATH)
    fi

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete Rebecca"
    confirm
}


marzhelp_template() {
    log "Checking environment file..."
    local env_file="/opt/marzban/.env"

    [[ -f "$env_file" ]] || { error "Environment file not found: $env_file"; exit 1; }

    # Check for MYSQL_ROOT_PASSWORD in .env
    local MYSQL_ROOT_PASSWORD=$(grep -v '^#' "$env_file" | grep 'MYSQL_ROOT_PASSWORD' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        error "MYSQL_ROOT_PASSWORD not found in $env_file. Please add it to the Marzban env file."
        exit 1
    fi

    local db_type db_name db_user db_password db_host db_port
    local BACKUP_DIRECTORIES=("/var/lib/marzban")  # Add default volume

    # Extract SQLALCHEMY_DATABASE_URL from .env file
    local SQLALCHEMY_DATABASE_URL=$(grep -v '^#' "$env_file" | grep 'SQLALCHEMY_DATABASE_URL' | awk -F '=' '{print $2}' | tr -d ' ' | tr -d '"' | tr -d "'")

    if [[ -z "$SQLALCHEMY_DATABASE_URL" || "$SQLALCHEMY_DATABASE_URL" == *"sqlite3"* ]]; then
        error "SQLite database detected. This script only supports MySQL/MariaDB databases."
        exit 1
    fi

    # Parse SQLALCHEMY_DATABASE_URL to extract database details
    if [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([^:]+):([0-9]+)/(.+)$ ]]; then
        db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
        db_user="${BASH_REMATCH[2]}"
        db_password="${BASH_REMATCH[3]}"
        db_host="${BASH_REMATCH[4]}"
        db_port="${BASH_REMATCH[5]}"
        db_name="${BASH_REMATCH[6]}"
    elif [[ "$SQLALCHEMY_DATABASE_URL" =~ ^(mysql\+pymysql|mariadb\+pymysql)://([^:]+):([^@]+)@([0-9.]+)/(.+)$ ]]; then
        db_type="${BASH_REMATCH[1]%%+*}"  # Extract mysql or mariadb
        db_user="${BASH_REMATCH[2]}"
        db_password="${BASH_REMATCH[3]}"
        db_host="${BASH_REMATCH[4]}"
        db_port="3306"  # Default MySQL/MariaDB port
        db_name="${BASH_REMATCH[5]}"
    else
        error "Invalid SQLALCHEMY_DATABASE_URL format in $env_file."
        exit 1
    fi

    # Check if marzhelp database exists
    log "Checking if marzhelp database exists..."
    ensure_command mysqlshow
    ensure_command mysqldump
    if ! mysqlshow -h "$db_host" -P "$db_port" -u root -p"$MYSQL_ROOT_PASSWORD" marzhelp &>/dev/null; then
        error "marzhelp database not found or not accessible. Please ensure it exists and you have proper permissions."
        exit 1
    fi

    local MARZHELP_DB_PATH="/root/__${REMARK}${DATABASE_SUFFIX}"
    local MARZHELP_BACKUP_COMMAND="mysqldump -h $db_host -P $db_port -u root -p'$MYSQL_ROOT_PASSWORD' 'marzhelp' > $MARZHELP_DB_PATH"
    BACKUP_COMMANDS+=("$MARZHELP_BACKUP_COMMAND")
    DIRECTORIES+=("$MARZHELP_DB_PATH")

    add_directories "/opt/marzban"
    DIRECTORIES+=("/root/marzhelp.txt")
    add_directories "/var/lib/marzban"
    success "Database type: $db_type"
    success "Database user: $db_user"
    success "Database password: $db_password"
    success "Database host: $db_host"
    success "Database port: $db_port"
    success "Database name: $db_name"
    success "MarzHelp database exists and is accessible"

    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    # Generate backup command for MySQL/MariaDB
    BACKUP_DB_COMMAND="mysqldump -h $db_host -P $db_port -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    BACKUP_DB_COMMAND="$BACKUP_DB_COMMAND && $MARZHELP_BACKUP_COMMAND"  # Combine both commands
    log "Complete Marzban + MarzHelp"
    confirm
}

mirzabot_template() {
    log "Checking MirzaBot file..."
    local mirzabot_file='/var/www/html/mirzabotconfig/config.php'

    [[ -f "$mirzabot_file" ]] || { error "MirzaBot file not found: $mirzabot_file"; return 1; }

    # Extract database values from config.php
    db_name=$(grep -m 1 "\$dbname" $mirzabot_file | sed -E "s/.*dbname\s*=\s*'([^']+)'.*/\1/")
    db_user=$(grep -m 1 "\$usernamedb" $mirzabot_file | sed -E "s/.*usernamedb\s*=\s*'([^']+)'.*/\1/")
    db_password=$(grep -m 1 "\$passworddb" $mirzabot_file | sed -E "s/.*passworddb\s*=\s*'([^']+)'.*/\1/")

    # Check if the values are extracted correctly
    if [ -z "$db_name" ] || [ -z "$db_password" ] || [ -z "$db_user" ]; then
        error "Failed to extract database values from $mirzabot_file."
        exit 1
    fi

    # Generate backup command for MySQL/MariaDB
    ensure_command mysqldump
    local DB_PATH="/root/_${REMARK}${DATABASE_SUFFIX}"
    BACKUP_DB_COMMAND="mysqldump -u $db_user -p'$db_password' '$db_name' > $DB_PATH"
    DIRECTORIES+=($DB_PATH)

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Complete MirzaBot"
    confirm
}

hiddify_template() {
    log "Checking Hiddify configuration..."

    # Set default value for HIDDIFY_DB_FOLDER if not set
    local HIDDIFY_DB_FOLDER="/opt/hiddify-manager/hiddify-panel/backup.sh"
    local BACKUP_FOLDER="/opt/hiddify-manager/hiddify-panel/backup"

    # Check if the backup script exists
    if [ ! -f "$HIDDIFY_DB_FOLDER" ]; then
        error "Backup script not found: $HIDDIFY_DB_FOLDER"
        return 1
    fi

    # Create backup directory if it doesn't exist
    if [ ! -d "$BACKUP_FOLDER" ]; then
        log "Creating backup directory: $BACKUP_FOLDER"
        mkdir -p "$BACKUP_FOLDER"
        if [ $? -ne 0 ]; then
            error "Failed to create backup directory: $BACKUP_FOLDER"
            return 1
        fi
    fi

    # Set full access permissions to the backup directory and script
    log "Setting permissions for backup directory and script..."
    chmod -R 755 "$BACKUP_FOLDER"
    chmod 755 "$HIDDIFY_DB_FOLDER"

    # Add the directory to BACKUP_DIRECTORIES
    add_directories "$BACKUP_FOLDER"

    # Set the backup command
    BACKUP_DB_COMMAND="bash $HIDDIFY_DB_FOLDER"

    # Export backup variables
    BACKUP_DIRECTORIES="${DIRECTORIES[*]}"
    log "Hiddify configuration completed successfully."
    confirm
}
