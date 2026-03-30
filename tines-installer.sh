#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
GUIDED=false
NON_INTERACTIVE=false
INIT_CONFIG=false
SKIP_DOCKER_INSTALL=false
FORCE=false

CONFIG_FILE=""
SAVE_CONFIG_PATH=""

# Config defaults
INSTALL_DIR="/opt/tines"
BUNDLE_PATH=""
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
COMPOSE_CMD_STR=""
COMPOSE_BIN=""

readonly CONFIG_KEYS=(
  INSTALL_DIR BUNDLE_PATH TENANT_NAME DOMAIN
  SEED_EMAIL SEED_FIRST_NAME SEED_LAST_NAME SEED_PASSWORD
  SMTP_SERVER SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD EMAIL_FROM_ADDRESS
  DATABASE_PASSWORD APP_SECRET_TOKEN TELEMETRY_ID
  TLS_MODE TLS_CERT_PATH TLS_KEY_PATH
  AUTO_START USE_SYSTEMD RESTART_POLICY
)

readonly ENV_MAP=(
  "TENANT_NAME:TENANT_NAME"
  "DOMAIN:DOMAIN"
  "SEED_EMAIL:SEED_EMAIL"
  "SEED_FIRST_NAME:SEED_FIRST_NAME"
  "SEED_LAST_NAME:SEED_LAST_NAME"
  "SEED_PASSWORD:SEED_PASSWORD"
  "SMTP_SERVER:SMTP_SERVER"
  "SMTP_PORT:SMTP_PORT"
  "SMTP_DOMAIN:SMTP_DOMAIN"
  "SMTP_USERNAME:SMTP_USER_NAME"
  "SMTP_PASSWORD:SMTP_PASSWORD"
  "EMAIL_FROM_ADDRESS:EMAIL_FROM_ADDRESS"
  "DATABASE_PASSWORD:DATABASE_PASSWORD"
  "APP_SECRET_TOKEN:APP_SECRET_TOKEN"
  "TELEMETRY_ID:TELEMETRY_ID"
  "RESTART_POLICY:RESTART_POLICY"
)

log_info() { printf '[INFO] %s\n' "$*"; }
log_pass() { printf '[PASS] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
log_fail() { printf '[FAIL] %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

die() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

contains_key() {
  local key="$1"
  local k
  for k in "${CONFIG_KEYS[@]}"; do
    [[ "$k" == "$key" ]] && return 0
  done
  return 1
}

strip_quotes() {
  local value="$1"
  if [[ "$value" =~ ^\"(.*)\"$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$value"
  fi
}

is_boolean() {
  [[ "$1" == "true" || "$1" == "false" ]]
}

print_help() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --guided                    Run guided interactive setup
  --config <path>             Load configuration file
  --init-config               Generate sample config and exit
  --dry-run                   Validate only (no writes, installs, setup/upgrade)
  --non-interactive           Disable prompts; requires --config
  --install-dir <path>        Override install directory
  --bundle <path>             Path to official Tines bundle (dir/.zip/.tar.gz/.tgz)
  --skip-docker-install       Skip Docker installation attempts if missing
  --save-config <path>        Save current config values to file
  --force                     Overwrite existing staged release directory if needed
  --help                      Show this help
USAGE
}

write_example_config() {
  local target="$1"
  cat > "$target" <<'CONF'
INSTALL_DIR="/opt/tines"
BUNDLE_PATH="/path/to/tines-bundle.zip"

TENANT_NAME="my-tines"
DOMAIN="tines.local"

SEED_EMAIL="admin@example.com"
SEED_FIRST_NAME="Admin"
SEED_LAST_NAME="User"
SEED_PASSWORD="ChangeMe123!"

SMTP_SERVER="smtp.example.com"
SMTP_PORT="587"
SMTP_DOMAIN="example.com"
SMTP_USERNAME="smtp-user"
SMTP_PASSWORD="smtp-password"
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

show_menu() {
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
    1) read -r -p "Config path: " CONFIG_FILE ;;
    2) GUIDED=true ;;
    3) write_example_config "tines.conf.example"; exit 0 ;;
    4)
      DRY_RUN=true
      read -r -p "Config path: " CONFIG_FILE
      ;;
    *) die "Invalid menu option: $choice" ;;
  esac
}

load_config_file() {
  local cfg="$1"
  [[ -f "$cfg" ]] || die "Config file not found: $cfg"

  local line key raw value line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      die "Invalid config syntax at $cfg:$line_no"
    fi

    key="${line%%=*}"
    raw="${line#*=}"
    key="${key//[[:space:]]/}"
    value="$(strip_quotes "$raw")"

    if contains_key "$key"; then
      printf -v "$key" '%s' "$value"
    else
      log_warn "Ignoring unsupported config key: $key"
    fi
  done < "$cfg"

  log_pass "Loaded config: $cfg"
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
  [[ -n "$input" ]] && printf -v "$var_name" '%s' "$input"
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
  prompt_default SMTP_SERVER "SMTP server"
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
}

save_config() {
  local target="$1"
  cat > "$target" <<CONF
INSTALL_DIR="$INSTALL_DIR"
BUNDLE_PATH="$BUNDLE_PATH"

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
    disk_gb=$(df -BG "$INSTALL_DIR" | awk 'NR==2 {gsub("G","",$4); print $4}')
  else
    disk_gb=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
  fi

  if (( mem_gb < 4 )); then log_fail "Low memory (${mem_gb} GB). Minimum 4 GB required"
  elif (( mem_gb < 8 )); then log_warn "Memory ${mem_gb} GB. 8+ GB recommended"
  else log_pass "Memory check passed (${mem_gb} GB)"; fi

  if (( cpu_cores < 2 )); then log_fail "CPU cores ${cpu_cores}. Minimum 2 required"
  elif (( cpu_cores < 4 )); then log_warn "CPU cores ${cpu_cores}. 4+ recommended"
  else log_pass "CPU check passed (${cpu_cores} cores)"; fi

  if (( disk_gb < 20 )); then log_fail "Disk ${disk_gb} GB. Minimum 20 GB required"
  elif (( disk_gb < 50 )); then log_warn "Disk ${disk_gb} GB. 50+ GB recommended"
  else log_pass "Disk check passed (${disk_gb} GB free)"; fi
}

detect_compose_command() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN="docker compose"
    COMPOSE_CMD_STR="docker compose"
    return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="docker-compose"
    COMPOSE_CMD_STR="docker-compose"
    return 0
  fi
  return 1
}

validate_dependencies() {
  log_info "Checking required tools"
  local deps=(curl unzip openssl nc tar)
  local dep
  for dep in "${deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      log_pass "$dep installed"
    else
      log_fail "$dep is missing"
    fi
  done

  if command -v docker >/dev/null 2>&1; then
    log_pass "docker installed"
  else
    log_fail "docker is missing"
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      log_pass "Docker daemon is running"
    else
      log_fail "Docker daemon is not running"
    fi
  fi

  if detect_compose_command; then
    log_pass "Compose command detected: $COMPOSE_CMD_STR"
  else
    log_fail "Neither 'docker compose' nor 'docker-compose' is available"
  fi
}

validate_network() {
  log_info "Checking network prerequisites"
  if getent hosts registry-1.docker.io >/dev/null 2>&1; then
    log_pass "DNS resolution to container registry succeeded"
  else
    log_warn "Could not resolve registry-1.docker.io (network may be restricted)"
  fi

  if nc -z localhost 443 >/dev/null 2>&1; then
    log_warn "Port 443 appears in use on localhost"
  else
    log_pass "Port 443 appears available on localhost"
  fi
}

validate_domain() {
  if [[ "$DOMAIN" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
    log_pass "Domain format looks valid"
  else
    log_fail "DOMAIN must be a valid FQDN (example: tines.example.com)"
  fi
}

validate_database_password() {
  if [[ ${#DATABASE_PASSWORD} -lt 12 ]]; then
    log_fail "DATABASE_PASSWORD must be at least 12 characters"
    return
  fi
  if [[ ! "$DATABASE_PASSWORD" =~ ^[A-Za-z0-9._~!@%+=,:/-]+$ ]]; then
    log_fail "DATABASE_PASSWORD contains unsupported characters"
    return
  fi
  log_pass "DATABASE_PASSWORD format looks valid"
}

validate_config() {
  log_info "Validating configuration"
  [[ -n "$TENANT_NAME" ]] || log_fail "TENANT_NAME is required"
  [[ -n "$DOMAIN" ]] || log_fail "DOMAIN is required"
  [[ -n "$BUNDLE_PATH" ]] || log_fail "BUNDLE_PATH is required"

  [[ -n "$DOMAIN" ]] && validate_domain
  [[ -n "$DATABASE_PASSWORD" ]] && validate_database_password || log_fail "DATABASE_PASSWORD is required"

  is_boolean "$AUTO_START" || log_fail "AUTO_START must be true or false"
  is_boolean "$USE_SYSTEMD" || log_fail "USE_SYSTEMD must be true or false"

  case "$TLS_MODE" in
    self-signed) log_pass "TLS mode: self-signed" ;;
    provided)
      if [[ -f "$TLS_CERT_PATH" && -f "$TLS_KEY_PATH" ]]; then
        log_pass "Provided TLS files found"
      else
        log_fail "TLS_MODE=provided requires valid TLS_CERT_PATH and TLS_KEY_PATH"
      fi
      ;;
    none) log_warn "TLS disabled (TLS_MODE=none)" ;;
    *) log_fail "TLS_MODE must be one of: self-signed, provided, none" ;;
  esac

  if [[ -z "$SMTP_SERVER" || -z "$SMTP_USERNAME" || -z "$SMTP_PASSWORD" ]]; then
    log_warn "SMTP not fully configured"
  else
    log_pass "SMTP appears configured"
  fi

  [[ -z "$APP_SECRET_TOKEN" ]] && log_warn "APP_SECRET_TOKEN is empty and will be generated"
}

list_archive_files() {
  local bundle="$1"
  if [[ "$bundle" == *.zip ]]; then
    unzip -Z1 "$bundle"
  else
    tar -tf "$bundle"
  fi
}

validate_bundle_contents_in_list() {
  local file_list="$1"
  local missing=0
  local required=(setup.sh upgrade.sh .env.tmpl docker-compose.yml)
  local r
  for r in "${required[@]}"; do
    if ! grep -qE "(^|/)$r$" <<<"$file_list"; then
      log_fail "Missing $r in bundle"
      missing=1
    else
      log_pass "Found $r in bundle"
    fi
  done
  return "$missing"
}

validate_bundle_path() {
  log_info "Validating bundle path"
  [[ -n "$BUNDLE_PATH" ]] || { log_fail "BUNDLE_PATH is required"; return; }

  if [[ -d "$BUNDLE_PATH" ]]; then
    local missing=0
    local required=(setup.sh upgrade.sh .env.tmpl docker-compose.yml)
    local r
    for r in "${required[@]}"; do
      if find "$BUNDLE_PATH" -maxdepth 2 -type f -name "$r" | grep -q .; then
        log_pass "Found $r in bundle directory"
      else
        log_fail "Missing $r in bundle directory"
        missing=1
      fi
    done
    return "$missing"
  fi

  if [[ -f "$BUNDLE_PATH" ]]; then
    case "$BUNDLE_PATH" in
      *.zip|*.tar.gz|*.tgz)
        local list
        list="$(list_archive_files "$BUNDLE_PATH")"
        validate_bundle_contents_in_list "$list" || true
        ;;
      *) log_fail "Unsupported bundle format: $BUNDLE_PATH" ;;
    esac
    return
  fi

  log_fail "Bundle path not found: $BUNDLE_PATH"
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

ensure_runtime_dependencies() {
  if $DRY_RUN; then
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    return
  fi

  if $SKIP_DOCKER_INSTALL; then
    die "Docker missing and --skip-docker-install was provided"
  fi

  log_info "Installing Docker packages"
  apt-get update -y
  apt-get install -y docker.io docker-compose-plugin
  systemctl enable --now docker

  detect_compose_command || die "Compose command not available after Docker install"
}

prepare_release_dir() {
  local release_id release_dir
  release_id="$(date +%Y%m%d%H%M%S)"
  release_dir="$INSTALL_DIR/releases/$release_id"

  if [[ -e "$release_dir" ]]; then
    if $FORCE; then
      rm -rf "$release_dir"
    else
      die "Release directory already exists: $release_dir (use --force to overwrite)"
    fi
  fi
  mkdir -p "$release_dir"
  printf '%s' "$release_dir"
}

extract_bundle_to_release() {
  local target="$1"
  local tmp
  tmp="$(mktemp -d)"

  cleanup_tmp() { rm -rf "$tmp"; }
  trap cleanup_tmp RETURN

  if [[ -d "$BUNDLE_PATH" ]]; then
    cp -a "$BUNDLE_PATH"/. "$tmp"/
  elif [[ "$BUNDLE_PATH" == *.zip ]]; then
    unzip -q "$BUNDLE_PATH" -d "$tmp"
  elif [[ "$BUNDLE_PATH" == *.tar.gz || "$BUNDLE_PATH" == *.tgz ]]; then
    tar -xzf "$BUNDLE_PATH" -C "$tmp"
  else
    die "Unsupported bundle format: $BUNDLE_PATH"
  fi

  local root="$tmp"
  if [[ ! -f "$root/setup.sh" ]]; then
    local detected
    detected=$(find "$tmp" -mindepth 1 -maxdepth 2 -type f -name setup.sh | head -n1 || true)
    [[ -n "$detected" ]] || die "Unable to locate setup.sh after extraction"
    root="$(dirname "$detected")"
  fi

  local required=(setup.sh upgrade.sh .env.tmpl docker-compose.yml)
  local r
  for r in "${required[@]}"; do
    [[ -f "$root/$r" ]] || die "Missing $r in extracted bundle root"
  done

  cp -a "$root"/. "$target"/
}

set_env_key() {
  local file="$1" key="$2" value="$3"
  local escaped_value
  escaped_value=$(printf '%s' "$value" | sed 's/[\\&]/\\&/g')
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$file"
  else
    log_warn "Key $key not found in .env.tmpl; leaving vendor defaults unchanged"
  fi
}

render_env_file() {
  local release_dir="$1"
  local env_file="$release_dir/.env"
  cp "$release_dir/.env.tmpl" "$env_file"

  local mapping cfg_key env_key value
  for mapping in "${ENV_MAP[@]}"; do
    cfg_key="${mapping%%:*}"
    env_key="${mapping##*:}"
    value="${!cfg_key:-}"
    [[ -n "$value" ]] || continue
    set_env_key "$env_file" "$env_key" "$value"
  done

  cp "$env_file" "$INSTALL_DIR/shared/.env"
}

stage_tls_files() {
  local release_dir="$1"
  local cert_dir="$INSTALL_DIR/shared/certs"
  mkdir -p "$cert_dir"

  case "$TLS_MODE" in
    self-signed)
      openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$cert_dir/tines.key" \
        -out "$cert_dir/tines.crt" \
        -subj "/CN=$DOMAIN" >/dev/null 2>&1
      log_pass "Generated self-signed TLS certificates"
      ;;
    provided)
      cp "$TLS_CERT_PATH" "$cert_dir/tines.crt"
      cp "$TLS_KEY_PATH" "$cert_dir/tines.key"
      log_pass "Copied provided TLS certificates"
      ;;
    none)
      log_warn "TLS staging skipped"
      return
      ;;
  esac

  cp "$cert_dir/tines.crt" "$release_dir/tines.crt"
  cp "$cert_dir/tines.key" "$release_dir/tines.key"
  log_pass "TLS files staged in release directory for setup.sh"
}

has_existing_install() {
  [[ -L "$INSTALL_DIR/current" ]] && [[ -f "$INSTALL_DIR/shared/.env" ]] && [[ -f "$INSTALL_DIR/current/upgrade.sh" ]]
}

run_tines_script() {
  local release_dir="$1"
  local mode="$2"
  if [[ "$mode" == "upgrade" ]]; then
    log_info "Running official upgrade.sh"
    (cd "$release_dir" && bash ./upgrade.sh)
  else
    log_info "Running official setup.sh"
    (cd "$release_dir" && bash ./setup.sh)
  fi
}

install_systemd_unit() {
  local unit_path="/etc/systemd/system/tines.service"
  cat > "$unit_path" <<UNIT
[Unit]
Description=Tines Self Hosted
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR/current
ExecStart=/bin/bash -lc '$COMPOSE_CMD_STR up -d'
ExecStop=/bin/bash -lc '$COMPOSE_CMD_STR down'

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable tines.service
  log_pass "Installed and enabled tines.service"
}

start_services() {
  local release_dir="$1"
  (cd "$release_dir" && eval "$COMPOSE_CMD_STR up -d")
  log_pass "Services started with $COMPOSE_CMD_STR"
}

main() {
  parse_args "$@"

  if $INIT_CONFIG; then
    write_example_config "tines.conf.example"
    exit 0
  fi

  [[ -n "$CONFIG_FILE" ]] && load_config_file "$CONFIG_FILE"

  if ! $NON_INTERACTIVE && ! $GUIDED && [[ -z "$CONFIG_FILE" ]]; then
    show_menu
    [[ -n "$CONFIG_FILE" ]] && load_config_file "$CONFIG_FILE"
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
  log_info "Preflight summary: warnings=$WARN_COUNT failures=$FAIL_COUNT"
  (( FAIL_COUNT == 0 )) || die "Preflight failed"

  if $DRY_RUN; then
    log_pass "Dry-run complete"
    exit 0
  fi

  ensure_runtime_dependencies
  detect_compose_command || die "Compose command is required"

  mkdir -p "$INSTALL_DIR/releases" "$INSTALL_DIR/shared/backups" "$INSTALL_DIR/shared/certs"

  local prior_install mode release_dir
  if has_existing_install; then
    prior_install=true
    mode="upgrade"
  else
    prior_install=false
    mode="install"
  fi

  release_dir="$(prepare_release_dir)"
  if ! extract_bundle_to_release "$release_dir"; then
    rm -rf "$release_dir"
    die "Bundle extraction failed"
  fi

  if [[ -z "$APP_SECRET_TOKEN" ]]; then
    APP_SECRET_TOKEN="$(openssl rand -hex 64)"
    log_info "Generated APP_SECRET_TOKEN"
  fi

  render_env_file "$release_dir"
  stage_tls_files "$release_dir"

  ln -sfn "$release_dir" "$INSTALL_DIR/current"

  if [[ "$mode" == "upgrade" && "$prior_install" == true ]]; then
    run_tines_script "$release_dir" "upgrade"
  else
    run_tines_script "$release_dir" "install"
  fi

  if [[ "$USE_SYSTEMD" == "true" ]]; then
    install_systemd_unit
  fi

  if [[ "$AUTO_START" == "true" ]]; then
    start_services "$release_dir"
  fi

  log_pass "Installation flow complete"
  log_info "Current release: $(readlink -f "$INSTALL_DIR/current")"
  log_info "Managed env: $INSTALL_DIR/shared/.env"
}

main "$@"
