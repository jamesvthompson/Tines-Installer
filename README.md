# Tines Self-Hosted One-Time Bootstrap Installer

A simple Bash bootstrap for one-time preparation of a Linux host before running the official Tines self-hosted Docker Compose installation bundle.

## Why this exists

Tines self-hosted environments are typically installed once and then managed using Tines-provided tooling and guidance. This project automates host prerequisites, configuration validation, and required file staging to reduce manual setup mistakes.

## Before you run this

This bootstrap is a helper around the official Tines self-hosted installation process, not a replacement.

Before using this repo:

1. Contact Tines first  
   Self-hosted customers should work with their Tines Account Executive (AE) or Customer Success Manager (CSM). Tines will connect you with the right technical resources for installation guidance, access to images, and self-hosted support.

2. Gather required deployment information  
   Have these values ready before you run the bootstrap:
   - tenant name
   - domain / FQDN
   - seed user details
   - SMTP settings
   - TLS certificate plan

3. Review the official Tines docs  
   - Before you begin: https://www.tines.com/docs/self-hosted/before-you-begin/
   - Docker Compose installation guide: https://www.tines.com/docs/self-hosted/deploying-tines/docker-compose/tines-docker-compose-installation-guide/
   - Self-hosted tenant overview: https://explained.tines.com/en/articles/12729997-can-i-set-up-a-self-hosted-tenant

## What this bootstrap does (and does not do)

This bootstrap helps with Linux-side preparation around the official Tines bundle.

It does:
- validate host preflight checks with PASS / WARN / FAIL output
- install missing prerequisites on Ubuntu 24.04 (optional)
- support guided setup, config-file mode, and a no-flags interactive menu
- validate supported bundle formats and required files
- stage the official bundle into one install directory
- copy `.env.tmpl` to `.env` and map conservative known config keys
- generate or copy `tines.crt` and `tines.key`
- run `bash setup.sh` from the staged install directory

It does not:
- grant self-hosted entitlement, bundle access, or Docker image access
- replace official Tines documentation or support guidance
- reimplement or replace `setup.sh` or `upgrade.sh`
- handle lifecycle or upgrade orchestration (use official `upgrade.sh` guidance)

## Prerequisites

You need:
- Ubuntu 24.04
- sudo/root access
- Official Tines self-hosted bundle (`.zip`, `.tar.gz`, `.tgz`, or extracted directory)
- Network access recommended for package installation and external checks

The bootstrap installs if missing:
- `curl`
- `unzip`
- `openssl`
- `netcat`
- `docker` (unless `--skip-docker-install` is used)
- Docker Compose plugin (`docker-compose-plugin`)

If Docker or Compose installation fails, follow: https://docs.docker.com/compose/install/linux/

## Get the official Tines bundle

From your Tines tenant:
- Go to `/settings/upgrade`
- Download the self-hosted package (named similar to `tines_<build_id>.zip`)
- The download link is short-lived (about 3 minutes)

Place the bundle on your target server.

## Quick start

### 1. Download the official Tines bundle

Use the instructions in **Get the official Tines bundle** and place the bundle on your target server.

### 2. Download the bootstrap script

```bash
wget https://raw.githubusercontent.com/jamesvthompson/Tines-Installer/main/tines-bootstrap.sh
chmod +x tines-bootstrap.sh
```

Or with curl:

```bash
curl -O https://raw.githubusercontent.com/jamesvthompson/Tines-Installer/main/tines-bootstrap.sh
chmod +x tines-bootstrap.sh
```

### 3. Run the bootstrap

Interactive (recommended):

```bash
./tines-bootstrap.sh
```

### 4. Optional: use a config file

```bash
cp ./tines.conf.example ./tines.conf
# edit values

./tines-bootstrap.sh --config ./tines.conf
```

### 5. Optional: dry-run first

```bash
./tines-bootstrap.sh --config ./tines.conf --dry-run
```

## Default no-flags flow

Running `./tines-bootstrap.sh` with no flags opens a menu:

1. Guided setup
2. Use config file
3. Generate sample config and exit
4. Exit

> No-flags mode requires an interactive terminal (TTY). In non-interactive environments, use `--config` with optional `--non-interactive`.

After guided answers or config loading, the script asks whether to run a dry-run preflight first:
- If dry-run passes, you can choose to continue to install or exit.
- If dry-run fails, install does not continue.
- If you skip dry-run, install proceeds directly.

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

## Dry-run usage

```bash
./tines-bootstrap.sh --config ./tines.conf --dry-run
```

Dry-run performs preflight validation only. It does **not** install packages, write files, permanently extract bundles, or run `setup.sh`.
When `--dry-run` is explicitly passed, it always exits after validation.

## Guided usage (expert/direct flag)

```bash
./tines-bootstrap.sh --guided
```

No-flags behavior is menu-driven (see **Default no-flags flow** above).

## Flags (expert/direct use)

These flags are kept for direct usage and automation:

- `--guided`
- `--config <path>`
- `--init-config`
- `--dry-run`
- `--non-interactive`
- `--install-dir <path>`
- `--bundle <path>`
- `--skip-docker-install`
- `--save-config <path>`
- `--help`

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

## Install directory model

This bootstrap follows the documented Tines Docker Compose model:

- one install directory
- official bundle extracted there
- `.env` lives there
- `tines.crt` and `tines.key` live there
- `bash setup.sh` runs there

In other words, the install directory used by `setup.sh` must contain the official bundle files plus `.env` and TLS files. This bootstrap stages those items accordingly.

## License

MIT (see [`LICENSE`](./LICENSE)).
