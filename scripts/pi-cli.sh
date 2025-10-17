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
    help|--help|-h)
      show_usage
      ;;
    *)
      error "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
