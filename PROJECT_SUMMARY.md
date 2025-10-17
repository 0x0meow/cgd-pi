# CoreGeek Displays Raspberry Pi Signage Player – Project Summary

## Overview

This repository delivers the native Raspberry Pi signage player for CoreGeek Displays (docs/server-api-events.md, Section 8). The solution removes Docker dependencies in favour of a streamlined Node.js service managed directly by systemd and configured through a single installer script.

---

## Repository Structure

```
├── server.js                   # Node.js Express server
├── views/events.njk            # Nunjucks template for signage
├── public/signage.css          # Responsive styles
├── scripts/
│   ├── quick-setup.sh          # Automated install/reinstall
│   ├── validate.sh             # Deployment validation suite
│   └── configure-api-key.js    # CLI for controller API key
├── deployment/
│   ├── signage.service         # systemd unit for Node.js runtime
│   └── chromium-kiosk.service  # systemd unit for Chromium kiosk
├── deployment/start-kiosk.sh   # Chromium launcher script
├── .env.example                # Configuration template
└── docs…                       # Architecture, troubleshooting, checklist
```

---

## Key Components

### server.js
- Express server serving `/`, `/healthz`, `/status`
- Periodic controller fetch with configurable interval
- Media URL hydration and chronological sorting
- In-memory cache with offline retention window
- Optional venue scoping via `VENUE_SLUG`
- Supports authenticated requests using `CONTROLLER_API_KEY`

### Views & Styling
- `views/events.njk` implements templated event cards, offline notices, and metadata
- `public/signage.css` optimises typography, layout, and animations for 1080p/4K displays

### Automation Scripts
- `scripts/quick-setup.sh`
  - Ensures root execution, updates OS packages
  - Installs Chromium, git, curl, unclutter, and Node.js 20+
  - Removes existing `/opt/signage` installation (with `.env` backup) before cloning latest code
  - Restores configuration, prompts for controller URL, and triggers the API Key CLI if needed
  - Installs npm dependencies and systemd services, enables auto-login, starts services, and offers reboot
- `scripts/configure-api-key.js`
  - Node CLI to create/update `.env`
  - Accepts `--key`, `--env`, and `--signage-dir` arguments for automation
  - Provides interactive prompt when run without arguments
- `scripts/validate.sh`
  - Hardware checks (model, architecture, temperature)
  - Node.js/npm version verification
  - Ensures required files, `.env`, and service units exist
  - Validates controller connectivity, `/healthz`, `/status`
  - Confirms Chromium/unclutter availability and auto-login configuration

### Systemd Units & Kiosk Script
- `deployment/signage.service` runs `npm start` equivalent (`node server.js`) with restart policies and environment loading from `/opt/signage/.env`
- `deployment/chromium-kiosk.service` executes `/home/pi/start-kiosk.sh` after the signage service is healthy
- `deployment/start-kiosk.sh` ensures display power management, waits for health endpoint, and launches Chromium in kiosk mode with cursor hiding

---

## Configuration & CLI

- `.env.example` documents every environment variable with guidance
- Quick setup copies template (or restores backup) and ensures `CONTROLLER_BASE_URL`
- API key handling delegated to `npm run configure-api-key`, which can be invoked non-interactively (`npm run configure-api-key -- --key ...`)
- Additional tuning variables: `FETCH_INTERVAL_S`, `DISPLAY_ROTATION_S`, `MAX_EVENTS_DISPLAY`, `OFFLINE_RETENTION_HOURS`, `PORT`

---

## Operations & Maintenance

- Install/Reinstall: `curl -fsSL .../quick-setup.sh | sudo bash`
- Update: `git pull && npm install --production && sudo systemctl restart signage chromium-kiosk`
- API Key rotation: `npm run configure-api-key` (interactive or with `--key`)
- Monitoring: `sudo journalctl -u signage -f`, `curl http://localhost:3000/healthz`
- Validation: `./scripts/validate.sh`

The single setup script always produces a clean deployment, reinstalling dependencies while preserving configuration backups, fulfilling the request for automated provisioning without Docker.
