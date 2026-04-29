#!/bin/bash

APP_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

source "$APP_ROOT/lib/constants.sh"
source "$APP_ROOT/lib/ui.sh"
source "$APP_ROOT/lib/system.sh"
source "$APP_ROOT/lib/menu.sh"
source "$APP_ROOT/lib/prompts.sh"
source "$APP_ROOT/lib/templates.sh"
source "$APP_ROOT/lib/platforms.sh"
source "$APP_ROOT/lib/script_generator.sh"

main() {
    clear
    check_root
    menu
}

main
