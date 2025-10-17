# CoreGeek Displays - Architecture Diagrams

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Raspberry Pi 4/5 (ARM64)                     │
│                      Raspberry Pi OS Lite                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │         Chromium Browser (Kiosk Mode)                  │    │
│  │         systemd: chromium-kiosk.service                │    │
│  │                                                         │    │
│  │  • Full-screen mode (--kiosk --app)                    │    │
│  │  • No browser chrome                                   │    │
│  │  • Auto-restart on crash                               │    │
│  │  • URL: http://localhost:3000                          │    │
│  └──────────────────────┬─────────────────────────────────┘    │
│                         │ HTTP GET                              │
│                         ▼                                       │
│  ┌────────────────────────────────────────────────────────┐    │
│  │    Docker Container (coregeek-signage:latest)          │    │
│  │    systemd: signage.service                            │    │
│  │    Network: host mode (localhost:3000)                 │    │
│  │                                                         │    │
│  │  ┌─────────────────────────────────────────────────┐  │    │
│  │  │   Node.js Express Server (server.js)            │  │    │
│  │  │                                                  │  │    │
│  │  │  Routes:                                         │  │    │
│  │  │    GET /           → Render events.njk          │  │    │
│  │  │    GET /healthz    → Health check               │  │    │
│  │  │    GET /status     → Debug info                 │  │    │
│  │  │                                                  │  │    │
│  │  │  Background Tasks:                               │  │    │
│  │  │    setInterval()   → Fetch events every 60s     │  │    │
│  │  │                                                  │  │    │
│  │  │  Caching:                                        │  │    │
│  │  │    cachedDataset   → In-memory event storage    │  │    │
│  │  │    Offline mode    → 24hr retention             │  │    │
│  │  └─────────────────────────────────────────────────┘  │    │
│  │                         │                              │    │
│  │                         │ HTTPS (fetch)                │    │
│  └─────────────────────────┼──────────────────────────────┘    │
│                            │                                   │
└────────────────────────────┼───────────────────────────────────┘
                             │
                             ▼ Internet
              ┌──────────────────────────────┐
              │  CoreGeek Displays Controller │
              │   (displays.example.com)      │
              │                               │
              │  Public API Endpoints:        │
              │   GET /api/public/events      │
              │   GET /api/public/venues/:id  │
              │   GET /uploads/*              │
              └───────────────────────────────┘
```

## Data Flow

```
Controller      Network        Raspberry Pi                Display
─────────       ────────       ────────────                ────────

   [DB]
    │
    ├─→ Events API
    │   /api/public/events
    │             │
    │             │ HTTPS GET
    │             │ Every 60s
    │             ▼
    │         Docker Container
    │         ┌──────────────┐
    │         │ fetch()      │
    │         │   ↓          │
    │         │ Hydrate URLs │
    │         │   ↓          │
    │         │ Sort by date │
    │         │   ↓          │
    │         │ Cache data   │───────────┐
    │         └──────────────┘           │
    │                                    │ Offline
    │                                    │ Resilience
    ├─→ Media Files                     │ (24h cache)
    │   /uploads/*.png ──────────────────┘
    │             │
    │             │ HTTP GET (from browser)
    │             │
    │             ▼
    │         Chromium
    │         ┌──────────────┐
    │         │ localhost:3000│
    │         │   ↓          │
    │         │ Render HTML  │
    │         │   ↓          │
    │         │ Load CSS     │
    │         │   ↓          │
    │         │ Load Images  │
    │         └──────────────┘
    │                   │
    │                   │ HDMI
    │                   ▼
    │             ┌────────────┐
    │             │  Monitor   │
    │             │  (1920x1080)│
    └─────────────│  Digital   │
                  │  Signage   │
                  └────────────┘
```

## Boot Sequence

```
Power On
   │
   ├─→ Raspberry Pi OS Boots
   │     │
   │     ├─→ Network Initialization
   │     │     └─→ Wi-Fi/Ethernet connects
   │     │
   │     ├─→ Docker Service Starts (systemd)
   │     │     └─→ Docker daemon running
   │     │
   │     ├─→ Signage Service Starts (systemd)
   │     │     └─→ docker compose up -d
   │     │           │
   │     │           ├─→ Pull image (if updated)
   │     │           ├─→ Start container
   │     │           ├─→ Node.js server starts
   │     │           ├─→ Initial event fetch
   │     │           └─→ Health check passes ✓
   │     │
   │     ├─→ Graphical Desktop Loads (X11)
   │     │     └─→ Auto-login as 'pi' user
   │     │
   │     └─→ Chromium Kiosk Starts (systemd)
   │           │
   │           ├─→ Disable screen saver (xset)
   │           ├─→ Hide cursor (unclutter)
   │           ├─→ Wait for localhost:3000/healthz
   │           └─→ Launch Chromium in kiosk mode
   │                 │
   │                 └─→ Full-screen signage visible ✓
   │
   └─→ Ready (total time: ~60-90 seconds)
```

## File Structure

```
/opt/signage/                    # Deployment directory
├── .env                         # Configuration (CONTROLLER_BASE_URL, etc.)
├── docker-compose.yml           # Docker stack definition
├── logs/                        # Container logs (optional)
└── [other repo files]

/home/pi/
└── start-kiosk.sh              # Chromium startup script

/etc/systemd/system/
├── signage.service             # Docker stack manager
└── chromium-kiosk.service      # Chromium kiosk manager

Container Internal:
/app/
├── server.js                   # Main application
├── package.json                # Dependencies
├── node_modules/               # Installed packages
├── views/
│   └── events.njk             # Event display template
└── public/
    └── signage.css            # Styling
```

## Environment Configuration Flow

```
.env.example (template)
      │
      ├─→ Copy to .env
      │
      ▼
.env (deployment config)
      │
      ├─→ CONTROLLER_BASE_URL=https://displays.example.com
      ├─→ VENUE_SLUG=coregeek-taproom
      ├─→ FETCH_INTERVAL_S=60
      ├─→ MAX_EVENTS_DISPLAY=6
      └─→ OFFLINE_RETENTION_HOURS=24
      │
      ├─→ docker-compose.yml (env_file)
      │
      ▼
Docker Container Environment Variables
      │
      ├─→ process.env.CONTROLLER_BASE_URL
      ├─→ process.env.VENUE_SLUG
      └─→ [etc.]
      │
      ▼
server.js Configuration Object
      │
      └─→ Used by fetch logic, routes, etc.
```

## Network Flow

```
Internet                 Raspberry Pi              Display
────────                 ────────────              ───────

┌─────────────┐
│ Controller  │
│ HTTPS API   │
└──────┬──────┘
       │
       │ Port 443 (HTTPS)
       │ Outbound only
       │
       ▼
┌─────────────┐
│ Pi Firewall │
│ (optional)  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Docker      │         ┌──────────┐
│ Container   │◄────────│ Chromium │
│ Port 3000   │  HTTP   │ Browser  │
└─────────────┘ localhost└─────┬────┘
                               │
                               │ HDMI
                               │
                               ▼
                         ┌──────────┐
                         │ Monitor  │
                         └──────────┘

Notes:
• No inbound ports required
• Controller must be publicly accessible via HTTPS
• Container uses host networking (localhost:3000)
• Chromium and container communicate on loopback
```

## State Machine

```
┌─────────────┐
│   Initial   │
│   (Empty)   │
└──────┬──────┘
       │
       │ Server starts
       │ Immediate fetch
       ▼
┌─────────────┐     Fetch Success     ┌─────────────┐
│  Fetching   │────────────────────────▶│   Healthy   │
└──────┬──────┘                         └──────┬──────┘
       │                                       │
       │ Fetch Failure                         │ Every FETCH_INTERVAL_S
       │ (Network error)                       │ Fetch again
       ▼                                       │
┌─────────────┐                                │
│   Offline   │◄───────────────────────────────┘
│  (Cached)   │          Fetch Failure
└──────┬──────┘          (Use cache)
       │
       │ Cache age < OFFLINE_RETENTION_HOURS
       │ Display cached events
       │
       ├───────────────────────────────────────┐
       │                                       │
       │ Cache expires                         │ Network restored
       ▼                                       ▼
┌─────────────┐                         ┌─────────────┐
│   Unhealthy │                         │   Healthy   │
│  (No data)  │                         │  (Recovered)│
└─────────────┘                         └─────────────┘
       │                                       │
       │ Network restored                      │
       │ Successful fetch                      │
       └───────────────────────────────────────┘
```

## Monitoring & Health

```
External Monitoring          Health Checks
───────────────────          ─────────────

┌──────────────┐
│ Admin/Staff  │
└──────┬───────┘
       │
       │ Check display visually
       │ Events updating?
       │
       ▼
┌──────────────┐           ┌──────────────┐
│   Display    │           │  Docker HC   │
│   Screen     │           │  /healthz    │
└──────────────┘           └──────┬───────┘
                                  │
                                  │ Every 30s
                                  │
                                  ▼
                           ┌──────────────┐
       SSH Access ────────▶│ systemd logs │
       Troubleshoot        │  journalctl  │
                           └──────┬───────┘
                                  │
                                  │ Log aggregation
                                  │
                                  ▼
                           ┌──────────────┐
                           │ Monitoring   │
                           │ Dashboard    │
                           │ (optional)   │
                           └──────────────┘
```

---

## Key Design Decisions

1. **Host Networking**: Simplifies localhost access from Chromium, avoids port mapping complexity in kiosk scenario

2. **systemd Integration**: Ensures services start on boot and restart on failure; native to Raspberry Pi OS

3. **In-Memory Cache**: Fast access, sufficient for signage use case; no database overhead

4. **Chromium Kiosk**: Mature, widely supported; better rendering than lightweight browsers

5. **Docker for App**: Isolation, easy updates, consistent environment across Pi devices

6. **Static Asset Serving**: Express serves CSS/JS; simple architecture vs. separate web server

7. **Periodic Fetch**: Pull model avoids webhook complexity; suitable for event update frequency

8. **ARM64 Build**: Future-proof for Pi 5 and newer models; backward compatible with Pi 4

---

These diagrams are referenced in the main README.md and help visualize the architecture described in docs/server-api-events.md Section 8.
