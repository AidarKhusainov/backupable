# Backupable

![Backupable preview](assets/backupable-preview.webp)

Backupable is a maintained fork of `erfjab/Backuper`. It creates scheduled server backups and sends them to Telegram, Discord, or Gmail.

Remnawave is supported directly. Telegram and Discord delivery can also use an HTTP or SOCKS proxy.

## Features

- fixed daily wall-clock schedules with explicit IANA timezones;
- configurable legacy backup intervals;
- Telegram, Discord, and Gmail delivery;
- HTTP/SOCKS proxy support for Telegram and Discord;
- Telegram forum topics;
- split archives for platform upload limits;
- optional ZIP password protection;
- Remnawave and other application templates;
- per-job locking and root-only generated files.

## Remnawave

The built-in Remnawave template targets the standard local Docker deployment:

- files under `/opt/remnawave`;
- PostgreSQL container named `remnawave-db`.

A backup includes the full `/opt/remnawave` directory and a PostgreSQL dump created inside `remnawave-db`.

External PostgreSQL deployments and custom container names are not detected automatically. Use a custom job for those layouts.

## Installation

### Native

```bash
git clone https://github.com/AidarKhusainov/backupable.git
cd backupable
sudo bash backupable.sh
```

Native mode stores generated jobs under `/root` and uses root's crontab.

### Docker Compose

Docker mode is a convenient option for the standard Remnawave deployment. It uses an internal scheduler, so no host cron setup is needed.

```bash
mkdir -p /opt/backupable
cd /opt/backupable

curl -fsSLo compose.yaml \
  https://raw.githubusercontent.com/AidarKhusainov/backupable/master/compose.yaml

docker compose pull
docker compose up -d
docker compose run --rm backupable setup
```

Jobs and scheduler state are stored in the `backupable-data` volume.

Useful commands:

```bash
docker compose exec backupable backupable status
docker compose exec backupable backupable backup-now
docker compose logs -f backupable

docker compose pull
docker compose up -d
```

The image is published as `ghcr.io/aidarkhusainov/backupable:latest` for amd64 and arm64.

Docker mode mounts `/opt/remnawave` read-only and mounts `/var/run/docker.sock` so Backupable can run `pg_dump` inside `remnawave-db`. Docker socket access is effectively root-level access to the host.

## Proxy support

Telegram and Discord support HTTP, HTTPS, SOCKS4, SOCKS4a, SOCKS5, and SOCKS5h proxies.

Proxy credentials are treated as secrets and are not echoed during setup.

## Scheduling

New jobs can use one of two scheduling modes:

- **Daily at a fixed local time** (recommended): choose an `HH:MM` wall-clock time and an explicit IANA timezone such as `UTC`, `Europe/Moscow`, or `Europe/Stockholm`.
- **Interval mode**: the legacy behavior, from 1 to 1440 minutes between successful runs.

Native mode uses root cron as a one-minute poller. Docker mode uses the internal scheduler with the same polling model. The generated job decides whether its schedule is due.

Daily scheduling is slot-based rather than `last success + 24h`. For example, a job scheduled for `00:00` that fails and finally succeeds at `00:07` records the `00:00` slot as completed, so the next scheduled run is still `00:00` the following day. Failed scheduled runs are retried on the next scheduler tick without moving the next slot.

If Backupable was stopped when a daily slot occurred, the most recent missed slot is run once after startup. It does not replay every missed day. Manual `backup-now` runs do not consume or shift a daily scheduled slot.

`flock` prevents overlapping runs of the same job. A job is registered only after its first backup succeeds.

## Security notes

- Backupable runs with root-level access because backups can include root-readable application data.
- Generated jobs may contain delivery credentials and, for some legacy templates, database credentials. Job files and runtime state are restricted to root.
- Do not post generated jobs, `.env` files, tokens, proxy URLs, webhooks, or database credentials in public issues.
- ZIP passwords are not a replacement for modern authenticated encryption.
- Test restore procedures, not just backup creation.
- Docker mode uses the Docker socket and therefore has root-equivalent access to the host.

## Development

Static checks:

```bash
bash -n backupable.sh lib/*.sh docker/*.sh tests/*.sh
shellcheck -s bash --severity=error backupable.sh lib/*.sh docker/*.sh tests/*.sh
```

CI also runs two integration suites:

- native Remnawave backup flow with a real PostgreSQL container;
- Docker image build and runtime flow, including the internal scheduler.

Telegram, Discord, proxy, and Gmail setup are tested with local mocks, so CI does not require real delivery credentials.

## Project origin and license

Backupable continues the original `erfjab/Backuper` project history and keeps attribution to the upstream project.

Licensed under the [MIT License](LICENSE).

## Attribution

Original project: `erfjab/Backuper`.

Current maintenance: AidarKhusainov.
