#!/usr/bin/env bash
# CoreGeek Displays Signage Player - Raspberry Pi management CLI
#
# This helper can be invoked remotely over SSH to inspect and manage
# the signage player installation.  It detects the current hardware
#/OS, ensures dependencies are present, and provides lifecycle commands
# for the kiosk services.

set -euo pipefail

SIGNAGE_DIR="/opt/signage"
PI_USER="${PI_USER:-pi}"
REQUIRED_PACKAGES=(
  chromium-browser
  unclutter
  curl
  git
  xserver-xorg
  x11-xserver-utils
  xinit
  dnsutils
)
NODE_MAJOR="20"
SERVICES=(
  signage.service
  chromium-kiosk.service
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUICK_SETUP_SCRIPT="$PROJECT_ROOT/scripts/quick-setup.sh"

systemd_ready() {
  command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This command must be run as root (sudo)."
  fi
}

detect_pi_model() {
  if [[ -f /proc/device-tree/model ]]; then
    tr -d '\0' < /proc/device-tree/model
  elif command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint get_pi_type 2>/dev/null || echo "Unknown Raspberry Pi"
  else
    echo "Unknown Raspberry Pi"
  fi
}

detect_os_name() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '%s %s' "${NAME:-Unknown OS}" "${VERSION:-}" | xargs
  else
    uname -srv
  fi
}

print_detection() {
  local model os arch kernel
  model="$(detect_pi_model)"
  os="$(detect_os_name)"
  arch="$(uname -m)"
  kernel="$(uname -r)"

  cat <<INFO
Detected hardware/software profile:
  Model : ${model:-Unknown}
  OS    : ${os:-Unknown}
  Arch  : ${arch:-Unknown}
  Kernel: ${kernel:-Unknown}
INFO
}

get_env_var() {
  local file="$1"
  local key="$2"

  if [[ -f $file ]]; then
    grep -E "^${key}=" "$file" | tail -n 1 | cut -d'=' -f2-
  fi
}

ensure_packages() {
  require_root
  local missing=()

  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log "Installing required packages: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "${missing[@]}"
  else
    log "All required packages are already installed."
  fi
}

ensure_node() {
  require_root
  local current_major=0

  if command -v node >/dev/null 2>&1; then
    current_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  fi

  if [[ $current_major -lt $NODE_MAJOR ]]; then
    log "Installing Node.js $NODE_MAJOR.x via NodeSource"
    export DEBIAN_FRONTEND=noninteractive
    apt-get remove -y nodejs npm >/dev/null 2>&1 || true
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    apt-get install -y nodejs
  else
    log "Node.js $(node -v) already meets requirement >= $NODE_MAJOR"
  fi
}

stop_services() {
  if ! systemd_ready; then
    return
  fi

  for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}"; then
      systemctl stop "$svc" >/dev/null 2>&1 || true
      systemctl disable "$svc" >/dev/null 2>&1 || true
    fi
  done
}

remove_services() {
  if ! systemd_ready; then
    return
  fi

  for svc in "${SERVICES[@]}"; do
    if [[ -f "/etc/systemd/system/$svc" ]]; then
      rm -f "/etc/systemd/system/$svc"
    fi
  done
  systemctl daemon-reload >/dev/null 2>&1 || true
}

uninstall_signage() {
  require_root
  stop_services
  remove_services

  if [[ -d $SIGNAGE_DIR ]]; then
    log "Removing existing installation at $SIGNAGE_DIR"
    rm -rf "$SIGNAGE_DIR"
  else
    log "No existing installation directory found at $SIGNAGE_DIR"
  fi

  local kiosk_script
  kiosk_script="/home/${PI_USER}/start-kiosk.sh"
  if [[ -f $kiosk_script ]]; then
    rm -f "$kiosk_script"
  fi

  log "Signage player removed."
}

install_signage() {
  require_root
  ensure_packages
  ensure_node

  if [[ ! -x $QUICK_SETUP_SCRIPT ]]; then
    error "Quick setup script not found at $QUICK_SETUP_SCRIPT"
  fi

  log "Launching quick setup..."
  "$QUICK_SETUP_SCRIPT"
}

reinstall_signage() {
  uninstall_signage
  install_signage
}

show_status() {
  print_detection
  echo
  if ! systemd_ready; then
    echo "systemd is not active on this host; kiosk services are unavailable."
    return
  fi

  for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^${svc}"; then
      systemctl status "$svc" --no-pager || true
    else
      echo "Service $svc is not installed."
    fi
  done
}

run_diagnostics() {
  local env_file="$SIGNAGE_DIR/.env"
  local exit_code=0

  print_detection
  echo

  if [[ ! -f $env_file ]]; then
    error "Environment file not found at $env_file. Run the installer first."
  fi

  if ! command -v curl >/dev/null 2>&1; then
    error "curl is required for diagnostics. Install dependencies first (install-deps)."
  fi

  if ! command -v node >/dev/null 2>&1; then
    error "Node.js is required for diagnostics JSON parsing. Run install-deps to install Node.js."
  fi

  local controller_url controller_base controller_host venue_slug api_key
  controller_url="$(get_env_var "$env_file" "CONTROLLER_BASE_URL")"
  venue_slug="$(get_env_var "$env_file" "VENUE_SLUG")"
  api_key="$(get_env_var "$env_file" "CONTROLLER_API_KEY")"

  if [[ -z ${controller_url:-} ]]; then
    error "CONTROLLER_BASE_URL is not configured in $env_file."
  fi

  controller_base="${controller_url%/}"
  controller_host="${controller_base#*//}"
  controller_host="${controller_host%%/*}"

  log "Controller base URL: $controller_base"

  if [[ -n ${controller_host:-} ]]; then
    log "Pinging controller host ($controller_host)..."
    if ping -c 1 -W 3 "$controller_host" >/dev/null 2>&1; then
      log "  ✓ Controller host is reachable"
    else
      log "  ✗ Unable to reach $controller_host via ping"
      exit_code=1
    fi
  fi

  local endpoint
  if [[ -n ${venue_slug:-} ]]; then
    endpoint="$controller_base/api/public/venues/${venue_slug}/events"
  else
    endpoint="$controller_base/api/public/events"
  fi

  log "Requesting event feed: $endpoint"

  local tmp_json
  tmp_json="$(mktemp)"

  local curl_cmd=(curl -fsS --max-time 20 -H "Accept: application/json")
  if [[ -n ${api_key:-} ]]; then
    curl_cmd+=(-H "x-api-key: $api_key")
  fi
  curl_cmd+=(-o "$tmp_json" "$endpoint")

  if "${curl_cmd[@]}"; then
    log "  ✓ Controller API responded successfully"
  else
    log "  ✗ Failed to download events from controller"
    rm -f "$tmp_json"
    return 1
  fi

  local diag_output event_count image_url diag_output_file
  diag_output_file="$(mktemp)"
  if node - "$tmp_json" "$controller_base" <<'NODE' >"$diag_output_file"
const fs = require('fs');

const file = process.argv[1];
const controllerBase = process.argv[2] || '';

let data;
try {
  data = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

let events = [];
if (Array.isArray(data)) {
  events = data;
} else if (data && Array.isArray(data.events)) {
  events = data.events;
}

const firstWithImage = events.find((event) => event && typeof event.imageUrl === 'string' && event.imageUrl.trim().length > 0);

let imageUrl = '';
if (firstWithImage) {
  imageUrl = firstWithImage.imageUrl.trim();
  if (imageUrl.startsWith('/')) {
    imageUrl = controllerBase.replace(/\/$/, '') + imageUrl;
  }
}

console.log(events.length);
console.log(imageUrl);
NODE
  then
    diag_output=$(cat "$diag_output_file")
  else
    diag_output=''
  fi
  rm -f "$diag_output_file"

  event_count=$(printf '%s\n' "$diag_output" | sed -n '1p' | tr -d '\r')
  image_url=$(printf '%s\n' "$diag_output" | sed -n '2p' | tr -d '\r')

  if [[ -n ${event_count:-} ]]; then
    log "  • Retrieved ${event_count:-0} events from controller"
  fi

  if [[ -n ${image_url:-} ]]; then
    log "Checking image download: $image_url"
    if curl -fsS --max-time 20 -o /dev/null "$image_url"; then
      log "  ✓ Successfully downloaded sample event image"
    else
      log "  ✗ Unable to download event image: $image_url"
      exit_code=1
    fi
  else
    log "  ⚠ No events with images were returned in the feed"
  fi

  rm -f "$tmp_json"

  return $exit_code
}

show_usage() {
  cat <<USAGE
CoreGeek Displays Raspberry Pi CLI
Usage: $0 <command>

Commands:
  detect        Print hardware/OS detection information.
  install-deps  Ensure apt packages and Node.js prerequisites are installed.
  install       Run the interactive quick-setup installer.
  reinstall     Remove any existing deployment and run a fresh install.
  uninstall     Stop services and remove all installed files.
  status        Show system information and service status.
  diagnostics   Verify controller connectivity and media downloads.
  help          Show this help message.

Examples:
  sudo $0 detect
  sudo $0 install-deps
  sudo $0 reinstall
USAGE
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    detect)
      print_detection
      ;;
    install-deps)
      ensure_packages
      ensure_node
      ;;
    install)
      install_signage
      ;;
    reinstall)
      reinstall_signage
      ;;
    uninstall)
      uninstall_signage
      ;;
    status)
      show_status
      ;;
    diagnostics)
      run_diagnostics
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      error "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
