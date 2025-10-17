#!/usr/bin/env bash
#
# CoreGeek Displays Signage Player - Quick Setup Script
# This script automates the initial deployment on a fresh Raspberry Pi
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/0x0meow/cgd-pi/main/scripts/quick-setup.sh | bash
#
# Or locally:
#   chmod +x scripts/quick-setup.sh
#   sudo ./scripts/quick-setup.sh

set -euo pipefail

TTY_INPUT_FD=0
TTY_OUTPUT_FD=1
INTERACTIVE_AVAILABLE=true

if [ ! -t 0 ]; then
  if [ -r /dev/tty ] && [ -w /dev/tty ]; then
    exec 3</dev/tty
    exec 4>/dev/tty
    TTY_INPUT_FD=3
    TTY_OUTPUT_FD=4
  else
    INTERACTIVE_AVAILABLE=false
  fi
fi

# ============================================================================
# Configuration
# ============================================================================

SIGNAGE_DIR="/opt/signage"
REPO_URL="https://github.com/0x0meow/cgd-pi.git"
REQUIRED_PACKAGES="chromium-browser unclutter curl git xserver-xorg x11-xserver-utils xinit"
NODE_VERSION="20"
CURRENT_NODE_VERSION=0
PI_USER="${PI_USER:-pi}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
  exit 1
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    error "Please run as root (use sudo)"
  fi
}

ensure_user_exists() {
  local user="$1"

  if ! id "$user" > /dev/null 2>&1; then
    error "User '$user' not found. Create the user or set PI_USER to an existing account."
  fi
}

get_user_home() {
  local user="$1"
  getent passwd "$user" | cut -d: -f6
}

update_env_var() {
  local file="$1"
  local key="$2"
  local value="${3:-}"
  local escaped_value

  escaped_value=$(printf '%s' "$value" | sed -e 's/[\/&|]/\\&/g')

  if grep -q "^$key=" "$file"; then
    sed -i "s|^$key=.*|$key=$escaped_value|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

prompt_for_required_input() {
  local prompt_message="$1"
  local default_value="${2:-}"
  local input

  while true; do
    if [ "$INTERACTIVE_AVAILABLE" != true ]; then
      if [ -n "$default_value" ]; then
        printf '%s' "$default_value"
        return
      fi

      error "Cannot prompt for input without an interactive terminal. Set CONTROLLER_BASE_URL before running."
    fi

    if [ -n "$default_value" ]; then
      printf "%s [%s]: " "$prompt_message" "$default_value" >&$TTY_OUTPUT_FD
      if ! read -u $TTY_INPUT_FD -r input; then
        warn "Unable to read input. Please try again."
        continue
      fi
      input="${input:-$default_value}"
    else
      printf "%s: " "$prompt_message" >&$TTY_OUTPUT_FD
      if ! read -u $TTY_INPUT_FD -r input; then
        warn "Unable to read input. Please try again."
        continue
      fi
    fi

    input="$(printf '%s' "$input" | xargs)"

    if [ -n "$input" ]; then
      printf '%s' "$input"
      return
    fi

    warn "A value is required. Please try again."
  done
}

prompt_for_required_secret() {
  local prompt_message="$1"
  local input

  while true; do
    if [ "$INTERACTIVE_AVAILABLE" != true ]; then
      error "Cannot prompt for secret without an interactive terminal. Set CONTROLLER_API_KEY before running."
    fi

    printf "%s: " "$prompt_message" >&$TTY_OUTPUT_FD
    if ! read -u $TTY_INPUT_FD -rs input; then
      printf '\n' >&$TTY_OUTPUT_FD
      warn "Unable to read input. Please try again."
      continue
    fi
    printf '\n' >&$TTY_OUTPUT_FD

    input="$(printf '%s' "$input" | xargs)"

    if [ -n "$input" ]; then
      printf '%s' "$input"
      return
    fi

    warn "A value is required. Please try again."
  done
}

prompt_for_secret_with_default() {
  local prompt_message="$1"
  local default_value="${2:-}"
  local input

  while true; do
    if [ "$INTERACTIVE_AVAILABLE" != true ]; then
      if [ -n "$default_value" ]; then
        printf '%s' "$default_value"
        return
      fi

      error "Cannot prompt for secret without an interactive terminal. Set CONTROLLER_API_KEY before running."
    fi

    if [ -n "$default_value" ]; then
      printf "%s (leave blank to keep current): " "$prompt_message" >&$TTY_OUTPUT_FD
      if ! read -u $TTY_INPUT_FD -rs input; then
        printf '\n' >&$TTY_OUTPUT_FD
        warn "Unable to read input. Please try again."
        continue
      fi
      printf '\n' >&$TTY_OUTPUT_FD

      if [ -z "$input" ]; then
        printf '%s' "$default_value"
        return
      fi
    else
      printf "%s: " "$prompt_message" >&$TTY_OUTPUT_FD
      if ! read -u $TTY_INPUT_FD -rs input; then
        printf '\n' >&$TTY_OUTPUT_FD
        warn "Unable to read input. Please try again."
        continue
      fi
      printf '\n' >&$TTY_OUTPUT_FD
    fi

    input="$(printf '%s' "$input" | xargs)"

    if [ -n "$input" ]; then
      printf '%s' "$input"
      return
    fi

    warn "A value is required. Please try again."
  done
}

get_env_var() {
  local file="$1"
  local key="$2"

  if [ -f "$file" ]; then
    grep -m1 "^$key=" "$file" | cut -d'=' -f2-
  fi
}

validate_controller_url() {
  local url="$1"

  if [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
    return 0
  fi

  return 1
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

log "CoreGeek Displays Signage Player - Quick Setup"
log "================================================"

check_root

# Check if running on Raspberry Pi
if [ ! -f /proc/device-tree/model ]; then
  warn "Not running on a Raspberry Pi - continuing anyway"
else
  PI_MODEL=$(cat /proc/device-tree/model)
  log "Detected: $PI_MODEL"
fi

ensure_user_exists "$PI_USER"
PI_HOME=$(get_user_home "$PI_USER")

if [ -z "$PI_HOME" ]; then
  error "Unable to determine home directory for user '$PI_USER'"
fi

log "Using kiosk user: $PI_USER (home: $PI_HOME)"

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv7l" ]; then
  warn "Expected ARM64 architecture, got: $ARCH"
fi

# ============================================================================
# System Updates
# ============================================================================

log "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# ============================================================================
# Install Required Packages
# ============================================================================

log "Installing required packages: $REQUIRED_PACKAGES"
apt-get install -y $REQUIRED_PACKAGES

# ============================================================================
# Install Node.js
# ============================================================================

if command -v node &> /dev/null; then
  CURRENT_NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
  if [ "$CURRENT_NODE_VERSION" -ge "$NODE_VERSION" ]; then
    log "Node.js already installed: $(node -v)"
  else
    warn "Node.js version too old ($(node -v)). Installing Node.js $NODE_VERSION..."
    apt-get remove -y nodejs npm 2>/dev/null || true
  fi
fi

if ! command -v node &> /dev/null || [ "$CURRENT_NODE_VERSION" -lt "$NODE_VERSION" ]; then
  log "Installing Node.js $NODE_VERSION..."
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
  apt-get install -y nodejs
  log "Node.js installed: $(node -v)"
  log "npm installed: $(npm -v)"
fi

# ============================================================================
# Clone Repository
# ============================================================================

BACKUP_ENV=""

if [ -d "$SIGNAGE_DIR" ]; then
  warn "Existing installation detected at $SIGNAGE_DIR"

  if [ -f "$SIGNAGE_DIR/.env" ]; then
    BACKUP_ENV="/tmp/signage-env-$(date +'%Y%m%d%H%M%S')"
    cp "$SIGNAGE_DIR/.env" "$BACKUP_ENV"
    log "Backed up current environment to $BACKUP_ENV"
  fi

  log "Removing previous installation..."
  rm -rf "$SIGNAGE_DIR"
fi

log "Cloning repository to $SIGNAGE_DIR..."
mkdir -p "$SIGNAGE_DIR"
git clone "$REPO_URL" "$SIGNAGE_DIR"
cd "$SIGNAGE_DIR"

chown -R "$PI_USER:$PI_USER" "$SIGNAGE_DIR"

if [ -n "$BACKUP_ENV" ] && [ -f "$BACKUP_ENV" ]; then
  cp "$BACKUP_ENV" "$SIGNAGE_DIR/.env"
  log "Restored environment from backup"
fi

# ============================================================================
# Configure Environment
# ============================================================================

log "Configuring environment..."

if [ ! -f "$SIGNAGE_DIR/.env" ]; then
  cp "$SIGNAGE_DIR/.env.example" "$SIGNAGE_DIR/.env"
fi

CONFIG_FILE="$SIGNAGE_DIR/.env"
chown "$PI_USER:$PI_USER" "$CONFIG_FILE"

CURRENT_URL=$(get_env_var "$CONFIG_FILE" "CONTROLLER_BASE_URL")
if [ -n "${CONTROLLER_BASE_URL:-}" ]; then
  if ! validate_controller_url "$CONTROLLER_BASE_URL"; then
    error "CONTROLLER_BASE_URL must start with http:// or https://"
  fi
  update_env_var "$CONFIG_FILE" "CONTROLLER_BASE_URL" "$CONTROLLER_BASE_URL"
  log "Controller URL configured from environment variable"
else
  DEFAULT_URL=""
  if [ -n "$CURRENT_URL" ] && [ "$CURRENT_URL" != "https://displays.example.com" ]; then
    DEFAULT_URL="$CURRENT_URL"
  fi

  while true; do
    CONTROLLER_URL=$(prompt_for_required_input \
      "Enter CoreGeek Displays controller URL (e.g., https://displays.example.com)" \
      "$DEFAULT_URL")

    if validate_controller_url "$CONTROLLER_URL"; then
      break
    fi

    warn "Controller URL must start with http:// or https://"
    DEFAULT_URL="$CONTROLLER_URL"
  done

  update_env_var "$CONFIG_FILE" "CONTROLLER_BASE_URL" "$CONTROLLER_URL"
  log "Controller URL configured"
fi

if [ -n "${VENUE_SLUG:-}" ]; then
  update_env_var "$CONFIG_FILE" "VENUE_SLUG" "$VENUE_SLUG"
fi

CURRENT_API_KEY=$(get_env_var "$CONFIG_FILE" "CONTROLLER_API_KEY")
if [ -n "${CONTROLLER_API_KEY:-}" ]; then
  update_env_var "$CONFIG_FILE" "CONTROLLER_API_KEY" "$CONTROLLER_API_KEY"
  log "Controller API key configured from environment variable"
else
  if [ -n "$CURRENT_API_KEY" ]; then
    CONTROLLER_API_KEY=$(prompt_for_secret_with_default \
      "Enter CoreGeek Displays API key" \
      "$CURRENT_API_KEY")
  else
    CONTROLLER_API_KEY=$(prompt_for_required_secret "Enter CoreGeek Displays API key")
  fi

  update_env_var "$CONFIG_FILE" "CONTROLLER_API_KEY" "$CONTROLLER_API_KEY"
  log "Controller API key configured"
fi

chown "$PI_USER:$PI_USER" "$CONFIG_FILE"

log "Environment configured"

# ============================================================================
# Install Node.js Dependencies
# ============================================================================

log "Installing Node.js dependencies..."
if command -v sudo > /dev/null 2>&1; then
  if ! sudo -u "$PI_USER" -- bash -c "cd '$SIGNAGE_DIR' && npm install --production"; then
    error "Failed to install Node.js dependencies"
  fi
else
  if ! su - "$PI_USER" -c "cd '$SIGNAGE_DIR' && npm install --production"; then
    error "Failed to install Node.js dependencies"
  fi
fi

log "Node.js dependencies installed"

# ============================================================================
# Install Systemd Services
# ============================================================================

log "Installing systemd services..."

TMP_SIGNAGE_SERVICE=$(mktemp)
cp "$SIGNAGE_DIR/deployment/signage.service" "$TMP_SIGNAGE_SERVICE"
sed -i "s/^User=.*/User=$PI_USER/" "$TMP_SIGNAGE_SERVICE"
sed -i "s/^Group=.*/Group=$PI_USER/" "$TMP_SIGNAGE_SERVICE"
install -o root -g root -m 0644 "$TMP_SIGNAGE_SERVICE" /etc/systemd/system/signage.service
rm -f "$TMP_SIGNAGE_SERVICE"

install -o "$PI_USER" -g "$PI_USER" -m 0755 "$SIGNAGE_DIR/deployment/start-kiosk.sh" "$PI_HOME/start-kiosk.sh"

TMP_KIOSK_SERVICE=$(mktemp)
cp "$SIGNAGE_DIR/deployment/chromium-kiosk.service" "$TMP_KIOSK_SERVICE"
sed -i "s/^User=.*/User=$PI_USER/" "$TMP_KIOSK_SERVICE"
sed -i "s/^Group=.*/Group=$PI_USER/" "$TMP_KIOSK_SERVICE"
sed -i "s|^ExecStart=.*|ExecStart=$PI_HOME/start-kiosk.sh|" "$TMP_KIOSK_SERVICE"
sed -i "s|^Environment=XAUTHORITY=.*|Environment=XAUTHORITY=$PI_HOME/.Xauthority|" "$TMP_KIOSK_SERVICE"
install -o root -g root -m 0644 "$TMP_KIOSK_SERVICE" /etc/systemd/system/chromium-kiosk.service
rm -f "$TMP_KIOSK_SERVICE"

systemctl daemon-reload
systemctl enable signage.service || warn "Failed to enable signage.service"
systemctl enable chromium-kiosk.service || warn "Failed to enable chromium-kiosk.service"

log "Systemd services installed"

# ============================================================================
# Configure Auto-Login
# ============================================================================

log "Configuring auto-login for kiosk mode..."
if command -v raspi-config > /dev/null 2>&1; then
  if raspi-config nonint do_boot_behaviour B4; then
    log "Auto-login enabled via raspi-config"
  else
    warn "Failed to configure auto-login via raspi-config"
  fi
else
  warn "raspi-config not found. Skip auto-login configuration. Configure manually if required."
fi

# ============================================================================
# Start Services
# ============================================================================

log "Starting signage service..."
if ! systemctl start signage.service; then
  error "Failed to start signage.service. Check logs with: sudo journalctl -u signage -n 50"
fi

# Wait for service to be healthy
log "Waiting for signage service to be ready..."
sleep 5

for i in {1..30}; do
  if curl -sf http://localhost:3000/healthz > /dev/null 2>&1; then
    log "Signage service is healthy!"
    break
  fi
  
  if [ $i -eq 30 ]; then
    error "Signage service failed to become healthy. Check logs: sudo journalctl -u signage -f"
  fi
  
  sleep 2
done

if systemctl is-active --quiet graphical.target 2>/dev/null; then
  log "Starting Chromium kiosk service..."
  if systemctl start chromium-kiosk.service; then
    log "Chromium kiosk service started"
  else
    warn "Failed to start chromium-kiosk.service. Ensure a graphical session is available, then run: sudo systemctl start chromium-kiosk"
  fi
else
  warn "Graphical target is not active yet. Chromium kiosk will start automatically after the next reboot."
fi

# ============================================================================
# Final Instructions
# ============================================================================

echo
echo "===================================="
echo "Setup Complete!"
echo "===================================="
echo
echo "Next steps:"
echo "  1. Review configuration: nano $SIGNAGE_DIR/.env"
echo "  2. Reboot to refresh services (recommended): sudo reboot"
echo
echo "Chromium kiosk mode has been enabled and started (when a graphical target is available)."
echo "After reboot, the display will automatically show signage."
echo
echo "Useful commands:"
echo "  - Check status: sudo systemctl status signage chromium-kiosk"
echo "  - View logs: sudo journalctl -u signage -f"
echo "  - Restart display: sudo systemctl restart chromium-kiosk"
echo
echo "For troubleshooting, see: $SIGNAGE_DIR/TROUBLESHOOTING.md"
echo

if [ "$INTERACTIVE_AVAILABLE" = true ]; then
  printf "Reboot now? (y/N): " >&$TTY_OUTPUT_FD
  if read -u $TTY_INPUT_FD -r -n 1 REPLY; then
    :
  else
    REPLY=""
  fi
  printf '\n' >&$TTY_OUTPUT_FD

  if [[ ${REPLY:-N} =~ ^[Yy]$ ]]; then
    log "Rebooting..."
    reboot
  else
    log "Setup complete. Remember to reboot when ready: sudo reboot"
  fi
else
  log "Setup complete. Reboot when ready: sudo reboot"
fi
