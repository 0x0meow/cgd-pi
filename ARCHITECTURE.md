# CoreGeek Displays - Architecture Overview

This document visualises the native Raspberry Pi deployment used by the CoreGeek Displays signage player.

---

## System Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Raspberry Pi 4/5 (ARM64)                 │
│                    Raspberry Pi OS (64-bit)                 │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌────────────────────────────────────────────────────┐    │
│  │        Chromium Browser (Kiosk Mode)               │    │
│  │        systemd: chromium-kiosk.service             │    │
│  │                                                    │    │
│  │  • Launches http://localhost:3000 in full screen   │    │
│  │  • Auto-login + cursor hiding (unclutter)          │    │
│  │  • Restarts automatically on crash                 │    │
│  └───────────────┬────────────────────────────────────┘    │
│                  │ HTTP GET                                │
│                  ▼                                         │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Node.js Express Service (server.js)               │    │
│  │  systemd: signage.service                          │    │
│  │                                                    │    │
│  │  • Renders signage views with Nunjucks             │    │
│  │  • Fetches controller events + metadata            │    │
│  │  • Maintains in-memory cache + offline flag        │    │
│  │  • Exposes /, /status, /healthz endpoints          │    │
│  └───────────────┬────────────────────────────────────┘    │
│                  │ HTTPS (node-fetch)                      │
└──────────────────┼─────────────────────────────────────────┘
                   │
                   ▼
        CoreGeek Displays Controller (HTTPS API)
```

---

## Data Flow

```
Controller API        Raspberry Pi                    Display
──────────────        ────────────                    ───────
GET /events ────────► Node fetch() ──┐
                     hydrateMedia()  │  cachedDataset
GET /venues/:slug ─► Node fetch() ───┤──→ offline fallback + timestamps
                                      │
Media /uploads/* ◄── Chromium ────────┘  (HTTP requests from kiosk)
                                      │
                                      ▼
                               events.njk renders
                                      │
                                      ▼
                               HDMI Monitor
```

The server polls the controller at configurable intervals (default 60s). Successful responses refresh the cache and clear the offline flag; failures reuse cached content for up to 24 hours.

---

## Boot Sequence

```
Power On
  └─► Raspberry Pi OS initialises
       ├─► Network comes online
       ├─► systemd starts signage.service
       │     ├─► Node.js installs dependencies (pre-deployed)
       │     ├─► server.js executes
       │     ├─► Immediate event fetch + scheduler
       │     └─► /healthz available
       ├─► systemd starts chromium-kiosk.service
       │     ├─► Auto-login ensured
       │     ├─► start-kiosk.sh waits for healthz
       │     └─► Chromium launches in kiosk mode
       └─► Signage visible (~60-90s total)
```

---

## File Structure

```
/opt/signage/                     # Managed by quick-setup.sh
├── .env                          # Deployment configuration
├── .env.example                  # Template
├── deployment/
│   ├── signage.service           # Node.js systemd unit
│   └── chromium-kiosk.service    # Chromium kiosk unit
├── public/                       # Static assets (CSS, fonts)
├── scripts/
│   ├── quick-setup.sh            # Installer / reinstaller
│   ├── validate.sh               # Post-install checks
│   └── configure-api-key.js      # CLI for controller API key
├── views/                        # Nunjucks templates
├── package.json                  # Node metadata
└── server.js                     # Express application

/home/pi/start-kiosk.sh           # Launches Chromium (copied by installer)
/etc/systemd/system/
  ├── signage.service
  └── chromium-kiosk.service
```

---

## Configuration Flow

```
.env.example
    │
    └─► quick-setup.sh copies to .env (or restores backup)
           │
           ├─► Prompts for CONTROLLER_BASE_URL if missing
           ├─► Invokes configure-api-key CLI when key empty
           └─► Applies VENUE_SLUG / overrides from environment
                │
                ▼
        server.js reads process.env.* at runtime
```

The `scripts/configure-api-key.js` CLI can be invoked post-install to set, rotate, or clear the API key without editing the file manually.

---

## Monitoring & Health

- `GET /healthz` – returns HTTP 200 with cache + offline metadata when healthy, 503 otherwise.
- `GET /status` – detailed JSON payload including uptime, memory usage, and cached events.
- `systemctl status signage` – confirms Node.js service state and restarts automatically on failures.
- `systemctl status chromium-kiosk` – monitors kiosk launcher.

These endpoints and services are designed to integrate with Pi-level monitoring or third-party supervisors.

---

## Update Strategy

1. Pull latest code: `git pull`
2. Install dependencies: `npm install --production`
3. Restart services: `sudo systemctl restart signage chromium-kiosk`

Alternatively, rerun `quick-setup.sh` for a clean reinstall; the script backs up the existing `.env` before replacing the codebase.

---

This native architecture keeps deployments lightweight, resilient, and easy to manage on Raspberry Pi hardware without Docker.
