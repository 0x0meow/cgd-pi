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
# Install Docker
# ============================================================================

if command -v docker &> /dev/null; then
  log "Docker already installed: $(docker --version)"
else
  log "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  
  # Add pi user to docker group
  if id "pi" &>/dev/null; then
    usermod -aG docker pi
    log "Added 'pi' user to docker group"
  fi
  
  # Enable Docker at boot
  systemctl enable docker
  systemctl start docker
  
  log "Docker installed successfully"
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
  
  read -p "Enter CoreGeek Displays controller URL (e.g., https://displays.example.com): " CONTROLLER_URL
  read -p "Enter venue slug (leave empty for all events): " VENUE_SLUG
  
  # Update .env file
  sed -i "s|CONTROLLER_BASE_URL=.*|CONTROLLER_BASE_URL=$CONTROLLER_URL|" "$SIGNAGE_DIR/.env"
  if [ -n "$VENUE_SLUG" ]; then
    sed -i "s|VENUE_SLUG=.*|VENUE_SLUG=$VENUE_SLUG|" "$SIGNAGE_DIR/.env"
  fi
  
  log "Environment configured"
else
  warn ".env file already exists - skipping configuration"
fi

# ============================================================================
# Build Docker Image
# ============================================================================

log "Building Docker image for ARM64..."
cd "$SIGNAGE_DIR"
docker buildx build --platform linux/arm64 -t coregeek-signage:latest .

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

# Wait for container to be healthy
log "Waiting for signage service to be ready..."
sleep 10

for i in {1..30}; do
  if curl -sf http://localhost:3000/healthz > /dev/null 2>&1; then
    log "Signage service is healthy!"
    break
  fi
  
  if [ $i -eq 30 ]; then
    error "Signage service failed to become healthy. Check logs: docker compose -f $SIGNAGE_DIR/docker-compose.yml logs"
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
echo "  - View logs: docker compose -f $SIGNAGE_DIR/docker-compose.yml logs -f"
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
