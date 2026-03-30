# Tines Installer (Self-Hosted Linux)

Bash installer wrapper for deploying **Tines self-hosted** from the **official Docker Compose bundle**.

## Start here

1. Read the Tines docs first:
   - Installation guide: https://www.tines.com/docs/self-hosted/deploying-tines/docker-compose/tines-docker-compose-installation-guide/
   - Before you begin: https://www.tines.com/docs/self-hosted/before-you-begin/
   - Self-hosted overview: https://explained.tines.com/en/articles/12729997-can-i-set-up-a-self-hosted-tenant
2. Obtain your official self-hosted bundle from Tines (includes `setup.sh`, `upgrade.sh`, `.env.tmpl`, `docker-compose.yml`).
3. Copy `tines.conf.example` to `tines.conf` and fill in values.
4. Run dry-run validation before any real install.

> A valid Tines self-hosted license/entitlement is required. This project does not replace Tines licensing or official deployment scripts.

---

## What this installer does

- Wraps the **official Tines bundle** (does not replace it).
- Validates host and config before install.
- Supports guided and config-driven installs.
- Renders `.env` from `.env.tmpl` using a simplified config.
- Stages TLS certs (`tines.crt` / `tines.key`) where `setup.sh` expects them.
- Uses official scripts:
  - first install: `setup.sh`
  - upgrade: `upgrade.sh`

---

## Prerequisites

Target OS: Ubuntu 24.04

Required tools:
- docker
- docker compose **or** docker-compose
- curl
- unzip
- tar
- openssl
- netcat (`nc`)

Environment expectations from Tines docs:
- Linux host suitable for self-hosting
- Internet/DNS access for required artifacts
- Port 443 available or intentionally managed
- SMTP details for outbound email
- TLS certificates for production

---

## Quick start (config driven)

```bash
cp tines.conf.example tines.conf
# edit tines.conf

./tines-installer.sh --config ./tines.conf --non-interactive --dry-run
./tines-installer.sh --config ./tines.conf --non-interactive
```

---

## Guided usage

```bash
./tines-installer.sh --guided
```

Or launch with no flags to use menu mode:

1) Use existing config file  
2) Guided setup  
3) Generate sample config and exit  
4) Dry-run validation only

---

## CLI flags

- `--guided`
- `--config <path>`
- `--init-config`
- `--dry-run`
- `--non-interactive`
- `--install-dir <path>`
- `--bundle <path>`
- `--skip-docker-install`
- `--save-config <path>`
- `--force`
- `--help`

---

## Config file usage

The config format is simple `KEY="VALUE"` pairs.

Key fields:
- `BUNDLE_PATH` path to official bundle (directory, `.zip`, `.tar.gz`, `.tgz`)
- `TENANT_NAME`, `DOMAIN`
- SMTP keys (`SMTP_*`, `EMAIL_FROM_ADDRESS`)
- `DATABASE_PASSWORD`
- TLS options:
  - `TLS_MODE="self-signed"`
  - `TLS_MODE="provided"` + `TLS_CERT_PATH` / `TLS_KEY_PATH`
  - `TLS_MODE="none"` (not recommended)

Generate a starter file:

```bash
./tines-installer.sh --init-config
```

---

## Dry-run behavior

Dry-run performs validation only:
- no package installs
- no release extraction
- no file writes
- no `setup.sh` / `upgrade.sh` execution

Example:

```bash
./tines-installer.sh --config ./tines.conf --non-interactive --dry-run
```

Output uses:
- `[PASS]`
- `[WARN]`
- `[FAIL]`

---

## Upgrade usage

1. Put new official bundle on host.
2. Update `BUNDLE_PATH`.
3. Run dry-run.
4. Run installer normally.

```bash
./tines-installer.sh --config ./tines.conf --non-interactive --dry-run
./tines-installer.sh --config ./tines.conf --non-interactive
```

Installer uses `upgrade.sh` when an existing installation is detected.

---

## Directory layout

Default install root is `/opt/tines`:

```text
/opt/tines/
  releases/
    <timestamp>/
  shared/
    .env
    certs/
    backups/
  current -> /opt/tines/releases/<timestamp>/
```

---

## Safety notes

- This project is a wrapper around official Tines artifacts only.
- Do not modify vendor `setup.sh`, `upgrade.sh`, or `docker-compose.yml`.
- Always run dry-run first.
- Keep backups of `.env`, certs, and release bundles.
