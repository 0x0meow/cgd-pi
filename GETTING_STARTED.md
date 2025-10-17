# 🚀 CoreGeek Displays - Raspberry Pi Signage Player

## Complete Production-Ready Implementation

This repository contains the **complete, production-ready implementation** of the Raspberry Pi Kiosk Integration for CoreGeek Displays, as specified in **docs/server-api-events.md Section 8**.

---

## ✨ What's Included

### Core Application
- ✅ **Node.js Express Server** (`server.js`) - Event fetching, caching, and rendering
- ✅ **ARM64 Docker Container** (`Dockerfile`) - Optimized for Raspberry Pi 4/5
- ✅ **Nunjucks Templates** (`views/events.njk`) - Beautiful event display
- ✅ **Responsive CSS** (`public/signage.css`) - HD/4K display optimization

### Deployment Infrastructure
- ✅ **Docker Compose** (`docker-compose.yml`) - One-command deployment
- ✅ **systemd Services** (`deployment/*.service`) - Boot-on-startup management
- ✅ **Chromium Kiosk** (`deployment/start-kiosk.sh`) - Full-screen browser automation

### Automation & Tools
- ✅ **Quick Setup Script** (`scripts/quick-setup.sh`) - Automated deployment
- ✅ **Validation Script** (`scripts/validate.sh`) - Health checks and diagnostics
- ✅ **Environment Template** (`.env.example`) - Easy configuration

### Documentation
- ✅ **README.md** - Comprehensive setup guide
- ✅ **TROUBLESHOOTING.md** - Common issues and solutions
- ✅ **DEPLOYMENT_CHECKLIST.md** - Step-by-step deployment verification
- ✅ **ARCHITECTURE.md** - Visual diagrams and design decisions
- ✅ **PROJECT_SUMMARY.md** - Technical implementation details

---

## 🎯 Key Features

### Robust Event Fetching
- Periodic refresh from CoreGeek Displays public API
- Configurable fetch intervals (default: 60s)
- Automatic media URL hydration
- Smart event sorting by date

### Offline Resilience
- 24-hour event cache for network outages
- Automatic recovery when connection restores
- Offline mode indicator in UI
- Health check endpoints for monitoring

### Beautiful Display
- Responsive grid layout (1-3 columns)
- Optimized for 1920x1080 and 4K displays
- High-contrast colors for TV/monitor visibility
- Smooth animations and transitions
- Event carousel for large datasets

### Production-Ready
- Docker containerization for consistency
- systemd integration for auto-start/restart
- Security hardening (non-root user, resource limits)
- Comprehensive logging and health checks
- Zero-downtime updates

---

## 📦 Quick Start

### Option 1: Automated Setup (Recommended)

```bash
# On a fresh Raspberry Pi OS (64-bit) installation:
curl -fsSL https://raw.githubusercontent.com/coregeek/cgd-pi/main/scripts/quick-setup.sh | sudo bash
```

**Time to deploy**: ~5 minutes  
**What it does**:
1. Updates system packages
2. Installs Docker, Chromium, dependencies
3. Clones repository to `/opt/signage`
4. Configures environment (prompts for controller URL)
5. Builds ARM64 Docker image
6. Installs and enables systemd services
7. Configures auto-login for kiosk mode
8. Reboots to start signage display

### Option 2: Manual Deployment

See detailed instructions in **[README.md](README.md)** → Quick Start section.

**Time to deploy**: ~15-20 minutes

---

## 🔧 Configuration

### Required Settings

Edit `/opt/signage/.env`:

```bash
CONTROLLER_BASE_URL=https://displays.example.com  # Your controller URL
VENUE_SLUG=coregeek-taproom                      # Optional: venue slug
```

### Optional Tuning

```bash
FETCH_INTERVAL_S=60          # How often to fetch events
DISPLAY_ROTATION_S=10        # Carousel rotation speed
MAX_EVENTS_DISPLAY=6         # Events shown simultaneously
OFFLINE_RETENTION_HOURS=24   # Cache duration
```

See **[.env.example](.env.example)** for all available options.

---

## 📊 Validation

After deployment, verify everything is working:

```bash
cd /opt/signage
./scripts/validate.sh
```

**What it checks**:
- ✓ System information (Pi model, memory, temperature)
- ✓ Docker installation and configuration
- ✓ Application files and environment
- ✓ Container health and status
- ✓ Network connectivity to controller
- ✓ systemd service configuration
- ✓ Display settings and auto-login

---

## 🛠️ Management

### Status Checks

```bash
# Quick health check
curl http://localhost:3000/healthz

# Detailed status
curl http://localhost:3000/status | jq

# Service status
sudo systemctl status signage chromium-kiosk

# Container logs
docker compose -f /opt/signage/docker-compose.yml logs -f
```

### Restart Display

```bash
# Restart just the browser
sudo systemctl restart chromium-kiosk

# Restart the backend (fetches fresh data)
docker compose -f /opt/signage/docker-compose.yml restart

# Full reboot
sudo reboot
```

### Update Software

```bash
cd /opt/signage

# Pull latest code
git pull

# Rebuild and restart
docker buildx build --platform linux/arm64 -t coregeek-signage:latest .
docker compose down && docker compose up -d
sudo systemctl restart chromium-kiosk
```

---

## 📚 Documentation Map

| Document | Purpose |
|----------|---------|
| **[README.md](README.md)** | Complete setup guide and quick start |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | System diagrams and design decisions |
| **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** | Common issues and solutions |
| **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** | Technical implementation details |
| **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** | Step-by-step deployment verification |
| **[.env.example](.env.example)** | Configuration reference |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│       Raspberry Pi 4/5 (ARM64)          │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Chromium (Kiosk)                │  │
│  │  http://localhost:3000           │  │
│  └─────────────┬────────────────────┘  │
│                │                        │
│  ┌─────────────▼────────────────────┐  │
│  │  Docker Container                │  │
│  │  - Express server                │  │
│  │  - Event fetching & caching      │  │
│  │  - Template rendering            │  │
│  └─────────────┬────────────────────┘  │
│                │                        │
└────────────────┼────────────────────────┘
                 │ HTTPS
                 ▼
      ┌─────────────────────┐
      │  CoreGeek Displays  │
      │  Public API         │
      └─────────────────────┘
```

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for detailed diagrams.

---

## 🎨 Customization

### Branding

Edit `public/signage.css`:
```css
:root {
  --color-primary: #2563eb;    /* Brand color */
  --font-size-lg: 2.5rem;      /* Adjust for display size */
}
```

### Layout

Edit `views/events.njk` to change:
- Event card structure
- Header/footer content
- Displayed fields

### Behavior

Edit `.env` to adjust:
- Refresh frequency
- Event limits
- Offline duration

---

## 🔐 Security

- ✅ Non-root container user
- ✅ No inbound ports required
- ✅ HTTPS-only API communication
- ✅ SSH key authentication recommended
- ✅ Firewall-friendly (outbound only)

See **[README.md](README.md)** → Production Best Practices → Security

---

## 🐛 Troubleshooting

Common issues and solutions in **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**:

- **Black screen on boot** → Check kiosk service logs
- **Events not updating** → Verify controller connectivity
- **Images not loading** → Check media URL hydration
- **Container unhealthy** → Review fetch interval and cache settings
- **Performance issues** → Monitor temperature and memory

---

## 📞 Support

- **Documentation**: This repository + referenced docs
- **Issues**: [GitHub Issues](https://github.com/coregeek/cgd-pi/issues)
- **Reference**: CoreGeek Displays `docs/server-api-events.md` Section 8
- **Validation**: Run `./scripts/validate.sh` for diagnostics

---

## ✅ Implementation Checklist

This implementation fully satisfies **docs/server-api-events.md Section 8**:

- ✅ **8.1** Architecture & Requirements
- ✅ **8.2** Prepare Raspberry Pi OS
- ✅ **8.3** Install Docker Engine
- ✅ **8.4** Build the Signage Container
- ✅ **8.5** Runtime Configuration
- ✅ **8.6** Deploy on the Raspberry Pi
- ✅ **8.7** Configure Chromium Kiosk on the Host
- ✅ **8.8** Monitoring, Updates & Recovery

---

## 📁 Project Structure

```
cgd-pi/
├── 📄 server.js                    # Main Express application
├── 📄 package.json                 # Node.js dependencies
├── 📄 Dockerfile                   # ARM64 container build
├── 📄 docker-compose.yml           # Deployment configuration
├── 📄 .env.example                 # Configuration template
│
├── 📁 views/
│   └── events.njk                  # Event display template
│
├── 📁 public/
│   └── signage.css                 # Display styling
│
├── 📁 deployment/
│   ├── signage.service             # Docker stack service
│   ├── chromium-kiosk.service      # Kiosk service
│   └── start-kiosk.sh              # Kiosk startup script
│
├── 📁 scripts/
│   ├── quick-setup.sh              # Automated deployment
│   └── validate.sh                 # Health validation
│
├── 📖 README.md                    # Setup guide
├── 📖 ARCHITECTURE.md              # System diagrams
├── 📖 TROUBLESHOOTING.md           # Issue solutions
├── 📖 PROJECT_SUMMARY.md           # Technical details
├── 📖 DEPLOYMENT_CHECKLIST.md      # Verification checklist
└── 📄 LICENSE                      # MIT License
```

---

## 🎯 Use Cases

Perfect for:
- **Breweries & Taprooms** - Display tap list and events
- **Restaurants & Bars** - Show daily specials and entertainment
- **Event Venues** - Highlight upcoming shows and performances
- **Community Centers** - Promote classes and activities
- **Retail Stores** - Advertise promotions and events
- **Corporate Offices** - Display company events and announcements

---

## 🚀 Next Steps

1. **Deploy**: Follow Quick Start above
2. **Configure**: Edit `/opt/signage/.env` with your settings
3. **Validate**: Run `./scripts/validate.sh`
4. **Customize**: Adjust CSS/templates for your brand
5. **Monitor**: Set up logging and health checks
6. **Scale**: Deploy to multiple locations

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built to specification from **CoreGeek Displays Server & Events API Guide**.

Architecture, implementation, and documentation strictly follow the requirements in `docs/server-api-events.md` Section 8: Option 1 – Raspberry Pi Kiosk Integration.

---

**Ready to deploy?** Start with the [Quick Start](#-quick-start) above or dive into the full [README.md](README.md).

**Questions?** Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or run `./scripts/validate.sh` for diagnostics.

**Need help?** Open an issue on GitHub with validation output and logs.

---

*CoreGeek Displays Raspberry Pi Signage Player v1.0.0*
