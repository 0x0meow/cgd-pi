# 🚀 CoreGeek Displays - Raspberry Pi Signage Player

## Complete Production-Ready Implementation

This repository contains the **production-ready Raspberry Pi kiosk player** for CoreGeek Displays public event feeds. Everything runs natively on the Pi – no containers required – and can be deployed or re-deployed with a single command.

---

## ✨ What's Included

### Core Application
- ✅ **Node.js Express Server** (`server.js`) – Event fetching, caching, and rendering
- ✅ **Nunjucks Templates** (`views/events.njk`) – Responsive event layouts
- ✅ **Optimised CSS** (`public/signage.css`) – Designed for HD/4K displays

### Deployment Automation
- ✅ **Quick Setup Script** (`scripts/quick-setup.sh`) – One command install/reinstall
- ✅ **API Key CLI** (`npm run configure-api-key`) – Interactive credential helper
- ✅ **Systemd Services** (`deployment/*.service`) – Boot-on-start management
- ✅ **Chromium Kiosk Script** (`deployment/start-kiosk.sh`) – Full-screen display launcher

### Tooling & Docs
- ✅ **Validation Script** (`scripts/validate.sh`) – Hardware/network checks
- ✅ **Environment Template** (`.env.example`) – Copy/paste configuration
- ✅ **Documentation** (`README.md`, `TROUBLESHOOTING.md`, etc.) – Everything you need to support deployments

---

## 🎯 Key Features

### Smart Event Delivery
- Periodic sync with the CoreGeek Displays controller
- Optional venue scoping using slugs
- Automatic media URL hydration and chronological ordering

### Offline Resilience
- 24-hour cached dataset keeps signage online during outages
- Health endpoints for monitoring and alerting
- Visual offline indicator for operators

### Managed Display Experience
- Chromium kiosk mode with hidden cursor support
- Configurable carousel rotation and event limits
- Systemd-managed services for automatic recovery

---

## 📦 Quick Start (Single Command)

Run this on a fresh Raspberry Pi OS (64-bit) installation:

```bash
curl -fsSL https://raw.githubusercontent.com/0x0meow/cgd-pi/main/scripts/quick-setup.sh | sudo bash
```

**What the script does:**
1. Updates system packages
2. Installs Chromium, git, curl, and dependencies
3. Installs Node.js 20+ (upgrading if required)
4. Removes any previous installation and clones to `/opt/signage`
5. Restores previous `.env` if available, otherwise prompts for settings
6. Invokes the API Key CLI if the key is missing
7. Installs npm dependencies
8. Installs & enables systemd services (signage + Chromium kiosk)
9. Configures auto-login for kiosk mode
10. Starts the signage service and offers to reboot
11. Runs end-to-end diagnostics to confirm controller connectivity and kiosk readiness

Re-running the script always results in a clean reinstall while preserving configuration backups.

> ℹ️ The installer aborts if diagnostics fail, ensuring every Pi leaves setup with a verified connection to the controller.

---

## 🔧 Manual Configuration

If you need to adjust settings after install:

```bash
cd /opt/signage
cp .env.example .env  # if missing
nano .env
```

Key variables:

```ini
CONTROLLER_BASE_URL=https://displays.example.com  # Required
CONTROLLER_API_KEY=                               # Prompted by CLI (can be blank)
VENUE_SLUG=                                       # Optional: restrict to a venue
FETCH_INTERVAL_S=60
DISPLAY_ROTATION_S=10
MAX_EVENTS_DISPLAY=6
OFFLINE_RETENTION_HOURS=24
```

To update the API key at any time:

```bash
cd /opt/signage
npm run configure-api-key
```

Pass `-- --key sk_live_123` to provide the value non-interactively. The CLI creates the `.env` file if it does not yet exist.

---

## 📊 Validation

After deployment (or during troubleshooting) run:

```bash
cd /opt/signage
./scripts/validate.sh
```

The validator confirms:
- Raspberry Pi hardware, architecture, OS, and thermal status
- Node.js / npm versions
- Presence of required files and configuration
- Controller connectivity and health endpoint responses
- Systemd services and kiosk script installation
- Display readiness (Chromium, unclutter, auto-login)

---

## 🛠️ Management

### Service Operations

```bash
sudo systemctl status signage chromium-kiosk
sudo systemctl restart signage chromium-kiosk
sudo journalctl -u signage -f
```

### Application Logs & Health

```bash
curl http://localhost:3000/healthz
curl http://localhost:3000/status | jq
```

### Updating Software

```bash
cd /opt/signage
git pull
npm install --production
sudo systemctl restart signage chromium-kiosk
```

---

## 📚 Documentation Map

| Document | Purpose |
|----------|---------|
| **[README.md](README.md)** | Complete setup & operation guide |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | System diagrams and design decisions |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | Common issues and fixes |
| **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** | Implementation overview |
| **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** | Verification steps |
| **[.env.example](.env.example)** | Configuration reference |

---

## 🏗️ High-Level Architecture

```
┌─────────────────────────────┐
│ Raspberry Pi 4/5 (ARM64)    │
│ ┌─────────────────────────┐ │
│ │ Chromium (Kiosk Mode)   │ │
│ │ http://localhost:3000   │ │
│ └────────────┬────────────┘ │
│              │              │
│ ┌────────────▼────────────┐ │
│ │ Node.js Express Server  │ │
│ │ - Fetch & cache events  │ │
│ │ - Render signage views  │ │
│ │ - Health monitoring     │ │
│ └────────────┬────────────┘ │
│              │              │
└──────────────┼──────────────┘
               │ Internet (HTTPS)
               ▼
      CoreGeek Displays Controller
```

Happy deploying! 🎉
