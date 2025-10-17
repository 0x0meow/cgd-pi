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

if [ -d "$SIGNAGE_DIR" ]; then
  warn "Directory $SIGNAGE_DIR already exists"
  read -p "Remove and re-clone? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$SIGNAGE_DIR"
  else
    log "Skipping repository clone"
    cd "$SIGNAGE_DIR"
  fi
fi

if [ ! -d "$SIGNAGE_DIR" ]; then
  log "Cloning repository to $SIGNAGE_DIR..."
  mkdir -p "$SIGNAGE_DIR"
  git clone "$REPO_URL" "$SIGNAGE_DIR"
  cd "$SIGNAGE_DIR"
fi

# ============================================================================
# Configure Environment
# ============================================================================

log "Configuring environment..."

if [ ! -f "$SIGNAGE_DIR/.env" ]; then
  cp "$SIGNAGE_DIR/.env.example" "$SIGNAGE_DIR/.env"
  
  echo
  echo "===================================="
  echo "Environment Configuration Required"
  echo "===================================="
  echo
  
  read -rp "Enter CoreGeek Displays API key (leave empty if not required): " CONTROLLER_API_KEY

  while true; do
    read -rp "Enter CoreGeek Displays controller URL (e.g., https://displays.example.com): " CONTROLLER_URL
    if [ -n "$CONTROLLER_URL" ]; then
      break
    fi
    warn "Controller URL is required. Please enter a valid URL."
  done

  read -rp "Enter venue slug (leave empty for all events): " VENUE_SLUG

  update_env_var "$SIGNAGE_DIR/.env" "CONTROLLER_API_KEY" "$CONTROLLER_API_KEY"
  update_env_var "$SIGNAGE_DIR/.env" "CONTROLLER_BASE_URL" "$CONTROLLER_URL"
  update_env_var "$SIGNAGE_DIR/.env" "VENUE_SLUG" "$VENUE_SLUG"
  
  log "Environment configured"
else
  warn ".env file already exists - skipping configuration"
fi

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
