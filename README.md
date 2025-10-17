# CoreGeek Displays - Raspberry Pi Kiosk Integration

**Production-ready digital signage player for Raspberry Pi 4/5** that consumes CoreGeek Displays public event feeds and displays them in Chromium kiosk mode.

> 📖 **Documentation Reference**: This implementation follows the architecture described in [docs/server-api-events.md](../coregeek-displays/docs/server-api-events.md) **Section 8: Option 1 – Raspberry Pi Kiosk Integration**.

---

## Overview

This signage player consists of:

- **Native Node.js service** – Fetches event data from CoreGeek Displays public API, renders HTML/CSS signage, serves on `http://localhost:3000`
- **Chromium kiosk mode** – Full-screen browser display managed by systemd
- **Offline resilience** – Caches event data and continues displaying when controller is unreachable
- **Auto-updates** – Configurable refresh intervals keep content synchronized

### Architecture

```
┌─────────────────────────────────────────────┐
│         Raspberry Pi 4/5 (ARM64)            │
│                                             │
│  ┌────────────────────────────────────┐   │
│  │  Chromium (Kiosk Mode)             │   │
│  │  http://localhost:3000             │   │
│  └──────────────┬─────────────────────┘   │
│                 │                           │
│  ┌──────────────▼─────────────────────┐   │
│  │  Node.js Express Server            │   │
│  │  - Periodic event fetch            │   │
│  │  - Media URL hydration             │   │
│  │  - Offline caching                 │   │
│  │  - Nunjucks templating             │   │
│  └────────────────────────────────────┘   │
│                 │                           │
│                 ▼                           │
│      Internet (HTTPS)                       │
└─────────────────┼───────────────────────────┘
                  │
                  ▼
    ┌─────────────────────────────┐
    │ CoreGeek Displays Controller │
    │ /api/public/events           │
    │ /api/public/venues/:slug     │
    └─────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Raspberry Pi 4 or 5 (4GB+ RAM recommended)
- MicroSD card (32GB+)
- Raspberry Pi OS (64-bit, Lite or Desktop)
- Stable network connection (Ethernet recommended)
- Monitor with HDMI connection

### 1. Flash Raspberry Pi OS

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash **Raspberry Pi OS (64-bit)**.

**During setup, configure:**
- Hostname: `cg-signage-<location>` (e.g., `cg-signage-taproom`)
- Wi-Fi credentials (if not using Ethernet)
- Enable SSH for remote management
- Set strong password for `pi` user

**Reference**: [docs/server-api-events.md Section 8.2](#)

### 2. Automated Setup (Recommended)

The easiest way to set up the signage player is using our automated setup script:

```bash
curl -fsSL https://raw.githubusercontent.com/0x0meow/cgd-pi/main/scripts/quick-setup.sh | sudo bash
```

The script will:
- Update system packages
- Install Node.js 20+ and required dependencies
- Clone this repository to `/opt/signage`
- Prompt for API key and controller URL
- Install npm dependencies
- Configure systemd services
- Set up Chromium kiosk mode

**After the script completes, reboot your Pi:**

```bash
sudo reboot
```

### 3. Manual Setup (Alternative)

If you prefer to set up manually, follow these steps:

```bash
# Update system
sudo apt update && sudo apt full-upgrade -y

# Set timezone (adjust for your location)
sudo raspi-config nonint do_change_timezone America/Chicago

# Install required packages
sudo apt install -y git curl chromium-browser unclutter

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs

# Reboot to apply changes
sudo reboot
```

**Reference**: [docs/server-api-events.md Section 8.2, 8.3](#)

### 4. Deploy Signage Player

```bash
# Create deployment directory
sudo mkdir -p /opt/signage
cd /opt/signage

# Clone this repository
sudo git clone https://github.com/0x0meow/cgd-pi.git .

# Configure environment (see Configuration section below)
sudo cp .env.example .env
sudo nano .env  # Edit with your settings

# Install Node.js dependencies
sudo npm install --production

# Install systemd services
sudo cp deployment/signage.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable signage.service
sudo systemctl start signage.service

# Verify it's running
sudo systemctl status signage
curl http://localhost:3000/healthz
```

**Reference**: [docs/server-api-events.md Section 8.4, 8.5, 8.6](#)

### 5. Install Chromium Kiosk

```bash
# Install Chromium kiosk service
sudo cp deployment/chromium-kiosk.service /etc/systemd/system/
sudo cp deployment/start-kiosk.sh /home/pi/
sudo chmod +x /home/pi/start-kiosk.sh
sudo chown pi:pi /home/pi/start-kiosk.sh
sudo systemctl enable chromium-kiosk.service

# Enable auto-login (required for kiosk mode)
sudo raspi-config nonint do_boot_behaviour B4  # Desktop auto-login

# Reboot to start kiosk
sudo reboot
```

**Reference**: [docs/server-api-events.md Section 8.6, 8.7](#)

---

## Configuration

### Environment Variables

Create `/opt/signage/.env` with your CoreGeek Displays controller settings:

```bash
# CoreGeek Displays Controller
CONTROLLER_BASE_URL=https://displays.example.com

# Venue Configuration
# Leave empty to display all public events, or specify a venue slug
VENUE_SLUG=coregeek-taproom

# Refresh Settings
FETCH_INTERVAL_S=60          # Fetch events every 60 seconds
DISPLAY_ROTATION_S=10        # Rotate event cards every 10 seconds
MAX_EVENTS_DISPLAY=6         # Show up to 6 events at once

# Offline Behavior
OFFLINE_RETENTION_HOURS=24   # Cache events for 24 hours when offline

# Server Configuration
PORT=3000                    # Internal port (accessed via localhost)
NODE_ENV=production
```

**Reference**: [docs/server-api-events.md Section 8.5](#)

### Venue Modes

**All Events Mode** (leave `VENUE_SLUG` empty):
- Fetches from `/api/public/events`
- Shows all public events across all venues

**Single Venue Mode** (set `VENUE_SLUG`):
- Fetches from `/api/public/venues/:slug/events`
- Shows only events for the specified venue
- Displays venue branding and metadata

---

## Management & Monitoring

### Service Status

```bash
# Check signage service
sudo systemctl status signage
sudo journalctl -u signage -f

# Check Chromium kiosk
sudo systemctl status chromium-kiosk
sudo journalctl -u chromium-kiosk -f

# Check health endpoint
curl http://localhost:3000/healthz
```

### Restart Services

```bash
# Restart signage service (refresh data)
sudo systemctl restart signage

# Restart Chromium (refresh display)
sudo systemctl restart chromium-kiosk

# Full reboot
sudo reboot
```

### View Logs

```bash
# Signage service logs
sudo journalctl -u signage -f

# Chromium kiosk logs
sudo journalctl -u chromium-kiosk -f

# All system logs
sudo journalctl -xe
```

### Update Signage Software

```bash
cd /opt/signage

# Pull latest code
sudo git pull

# Install/update dependencies
sudo npm install --production

# Restart service
sudo systemctl restart signage
sudo systemctl restart chromium-kiosk
```

**Reference**: [docs/server-api-events.md Section 8.8](#)

---

## Customization

### Styling & Branding

Edit `/opt/signage/public/signage.css` to customize:

- Color palette (`:root` CSS variables)
- Font sizes for different display resolutions
- Layout and spacing
- Animation timing

Restart after changes:

```bash
sudo systemctl restart signage
sudo systemctl restart chromium-kiosk
```

### Template Modifications

Edit `/opt/signage/views/events.njk` to change:

- Event card layout
- Header/footer content
- Displayed event fields
- Client-side behavior

### Display Resolution

The CSS is optimized for:

- **1920x1080 (Full HD)** – Default sizing
- **3840x2160 (4K)** – Automatically scales up
- **Portrait displays** – Responsive grid layout

Test on your display and adjust CSS media queries as needed.

---

## Troubleshooting

### Display Shows Black Screen

```bash
# Check if Chromium is running
ps aux | grep chromium

# Check kiosk service logs
sudo journalctl -u chromium-kiosk -n 50

# Restart kiosk
sudo systemctl restart chromium-kiosk
```

### "Events Temporarily Unavailable"

```bash
# Check service health
sudo systemctl status signage
sudo journalctl -u signage -n 50

# Test controller connectivity
curl https://displays.example.com/api/public/events

# Check environment variables
cat /opt/signage/.env
```

### Events Not Updating

```bash
# Check fetch logs
sudo journalctl -u signage | grep -i fetch

# Verify FETCH_INTERVAL_S setting
cat /opt/signage/.env | grep FETCH_INTERVAL_S

# Force refresh
sudo systemctl restart signage
```

### Service Won't Start

```bash
# Check service status
sudo systemctl status signage

# View service logs
sudo journalctl -u signage -n 100

# Reinstall dependencies
cd /opt/signage
sudo npm install --production
sudo systemctl restart signage
```

**Reference**: [docs/server-api-events.md Section 8.8](#)

---

## Production Best Practices

### Security

- Change default `pi` user password immediately
- Use SSH keys instead of passwords
- Keep Raspberry Pi OS updated: `sudo apt update && sudo apt full-upgrade`
- Restrict SSH access (firewall rules or VPN)
- Use HTTPS for controller endpoints

### Reliability

- Use **Ethernet** connection for stability
- Enable watchdog: `sudo modprobe bcm2835_wdt && echo "bcm2835_wdt" | sudo tee -a /etc/modules`
- Set up remote access (Tailscale, WireGuard) for support
- Schedule weekly reboots during off-hours: `sudo crontab -e` → `0 4 * * 1 /sbin/reboot`

### Monitoring

- Monitor service health: `sudo systemctl status signage chromium-kiosk`
- Set up remote logging (syslog, Loki, etc.)
- Monitor disk space: `df -h`
- Track temperature: `vcgencmd measure_temp`

### Updates

- Test updates on staging Pi before deploying to production
- Use `git pull` + `npm install` + `systemctl restart` for updates
- Keep CoreGeek Displays controller updated for latest API features
- Regularly update system packages: `sudo apt update && sudo apt upgrade`

**Reference**: [docs/server-api-events.md Section 8.8](#)

---

## API Integration Details

### Public Endpoints Used

| Endpoint | Purpose | Frequency |
|----------|---------|-----------|
| `GET /api/public/events` | Fetch all public events | Every `FETCH_INTERVAL_S` |
| `GET /api/public/venues/:slug` | Fetch venue metadata | Once per fetch cycle |
| `GET /api/public/venues/:slug/events` | Fetch venue-specific events | Every `FETCH_INTERVAL_S` |
| `GET /api/public/uploads/*` | Load event images | On-demand |

### Data Hydration

The server automatically:

1. Fetches event JSON from controller
2. Converts relative `/uploads/*` paths to fully-qualified URLs
3. Sorts events by `startDatetime` (upcoming first)
4. Caches data for offline resilience
5. Renders HTML with Nunjucks templates

**Reference**: [docs/server-api-events.md Section 2, 4, 5](#)

### Offline Behavior

When the controller is unreachable:

- Last successful dataset is retained for `OFFLINE_RETENTION_HOURS`
- Offline banner appears in UI
- Display continues showing cached events
- Health endpoint returns 503 after cache expires

**Reference**: [docs/server-api-events.md Section 8.8](#)

---

## Hardware Specifications

### Recommended Setup

- **Raspberry Pi 4 (4GB)** or **Raspberry Pi 5 (8GB)**
- **Class 10 microSD** (SanDisk Extreme 32GB+)
- **Official Raspberry Pi Power Supply** (prevents under-voltage)
- **Micro-HDMI to HDMI cable** (Raspberry Pi 4/5 use micro-HDMI)
- **Ethernet cable** (more reliable than Wi-Fi for 24/7 operation)

### Performance Notes

- **Pi 4 (4GB)**: Handles 1080p displays, 6-12 events smoothly
- **Pi 5 (8GB)**: Handles 4K displays, more concurrent events
- **Older Pi models**: May struggle with Chromium rendering; use Pi 4+ for production

---

## Development

### Local Development (Mac/Linux)

```bash
# Install dependencies
npm install

# Start development server with hot reload
npm run dev

# Set environment variables
export CONTROLLER_BASE_URL=https://displays.example.com
export VENUE_SLUG=test-venue
export FETCH_INTERVAL_S=10

# Access at http://localhost:3000
```

### Testing Template Changes

```bash
# Edit views/events.njk or public/signage.css
# Changes reflect immediately - just restart service

sudo nano /opt/signage/views/events.njk
# or
sudo nano /opt/signage/public/signage.css

sudo systemctl restart signage
sudo systemctl restart chromium-kiosk
```

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Support

- **Documentation**: [docs/server-api-events.md](../coregeek-displays/docs/server-api-events.md)
- **Issues**: [GitHub Issues](https://github.com/0x0meow/cgd-pi/issues)
- **Controller Setup**: [CoreGeek Displays Documentation](https://github.com/coregeek/displays)

---

## Acknowledgments

Built according to the specification in **CoreGeek Displays Server & Events API Guide**, Section 8: Raspberry Pi Kiosk Integration.
