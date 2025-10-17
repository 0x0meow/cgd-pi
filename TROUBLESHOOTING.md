# CoreGeek Displays Signage Player - Troubleshooting Guide

This guide provides solutions to common issues encountered when deploying and operating the Raspberry Pi signage player (Native Node.js deployment).

---

## Table of Contents

1. [Display Issues](#display-issues)
2. [Service Issues](#service-issues)
3. [Network & Connectivity](#network--connectivity)
4. [Event Data Issues](#event-data-issues)
5. [Performance Problems](#performance-problems)
6. [System Issues](#system-issues)

---

## Display Issues

### Black Screen on Boot

**Symptoms**: Monitor shows no output or black screen after Pi boots.

**Diagnostic Steps**:
```bash
# Check if Chromium is running
ps aux | grep chromium

# Check kiosk service status
sudo systemctl status chromium-kiosk

# View kiosk logs
sudo journalctl -u chromium-kiosk -n 50
```

**Common Causes & Solutions**:

1. **Chromium not starting**:
   ```bash
   sudo systemctl restart chromium-kiosk
   ```

2. **Auto-login not configured**:
   ```bash
   sudo raspi-config nonint do_boot_behaviour B4
   sudo reboot
   ```

3. **X11 DISPLAY variable issues**:
   ```bash
   # Check if X server is running
   ps aux | grep Xorg
   
   # Verify DISPLAY in kiosk script
   grep DISPLAY /home/pi/start-kiosk.sh
   ```

4. **HDMI detection problems**:
   ```bash
   # Add to /boot/config.txt
   sudo nano /boot/config.txt
   # Add: hdmi_force_hotplug=1
   sudo reboot
   ```

### Display Shows Browser Chrome/UI

**Symptoms**: Chromium title bar, address bar, or bookmarks visible.

**Solution**:
```bash
# Verify kiosk flags in start script
cat /home/pi/start-kiosk.sh

# Should include --kiosk and --app flags
# Restart kiosk
sudo systemctl restart chromium-kiosk
```

### Events Not Visible / White Page

**Symptoms**: Chromium loads but page is blank or shows error.

**Diagnostic Steps**:
```bash
# Test signage service directly
curl http://localhost:3000

# Check service health
sudo systemctl status signage
sudo journalctl -u signage -n 50
```

**Solutions**:
1. **Service not running**:
   ```bash
   sudo systemctl start signage
   ```

2. **Port conflict**:
   ```bash
   # Check if port 3000 is in use
   sudo lsof -i :3000
   
   # Change PORT in .env if needed
   sudo nano /opt/signage/.env
   sudo systemctl restart signage
   ```

3. **Node.js error**:
   ```bash
   # Check for errors in logs
   sudo journalctl -u signage -n 100
   
   # Verify Node.js is installed
   node --version
   ```

---

## Service Issues

### Service Fails to Start

**Symptoms**: `systemctl status signage` shows "failed" or "inactive".

**Diagnostic Steps**:
```bash
# Check service status
sudo systemctl status signage

# View service logs
sudo journalctl -u signage -n 100

# Verify Node.js installation
node --version
npm --version

# Check if application files exist
ls -la /opt/signage/
```

**Common Causes & Solutions**:

1. **Missing dependencies**:
   ```bash
   cd /opt/signage
   sudo npm install --production
   sudo systemctl restart signage
   ```

2. **Environment file missing**:
   ```bash
   # Check if .env exists
   ls -la /opt/signage/.env
   
   # Create from example if missing
   sudo cp /opt/signage/.env.example /opt/signage/.env
   sudo nano /opt/signage/.env
   # Configure required variables
   sudo systemctl restart signage
   ```

3. **Permission issues**:
   ```bash
   # Fix ownership
   sudo chown -R pi:pi /opt/signage
   sudo systemctl restart signage
   ```

4. **Port already in use**:
   ```bash
   # Find what's using port 3000
   sudo lsof -i :3000
   
   # Kill the process or change port in .env
   sudo nano /opt/signage/.env
   # Change PORT=3000 to PORT=3001
   sudo systemctl restart signage
   ```

### Service Running But Unhealthy

**Symptoms**: Service is active but health check fails.

**Diagnostic Steps**:
```bash
# Test health endpoint
curl http://localhost:3000/healthz

# View real-time logs
sudo journalctl -u signage -f

# Check if port is accessible
sudo netstat -tulpn | grep 3000
```

**Solutions**:

1. **API connectivity issues**:
   ```bash
   # Test controller API
   curl -I https://displays.example.com/api/public/events
   
   # Check .env configuration
   cat /opt/signage/.env | grep CONTROLLER
   ```

2. **Offline for too long**:
   - Service may be unhealthy if offline for > `OFFLINE_RETENTION_HOURS`
   - Restore network connectivity and service will recover automatically

3. **Application crash loop**:
   ```bash
   # Check for repeated restarts
   sudo journalctl -u signage | grep "Started\|Stopped"
   
   # View error details
   sudo journalctl -u signage -p err
   ```

---

## Network & Connectivity

Start with the automated diagnostics to capture a full report in one command:

```bash
sudo /opt/signage/scripts/pi-cli.sh diagnostics
```

### "Events Temporarily Unavailable" Message

**Symptoms**: Display shows fallback message instead of events.

**Diagnostic Steps**:
```bash
# Test internet connectivity
ping -c 3 8.8.8.8

# Test controller reachability
curl -I https://displays.example.com/api/public/events

# Check DNS resolution
nslookup displays.example.com

# View fetch logs
sudo journalctl -u signage | grep -i fetch
```

**Solutions**:

1. **No internet connection**:
   ```bash
   # Check network interfaces
   ip addr show
   
   # Restart networking
   sudo systemctl restart NetworkManager
   
   # For Ethernet issues, check cable
   ethtool eth0
   ```

2. **Controller URL incorrect**:
   ```bash
   # Verify CONTROLLER_BASE_URL
   cat /opt/signage/.env | grep CONTROLLER_BASE_URL
   
   # Update if needed
   sudo nano /opt/signage/.env
   sudo systemctl restart signage
   ```

3. **Firewall blocking outbound**:
   ```bash
   # Check if firewall is active
   sudo ufw status
   
   # Allow outbound HTTPS if needed
   sudo ufw allow out 443/tcp
   ```

4. **SSL/TLS certificate issues**:
   ```bash
   # Update CA certificates
   sudo apt update
   sudo apt install --reinstall ca-certificates
   sudo systemctl restart signage
   ```

### Slow Event Updates

**Symptoms**: Events take too long to update after changes in controller.

**Diagnostic Steps**:
```bash
# Check current fetch interval
cat /opt/signage/.env | grep FETCH_INTERVAL_S

# View fetch activity
sudo journalctl -u signage | grep -i "fetching events"
```

**Solutions**:

1. **Increase fetch frequency**:
   ```bash
   sudo nano /opt/signage/.env
   # Set: FETCH_INTERVAL_S=30  # (was 60)
   sudo systemctl restart signage
   ```

2. **Manual refresh**:
   ```bash
   # Restart service to force immediate fetch
   sudo systemctl restart signage
   ```

---

## Event Data Issues

### No Events Showing

**Symptoms**: Display shows "No upcoming events" when events exist.

**Diagnostic Steps**:
```bash
# Test API directly
curl https://displays.example.com/api/public/events

# Check if venue filter is too restrictive
cat /opt/signage/.env | grep VENUE_SLUG

# View fetch logs
sudo journalctl -u signage | grep -i "fetched.*events"
```

**Solutions**:

1. **Venue slug mismatch**:
   ```bash
   sudo nano /opt/signage/.env
   # Remove or correct VENUE_SLUG
   sudo systemctl restart signage
   ```

2. **API authentication required**:
   ```bash
   # Check if API requires key
   sudo nano /opt/signage/.env
   # Add: CONTROLLER_API_KEY=your-key-here
   sudo systemctl restart signage
   ```

3. **Events are private**:
   - Only public events are displayed
   - Check event visibility in CoreGeek Displays controller

### Event Images Not Loading

**Symptoms**: Event cards show placeholder images or broken images.

**Diagnostic Steps**:
```bash
# Check image URL hydration
sudo journalctl -u signage | grep -i media

# Test image URLs from browser
# Open: http://localhost:3000
```

**Solutions**:

1. **Media URLs not absolute**:
   - Check that `CONTROLLER_BASE_URL` is set correctly
   - Media URLs should be hydrated to full https:// URLs

2. **CORS issues** (if external images):
   - Not applicable for server-side rendering
   - Check browser console for client-side issues

3. **Image files missing**:
   - Verify images exist in controller's media library
   - Check controller logs for upload issues

---

## Performance Problems

### High CPU Usage

**Symptoms**: `htop` shows high CPU utilization, Pi runs hot.

**Diagnostic Steps**:
```bash
# Monitor CPU usage
top -bn1 | head -20

# Check process tree
ps aux --forest | grep -E 'node|chromium'

# Check service resource usage
systemctl status signage
```

**Solutions**:

1. **Chromium consuming resources**:
   ```bash
   # Disable hardware acceleration if causing issues
   # Edit start-kiosk.sh
   sudo nano /home/pi/start-kiosk.sh
   # Add: --disable-gpu
   sudo systemctl restart chromium-kiosk
   ```

2. **Too many events fetched**:
   ```bash
   sudo nano /opt/signage/.env
   # Set: MAX_EVENTS_DISPLAY=6  # (reduce if higher)
   sudo systemctl restart signage
   ```

3. **Fetch interval too aggressive**:
   ```bash
   sudo nano /opt/signage/.env
   # Set: FETCH_INTERVAL_S=120  # (increase from 60)
   sudo systemctl restart signage
   ```

### High Memory Usage

**Symptoms**: `free -h` shows low available memory, system swapping.

**Diagnostic Steps**:
```bash
# Check memory usage
free -h

# Monitor process memory
ps aux --sort=-%mem | head -10

# Check for memory leaks
sudo journalctl -u signage | grep -i memory
```

**Solutions**:

1. **Chromium memory leak**:
   ```bash
   # Restart kiosk daily via cron
   crontab -e
   # Add: 0 3 * * * systemctl --user restart chromium-kiosk
   ```

2. **Node.js memory limit**:
   ```bash
   # Edit service file
   sudo nano /etc/systemd/system/signage.service
   # Add under [Service]:
   # Environment="NODE_OPTIONS=--max-old-space-size=512"
   sudo systemctl daemon-reload
   sudo systemctl restart signage
   ```

3. **Reduce cache size**:
   ```bash
   sudo nano /opt/signage/.env
   # Set: OFFLINE_RETENTION_HOURS=12  # (reduce from 24)
   sudo systemctl restart signage
   ```

---

## System Issues

### Disk Space Full

**Symptoms**: Service won't start, logs show "No space left on device".

**Diagnostic Steps**:
```bash
# Check disk usage
df -h

# Find large files
sudo du -h / | sort -rh | head -20

# Check log sizes
sudo du -sh /var/log/*
```

**Solutions**:

1. **Clear old logs**:
   ```bash
   # Clean systemd journal
   sudo journalctl --vacuum-time=7d
   
   # Rotate logs
   sudo logrotate -f /etc/logrotate.conf
   ```

2. **Clear package cache**:
   ```bash
   sudo apt clean
   sudo apt autoremove -y
   ```

3. **Expand SD card** (if cloned to larger card):
   ```bash
   sudo raspi-config --expand-rootfs
   sudo reboot
   ```

### Time/Date Incorrect

**Symptoms**: SSL errors, log timestamps wrong.

**Solution**:
```bash
# Check current time
timedatectl

# Set timezone
sudo timedatectl set-timezone America/Chicago

# Enable NTP
sudo timedatectl set-ntp true

# Force sync
sudo systemctl restart systemd-timesyncd

# Verify
timedatectl
```

### Updates Breaking System

**Symptoms**: Signage stops working after `apt upgrade`.

**Solution**:
```bash
# Check which packages were upgraded
cat /var/log/apt/history.log

# Reinstall Node.js if updated
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt install -y nodejs

# Reinstall dependencies
cd /opt/signage
sudo npm install --production

# Restart services
sudo systemctl restart signage
sudo systemctl restart chromium-kiosk
```

---

## Getting Help

If problems persist after trying these solutions:

1. **Collect diagnostic information**:
   ```bash
   # System info
   uname -a
   cat /etc/os-release
   
   # Service status
   sudo systemctl status signage chromium-kiosk
   
   # Recent logs
   sudo journalctl -u signage -n 200 > signage.log
   sudo journalctl -u chromium-kiosk -n 200 > kiosk.log
   
   # Environment (redact sensitive values!)
   cat /opt/signage/.env
   ```

2. **Check GitHub Issues**:
   - Visit: https://github.com/0x0meow/cgd-pi/issues
   - Search for similar problems
   - Open new issue with diagnostic info

3. **Contact CoreGeek Displays Support**:
   - Include diagnostic logs
   - Describe what you've already tried
   - Specify your Raspberry Pi model and OS version

---

## Useful Commands Reference

```bash
# Service management
sudo systemctl status signage
sudo systemctl restart signage
sudo systemctl stop signage
sudo systemctl start signage

# View logs
sudo journalctl -u signage -f          # Follow logs
sudo journalctl -u signage -n 100      # Last 100 lines
sudo journalctl -u signage -p err      # Errors only
sudo journalctl -u signage --since "1 hour ago"

# Test endpoints
curl http://localhost:3000/healthz
curl http://localhost:3000
curl https://displays.example.com/api/public/events

# System monitoring
htop                    # Interactive process viewer
df -h                   # Disk usage
free -h                 # Memory usage
sudo lsof -i :3000     # What's using port 3000
ps aux | grep node     # Find Node.js processes

# Quick fixes
sudo systemctl restart signage chromium-kiosk
sudo reboot
```
