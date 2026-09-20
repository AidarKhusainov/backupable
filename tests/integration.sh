#!/usr/bin/env bash
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "integration tests must run as root" >&2; exit 1; }
[[ "${BACKUPABLE_INTEGRATION_TESTS:-}" == "1" ]] || {
    echo "refusing to run destructive integration tests without BACKUPABLE_INTEGRATION_TESTS=1" >&2
    exit 1
}

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/backupable-integration.XXXXXX)"
DELIVERY_DIR="$TEST_ROOT/delivery"
RUN_LOG="$TEST_ROOT/runs.log"
FAKE_BIN="$TEST_ROOT/bin"
ORIGINAL_CRONTAB="$(crontab -l 2>/dev/null || true)"

export REPO_ROOT TEST_ROOT DELIVERY_DIR RUN_LOG FAKE_BIN
mkdir -p "$DELIVERY_DIR" "$FAKE_BIN"
: > "$RUN_LOG"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_file() {
    [[ -f "$1" ]] || fail "expected file: $1"
}

assert_not_file() {
    [[ ! -f "$1" ]] || fail "unexpected file: $1"
}

assert_contains() {
    local file="$1"
    local value="$2"
    grep -Fq -- "$value" "$file" || fail "expected '$value' in $file"
}

restore_crontab() {
    if [[ -n "$ORIGINAL_CRONTAB" ]]; then
        printf '%s\n' "$ORIGINAL_CRONTAB" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
}

cleanup() {
    docker rm -f remnawave-db >/dev/null 2>&1 || true
    rm -rf /opt/remnawave
    rm -f /root/_ci_*_backupable_script.sh /root/*_ci_*_backupable.* 2>/dev/null || true
    rm -rf /root/.backupable
    restore_crontab
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

[[ ! -e /opt/remnawave ]] || fail "/opt/remnawave already exists; refusing destructive test"
if docker inspect remnawave-db >/dev/null 2>&1; then
    fail "container remnawave-db already exists; refusing destructive test"
fi

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
success() { printf '[OK] %s\n' "$*"; }
wrong() { printf '[WRONG] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
confirm() { :; }
clear() { :; }
sleep() { command sleep "$@"; }

# shellcheck source=../lib/constants.sh
source "$REPO_ROOT/lib/constants.sh"
# shellcheck source=../lib/system.sh
source "$REPO_ROOT/lib/system.sh"
# shellcheck source=../lib/templates.sh
source "$REPO_ROOT/lib/templates.sh"
# shellcheck source=../lib/script_generator.sh
source "$REPO_ROOT/lib/script_generator.sh"

setup_remnawave_fixture() {
    echo "[TEST] set up Remnawave/PostgreSQL fixture"
    mkdir -p /opt/remnawave/config
    printf 'DATABASE_URL=postgresql://backupable:secret@remnawave-db:5432/remnawave\n' > /opt/remnawave/.env
    printf 'services:\n  remnawave-db:\n    image: postgres:16-alpine\n' > /opt/remnawave/docker-compose.yml
    printf 'integration-config\n' > /opt/remnawave/config/app.conf

    docker run -d --name remnawave-db \
        -e POSTGRES_USER=backupable \
        -e POSTGRES_PASSWORD=secret \
        -e POSTGRES_DB=remnawave \
        postgres:16-alpine >/dev/null

    local ready=false
    for _ in {1..30}; do
        if docker exec remnawave-db pg_isready -U backupable -d remnawave >/dev/null 2>&1; then
            ready=true
            break
        fi
        command sleep 1
    done
    [[ "$ready" == true ]] || fail "PostgreSQL fixture did not become ready"

    docker exec remnawave-db psql -U backupable -d remnawave -v ON_ERROR_STOP=1 -c \
        "CREATE TABLE backupable_ci(id integer PRIMARY KEY, value text); INSERT INTO backupable_ci VALUES (1, 'integration-ok');" \
        >/dev/null
}

generate_remnawave_job() {
    echo "[TEST] generate and execute real Remnawave backup job"
    (
        set -euo pipefail
        REMARK="ci_remnawave"
        minutes=90
        CAPTION="CI"
        COMPRESS="zip -q -r -s 49m"
        PLATFORM_COMMAND="cp \"\$FILE\" \"$DELIVERY_DIR/\" && printf 'run\\n' >> \"$RUN_LOG\""

        remnawave_template
        generate_script
    )
}

verify_remnawave_archive() {
    echo "[TEST] verify archive contents and PostgreSQL dump"
    local archive
    archive="$(find "$DELIVERY_DIR" -maxdepth 1 -type f -name '*ci_remnawave_backupable.zip' -print -quit)"
    [[ -n "$archive" ]] || fail "delivered Remnawave archive not found"

    unzip -Z1 "$archive" | grep -Fxq "opt/remnawave/.env" || fail ".env missing from archive"
    unzip -Z1 "$archive" | grep -Fxq "opt/remnawave/docker-compose.yml" || fail "docker-compose.yml missing from archive"
    unzip -Z1 "$archive" | grep -Fxq "opt/remnawave/config/app.conf" || fail "Remnawave config missing from archive"
    unzip -Z1 "$archive" | grep -Fxq "root/_ci_remnawave_backupable.sql" || fail "PostgreSQL dump missing from archive"
    unzip -p "$archive" "root/_ci_remnawave_backupable.sql" | grep -Fq "integration-ok" ||
        fail "PostgreSQL dump does not contain fixture data"

    assert_eq "700" "$(stat -c '%a' /root/_ci_remnawave_backupable_script.sh)" "generated job permissions"
    assert_eq "700" "$(stat -c '%a' /root/.backupable)" "state directory permissions"
    assert_file "/root/.backupable/ci_remnawave.last-run"
    assert_not_file "/root/_ci_remnawave_backupable.sql"
    crontab -l | grep -Fq "/root/_ci_remnawave_backupable_script.sh --scheduled" ||
        fail "generated cron entry missing"
}

verify_scheduler() {
    echo "[TEST] verify interval scheduler"
    local before after
    before="$(wc -l < "$RUN_LOG")"
    bash /root/_ci_remnawave_backupable_script.sh --scheduled
    after="$(wc -l < "$RUN_LOG")"
    assert_eq "$before" "$after" "job should be skipped before interval expires"

    printf '%s\n' "$(( $(date +%s) - 6000 ))" > /root/.backupable/ci_remnawave.last-run
    bash /root/_ci_remnawave_backupable_script.sh --scheduled
    after="$(wc -l < "$RUN_LOG")"
    assert_eq "$((before + 1))" "$after" "job should run after interval expires"
}

generate_lock_job() {
    echo "[TEST] verify per-job locking"
    local lock_payload="$TEST_ROOT/lock-payload.txt"
    printf 'lock-test\n' > "$lock_payload"

    (
        set -euo pipefail
        REMARK="ci_lock"
        minutes=1
        CAPTION="CI"
        DIRECTORIES=("$lock_payload")
        BACKUP_DB_COMMAND=""
        COMPRESS="zip -q -r -s 49m"
        PLATFORM_COMMAND="sleep 2; printf 'lock-run\\n' >> \"$RUN_LOG\""
        generate_script
    )

    : > "$RUN_LOG"
    printf '%s\n' "$(( $(date +%s) - 120 ))" > /root/.backupable/ci_lock.last-run

    bash /root/_ci_lock_backupable_script.sh --scheduled &
    local first_pid=$!
    command sleep 0.3
    bash /root/_ci_lock_backupable_script.sh --scheduled &
    local second_pid=$!

    wait "$first_pid"
    wait "$second_pid"

    assert_eq "1" "$(grep -c '^lock-run$' "$RUN_LOG")" "flock should allow only one concurrent run"
}

verify_failed_first_run() {
    echo "[TEST] verify failed first run does not install cron or success state"
    local payload="$TEST_ROOT/failure-payload.txt"
    printf 'failure-test\n' > "$payload"

    if (
        set -euo pipefail
        REMARK="ci_failure"
        minutes=5
        CAPTION="CI"
        DIRECTORIES=("$payload")
        BACKUP_DB_COMMAND=""
        COMPRESS="zip -q -r -s 49m"
        PLATFORM_COMMAND="false"
        generate_script
    ); then
        fail "job generation unexpectedly succeeded with failing delivery"
    fi

    if crontab -l 2>/dev/null | grep -Fq "/root/_ci_failure_backupable_script.sh"; then
        fail "failed first run installed a cron entry"
    fi
    assert_not_file "/root/.backupable/ci_failure.last-run"
}

create_fake_delivery_commands() {
    cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_CURL_LOG:?}"
if [[ "$*" == *"discord.com/api/webhooks/"* ]]; then
    printf '204'
else
    printf '200'
fi
EOF

    cat > "$FAKE_BIN/msmtp" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$*" >> "${FAKE_MSMTP_LOG:?}"
exit 0
EOF

    cat > "$FAKE_BIN/mutt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_MUTT_LOG:?}"
exit 0
EOF

    chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/msmtp" "$FAKE_BIN/mutt"
}

verify_delivery_configuration() {
    echo "[TEST] verify Telegram, Discord, proxy, and Gmail configuration with local command mocks"
    create_fake_delivery_commands
    export PATH="$FAKE_BIN:$PATH"
    export FAKE_CURL_LOG="$TEST_ROOT/curl.log"
    export FAKE_MSMTP_LOG="$TEST_ROOT/msmtp.log"
    export FAKE_MUTT_LOG="$TEST_ROOT/mutt.log"
    : > "$FAKE_CURL_LOG"
    : > "$FAKE_MSMTP_LOG"
    : > "$FAKE_MUTT_LOG"

    # shellcheck source=../lib/platforms.sh
    source "$REPO_ROOT/lib/platforms.sh"

    secret_input() {
        local prompt="$1"
        local target="$2"
        case "$prompt" in
            *proxy*) printf -v "$target" '%s' 'socks5h://user:pass@127.0.0.1:1080' ;;
            *bot\ token*) printf -v "$target" '%s' '123456:abcdefghijklmnopqrstuvwxyzABCDEFGHI' ;;
            *Discord*) printf -v "$target" '%s' 'https://discord.com/api/webhooks/123/test-token' ;;
            *Gmail*) printf -v "$target" '%s' 'abcd efgh ijkl mnop' ;;
            *) fail "unexpected secret prompt: $prompt" ;;
        esac
    }

    input() {
        local prompt="$1"
        local target="$2"
        case "$prompt" in
            *chat\ ID*) printf -v "$target" '%s' '-1001234567890' ;;
            *topic\ ID*) printf -v "$target" '%s' '77' ;;
            *Gmail\ address*) printf -v "$target" '%s' 'backupable@example.com' ;;
            *) fail "unexpected input prompt: $prompt" ;;
        esac
    }

    sleep() { :; }

    configure_proxy
    telegram_progress
    [[ "$PLATFORM_COMMAND" == *"--proxy socks5h://user:pass@127.0.0.1:1080"* ]] ||
        fail "Telegram generated command does not contain proxy"
    [[ "$PLATFORM_COMMAND" == *"message_thread_id=77"* ]] ||
        fail "Telegram generated command does not contain topic ID"
    assert_contains "$FAKE_CURL_LOG" "api.telegram.org"

    discord_progress
    assert_eq "19" "$LIMITSIZE" "Discord split size"
    [[ "$PLATFORM_COMMAND" == *"--proxy socks5h://user:pass@127.0.0.1:1080"* ]] ||
        fail "Discord generated command does not contain proxy"
    assert_contains "$FAKE_CURL_LOG" "discord.com/api/webhooks/123/test-token"

    REMARK="ci_gmail"
    gmail_progress
    assert_file "/root/.backupable/ci_gmail.msmtprc"
    assert_file "/root/.backupable/ci_gmail.muttrc"
    assert_eq "600" "$(stat -c '%a' /root/.backupable/ci_gmail.msmtprc)" "msmtp config permissions"
    assert_eq "600" "$(stat -c '%a' /root/.backupable/ci_gmail.muttrc)" "mutt config permissions"
    assert_not_file "/root/.msmtprc"
    assert_not_file "/root/.muttrc"
    assert_contains "/root/.backupable/ci_gmail.msmtprc" "password abcdefghijklmnop"
    [[ "$PLATFORM_COMMAND" == *"/root/.backupable/ci_gmail.muttrc"* ]] ||
        fail "Gmail generated command does not use per-job mutt config"
}

setup_remnawave_fixture
generate_remnawave_job
verify_remnawave_archive
verify_scheduler
generate_lock_job
verify_failed_first_run
verify_delivery_configuration

echo "[PASS] Backupable integration test suite"
