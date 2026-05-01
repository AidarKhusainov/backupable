# Global constants
readonly SCRIPT_SUFFIX="_backupable_script.sh"
readonly TAG="_backupable."
readonly BACKUP_SUFFIX="${TAG}zip"
readonly DATABASE_SUFFIX="${TAG}sql"
readonly LOGS_SUFFIX="${TAG}log"
readonly VERSION="v0.6.0"


# ANSI color codes
declare -A COLORS=(
    [red]='\033[1;31m' [pink]='\033[1;35m' [green]='\033[1;92m'
    [spring]='\033[38;5;46m' [orange]='\033[1;38;5;208m' [cyan]='\033[1;36m' [reset]='\033[0m'
)
