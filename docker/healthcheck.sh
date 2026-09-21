#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUPABLE_BACKUP_DIR:-/var/lib/backupable/jobs}"
STATE_DIR="${BACKUPABLE_STATE_DIR:-/var/lib/backupable/state}"

[[ -d "$BACKUP_DIR" && -w "$BACKUP_DIR" ]]
[[ -d "$STATE_DIR" && -w "$STATE_DIR" ]]
docker version --format '{{.Client.Version}}' >/dev/null
