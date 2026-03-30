#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
RUN_USER="${USER:-$(id -un)}"
DRY_RUN=false
GUIDED=false
NON_INTERACTIVE=false
INIT_CONFIG=false
SKIP_DOCKER_INSTALL=false
CONFIG_PATH=""
SAVE_CONFIG_PATH=""
INSTALL_DIR="/opt/tines"
BUNDLE_PATH=""
COMPOSE_CMD=""
CLI_INSTALL_DIR_SET=false
CLI_BUNDLE_SET=false

declare -A CFG
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
WARNINGS=()
FAILURES=()
MISSING_TOOLS=()

print_help() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --guided                 Run guided setup prompts.
  --config <path>          Load configuration from file.
  --init-config            Generate sample config and exit.
  --dry-run                Run validation only; do not write/install/run setup.
  --non-interactive        Disable prompts (requires --config and needed values).
  --install-dir <path>     Override installation directory.
  --bundle <path>          Override bundle path.
  --skip-docker-install    Fail if docker missing instead of installing it.
  --save-config <path>     Save final configuration to path.
  --help                   Show this help message.
USAGE
}

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[ERROR] %s\n' "$*"; }

record_pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS: %s\n' "$1"; }
record_warn() { WARN_COUNT=$((WARN_COUNT + 1)); WARNINGS+=("$1"); printf 'WARN: %s\n' "$1"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1"; }

write_sample_config() {
  local target="$1"
  cat > "$target" <<'CFGEOF'
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
CFGEOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --guided) GUIDED=true ;;
      --config)
        [[ $# -ge 2 ]] || { fail "--config requires a path"; exit 1; }
        CONFIG_PATH="${2:-}"; shift
        ;;
      --init-config) INIT_CONFIG=true ;;
      --dry-run) DRY_RUN=true ;;
      --non-interactive) NON_INTERACTIVE=true ;;
      --install-dir)
        [[ $# -ge 2 ]] || { fail "--install-dir requires a path"; exit 1; }
        INSTALL_DIR="${2:-}"; CLI_INSTALL_DIR_SET=true; shift
        ;;
      --bundle)
        [[ $# -ge 2 ]] || { fail "--bundle requires a path"; exit 1; }
        BUNDLE_PATH="${2:-}"; CLI_BUNDLE_SET=true; shift
        ;;
      --skip-docker-install) SKIP_DOCKER_INSTALL=true ;;
      --save-config)
        [[ $# -ge 2 ]] || { fail "--save-config requires a path"; exit 1; }
        SAVE_CONFIG_PATH="${2:-}"; shift
        ;;
      --help) print_help; exit 0 ;;
      *) fail "Unknown argument: $1"; print_help; exit 1 ;;
    esac
    shift
  done
}

show_menu() {
  echo
  echo "No flags provided. Choose an option:"
  echo "1) Use existing config file"
  echo "2) Guided setup"
  echo "3) Generate sample config and exit"
  echo "4) Dry-run validation only"
  read -r -p "Enter choice [1-4]: " choice
  case "$choice" in
    1)
      read -r -p "Config path: " CONFIG_PATH
      ;;
    2)
      GUIDED=true
      ;;
    3)
      write_sample_config "./tines.conf.example"
      log "Sample config written to ./tines.conf.example"
      exit 0
      ;;
    4)
      DRY_RUN=true
      read -r -p "Config path: " CONFIG_PATH
      ;;
    *) fail "Invalid selection"; exit 1 ;;
  esac
}

load_config_file() {
  local file="$1"
  [[ -f "$file" ]] || { fail "Config file not found: $file"; exit 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line// }" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^([A-Z0-9_]+)=\"(.*)\"$ ]]; then
      CFG["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    else
      fail "Invalid config line (expected KEY=\"VALUE\"): $line"
      exit 1
    fi
  done < "$file"
}

prompt_if_missing() {
  local key="$1" prompt="$2" default="${3:-}"
  local current="${CFG[$key]:-$default}"
  if [[ -n "$current" ]]; then
    read -r -p "$prompt [$current]: " input || true
    CFG[$key]="${input:-$current}"
  else
    read -r -p "$prompt: " input
    CFG[$key]="$input"
  fi
}

run_guided_setup() {
  prompt_if_missing "INSTALL_DIR" "Install directory" "$INSTALL_DIR"
  prompt_if_missing "BUNDLE_PATH" "Path to official Tines bundle" "$BUNDLE_PATH"
  prompt_if_missing "TENANT_NAME" "Tenant name" "my-tines"
  prompt_if_missing "DOMAIN" "Domain" "tines.example.com"
  prompt_if_missing "SEED_EMAIL" "Seed email" "admin@example.com"
  prompt_if_missing "SEED_FIRST_NAME" "Seed first name" "Admin"
  prompt_if_missing "SEED_LAST_NAME" "Seed last name" "User"
  prompt_if_missing "SEED_PASSWORD" "Seed password" ""
  prompt_if_missing "SMTP_SERVER" "SMTP server" "smtp.gmail.com"
  prompt_if_missing "SMTP_PORT" "SMTP port" "587"
  prompt_if_missing "SMTP_DOMAIN" "SMTP domain" "gmail.com"
  prompt_if_missing "SMTP_USERNAME" "SMTP username" "admin@example.com"
  prompt_if_missing "SMTP_PASSWORD" "SMTP password" ""
  prompt_if_missing "EMAIL_FROM_ADDRESS" "Email from address" "admin@example.com"
  prompt_if_missing "DATABASE_PASSWORD" "Database password" ""
  prompt_if_missing "APP_SECRET_TOKEN" "App secret token (blank to auto-generate)" ""
  prompt_if_missing "TLS_MODE" "TLS mode (self-signed|provided|none)" "self-signed"
  if [[ "${CFG[TLS_MODE]}" == "provided" ]]; then
    prompt_if_missing "TLS_CERT_PATH" "TLS cert path" ""
    prompt_if_missing "TLS_KEY_PATH" "TLS key path" ""
  fi
}

apply_overrides() {
  [[ "$CLI_INSTALL_DIR_SET" == true ]] && CFG[INSTALL_DIR]="$INSTALL_DIR"
  [[ "$CLI_BUNDLE_SET" == true ]] && CFG[BUNDLE_PATH]="$BUNDLE_PATH"
  return 0
}

check_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
      record_pass "OS is Ubuntu 24.04"
      return
    fi
  fi
  record_fail "Unsupported OS. This bootstrap targets Ubuntu 24.04."
}

check_resources() {
  local mem_mb cpu_cores disk_gb
  mem_mb=$(awk '/MemTotal/ { print int($2/1024) }' /proc/meminfo)
  cpu_cores=$(nproc)
  disk_gb=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')

  if (( mem_mb < 4096 )); then record_fail "RAM < 4GB (${mem_mb}MB)";
  elif (( mem_mb < 8192 )); then record_warn "RAM 4-8GB (${mem_mb}MB)";
  else record_pass "RAM >= 8GB (${mem_mb}MB)"; fi

  if (( cpu_cores < 2 )); then record_fail "CPU cores < 2 (${cpu_cores})";
  elif (( cpu_cores == 2 )); then record_warn "CPU cores = 2";
  elif (( cpu_cores < 4 )); then record_warn "CPU cores < 4 (${cpu_cores})";
  else record_pass "CPU cores >= 4 (${cpu_cores})"; fi

  if (( disk_gb < 20 )); then record_fail "Disk free < 20GB (${disk_gb}GB)";
  elif (( disk_gb < 50 )); then record_warn "Disk free 20-50GB (${disk_gb}GB)";
  else record_pass "Disk free >= 50GB (${disk_gb}GB)"; fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

check_tools() {
  local tool
  for tool in curl unzip openssl nc; do
    if has_cmd "$tool"; then
      record_pass "Tool found: $tool"
    else
      record_warn "Tool missing: $tool"
      MISSING_TOOLS+=("$tool")
    fi
  done

  if has_cmd docker; then
    record_pass "Tool found: docker"
  else
    if [[ "$SKIP_DOCKER_INSTALL" == true ]]; then
      record_fail "Docker missing and --skip-docker-install was set"
    else
      record_warn "Tool missing: docker"
      MISSING_TOOLS+=("docker")
    fi
  fi

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    record_pass "Compose command detected: docker compose"
  elif has_cmd docker-compose; then
    COMPOSE_CMD="docker-compose"
    record_pass "Compose command detected: docker-compose"
  else
    record_warn "Compose command missing (docker compose or docker-compose)"
    MISSING_TOOLS+=("compose")
  fi
}

check_network() {
  if curl -fsSL --max-time 5 https://www.tines.com >/dev/null 2>&1; then
    record_pass "Internet connectivity check succeeded"
  else
    record_warn "Internet connectivity could not be confirmed"
  fi

  if has_cmd ss; then
    if ss -ltn '( sport = :443 )' 2>/dev/null | grep -q LISTEN; then
      record_warn "Port 443 appears to be in use"
    else
      record_pass "Port 443 not currently in use"
    fi
  else
    record_warn "Could not check port 443 usage (ss command missing)"
  fi
}

check_config() {
  local domain_re='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$'
  [[ -n "${CFG[TENANT_NAME]:-}" ]] && record_pass "TENANT_NAME set" || record_fail "TENANT_NAME is required"
  if [[ -n "${CFG[DOMAIN]:-}" && "${CFG[DOMAIN]}" =~ $domain_re ]]; then
    record_pass "DOMAIN looks valid"
  else
    record_fail "DOMAIN is required and must look like a valid hostname/FQDN"
  fi
  [[ -n "${CFG[BUNDLE_PATH]:-}" ]] && record_pass "BUNDLE_PATH set" || record_fail "BUNDLE_PATH is required"

  if [[ "${CFG[DATABASE_PASSWORD]:-}" =~ ^[A-Za-z0-9_-]{12,}$ ]]; then
    record_pass "DATABASE_PASSWORD meets minimum requirements"
  else
    record_fail "DATABASE_PASSWORD must be >=12 chars and contain only letters, numbers, underscore, dash"
  fi

  case "${CFG[TLS_MODE]:-}" in
    self-signed|provided|none) record_pass "TLS_MODE valid (${CFG[TLS_MODE]})" ;;
    *) record_fail "TLS_MODE must be one of: self-signed, provided, none" ;;
  esac

  if [[ "${CFG[TLS_MODE]:-}" == "provided" ]]; then
    [[ -f "${CFG[TLS_CERT_PATH]:-}" ]] && record_pass "TLS_CERT_PATH exists" || record_fail "TLS_CERT_PATH required for TLS_MODE=provided"
    [[ -f "${CFG[TLS_KEY_PATH]:-}" ]] && record_pass "TLS_KEY_PATH exists" || record_fail "TLS_KEY_PATH required for TLS_MODE=provided"
  fi
}

find_bundle_root() {
  local base="$1"
  if [[ -f "$base/setup.sh" && -f "$base/upgrade.sh" && -f "$base/.env.tmpl" && -f "$base/docker-compose.yml" ]]; then
    printf '%s\n' "$base"
    return 0
  fi
  local candidate
  while IFS= read -r candidate; do
    if [[ -f "$candidate/setup.sh" && -f "$candidate/upgrade.sh" && -f "$candidate/.env.tmpl" && -f "$candidate/docker-compose.yml" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$base" -mindepth 1 -maxdepth 2 -type d)
  return 1
}

validate_bundle_path() {
  local path="$1"
  [[ -e "$path" ]] || { record_fail "Bundle path does not exist: $path"; return; }

  local tmpdir root
  if [[ -d "$path" ]]; then
    if root=$(find_bundle_root "$path"); then
      record_pass "Bundle directory contains required files"
    else
      record_fail "Bundle directory missing required files"
    fi
    return
  fi

  tmpdir=$(mktemp -d)
  case "$path" in
    *.zip) unzip -q "$path" -d "$tmpdir" ;;
    *.tar.gz|*.tgz) tar -xzf "$path" -C "$tmpdir" ;;
    *) rm -rf "$tmpdir"; record_fail "Unsupported bundle format: $path"; return ;;
  esac

  if root=$(find_bundle_root "$tmpdir"); then
    record_pass "Bundle archive contains required files"
  else
    record_fail "Bundle archive missing required files"
  fi
  rm -rf "$tmpdir"
}

install_prerequisites() {
  [[ ${#MISSING_TOOLS[@]} -eq 0 ]] && return
  [[ "$DRY_RUN" == true ]] && { log "Dry-run: skipping prerequisite installation"; return; }

  log "Installing missing prerequisites on Ubuntu 24.04"
  sudo apt-get update
  local apt_pkgs=()
  local item
  for item in "${MISSING_TOOLS[@]}"; do
    case "$item" in
      curl) apt_pkgs+=(curl) ;;
      unzip) apt_pkgs+=(unzip) ;;
      openssl) apt_pkgs+=(openssl) ;;
      nc) apt_pkgs+=(netcat-openbsd) ;;
      compose) ;;
      docker) ;;
    esac
  done
  if [[ ${#apt_pkgs[@]} -gt 0 ]]; then
    sudo apt-get install -y "${apt_pkgs[@]}"
  fi

  if printf '%s\n' "${MISSING_TOOLS[@]}" | grep -qx docker; then
    if [[ "$SKIP_DOCKER_INSTALL" == true ]]; then
      fail "Docker is required and skip flag was set"
      exit 1
    fi
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$RUN_USER" || true
  fi
}

stage_bundle() {
  local src="$1" dest="$2" tmpdir root
  mkdir -p "$dest"

  if [[ -d "$src" ]]; then
    root=$(find_bundle_root "$src")
    cp -a "$root"/. "$dest"/
    return
  fi

  tmpdir=$(mktemp -d)
  case "$src" in
    *.zip) unzip -q "$src" -d "$tmpdir" ;;
    *.tar.gz|*.tgz) tar -xzf "$src" -C "$tmpdir" ;;
    *) fail "Unsupported bundle format for staging: $src"; rm -rf "$tmpdir"; exit 1 ;;
  esac
  root=$(find_bundle_root "$tmpdir")
  cp -a "$root"/. "$dest"/
  rm -rf "$tmpdir"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&#]/\\&/g' -e 's/"/\\"/g'
}

set_env_key() {
  local env_file="$1" key="$2" value="$3" escaped
  if grep -Eq "^${key}=(\".*\"|.*)$" "$env_file"; then
    escaped=$(escape_sed_replacement "$value")
    sed -i -E "s|^${key}=(\".*\"|.*)$|${key}=\"${escaped}\"|" "$env_file"
  else
    warn "Skipping env key not found in template: $key"
  fi
}

render_env() {
  local env_file="$1"
  cp "$env_file.tmpl" "$env_file"

  [[ -n "${CFG[APP_SECRET_TOKEN]:-}" ]] || CFG[APP_SECRET_TOKEN]="$(openssl rand -hex 64)"

  set_env_key "$env_file" "TENANT_NAME" "${CFG[TENANT_NAME]:-}"
  set_env_key "$env_file" "DOMAIN" "${CFG[DOMAIN]:-}"
  set_env_key "$env_file" "SEED_EMAIL" "${CFG[SEED_EMAIL]:-}"
  set_env_key "$env_file" "SEED_FIRST_NAME" "${CFG[SEED_FIRST_NAME]:-}"
  set_env_key "$env_file" "SEED_LAST_NAME" "${CFG[SEED_LAST_NAME]:-}"
  if grep -q '^SEED_PASSWORD=' "$env_file"; then
    set_env_key "$env_file" "SEED_PASSWORD" "${CFG[SEED_PASSWORD]:-}"
  fi
  set_env_key "$env_file" "SMTP_SERVER" "${CFG[SMTP_SERVER]:-}"
  set_env_key "$env_file" "SMTP_PORT" "${CFG[SMTP_PORT]:-}"
  set_env_key "$env_file" "SMTP_DOMAIN" "${CFG[SMTP_DOMAIN]:-}"
  set_env_key "$env_file" "SMTP_USER_NAME" "${CFG[SMTP_USERNAME]:-}"
  set_env_key "$env_file" "SMTP_PASSWORD" "${CFG[SMTP_PASSWORD]:-}"
  set_env_key "$env_file" "EMAIL_FROM_ADDRESS" "${CFG[EMAIL_FROM_ADDRESS]:-}"
  set_env_key "$env_file" "DATABASE_PASSWORD" "${CFG[DATABASE_PASSWORD]:-}"
  set_env_key "$env_file" "APP_SECRET_TOKEN" "${CFG[APP_SECRET_TOKEN]:-}"
}

stage_tls() {
  local dir="$1"
  case "${CFG[TLS_MODE]}" in
    self-signed)
      openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
        -keyout "$dir/tines.key" -out "$dir/tines.crt" \
        -subj "/CN=${CFG[DOMAIN]}" >/dev/null 2>&1
      ;;
    provided)
      cp "${CFG[TLS_CERT_PATH]}" "$dir/tines.crt"
      cp "${CFG[TLS_KEY_PATH]}" "$dir/tines.key"
      ;;
    none)
      warn "TLS_MODE=none selected. This is not recommended unless your deployment model supports it."
      ;;
  esac

  if [[ "${CFG[TLS_MODE]}" != "none" ]]; then
    [[ -f "$dir/tines.crt" && -f "$dir/tines.key" ]] || { fail "tines.crt and tines.key are required"; exit 1; }
  fi
}

print_summary() {
  echo
  echo "Preflight summary: PASS=$PASS_COUNT WARN=$WARN_COUNT FAIL=$FAIL_COUNT"
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "Warnings:"; printf '  - %s\n' "${WARNINGS[@]}"
  fi
  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo "Failures:"; printf '  - %s\n' "${FAILURES[@]}"
  fi
}

save_config_if_requested() {
  [[ -n "$SAVE_CONFIG_PATH" ]] || return 0
  [[ "$DRY_RUN" == true ]] && { log "Dry-run: skipping config save"; return; }
  {
    for k in INSTALL_DIR BUNDLE_PATH TENANT_NAME DOMAIN SEED_EMAIL SEED_FIRST_NAME SEED_LAST_NAME SEED_PASSWORD SMTP_SERVER SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD EMAIL_FROM_ADDRESS DATABASE_PASSWORD APP_SECRET_TOKEN TLS_MODE TLS_CERT_PATH TLS_KEY_PATH; do
      printf '%s="%s"\n' "$k" "${CFG[$k]:-}"
    done
  } > "$SAVE_CONFIG_PATH"
  log "Saved config to $SAVE_CONFIG_PATH"
}

validate_non_interactive_requirements() {
  local missing=()
  local key
  for key in INSTALL_DIR BUNDLE_PATH TENANT_NAME DOMAIN DATABASE_PASSWORD TLS_MODE; do
    [[ -n "${CFG[$key]:-}" ]] || missing+=("$key")
  done
  if [[ "${CFG[TLS_MODE]:-}" == "provided" ]]; then
    [[ -n "${CFG[TLS_CERT_PATH]:-}" ]] || missing+=("TLS_CERT_PATH")
    [[ -n "${CFG[TLS_KEY_PATH]:-}" ]] || missing+=("TLS_KEY_PATH")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    fail "--non-interactive requires values for: ${missing[*]}"
    exit 1
  fi
}

main() {
  parse_args "$@"

  if [[ "$INIT_CONFIG" == true ]]; then
    write_sample_config "./tines.conf.example"
    log "Sample config written to ./tines.conf.example"
    exit 0
  fi

  if [[ $# -eq 0 && "$NON_INTERACTIVE" == false && "$GUIDED" == false && -z "$CONFIG_PATH" ]]; then
    show_menu
  fi

  if [[ -n "$CONFIG_PATH" ]]; then
    load_config_file "$CONFIG_PATH"
  fi

  apply_overrides

  if [[ "$GUIDED" == true ]]; then
    run_guided_setup
  fi

  CFG[INSTALL_DIR]="${CFG[INSTALL_DIR]:-$INSTALL_DIR}"
  CFG[BUNDLE_PATH]="${CFG[BUNDLE_PATH]:-$BUNDLE_PATH}"
  CFG[TLS_MODE]="${CFG[TLS_MODE]:-self-signed}"
  if [[ "$NON_INTERACTIVE" == true ]]; then
    validate_non_interactive_requirements
  fi

  check_os
  check_resources
  check_tools
  check_network
  check_config
  validate_bundle_path "${CFG[BUNDLE_PATH]}"
  print_summary

  if (( FAIL_COUNT > 0 )); then
    fail "Preflight checks failed"
    exit 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "Dry-run complete. No files were written and setup.sh was not run."
    exit 0
  fi

  install_prerequisites

  local install_dir="${CFG[INSTALL_DIR]}"
  log "Creating install directory: $install_dir"
  sudo mkdir -p "$install_dir"
  sudo chown "$RUN_USER":"$RUN_USER" "$install_dir"

  log "Staging official bundle into install directory"
  stage_bundle "${CFG[BUNDLE_PATH]}" "$install_dir"
  if ! find_bundle_root "$install_dir" >/dev/null; then
    fail "Install directory does not contain required official bundle files"
    exit 1
  fi

  [[ -f "$install_dir/.env.tmpl" ]] || { fail ".env.tmpl not found in install directory"; exit 1; }
  render_env "$install_dir/.env"

  stage_tls "$install_dir"

  save_config_if_requested

  log "Running official setup.sh"
  ( cd "$install_dir" && bash setup.sh )

  echo
  echo "Install bootstrap complete. Next steps:"
  if [[ -n "$COMPOSE_CMD" ]]; then
    echo "- Detected compose command: $COMPOSE_CMD"
  fi
  echo "- Validate services with your standard Docker Compose checks"
  echo "- Keep $install_dir/.env and TLS materials secure"
  echo "- Follow official Tines docs and upgrade.sh for future upgrades"
}

main "$@"
