# Backupable

Backupable is a maintained fork of the original `erfjab/Backuper` project for automated server backups and delivery to Telegram, Discord, or Gmail.

The project includes a Remnawave template and is currently maintained with a focus on predictable scheduling, safer handling of credentials, and deployments where Telegram or Discord require an outbound proxy.

## Features

- automated backup jobs with configurable intervals;
- Telegram, Discord, and Gmail delivery;
- optional HTTP/SOCKS proxy for Telegram and Discord;
- Telegram forum topic support;
- split archives for platform upload limits;
- optional ZIP password protection;
- custom paths and application-specific templates;
- Remnawave, X-ui, S-ui, Hiddify, Marzban, Marzneshin, and other templates;
- root-only generated job files and per-job locking;
- dependency checks for the selected scenario.

## Remnawave

The Remnawave template targets the standard local Docker deployment:

- Remnawave directory: `/opt/remnawave`;
- PostgreSQL container: `remnawave-db`.

Each run creates a PostgreSQL dump using the database container itself and archives the complete `/opt/remnawave` directory, including the deployment configuration, together with the dump.

External PostgreSQL deployments and non-standard container names are not currently handled automatically by this template. Use a custom backup job for those layouts.

## Installation

Review the repository before running a root-level backup tool, then clone and start it:

```bash
git clone https://github.com/AidarKhusainov/backupable.git
cd backupable
sudo bash backupable.sh
```

Backupable creates generated jobs under `/root` and installs them in root's crontab.

## Proxy support

Telegram and Discord delivery can use an HTTP, HTTPS, SOCKS4, SOCKS4a, SOCKS5, or SOCKS5h proxy. Credentials embedded in a proxy URL are treated as secrets and are not echoed during interactive setup.

This is useful on servers where direct access to Telegram or Discord is unavailable.

## Security notes

- Backupable must run as root because application data and database configuration are commonly root-readable only.
- Generated backup jobs may contain delivery credentials and, for some legacy templates, database credentials. Generated job files and runtime state are therefore restricted to root.
- Do not paste generated job files, `.env` files, bot tokens, proxy URLs, webhooks, or database credentials into public issues.
- ZIP password protection should not be treated as a replacement for modern authenticated encryption.
- Backup archives can contain highly sensitive application state. Protect the destination account and test your recovery procedure.

## Scheduling

Backupable supports intervals from 1 to 1440 minutes. Root cron invokes scheduled jobs once per minute, while each job keeps private runtime state and runs only after its configured interval has elapsed. `flock` prevents overlapping executions of the same job.

The first backup is executed before the cron entry is installed. If that run fails, the schedule is not installed.

## Development checks

```bash
bash -n backupable.sh lib/*.sh
shellcheck -s bash --severity=error backupable.sh lib/*.sh
```

The same checks run in GitHub Actions.

## Project origin and licensing status

This repository is a maintained GitHub fork of `erfjab/Backuper`. The original repository is currently unavailable through its public GitHub page, but its commit history remains part of this fork.

The upstream project was published without an explicit software license, and this fork does not claim to relicense inherited code. That means the licensing status must be resolved with the original copyright holder before this fork can accurately be presented as an open-source replacement in directories that require an explicit open-source project.

Until that is resolved, contributions should avoid assuming that inherited code is available under MIT, Apache-2.0, GPL, or another standard license.

## Attribution

Original project: `erfjab/Backuper`.

Current maintenance and additional hardening: AidarKhusainov.

The legacy Persian README is available in [readme-fa.md](readme-fa.md) and may lag behind the current English documentation.
