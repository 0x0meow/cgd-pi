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

# ============================================================================
# Configuration
# ============================================================================

SIGNAGE_DIR="/opt/signage"
REPO_URL="https://github.com/0x0meow/cgd-pi.git"
REQUIRED_PACKAGES="chromium-browser unclutter curl git"
NODE_VERSION="20"
CURRENT_NODE_VERSION=0

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
    if [ -n "$default_value" ]; then
      read -rp "$prompt_message [$default_value]: " input
      input="${input:-$default_value}"
    else
      read -rp "$prompt_message: " input
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
    read -rsp "$prompt_message: " input
    echo

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
    if [ -n "$default_value" ]; then
      read -rsp "$prompt_message (leave blank to keep current): " input
      echo

      if [ -z "$input" ]; then
        printf '%s' "$default_value"
        return
      fi
    else
      read -rsp "$prompt_message: " input
      echo
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

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "armv7l" ]; then
  warn "Expected ARM64 architecture, got: $ARCH"
fi

# ============================================================================
# System Updates
# ============================================================================

log "Updating system packages..."
apt update
apt upgrade -y

# ============================================================================
# Install Required Packages
# ============================================================================

log "Installing required packages: $REQUIRED_PACKAGES"
apt install -y $REQUIRED_PACKAGES

# ============================================================================
# Install Node.js
# ============================================================================

if command -v node &> /dev/null; then
  CURRENT_NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
  if [ "$CURRENT_NODE_VERSION" -ge "$NODE_VERSION" ]; then
    log "Node.js already installed: $(node -v)"
  else
    warn "Node.js version too old ($(node -v)). Installing Node.js $NODE_VERSION..."
    apt remove -y nodejs npm 2>/dev/null || true
  fi
fi

if ! command -v node &> /dev/null || [ "$CURRENT_NODE_VERSION" -lt "$NODE_VERSION" ]; then
  log "Installing Node.js $NODE_VERSION..."
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
  apt install -y nodejs
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

CURRENT_URL=$(get_env_var "$CONFIG_FILE" "CONTROLLER_BASE_URL")
if [ -n "${CONTROLLER_BASE_URL:-}" ]; then
  update_env_var "$CONFIG_FILE" "CONTROLLER_BASE_URL" "$CONTROLLER_BASE_URL"
  log "Controller URL configured from environment variable"
else
  DEFAULT_URL=""
  if [ -n "$CURRENT_URL" ] && [ "$CURRENT_URL" != "https://displays.example.com" ]; then
    DEFAULT_URL="$CURRENT_URL"
  fi

  CONTROLLER_URL=$(prompt_for_required_input \
    "Enter CoreGeek Displays controller URL (e.g., https://displays.example.com)" \
    "$DEFAULT_URL")
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

log "Environment configured"

# ============================================================================
# Install Node.js Dependencies
# ============================================================================

log "Installing Node.js dependencies..."
cd "$SIGNAGE_DIR"
npm install --production

log "Node.js dependencies installed"

# ============================================================================
# Install Systemd Services
# ============================================================================

log "Installing systemd services..."

# Install signage service
cp "$SIGNAGE_DIR/deployment/signage.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable signage.service

# Install kiosk script and service
cp "$SIGNAGE_DIR/deployment/start-kiosk.sh" /home/pi/
chmod +x /home/pi/start-kiosk.sh
chown pi:pi /home/pi/start-kiosk.sh

cp "$SIGNAGE_DIR/deployment/chromium-kiosk.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable chromium-kiosk.service

log "Systemd services installed"

# ============================================================================
# Configure Auto-Login
# ============================================================================

log "Configuring auto-login for kiosk mode..."
raspi-config nonint do_boot_behaviour B4

# ============================================================================
# Start Services
# ============================================================================

log "Starting signage service..."
systemctl start signage.service

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
echo "  2. Reboot to start kiosk mode: sudo reboot"
echo
echo "After reboot, the display will automatically show signage."
echo
echo "Useful commands:"
echo "  - Check status: sudo systemctl status signage chromium-kiosk"
echo "  - View logs: sudo journalctl -u signage -f"
echo "  - Restart display: sudo systemctl restart chromium-kiosk"
echo
echo "For troubleshooting, see: $SIGNAGE_DIR/TROUBLESHOOTING.md"
echo

read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  log "Rebooting..."
  reboot
else
  log "Setup complete. Remember to reboot when ready: sudo reboot"
fi
