#!/usr/bin/env bash
#
# CoreGeek Signage - Chromium Kiosk Startup Script
# Reference: CoreGeek Displays Server API Integration Guide – Section 8.7
#
# This script configures the X11 display and launches Chromium in kiosk mode
# pointing at the local signage service (http://localhost:3000)
#
# Installation:
#   cp deployment/start-kiosk.sh /home/pi/
#   chmod +x /home/pi/start-kiosk.sh
#
# The script will be invoked automatically by chromium-kiosk.service

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SIGNAGE_URL="${SIGNAGE_URL:-http://localhost:3000}"
DISPLAY="${DISPLAY:-:0}"
XAUTHORITY="${XAUTHORITY:-/home/pi/.Xauthority}"

# ============================================================================
# Display Power Management
# ============================================================================

echo "[$(date)] Starting Chromium kiosk for CoreGeek Signage..."

# Export display variables for X11 commands
export DISPLAY
export XAUTHORITY

# Disable screen saver and power management (section 8.7)
echo "  → Disabling screen saver and DPMS..."
xset s off        # Disable screen saver
xset -dpms        # Disable Display Power Management Signaling
xset s noblank    # Prevent screen from blanking

# Hide mouse cursor after 0.5 seconds of inactivity
echo "  → Hiding mouse cursor..."
unclutter -idle 0.5 -root &

# ============================================================================
# Wait for Signage Service
# ============================================================================

echo "  → Waiting for signage service at ${SIGNAGE_URL}..."

MAX_RETRIES=30
RETRY_COUNT=0

until curl -sf "${SIGNAGE_URL}/healthz" > /dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "  ✗ ERROR: Signage service not available after ${MAX_RETRIES} attempts"
    echo "  → Please check service status: sudo systemctl status signage"
    exit 1
  fi
  
  echo "  → Attempt ${RETRY_COUNT}/${MAX_RETRIES}: Service not ready, retrying in 2s..."
  sleep 2
done

echo "  ✓ Signage service is healthy"

# ============================================================================
# Launch Chromium in Kiosk Mode
# ============================================================================

echo "  → Launching Chromium in kiosk mode..."

# Chromium flags explained:
#   --noerrdialogs         : Suppress error dialogs
#   --kiosk                : Full-screen kiosk mode
#   --app=URL              : Launch as standalone app (no browser chrome)
#   --incognito            : Don't save browsing data
#   --disable-infobars     : Hide "Chromium is being controlled" banner
#   --disable-session-crashed-bubble : Don't show crash recovery dialog
#   --disable-features=TranslateUI : Disable translation prompts
#   --check-for-update-interval=31536000 : Effectively disable update checks (1 year)
#   --disable-pinch        : Disable pinch-to-zoom gestures
#   --overscroll-history-navigation=0 : Disable swipe navigation

chromium-browser \
  --noerrdialogs \
  --kiosk \
  --app="${SIGNAGE_URL}" \
  --incognito \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --check-for-update-interval=31536000 \
  --disable-pinch \
  --overscroll-history-navigation=0

# If Chromium exits, log it
echo "[$(date)] Chromium exited with status $?"
