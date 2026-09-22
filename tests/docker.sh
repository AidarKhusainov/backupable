#!/usr/bin/env bash
set -euo pipefail

[[ "$EUID" -eq 0 ]] || { echo "docker integration tests must run as root" >&2; exit 1; }
[[ "${BACKUPABLE_DOCKER_TESTS:-}" == "1" ]] || {
    echo "refusing to run Docker integration tests without BACKUPABLE_DOCKER_TESTS=1" >&2
    exit 1
}

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/backupable-docker.XXXXXX)"
REMNAWAVE_DIR="$TEST_ROOT/remnawave"
DATA_DIR="$TEST_ROOT/data"
IMAGE="${BACKUPABLE_DOCKER_IMAGE:-backupable:test}"
DB_CONTAINER="remnawave-db"
SCHEDULER_CONTAINER="backupable-ci-scheduler"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

cleanup() {
    docker rm -f "$SCHEDULER_CONTAINER" >/dev/null 2>&1 || true
    docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

docker inspect "$DB_CONTAINER" >/dev/null 2>&1 &&
    fail "container $DB_CONTAINER already exists; refusing destructive test"
docker inspect "$SCHEDULER_CONTAINER" >/dev/null 2>&1 &&
    fail "container $SCHEDULER_CONTAINER already exists; refusing destructive test"

mkdir -p "$REMNAWAVE_DIR/config" "$DATA_DIR/delivery"
printf 'DATABASE_URL=postgresql://backupable:secret@remnawave-db:5432/remnawave\n' > "$REMNAWAVE_DIR/.env"
printf 'services:\n  remnawave-db:\n    image: postgres:16-alpine\n' > "$REMNAWAVE_DIR/docker-compose.yml"
printf 'docker-integration-config\n' > "$REMNAWAVE_DIR/config/app.conf"

cat > "$TEST_ROOT/setup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /app/lib/constants.sh
source /app/lib/ui.sh
source /app/lib/system.sh
source /app/lib/prompts.sh
source /app/lib/templates.sh
source /app/lib/script_generator.sh

confirm() { :; }
clear() { :; }

mkdir -p /var/lib/backupable/delivery

REMARK="docker_ci"
SCHEDULE_TYPE="daily"
SCHEDULE_TIME="${TEST_DAILY_TIME:?}"
SCHEDULE_TZ="UTC"
minutes=0
CAPTION="CI"
COMPRESS="zip -q -r -s 49m"
PLATFORM_COMMAND='cp "$FILE" /var/lib/backupable/delivery/'
DIRECTORIES=()
BACKUP_DB_COMMAND=""

remnawave_template
generate_script
EOF
chmod 0755 "$TEST_ROOT/setup.sh"

echo "[TEST] build Docker image"
docker build -t "$IMAGE" "$REPO_ROOT"

echo "[TEST] start PostgreSQL fixture"
docker run -d --name "$DB_CONTAINER" \
    -e POSTGRES_USER=backupable \
    -e POSTGRES_PASSWORD=secret \
    -e POSTGRES_DB=remnawave \
    postgres:16-alpine >/dev/null

ready=false
for _ in {1..30}; do
    if [[ "$(docker exec "$DB_CONTAINER" psql -U backupable -d remnawave -tAc 'SELECT 1' 2>/dev/null || true)" == "1" ]]; then
        ready=true
        break
    fi
    sleep 1
done
[[ "$ready" == true ]] || fail "PostgreSQL fixture did not become ready"

docker exec "$DB_CONTAINER" psql -U backupable -d remnawave -v ON_ERROR_STOP=1 -c \
    "CREATE TABLE backupable_docker_ci(id integer PRIMARY KEY, value text); INSERT INTO backupable_docker_ci VALUES (1, 'docker-integration-ok');" \
    >/dev/null

daily_time="$(date -u -d '-1 minute' +%H:%M)"
expected_slot="$(date -u -d "$(date -u -d '-1 minute' +%F) $daily_time:00" +%s)"

echo "[TEST] generate Remnawave job inside Backupable container"
docker run --rm \
    -e TEST_DAILY_TIME="$daily_time" \
    -e BACKUPABLE_BACKUP_DIR=/var/lib/backupable/jobs \
    -e BACKUPABLE_STATE_DIR=/var/lib/backupable/state \
    -e BACKUPABLE_SCHEDULER_MODE=internal \
    -e BACKUPABLE_SOURCE_LABEL=docker-ci \
    -v "$DATA_DIR:/var/lib/backupable" \
    -v "$REMNAWAVE_DIR:/opt/remnawave:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$TEST_ROOT/setup.sh:/tmp/setup.sh:ro" \
    "$IMAGE" bash /tmp/setup.sh

job="$DATA_DIR/jobs/_docker_ci_backupable_script.sh"
state="$DATA_DIR/state/docker_ci.last-run"
[[ -x "$job" ]] || fail "generated Docker-mode job not found"
[[ -f "$state" ]] || fail "Docker-mode state file not found"
[[ "$(cat "$state")" == "$expected_slot" ]] || fail "Docker-mode daily state is not anchored to the expected fixed slot"

archive="$(find "$DATA_DIR/delivery" -maxdepth 1 -type f -name '*docker_ci_backupable.zip' -print -quit)"
[[ -n "$archive" ]] || fail "Docker-mode delivered archive not found"

unzip -Z1 "$archive" | grep -Fxq "opt/remnawave/.env" || fail ".env missing from Docker archive"
unzip -Z1 "$archive" | grep -Fxq "opt/remnawave/docker-compose.yml" || fail "compose file missing from Docker archive"
unzip -Z1 "$archive" | grep -Fxq "opt/remnawave/config/app.conf" || fail "config file missing from Docker archive"

sql_path="$(unzip -Z1 "$archive" | grep -E '(^|/)_docker_ci_backupable\.sql$' | head -n 1)"
[[ -n "$sql_path" ]] || fail "PostgreSQL dump missing from Docker archive"
unzip -p "$archive" "$sql_path" | grep -Fq "docker-integration-ok" ||
    fail "Docker PostgreSQL dump does not contain fixture data"

echo "[TEST] verify container status and Docker socket health"
docker run --rm \
    -v "$DATA_DIR:/var/lib/backupable" \
    "$IMAGE" status | grep -Fq "docker_ci" || fail "status command does not list configured job"

docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$IMAGE" /app/docker/healthcheck.sh

echo "[TEST] verify internal scheduler executes persisted job"
initial_count="$(find "$DATA_DIR/delivery" -maxdepth 1 -type f -name '*docker_ci_backupable.zip' | wc -l)"
printf '0\n' > "$state"
sleep 2

docker run -d --name "$SCHEDULER_CONTAINER" \
    -e BACKUPABLE_BACKUP_DIR=/var/lib/backupable/jobs \
    -e BACKUPABLE_STATE_DIR=/var/lib/backupable/state \
    -e BACKUPABLE_SCHEDULER_MODE=internal \
    -e BACKUPABLE_POLL_SECONDS=1 \
    -e BACKUPABLE_SOURCE_LABEL=docker-ci \
    -v "$DATA_DIR:/var/lib/backupable" \
    -v "$REMNAWAVE_DIR:/opt/remnawave:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$IMAGE" >/dev/null

scheduled=false
for _ in {1..10}; do
    current_count="$(find "$DATA_DIR/delivery" -maxdepth 1 -type f -name '*docker_ci_backupable.zip' | wc -l)"
    if (( current_count > initial_count )); then
        scheduled=true
        break
    fi
    sleep 1
done
[[ "$scheduled" == true ]] || {
    docker logs "$SCHEDULER_CONTAINER" >&2 || true
    fail "internal scheduler did not execute persisted job"
}
[[ "$(cat "$state")" == "$expected_slot" ]] || fail "Docker scheduler recorded execution time instead of the fixed daily slot"

post_schedule_count="$(find "$DATA_DIR/delivery" -maxdepth 1 -type f -name '*docker_ci_backupable.zip' | wc -l)"
sleep 2
final_count="$(find "$DATA_DIR/delivery" -maxdepth 1 -type f -name '*docker_ci_backupable.zip' | wc -l)"
[[ "$final_count" == "$post_schedule_count" ]] || fail "Docker scheduler executed the same daily slot more than once"

echo "[PASS] Backupable Docker integration test suite"
