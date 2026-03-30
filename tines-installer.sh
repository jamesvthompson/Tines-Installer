#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"

DRY_RUN=false
GUIDED=false
NON_INTERACTIVE=false
INIT_CONFIG=false
SKIP_DOCKER_INSTALL=false
FORCE=false

CONFIG_FILE=""
BUNDLE_PATH=""
SAVE_CONFIG_PATH=""
INSTALL_DIR="/opt/tines"

# Simplified config defaults
TENANT_NAME=""
DOMAIN=""
SEED_EMAIL="admin@example.com"
SEED_FIRST_NAME="Admin"
SEED_LAST_NAME="User"
SEED_PASSWORD=""
SMTP_SERVER=""
SMTP_PORT="587"
SMTP_DOMAIN=""
SMTP_USERNAME=""
SMTP_PASSWORD=""
EMAIL_FROM_ADDRESS=""
DATABASE_PASSWORD=""
APP_SECRET_TOKEN=""
TELEMETRY_ID=""
TLS_MODE="self-signed"
TLS_CERT_PATH=""
TLS_KEY_PATH=""
AUTO_START="true"
USE_SYSTEMD="true"
RESTART_POLICY="unless-stopped"

FAIL_COUNT=0
WARN_COUNT=0

log_info() { printf '[INFO] %s\n' "$*"; }
log_pass() { printf '[PASS] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
log_fail() { printf '[FAIL] %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

die() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

print_help() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --guided                    Run guided interactive setup
  --config <path>             Load configuration file
  --init-config               Generate sample config and exit
  --dry-run                   Validate only (no writes, installs, or setup.sh)
  --non-interactive           Disable prompts; requires --config
  --install-dir <path>        Override install directory (default: /opt/tines)
  --bundle <path>             Path to official Tines bundle (.zip, .tar.gz, or dir)
  --skip-docker-install       Skip Docker install attempt if missing
  --save-config <path>        Save current config values to file
  --force                     Overwrite existing release directory if needed
  --help                      Show this help
USAGE
}

init_sample_config() {
  local target="${1:-tines.conf.example}"
  cat > "$target" <<'CONF'
INSTALL_DIR="/opt/tines"

TENANT_NAME="my-tines"
DOMAIN="tines.local"

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
TELEMETRY_ID=""

TLS_MODE="self-signed"
TLS_CERT_PATH=""
TLS_KEY_PATH=""

AUTO_START="true"
USE_SYSTEMD="true"
RESTART_POLICY="unless-stopped"
CONF
  log_pass "Wrote sample config: $target"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --guided) GUIDED=true ;;
      --config) CONFIG_FILE="${2:-}"; shift ;;
      --init-config) INIT_CONFIG=true ;;
      --dry-run) DRY_RUN=true ;;
      --non-interactive) NON_INTERACTIVE=true ;;
      --install-dir) INSTALL_DIR="${2:-}"; shift ;;
      --bundle) BUNDLE_PATH="${2:-}"; shift ;;
      --skip-docker-install) SKIP_DOCKER_INSTALL=true ;;
      --save-config) SAVE_CONFIG_PATH="${2:-}"; shift ;;
      --force) FORCE=true ;;
      --help) print_help; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done

  if $NON_INTERACTIVE && [[ -z "$CONFIG_FILE" ]] && ! $INIT_CONFIG; then
    die "--non-interactive requires --config <path>"
  fi
}

menu_prompt() {
  echo "Welcome to the Tines Self-Hosted Installer"
  echo
  echo "1) Use existing config file"
  echo "2) Guided setup"
  echo "3) Generate sample config and exit"
  echo "4) Dry-run validation only"
  echo
  local choice
  read -r -p "Select an option [1-4]: " choice
  case "$choice" in
    1)
      read -r -p "Config path: " CONFIG_FILE
      ;;
    2)
      GUIDED=true
      ;;
    3)
      init_sample_config "tines.conf.example"
      exit 0
      ;;
    4)
      DRY_RUN=true
      if [[ -z "$CONFIG_FILE" ]]; then
        read -r -p "Config path (optional, press Enter to skip): " CONFIG_FILE
      fi
      ;;
    *)
      die "Invalid menu option: $choice"
      ;;
  esac
}

load_config() {
  local file="$1"
  [[ -f "$file" ]] || die "Config file not found: $file"
  # shellcheck disable=SC1090
  source "$file"
  log_pass "Loaded config: $file"
}

prompt_default() {
  local var_name="$1"
  local prompt="$2"
  local current="${!var_name:-}"
  local input
  if [[ -n "$current" ]]; then
    read -r -p "$prompt [$current]: " input || true
  else
    read -r -p "$prompt: " input || true
  fi
  if [[ -n "$input" ]]; then
    printf -v "$var_name" '%s' "$input"
  fi
}

guided_setup() {
  log_info "Running guided setup"
  prompt_default INSTALL_DIR "Install directory"
  prompt_default BUNDLE_PATH "Path to official Tines bundle"
  prompt_default TENANT_NAME "Tenant name"
  prompt_default DOMAIN "Domain"
  prompt_default SEED_EMAIL "Seed admin email"
  prompt_default SEED_FIRST_NAME "Seed first name"
  prompt_default SEED_LAST_NAME "Seed last name"
  prompt_default SEED_PASSWORD "Seed password"
  prompt_default DATABASE_PASSWORD "Database password"
  prompt_default SMTP_SERVER "SMTP server (optional)"
  prompt_default SMTP_PORT "SMTP port"
  prompt_default SMTP_DOMAIN "SMTP domain"
  prompt_default SMTP_USERNAME "SMTP username"
  prompt_default SMTP_PASSWORD "SMTP password"
  prompt_default EMAIL_FROM_ADDRESS "Email from address"
  prompt_default TLS_MODE "TLS mode (self-signed/provided/none)"
  if [[ "$TLS_MODE" == "provided" ]]; then
    prompt_default TLS_CERT_PATH "TLS cert path"
    prompt_default TLS_KEY_PATH "TLS key path"
  fi
  prompt_default USE_SYSTEMD "Use systemd (true/false)"
  prompt_default AUTO_START "Auto-start services (true/false)"
  prompt_default RESTART_POLICY "Docker restart policy"
}

save_config() {
  local target="$1"
  cat > "$target" <<CONF
INSTALL_DIR="$INSTALL_DIR"

TENANT_NAME="$TENANT_NAME"
DOMAIN="$DOMAIN"

SEED_EMAIL="$SEED_EMAIL"
SEED_FIRST_NAME="$SEED_FIRST_NAME"
SEED_LAST_NAME="$SEED_LAST_NAME"
SEED_PASSWORD="$SEED_PASSWORD"

SMTP_SERVER="$SMTP_SERVER"
SMTP_PORT="$SMTP_PORT"
SMTP_DOMAIN="$SMTP_DOMAIN"
SMTP_USERNAME="$SMTP_USERNAME"
SMTP_PASSWORD="$SMTP_PASSWORD"
EMAIL_FROM_ADDRESS="$EMAIL_FROM_ADDRESS"

DATABASE_PASSWORD="$DATABASE_PASSWORD"

APP_SECRET_TOKEN="$APP_SECRET_TOKEN"
TELEMETRY_ID="$TELEMETRY_ID"

TLS_MODE="$TLS_MODE"
TLS_CERT_PATH="$TLS_CERT_PATH"
TLS_KEY_PATH="$TLS_KEY_PATH"

AUTO_START="$AUTO_START"
USE_SYSTEMD="$USE_SYSTEMD"
RESTART_POLICY="$RESTART_POLICY"
CONF
  log_pass "Saved config to: $target"
}

validate_os() {
  log_info "Checking operating system"
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
      log_pass "Ubuntu 24.04 detected"
    else
      log_fail "Unsupported OS: ${PRETTY_NAME:-unknown}. Ubuntu 24.04 required"
    fi
  else
    log_fail "Cannot detect OS (/etc/os-release missing)"
  fi
}

validate_resources() {
  log_info "Checking system resources"
  local mem_gb cpu_cores disk_gb
  mem_gb=$(awk '/MemTotal/ { printf "%.0f", $2/1024/1024 }' /proc/meminfo)
  cpu_cores=$(nproc)
  if [[ -d "$INSTALL_DIR" ]]; then
    disk_gb=$(df -BG "$INSTALL_DIR" | awk 'NR==2 {gsub("G", "", $4); print $4}')
  else
    disk_gb=$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}')
  fi

  if [[ -z "$disk_gb" || ! "$disk_gb" =~ ^[0-9]+$ ]]; then
    log_fail "Unable to determine available disk space"
    return
  fi

  if (( mem_gb < 4 )); then
    log_fail "Low memory (${mem_gb} GB). Minimum 4 GB required"
  elif (( mem_gb < 8 )); then
    log_warn "Memory is ${mem_gb} GB. 8+ GB recommended"
  else
    log_pass "Memory check passed (${mem_gb} GB)"
  fi

  if (( cpu_cores < 2 )); then
    log_fail "Insufficient CPU cores (${cpu_cores}). Minimum 2 required"
  elif (( cpu_cores < 4 )); then
    log_warn "CPU cores are ${cpu_cores}. 4+ recommended"
  else
    log_pass "CPU check passed (${cpu_cores} cores)"
  fi

  if (( disk_gb < 20 )); then
    log_fail "Available disk ${disk_gb} GB. Minimum 20 GB required"
  elif (( disk_gb < 50 )); then
    log_warn "Available disk ${disk_gb} GB. 50+ GB recommended"
  else
    log_pass "Disk check passed (${disk_gb} GB free)"
  fi
}

validate_network() {
  log_info "Checking network requirements"
  if curl -fsSL --max-time 8 https://www.google.com >/dev/null 2>&1; then
    log_pass "Internet access is available"
  else
    log_fail "Internet access check failed"
  fi

  if nc -z localhost 443 >/dev/null 2>&1; then
    log_warn "Port 443 appears in use on localhost"
  else
    log_pass "Port 443 appears available on localhost"
  fi
}

validate_dependencies() {
  log_info "Checking required tools"
  local deps=(curl unzip openssl nc)
  local dep
  for dep in "${deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      log_pass "$dep installed"
    else
      log_fail "$dep is missing"
    fi
  done

  if command -v docker >/dev/null 2>&1; then
    log_pass "Docker installed"
  else
    if $SKIP_DOCKER_INSTALL; then
      log_fail "Docker is missing and --skip-docker-install was used"
    else
      log_warn "Docker not installed; installer will attempt installation"
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      log_pass "Docker daemon is running"
    else
      log_fail "Docker daemon is not running"
    fi

    if docker compose version >/dev/null 2>&1; then
      log_pass "Docker Compose plugin available"
    else
      log_fail "Docker Compose plugin not available"
    fi
  fi
}

validate_config() {
  log_info "Validating configuration"

  [[ -n "$TENANT_NAME" ]] || log_fail "TENANT_NAME is required"
  [[ -n "$DOMAIN" ]] || log_fail "DOMAIN is required"
  [[ -n "$BUNDLE_PATH" ]] || log_fail "Bundle path is required (--bundle or BUNDLE_PATH in config)"

  if [[ -z "$DATABASE_PASSWORD" || ${#DATABASE_PASSWORD} -lt 12 ]]; then
    log_fail "DATABASE_PASSWORD is required and must be at least 12 characters"
  else
    log_pass "Database password format looks valid"
  fi

  if [[ -z "$SMTP_SERVER" || -z "$SMTP_USERNAME" || -z "$SMTP_PASSWORD" ]]; then
    log_warn "SMTP is not fully configured"
  else
    log_pass "SMTP appears configured"
  fi

  if [[ -z "$APP_SECRET_TOKEN" ]]; then
    log_warn "APP_SECRET_TOKEN is empty and will be generated"
  fi

  case "$TLS_MODE" in
    self-signed)
      log_pass "TLS mode: self-signed"
      ;;
    provided)
      if [[ -f "$TLS_CERT_PATH" && -f "$TLS_KEY_PATH" ]]; then
        log_pass "Provided TLS files found"
      else
        log_fail "TLS_MODE=provided requires valid TLS_CERT_PATH and TLS_KEY_PATH"
      fi
      ;;
    none)
      log_warn "TLS disabled (TLS_MODE=none)"
      ;;
    *)
      log_fail "Invalid TLS_MODE: $TLS_MODE (expected self-signed|provided|none)"
      ;;
  esac
}

archive_contains_required_files() {
  local bundle="$1"
  local missing=0
  local required=(setup.sh upgrade.sh .env.tmpl docker-compose.yml)
  local f
  for f in "${required[@]}"; do
    if [[ "$bundle" == *.zip ]]; then
      if ! unzip -Z1 "$bundle" | grep -qE "(^|/)$f$"; then
        log_fail "Missing $f in bundle archive"
        missing=1
      fi
    elif [[ "$bundle" == *.tar.gz || "$bundle" == *.tgz ]]; then
      if ! tar -tf "$bundle" | grep -qE "(^|/)$f$"; then
        log_fail "Missing $f in bundle archive"
        missing=1
      fi
    fi
  done
  return "$missing"
}

validate_bundle_path() {
  log_info "Validating bundle path and required files"
  if [[ -z "$BUNDLE_PATH" ]]; then
    log_fail "Bundle path is required"
    return
  fi

  if [[ -d "$BUNDLE_PATH" ]]; then
    local root
    root=$(bundle_root_dir "$BUNDLE_PATH")
    validate_bundle_contents "$root"
    return
  fi

  if [[ -f "$BUNDLE_PATH" ]]; then
    case "$BUNDLE_PATH" in
      *.zip|*.tar.gz|*.tgz)
        archive_contains_required_files "$BUNDLE_PATH" || true
        ;;
      *)
        log_fail "Unsupported bundle format: $BUNDLE_PATH"
        ;;
    esac
  else
    log_fail "Bundle path not found: $BUNDLE_PATH"
  fi
}

resolve_bundle() {
  local bundle="$1"
  local release_name release_dir
  release_name="$(date +%Y%m%d%H%M%S)"
  release_dir="$INSTALL_DIR/releases/$release_name"

  if [[ -d "$bundle" ]]; then
    echo "$bundle"
    return
  fi

  mkdir -p "$release_dir"
  if [[ "$bundle" == *.zip ]]; then
    unzip -q "$bundle" -d "$release_dir"
  elif [[ "$bundle" == *.tar.gz || "$bundle" == *.tgz ]]; then
    tar -xzf "$bundle" -C "$release_dir"
  else
    die "Unsupported bundle format: $bundle"
  fi
  echo "$release_dir"
}

bundle_root_dir() {
  local extracted="$1"
  if [[ -f "$extracted/setup.sh" ]]; then
    echo "$extracted"
    return
  fi
  local found
  found=$(find "$extracted" -mindepth 1 -maxdepth 2 -type f -name setup.sh | head -n1 || true)
  if [[ -z "$found" ]]; then
    echo "$extracted"
  else
    dirname "$found"
  fi
}

validate_bundle_contents() {
  local bundle_dir="$1"
  log_info "Validating official bundle contents"
  local required=(setup.sh upgrade.sh .env.tmpl docker-compose.yml)
  local f
  for f in "${required[@]}"; do
    if [[ -f "$bundle_dir/$f" ]]; then
      log_pass "Found $f"
    else
      log_fail "Missing $f in bundle"
    fi
  done
}

ensure_dependencies_installed() {
  log_info "Ensuring required dependencies are installed"
  local apt_packages=(curl unzip openssl netcat-openbsd)
  if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 || ! command -v nc >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y "${apt_packages[@]}"
  fi

  if ! command -v docker >/dev/null 2>&1; then
    if $SKIP_DOCKER_INSTALL; then
      die "Docker missing and installation skipped"
    fi
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin
    systemctl enable --now docker
  fi
}

upsert_env() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  if grep -qE "^${key}=" "$env_file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$env_file"
  fi
}

map_config_to_env() {
  local env_file="$1"
  upsert_env "$env_file" TENANT_NAME "$TENANT_NAME"
  upsert_env "$env_file" DOMAIN "$DOMAIN"
  upsert_env "$env_file" SEED_EMAIL "$SEED_EMAIL"
  upsert_env "$env_file" SEED_FIRST_NAME "$SEED_FIRST_NAME"
  upsert_env "$env_file" SEED_LAST_NAME "$SEED_LAST_NAME"
  upsert_env "$env_file" SEED_PASSWORD "$SEED_PASSWORD"
  upsert_env "$env_file" SMTP_SERVER "$SMTP_SERVER"
  upsert_env "$env_file" SMTP_PORT "$SMTP_PORT"
  upsert_env "$env_file" SMTP_DOMAIN "$SMTP_DOMAIN"
  upsert_env "$env_file" SMTP_USER_NAME "$SMTP_USERNAME"
  upsert_env "$env_file" SMTP_PASSWORD "$SMTP_PASSWORD"
  upsert_env "$env_file" EMAIL_FROM_ADDRESS "$EMAIL_FROM_ADDRESS"
  upsert_env "$env_file" DATABASE_PASSWORD "$DATABASE_PASSWORD"
  upsert_env "$env_file" APP_SECRET_TOKEN "$APP_SECRET_TOKEN"
  upsert_env "$env_file" TELEMETRY_ID "$TELEMETRY_ID"
  upsert_env "$env_file" RESTART_POLICY "$RESTART_POLICY"
}

setup_tls() {
  local cert_dir="$1"
  mkdir -p "$cert_dir"
  case "$TLS_MODE" in
    self-signed)
      openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$cert_dir/tines.key" \
        -out "$cert_dir/tines.crt" \
        -subj "/CN=$DOMAIN"
      log_pass "Generated self-signed TLS certs"
      ;;
    provided)
      cp "$TLS_CERT_PATH" "$cert_dir/tines.crt"
      cp "$TLS_KEY_PATH" "$cert_dir/tines.key"
      log_pass "Copied provided TLS certs"
      ;;
    none)
      log_warn "Skipping TLS setup"
      ;;
  esac
}

install_systemd_unit() {
  local unit_path="/etc/systemd/system/tines.service"
  cat > "$unit_path" <<UNIT
[Unit]
Description=Tines Self Hosted
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR/current
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable tines.service
  log_pass "Installed systemd service: tines.service"
}

run_preflight() {
  FAIL_COUNT=0
  WARN_COUNT=0
  validate_os
  validate_config
  validate_resources
  validate_dependencies
  validate_network
  validate_bundle_path
}

main() {
  parse_args "$@"

  if $INIT_CONFIG; then
    init_sample_config "tines.conf.example"
    exit 0
  fi

  if [[ -n "$CONFIG_FILE" ]]; then
    load_config "$CONFIG_FILE"
  fi

  if ! $NON_INTERACTIVE && ! $GUIDED && [[ -z "$CONFIG_FILE" ]]; then
    menu_prompt
    [[ -n "$CONFIG_FILE" ]] && load_config "$CONFIG_FILE"
  fi

  $GUIDED && guided_setup

  if [[ -n "$SAVE_CONFIG_PATH" ]]; then
    if $DRY_RUN; then
      log_info "Dry-run: would save config to $SAVE_CONFIG_PATH"
    else
      save_config "$SAVE_CONFIG_PATH"
    fi
  fi

  run_preflight

  if (( FAIL_COUNT > 0 )); then
    die "Preflight failed with $FAIL_COUNT error(s)"
  fi

  if $DRY_RUN; then
    log_pass "Dry-run complete: $WARN_COUNT warning(s), $FAIL_COUNT failure(s)"
    exit 0
  fi

  ensure_dependencies_installed

  mkdir -p "$INSTALL_DIR/releases" "$INSTALL_DIR/shared/certs" "$INSTALL_DIR/shared/backups"
  local extracted bundle_dir release_dir
  extracted=$(resolve_bundle "$BUNDLE_PATH")
  bundle_dir=$(bundle_root_dir "$extracted")
  validate_bundle_contents "$bundle_dir"
  if (( FAIL_COUNT > 0 )); then
    die "Bundle validation failed"
  fi

  release_dir="$bundle_dir"
  ln -sfn "$release_dir" "$INSTALL_DIR/current"

  cp "$bundle_dir/.env.tmpl" "$INSTALL_DIR/shared/.env"

  if [[ -z "$APP_SECRET_TOKEN" ]]; then
    APP_SECRET_TOKEN="$(openssl rand -hex 64)"
    log_info "Generated APP_SECRET_TOKEN"
  fi

  map_config_to_env "$INSTALL_DIR/shared/.env"
  setup_tls "$INSTALL_DIR/shared/certs"

  cp "$INSTALL_DIR/shared/.env" "$INSTALL_DIR/current/.env"

  if [[ -L "$INSTALL_DIR/current" && -f "$INSTALL_DIR/current/upgrade.sh" && -d "$INSTALL_DIR/releases" && $(find "$INSTALL_DIR/releases" -mindepth 1 -maxdepth 1 -type d | wc -l) -gt 1 ]]; then
    log_info "Existing installation detected; running official upgrade.sh"
    (cd "$INSTALL_DIR/current" && bash ./upgrade.sh)
  else
    log_info "Running official setup.sh"
    (cd "$INSTALL_DIR/current" && bash ./setup.sh)
  fi

  if [[ "$USE_SYSTEMD" == "true" ]]; then
    install_systemd_unit
  fi

  if [[ "$AUTO_START" == "true" ]]; then
    (cd "$INSTALL_DIR/current" && docker compose up -d)
    log_pass "Tines services started"
  fi

  cat <<NEXT
[PASS] Installation flow complete.
[INFO] Install directory: $INSTALL_DIR
[INFO] Current release: $(readlink -f "$INSTALL_DIR/current")
[INFO] Shared env: $INSTALL_DIR/shared/.env
[INFO] Shared certs: $INSTALL_DIR/shared/certs
NEXT
}

main "$@"
