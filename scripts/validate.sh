#!/usr/bin/env bash
#
# CoreGeek Displays Signage Player - Validation Script
# Tests deployment configuration and connectivity
#
# Usage:
#   chmod +x scripts/validate.sh
#   ./scripts/validate.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SIGNAGE_DIR="${SIGNAGE_DIR:-/opt/signage}"
PASSED=0
FAILED=0
WARNINGS=0

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
  echo -e "\n${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}\n"
}

test_pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASSED=$((PASSED + 1))
}

test_fail() {
  echo -e "${RED}✗${NC} $1"
  FAILED=$((FAILED + 1))
}

test_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  WARNINGS=$((WARNINGS + 1))
}

test_info() {
  echo -e "  ${BLUE}→${NC} $1"
}

# ============================================================================
# System Checks
# ============================================================================

print_header "System Information"

# Check if Raspberry Pi
if [ -f /proc/device-tree/model ]; then
  PI_MODEL=$(cat /proc/device-tree/model)
  test_pass "Raspberry Pi detected: $PI_MODEL"
else
  test_warn "Not running on Raspberry Pi"
fi

# Architecture
ARCH=$(uname -m)
if [ "$ARCH" == "aarch64" ]; then
  test_pass "ARM64 architecture confirmed"
elif [ "$ARCH" == "armv7l" ]; then
  test_warn "ARM32 architecture detected (ARM64 recommended)"
else
  test_fail "Unexpected architecture: $ARCH"
fi

# OS
if [ -f /etc/os-release ]; then
  OS_NAME=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
  test_info "OS: $OS_NAME"
fi

# Memory
TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
test_info "Memory: $TOTAL_MEM"

# Temperature
if command -v vcgencmd &> /dev/null; then
  TEMP=$(vcgencmd measure_temp | cut -d'=' -f2)
  TEMP_NUM=$(echo $TEMP | cut -d'.' -f1 | tr -d "'C")
  if [ "$TEMP_NUM" -lt 70 ]; then
    test_pass "Temperature: $TEMP (acceptable)"
  else
    test_warn "Temperature: $TEMP (consider cooling)"
  fi
fi

# ============================================================================
# Docker Checks
# ============================================================================

print_header "Docker Configuration"

# Docker installed
if command -v docker &> /dev/null; then
  DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
  test_pass "Docker installed: $DOCKER_VERSION"
else
  test_fail "Docker not installed"
  exit 1
fi

# Docker running
if systemctl is-active --quiet docker; then
  test_pass "Docker service running"
else
  test_fail "Docker service not running"
fi

# Docker compose
if docker compose version &> /dev/null; then
  COMPOSE_VERSION=$(docker compose version --short)
  test_pass "Docker Compose plugin installed: $COMPOSE_VERSION"
else
  test_fail "Docker Compose plugin not installed"
fi

# User in docker group
if groups $USER | grep -q docker; then
  test_pass "User '$USER' in docker group"
else
  test_warn "User '$USER' not in docker group (may need sudo)"
fi

# ============================================================================
# Signage Application Checks
# ============================================================================

print_header "Signage Application"

# Directory exists
if [ -d "$SIGNAGE_DIR" ]; then
  test_pass "Signage directory exists: $SIGNAGE_DIR"
else
  test_fail "Signage directory not found: $SIGNAGE_DIR"
  exit 1
fi

cd "$SIGNAGE_DIR"

# Required files
REQUIRED_FILES=("docker-compose.yml" "Dockerfile" "server.js" "package.json" ".env")
for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "$file" ]; then
    test_pass "Required file present: $file"
  else
    test_fail "Missing required file: $file"
  fi
done

# Environment file
if [ -f "$SIGNAGE_DIR/.env" ]; then
  test_pass "Environment file configured: .env"
  
  # Check key variables
  if grep -q "CONTROLLER_BASE_URL=https://" "$SIGNAGE_DIR/.env"; then
    CONTROLLER_URL=$(grep CONTROLLER_BASE_URL "$SIGNAGE_DIR/.env" | cut -d'=' -f2)
    test_pass "Controller URL configured: $CONTROLLER_URL"
  else
    test_fail "CONTROLLER_BASE_URL not properly configured in .env"
  fi
  
  if grep -q "VENUE_SLUG=" "$SIGNAGE_DIR/.env"; then
    VENUE_SLUG=$(grep VENUE_SLUG "$SIGNAGE_DIR/.env" | cut -d'=' -f2)
    if [ -n "$VENUE_SLUG" ]; then
      test_info "Venue slug: $VENUE_SLUG"
    else
      test_info "Venue slug: (all public events)"
    fi
  fi
else
  test_fail "Environment file not found (copy .env.example to .env)"
fi

# Docker image
if docker images | grep -q coregeek-signage; then
  IMAGE_ID=$(docker images coregeek-signage:latest --format "{{.ID}}")
  IMAGE_SIZE=$(docker images coregeek-signage:latest --format "{{.Size}}")
  test_pass "Docker image built: $IMAGE_ID ($IMAGE_SIZE)"
else
  test_fail "Docker image not built (run: docker buildx build --platform linux/arm64 -t coregeek-signage:latest .)"
fi

# Container running
if docker compose ps | grep -q "Up"; then
  test_pass "Container is running"
  
  # Container health
  if docker compose ps | grep -q "healthy"; then
    test_pass "Container is healthy"
  elif docker compose ps | grep -q "unhealthy"; then
    test_fail "Container is unhealthy (check logs: docker compose logs)"
  else
    test_warn "Container health unknown"
  fi
else
  test_fail "Container not running (start: docker compose up -d)"
fi

# ============================================================================
# Network Checks
# ============================================================================

print_header "Network Connectivity"

# Internet connection
if ping -c 1 8.8.8.8 &> /dev/null; then
  test_pass "Internet connectivity available"
else
  test_fail "No internet connection"
fi

# DNS resolution
if [ -f "$SIGNAGE_DIR/.env" ]; then
  CONTROLLER_URL=$(grep CONTROLLER_BASE_URL "$SIGNAGE_DIR/.env" | cut -d'=' -f2)
  CONTROLLER_HOST=$(echo "$CONTROLLER_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
  
  if nslookup "$CONTROLLER_HOST" &> /dev/null; then
    test_pass "DNS resolution working for $CONTROLLER_HOST"
  else
    test_fail "DNS resolution failed for $CONTROLLER_HOST"
  fi
  
  # HTTPS connectivity
  if curl -sf "$CONTROLLER_URL/api/public/events" -o /dev/null; then
    test_pass "Controller API accessible: $CONTROLLER_URL"
  else
    test_fail "Controller API not accessible (check URL and network)"
  fi
fi

# Local signage service
if curl -sf http://localhost:3000 -o /dev/null; then
  test_pass "Signage service responding on localhost:3000"
else
  test_fail "Signage service not responding on localhost:3000"
fi

# Health endpoint
if curl -sf http://localhost:3000/healthz -o /dev/null; then
  test_pass "Health endpoint responding"
  
  HEALTH_JSON=$(curl -s http://localhost:3000/healthz)
  if echo "$HEALTH_JSON" | grep -q '"status":"healthy"'; then
    test_pass "Health status: healthy"
  else
    test_warn "Health status: not healthy"
  fi
else
  test_fail "Health endpoint not responding"
fi

# ============================================================================
# Systemd Service Checks
# ============================================================================

print_header "Systemd Services"

# Signage service
if [ -f /etc/systemd/system/signage.service ]; then
  test_pass "Signage systemd service installed"
  
  if systemctl is-enabled --quiet signage.service 2>/dev/null; then
    test_pass "Signage service enabled at boot"
  else
    test_warn "Signage service not enabled (run: sudo systemctl enable signage.service)"
  fi
  
  if systemctl is-active --quiet signage.service 2>/dev/null; then
    test_pass "Signage service active"
  else
    test_fail "Signage service not active (run: sudo systemctl start signage.service)"
  fi
else
  test_fail "Signage systemd service not installed"
fi

# Chromium kiosk service
if [ -f /etc/systemd/system/chromium-kiosk.service ]; then
  test_pass "Chromium kiosk systemd service installed"
  
  if systemctl is-enabled --quiet chromium-kiosk.service 2>/dev/null; then
    test_pass "Chromium kiosk service enabled at boot"
  else
    test_warn "Chromium kiosk service not enabled (run: sudo systemctl enable chromium-kiosk.service)"
  fi
  
  # Check if graphical target is active (may not be if SSH only)
  if systemctl is-active --quiet graphical.target 2>/dev/null; then
    if systemctl is-active --quiet chromium-kiosk.service 2>/dev/null; then
      test_pass "Chromium kiosk service active"
    else
      test_warn "Chromium kiosk service not active (expected if no display attached)"
    fi
  else
    test_info "Graphical target not active (headless mode)"
  fi
else
  test_fail "Chromium kiosk systemd service not installed"
fi

# Kiosk script
if [ -f /home/pi/start-kiosk.sh ]; then
  test_pass "Kiosk startup script installed"
  
  if [ -x /home/pi/start-kiosk.sh ]; then
    test_pass "Kiosk script is executable"
  else
    test_warn "Kiosk script not executable (run: chmod +x /home/pi/start-kiosk.sh)"
  fi
else
  test_fail "Kiosk startup script not installed"
fi

# ============================================================================
# Display Checks
# ============================================================================

print_header "Display Configuration"

# Check if Chromium installed
if command -v chromium-browser &> /dev/null; then
  test_pass "Chromium browser installed"
else
  test_fail "Chromium browser not installed (run: sudo apt install chromium-browser)"
fi

# Check if unclutter installed
if command -v unclutter &> /dev/null; then
  test_pass "Unclutter (cursor hider) installed"
else
  test_warn "Unclutter not installed (run: sudo apt install unclutter)"
fi

# Check if X server is running
if [ -n "${DISPLAY:-}" ] && xset q &>/dev/null; then
  test_pass "X server running on DISPLAY=$DISPLAY"
  
  # Check screen saver settings
  XSET_OUTPUT=$(xset q | grep "DPMS is")
  if echo "$XSET_OUTPUT" | grep -q "Disabled"; then
    test_pass "DPMS (power management) disabled"
  else
    test_info "DPMS status: $XSET_OUTPUT"
  fi
else
  test_info "X server not detected (expected if SSH only)"
fi

# Check auto-login
if grep -q "autologin-user=pi" /etc/lightdm/lightdm.conf 2>/dev/null; then
  test_pass "Auto-login configured for pi user"
elif [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
  test_pass "Auto-login configured (console)"
else
  test_warn "Auto-login not configured (run: sudo raspi-config)"
fi

# ============================================================================
# Summary
# ============================================================================

print_header "Validation Summary"

echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Failed:${NC}   $FAILED"

echo

if [ $FAILED -eq 0 ]; then
  if [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Signage player is ready.${NC}"
    exit 0
  else
    echo -e "${YELLOW}⚠ All critical checks passed, but some warnings were found.${NC}"
    echo "Review warnings above and address if needed."
    exit 0
  fi
else
  echo -e "${RED}✗ Some checks failed. Please resolve errors before deployment.${NC}"
  echo "Refer to TROUBLESHOOTING.md for assistance."
  exit 1
fi
