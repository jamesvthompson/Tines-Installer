# Tines Installer (Self-Hosted, Linux)

A production-oriented Bash installer for deploying **Tines self-hosted** with the **official Docker Compose installation package**.

> This project intentionally treats the official Tines bundle as the source of truth. It does **not** generate custom container architecture or replace Tines `setup.sh` / `upgrade.sh`.

---

## What this installer does

- Supports **guided interactive** setup and **config-driven** setup.
- Supports **non-interactive** automation (`--config --non-interactive`).
- Supports **dry-run preflight** validation (`--dry-run`) with `[PASS]/[WARN]/[FAIL]` output.
- Generates `.env` from `.env.tmpl` using a simplified config abstraction.
- Runs official Tines scripts:
  - `bash setup.sh` for first install
  - `bash upgrade.sh` for upgrades
- Supports TLS modes:
  - `self-signed`
  - `provided`
  - `none`
- Optionally installs a systemd unit for service lifecycle control.

---

## External requirements (from Tines self-hosted docs)

Before installation, ensure the host/environment meets the expected Tines self-hosted requirements:

1. **Linux host** (this installer validates for Ubuntu 24.04).
2. **Docker Engine** installed and daemon running.
3. **Docker Compose plugin** (`docker compose`) installed.
4. **Internet access** from the host.
5. **Port 443** available/reachable for HTTPS.
6. **SMTP server** details available (recommended for production).
7. **TLS certificate files** available as `tines.crt` and `tines.key` (or let installer generate self-signed certs).
8. **Official Tines installation bundle** available and containing:
   - `setup.sh`
   - `upgrade.sh`
   - `.env.tmpl`
   - `docker-compose.yml`
   - bundled image archives (as provided by Tines)

> You are responsible for obtaining the official Tines bundle and any required license/access artifacts from Tines.

---

## Repository files

- `tines-installer.sh` — main installer script.
- `tines.conf.example` — sample configuration file.

---

## Quick start

### 1) Prepare host

On your Ubuntu 24.04 host, make sure basic tools are available:

- `bash`
- `curl`
- `unzip`
- `openssl`
- `netcat` (`nc`)
- `docker`
- `docker compose`

The installer validates these requirements and can attempt package installation for missing dependencies (unless `--skip-docker-install` is provided for Docker).

### 2) Create config from template

```bash
cp tines.conf.example tines.conf
```

Edit `tines.conf` with your tenant/domain/SMTP/database/TLS values.

### 3) Run dry-run first (recommended)

```bash
./tines-installer.sh --config ./tines.conf --non-interactive --dry-run
```

Dry-run performs full validation without writing files, installing packages, or running Tines setup scripts.

### 4) Run install

```bash
./tines-installer.sh --config ./tines.conf --non-interactive
```

If you prefer interactive setup:

```bash
./tines-installer.sh --guided
```

---

## CLI usage

```bash
./tines-installer.sh [options]
```

### Supported flags

- `--guided` — guided interactive setup.
- `--config <path>` — load config file.
- `--init-config` — generate sample config and exit.
- `--dry-run` — run validations only.
- `--non-interactive` — disable prompts (requires `--config`).
- `--install-dir <path>` — override install root (default `/opt/tines`).
- `--bundle <path>` — path to official Tines bundle (`.zip`, `.tar.gz`, `.tgz`, or extracted directory).
- `--skip-docker-install` — do not attempt Docker installation if missing.
- `--save-config <path>` — persist in-memory config to a file.
- `--force` — allow overwrite behavior in conflict scenarios.
- `--help` — print help.

---

## Install directory layout

By default, files are managed under `/opt/tines`:

```text
/opt/tines/
  releases/
    <version-or-timestamp>/
  shared/
    .env
    certs/
    backups/
  current -> /opt/tines/releases/<version-or-timestamp>
```

---

## Configuration model

The installer consumes a simplified key/value config (`tines.conf`).

Important keys include:

- Core: `INSTALL_DIR`, `TENANT_NAME`, `DOMAIN`, `BUNDLE_PATH`
- Seed user: `SEED_EMAIL`, `SEED_FIRST_NAME`, `SEED_LAST_NAME`, `SEED_PASSWORD`
- SMTP: `SMTP_SERVER`, `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `EMAIL_FROM_ADDRESS`
- Database: `DATABASE_PASSWORD`
- Secrets: `APP_SECRET_TOKEN`, `TELEMETRY_ID`
- TLS: `TLS_MODE`, `TLS_CERT_PATH`, `TLS_KEY_PATH`
- Runtime: `AUTO_START`, `USE_SYSTEMD`, `RESTART_POLICY`

### `.env` mapping behavior

- Installer copies official `.env.tmpl` to managed `.env`.
- Known keys are mapped from config (for example, `SMTP_USERNAME` -> `SMTP_USER_NAME`).
- Unknown `.env` keys from the template are preserved.
- If `APP_SECRET_TOKEN` is blank, installer generates one with:

```bash
openssl rand -hex 64
```

---

## Validation behavior

Preflight outputs:

- `[PASS]` informational success
- `[WARN]` non-blocking issue (install can continue)
- `[FAIL]` blocking issue (install stops)

Checks include:

- OS version
- CPU/RAM/disk thresholds
- Dependency presence
- Docker/Compose/daemon readiness
- Internet and port 443 status
- Required config fields and TLS mode
- Official bundle structure

---

## TLS behavior

- `TLS_MODE="self-signed"`:
  - Generates `tines.crt` and `tines.key` in shared cert directory.
- `TLS_MODE="provided"`:
  - Copies existing cert/key from configured file paths.
- `TLS_MODE="none"`:
  - Skips TLS provisioning (not recommended for production).

---

## Upgrade flow

To upgrade with a new official Tines bundle:

1. Update `BUNDLE_PATH` to the new bundle.
2. Run dry-run.
3. Run installer normally.
4. Installer updates release symlink and invokes official `upgrade.sh` when prior releases are detected.

Example:

```bash
./tines-installer.sh --config ./tines.conf --non-interactive --dry-run
./tines-installer.sh --config ./tines.conf --non-interactive
```

---

## Post-install operations

If `USE_SYSTEMD="true"`, installer writes and enables:

- `/etc/systemd/system/tines.service`

Common commands:

```bash
sudo systemctl status tines
sudo systemctl start tines
sudo systemctl stop tines
```

If systemd is disabled, manage directly from the current release directory:

```bash
cd /opt/tines/current
docker compose up -d
docker compose down
```

---

## Safety notes

- Always run `--dry-run` before first install and upgrades.
- Do not edit official Tines `setup.sh`, `upgrade.sh`, or `docker-compose.yml`.
- Keep backups of your managed `.env`, certs, and release bundles.
- Prefer valid CA-issued TLS certs and production SMTP configuration.

