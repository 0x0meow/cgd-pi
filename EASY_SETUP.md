# Easy Setup Guide for CoreGeek Displays Signage Player

This guide provides the simplest way to set up your Raspberry Pi as a digital signage display.

---

## What You Need

- Raspberry Pi 4 or 5 (4GB+ RAM recommended)
- MicroSD card (32GB minimum)
- Monitor with HDMI cable
- Keyboard (for initial setup only)
- Network connection (Ethernet recommended)

---

## Setup Steps

### Step 1: Prepare Your Raspberry Pi

1. **Flash Raspberry Pi OS**:
   - Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
   - Flash **Raspberry Pi OS (64-bit)** to your SD card
   - During setup in the imager:
     - Set hostname (e.g., `cg-signage-taproom`)
     - Enable SSH
     - Set a strong password
     - Configure WiFi (if not using Ethernet)

2. **Boot Your Pi**:
   - Insert the SD card
   - Connect monitor, keyboard, and network
   - Power on the Pi

### Step 2: Run the Automated Setup Script

This single command will do everything:

```bash
curl -fsSL https://raw.githubusercontent.com/0x0meow/cgd-pi/main/scripts/quick-setup.sh | sudo bash
```

The script will automatically:
- ✅ Update your system
- ✅ Install Node.js 20+
- ✅ Install Chromium browser
- ✅ Download the signage player
- ✅ Ask for your API settings
- ✅ Install all dependencies
- ✅ Set up automatic startup
- ✅ Configure kiosk mode
- ✅ Run diagnostics to verify controller connectivity and kiosk readiness
- ✅ Confirm before replacing an existing installation
- ✅ Show a summary of the settings it saves so you can double-check them

If diagnostics find an issue (for example, unreachable controller or missing services), the installer stops so you can resolve it before rebooting.

> 💡 When the script starts you'll see a short overview of what it is about to do and you'll be asked to confirm before it begins making changes. Have your network connection ready—the script now checks for internet access up front so you know immediately if something needs attention.

### Step 3: Configure Your API Settings

When prompted by the setup script, enter:

1. **API Key** (optional - leave empty if not required)
2. **Controller URL** (e.g., `https://displays.example.com`)
3. **Venue Slug** (optional - leave empty to show all events)

> ⚠️ The signage service refuses to run with the sample controller URL, so be sure to enter your production endpoint during setup.

### Step 4: Reboot

After the script completes, reboot your Pi:

```bash
sudo reboot
```

After rebooting, your display will automatically show the signage!

---

## What the Script Does

### System Updates
- Updates all system packages
- Installs required dependencies

### Node.js Installation
- Installs Node.js 20 (LTS version)
- Sets up npm package manager

### Application Setup
- Clones the repository to `/opt/signage`
- Installs Node.js dependencies
- Creates configuration file

### Service Configuration
- Sets up systemd service for the signage player
- Configures Chromium kiosk mode
- Enables automatic startup on boot
- Runs post-install diagnostics and halts if connectivity or service checks fail

---

## Managing Your Display

### Check Status

```bash
# Check if services are running
sudo systemctl status signage chromium-kiosk

# View logs
sudo journalctl -u signage -f
```

### Restart Services

```bash
# Restart signage service
sudo systemctl restart signage

# Restart display
sudo systemctl restart chromium-kiosk

# Restart everything
sudo reboot
```

### Update Configuration

```bash
# Edit settings
sudo nano /opt/signage/.env

# Apply changes
sudo systemctl restart signage
sudo systemctl restart chromium-kiosk
```

### Update Software

```bash
cd /opt/signage
sudo git pull
sudo npm install --production
sudo systemctl restart signage chromium-kiosk
```

### Run Diagnostics

```bash
sudo /opt/signage/scripts/pi-cli.sh diagnostics
```

---

## Configuration Options

Edit `/opt/signage/.env` to customize:

```bash
# CoreGeek Displays Controller
CONTROLLER_BASE_URL=https://displays.example.com
CONTROLLER_API_KEY=                    # Optional

# Venue Filter
VENUE_SLUG=                            # Empty = all events

# Refresh Rates
FETCH_INTERVAL_S=60                    # Fetch new events every 60 seconds
DISPLAY_ROTATION_S=10                  # Rotate cards every 10 seconds
MAX_EVENTS_DISPLAY=6                   # Show up to 6 events

# Offline Behavior
OFFLINE_RETENTION_HOURS=24             # Cache events for 24 hours

# Server
PORT=3000                              # Local server port
```

---

## Troubleshooting

### Display Shows Black Screen

```bash
# Check if services are running
sudo systemctl status chromium-kiosk

# Restart kiosk
sudo systemctl restart chromium-kiosk
```

### No Events Showing

```bash
# Check service logs
sudo journalctl -u signage -n 50

# Test API connection
curl http://localhost:3000/healthz

# Verify configuration
cat /opt/signage/.env
```

### Service Won't Start

```bash
# Check for errors
sudo journalctl -u signage -n 100

# Reinstall dependencies
cd /opt/signage
sudo npm install --production
sudo systemctl restart signage
```

For more detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## Remote Access (SSH)

To manage your display remotely:

```bash
# SSH into your Pi
ssh pi@cg-signage-taproom.local

# Or use IP address
ssh pi@192.168.1.100
```

---

## Manual Setup (Alternative)

If you prefer to set up manually instead of using the automated script, follow the steps in [README.md](README.md#3-manual-setup-alternative).

---

## Support

- **Issues**: [GitHub Issues](https://github.com/0x0meow/cgd-pi/issues)
- **Full Documentation**: [README.md](README.md)
- **Troubleshooting**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

## Security Tips

- Change the default password immediately
- Use SSH keys instead of passwords
- Keep your system updated: `sudo apt update && sudo apt upgrade`
- Use Ethernet instead of WiFi when possible
- Restrict SSH access to trusted networks
