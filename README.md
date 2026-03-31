# Tines Self-Hosted One-Time Bootstrap Installer

A simple Bash bootstrap for one-time preparation of a Linux host before running the official Tines self-hosted Docker Compose installation bundle.

## Why this exists

Tines self-hosted environments are typically installed once and then managed using Tines-provided tooling and guidance. This project saves time by automating host prerequisites, configuration validation, and required file staging to reduce manual setup mistakes.

This project **does not replace** the official Tines install process. It is a thin wrapper around the official bundle and runs `bash setup.sh` from that bundle.

## Before you run this

This bootstrap is a thin wrapper around the official Tines self-hosted installation bundle. It does not replace the documented Tines installation process.

Before using this repo:

1. Contact Tines first  
   Self-hosted customers should work with their Tines Account Executive or Customer Success Manager first. Tines will connect you with the right technical resources for installation guidance, access to images, and self-hosted support.

2. Confirm access to the official self-hosted package  
   Tines Support enables access to the installation package for your tenant. Once enabled, the package URL is available from `/settings/upgrade` in your Tines cloud tenant. The download URL is valid for 3 minutes, and the package is named similar to `tines_<build id>.zip`.

3. Gather the required deployment information  
   Before running the bootstrap, have these values ready:
   - tenant name
   - domain / FQDN
   - seed user details
   - SMTP settings
   - TLS certificate plan

4. Make sure the target host is appropriate  
   This bootstrap is intended for Ubuntu 24.04 and assumes sudo/root access for package installation and writing the install directory.

5. Review the official Tines docs first  
   - Before you begin: https://www.tines.com/docs/self-hosted/before-you-begin/
   - Docker Compose installation guide: https://www.tines.com/docs/self-hosted/deploying-tines/docker-compose/tines-docker-compose-installation-guide/
   - Self-hosted tenant overview: https://explained.tines.com/en/articles/12729997-can-i-set-up-a-self-hosted-tenant

## What this bootstrap automates

This bootstrap helps with the Linux-side setup around the official Tines bundle:

- validates host preflight checks with PASS / WARN / FAIL output
- optionally installs missing prerequisites on Ubuntu 24.04
- supports guided setup, config-file mode, and a no-flags interactive menu
- validates the official Tines bundle format and required files
- stages the official bundle into one install directory
- copies `.env.tmpl` to `.env` and maps conservative known config keys
- generates or copies `tines.crt` and `tines.key`
- detects `docker compose` (preferred) and falls back to `docker-compose` when available
- runs `bash setup.sh` from the install directory

## What you still need from Tines

This repo does not provide:
- access to self-hosted entitlement
- access to the official bundle or Docker images
- replacement instructions for `setup.sh` or `upgrade.sh`

You still need the official Tines self-hosted resources and should follow Tines guidance for upgrades and support.

## Prerequisites

- Target OS: Ubuntu 24.04
- Root/sudo access
- Official Tines self-hosted bundle (`.zip`, `.tar.gz`, `.tgz`, or extracted directory)
- Network access recommended for package installation and external checks

The bootstrap installs missing:
- `curl`
- `unzip`
- `openssl`
- `netcat`
- `docker` (unless `--skip-docker-install` is used)
- Docker Compose plugin (`docker-compose-plugin`) when compose is missing

If Docker or Compose installation fails, follow the official Docker installation guide:
https://docs.docker.com/compose/install/linux/

## Install directory model

This bootstrap follows the documented Tines Docker Compose model:

- one install directory
- official bundle extracted there
- `.env` lives there
- `tines.crt` and `tines.key` live there
- `bash setup.sh` runs there

In other words, the install directory used by `setup.sh` must contain the official bundle files plus `.env` and TLS files. This bootstrap stages those items accordingly.

## Quick start

### 1. Download the official Tines bundle

From your Tines tenant:

- Go to `/settings/upgrade`
- Download the self-hosted package (`tines_<build_id>.zip`)
- Note: the download link is valid for ~3 minutes

Place the bundle on your target server.

---

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

You will be prompted for:

- bundle path
- tenant/domain
- SMTP settings
- TLS mode

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

Notes:

- The bootstrap stages the bundle and runs `bash setup.sh` (official Tines installer)
- This does not replace Tines documentation or support processes
- Always follow Tines guidance for upgrades

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
