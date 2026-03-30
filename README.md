# Tines Self-Hosted One-Time Bootstrap Installer

A simple Bash bootstrap for one-time preparation of a Linux host before running the official Tines self-hosted Docker Compose installation bundle.

## Why this exists

Tines self-hosted environments are typically installed once and then managed using Tines-provided tooling and guidance. This project saves time by automating host prerequisites, configuration validation, and required file staging to reduce manual setup mistakes.

This project **does not replace** the official Tines install process. It is a thin wrapper around the official bundle and runs `bash setup.sh` from that bundle.

## Before you run this

- Self-hosted customers should contact their Tines AE or CSM first.
- Tines provides access to official installation resources and support guidance.
- Read these first:
  - https://www.tines.com/docs/self-hosted/before-you-begin/
  - https://www.tines.com/docs/self-hosted/deploying-tines/docker-compose/tines-docker-compose-installation-guide/
  - https://explained.tines.com/en/articles/12729997-can-i-set-up-a-self-hosted-tenant

## Official package access

- Tines Support enables package access for your tenant.
- The package URL is available from `/settings/upgrade` in your Tines cloud tenant.
- The download URL is valid for **3 minutes**.
- The package is named similar to `tines_<build id>.zip`.

## What this bootstrap does

1. Validates host preflight checks with `PASS / WARN / FAIL` output.
2. Optionally installs missing prerequisites on Ubuntu 24.04.
3. Supports guided mode, config-file mode, and a no-flags interactive menu.
4. Validates the official Tines bundle format and required files.
5. Stages the official bundle into one install directory.
6. Copies `.env.tmpl` to `.env` and maps conservative known config keys.
7. Generates or copies `tines.crt` and `tines.key`.
8. Detects `docker compose` (preferred) and falls back to `docker-compose` when available.
9. Runs `bash setup.sh` from the install directory.

## Prerequisites

- Target OS: Ubuntu 24.04 (script fails on unsupported OS).
- Root/sudo access for package installation and writing install directory.
- Official Tines self-hosted bundle (`.zip`, `.tar.gz`, `.tgz`, or extracted directory).
- Network access recommended for package install and external checks.
- The bootstrap installs missing `curl`, `unzip`, `openssl`, `netcat`, `docker` (unless `--skip-docker-install`), and the Docker Compose plugin (`docker-compose-plugin`) when compose is missing.
- If Docker or Compose installation fails, follow the official Docker installation guide: https://docs.docker.com/compose/install/linux/

## Quick start

```bash
chmod +x ./tines-bootstrap.sh
cp ./tines.conf.example ./tines.conf
# edit ./tines.conf
./tines-bootstrap.sh --config ./tines.conf
```

## Config file example

Use flat `KEY="VALUE"` lines only. Comments (`#`) and blank lines are allowed.

```bash
INSTALL_DIR="/opt/tines"
BUNDLE_PATH="/path/to/tines_<build_id>.zip"

TENANT_NAME="my-tines"
DOMAIN="tines.example.com"

SEED_EMAIL="admin@example.com"
SEED_FIRST_NAME="Admin"
SEED_LAST_NAME="User"
SEED_PASSWORD="ChangeMe123!"

SMTP_SERVER="smtp.gmail.com"
SMTP_PORT="587"
SMTP_DOMAIN="gmail.com"
SMTP_USERNAME="admin@example.com"
SMTP_PASSWORD="app-password"
EMAIL_FROM_ADDRESS="admin@example.com"

DATABASE_PASSWORD="TinesDbPass123"

APP_SECRET_TOKEN=""

TLS_MODE="self-signed"
TLS_CERT_PATH=""
TLS_KEY_PATH=""
```

## Dry-run usage

```bash
./tines-bootstrap.sh --config ./tines.conf --dry-run
```

Dry-run performs preflight validation only. It does **not** install packages, write files, permanently extract bundles, or run `setup.sh`.

## Guided usage

```bash
./tines-bootstrap.sh --guided
```

If no flags are provided, the script displays a simple menu for config, guided mode, sample config generation, or dry-run.

## Non-interactive usage

```bash
./tines-bootstrap.sh --config ./tines.conf --non-interactive
```

In `--non-interactive` mode, the script fails early unless required values are present:
- `INSTALL_DIR`
- `BUNDLE_PATH`
- `TENANT_NAME`
- `DOMAIN`
- `DATABASE_PASSWORD`
- `TLS_MODE`

If `TLS_MODE="provided"`, `TLS_CERT_PATH` and `TLS_KEY_PATH` are also required.

## Bundle formats

Supported `BUNDLE_PATH` formats:
- extracted directory
- `.zip`
- `.tar.gz`
- `.tgz`

## Config format expectations

Safe config-file format:
- flat `KEY="VALUE"` lines only
- only double-quoted values are supported (`KEY="VALUE"`)
- no single quotes
- no inline comments after values
- keys must be uppercase
- comments allowed (lines beginning with `#`)
- blank lines allowed
- strict format (invalid lines fail fast)

## TLS modes

- `self-signed` (bootstrap generates `tines.crt` and `tines.key`)
- `provided` (bootstrap copies `TLS_CERT_PATH` and `TLS_KEY_PATH`)
- `none` (bootstrap warns and does not stage cert/key)

## Install directory staging model (supportability)

This bootstrap intentionally follows the official model:

- one install directory
- official bundle extracted there
- `.env` lives there
- `tines.crt` and `tines.key` live there
- `bash setup.sh` runs there

In other words, the install directory used by `setup.sh` must contain the official bundle files plus `.env` and TLS files. This bootstrap stages those items accordingly.

## Notes about supportability

- This script does **not** reimplement or replace `setup.sh` or `upgrade.sh`.
- This script does **not** implement lifecycle/upgrade orchestration.
- Upgrades should follow official Tines documentation and the official `upgrade.sh` flow.
- A systemd unit is optional operational preference and not part of this bootstrap.

## License

MIT (see [`LICENSE`](./LICENSE)).
