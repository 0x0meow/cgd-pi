# CoreGeek Displays Signage Player - Troubleshooting Guide

This guide provides solutions to common issues encountered when deploying and operating the Raspberry Pi signage player.

---

## Table of Contents

1. [Display Issues](#display-issues)
2. [Docker Container Issues](#docker-container-issues)
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

# Check container health
docker compose -f /opt/signage/docker-compose.yml ps
docker compose -f /opt/signage/docker-compose.yml logs
```

**Solutions**:
1. **Container not running**:
   ```bash
   cd /opt/signage
   docker compose up -d
   ```

2. **Port conflict**:
   ```bash
   # Check if port 3000 is in use
   sudo lsof -i :3000
   
   # Change PORT in .env if needed
   ```

---

## Docker Container Issues

### Container Fails to Start

**Symptoms**: `docker compose ps` shows container as "Exited" or "Restarting".

**Diagnostic Steps**:
```bash
cd /opt/signage

# View container logs
docker compose logs signage

# Check for configuration errors
docker compose config

# Verify image exists
docker images | grep coregeek-signage
```

**Common Solutions**:

1. **Missing environment file**:
   ```bash
   # Ensure .env exists
   ls -la /opt/signage/.env
   
   # Create from example if missing
   cp .env.example .env
   nano .env
   ```

2. **Invalid environment variables**:
   ```bash
   # Test .env syntax
   docker compose config
   
   # Fix any parsing errors in .env
   ```

3. **Image not built**:
   ```bash
   docker buildx build --platform linux/arm64 -t coregeek-signage:latest .
   docker compose up -d
   ```

### Container Running But Unhealthy

**Symptoms**: `docker compose ps` shows "(unhealthy)" status.

**Diagnostic Steps**:
```bash
# Check health endpoint
curl http://localhost:3000/healthz

# View detailed logs
docker compose logs -f signage

# Inspect container health checks
docker inspect coregeek-signage | grep -A 10 Health
```

**Solutions**:
1. **Controller unreachable**:
   ```bash
   # Test controller connectivity
   curl https://displays.example.com/api/public/events
   
   # Verify CONTROLLER_BASE_URL in .env
   grep CONTROLLER_BASE_URL /opt/signage/.env
   ```

2. **Cache expired**:
   - Container may be unhealthy if offline for > `OFFLINE_RETENTION_HOURS`
   - Restore network connectivity and container will recover automatically

---

## Network & Connectivity

### Cannot Reach Controller

**Symptoms**: Logs show "Fetch failed", offline banner visible on display.

**Diagnostic Steps**:
```bash
# Test DNS resolution
nslookup displays.example.com

# Test HTTPS connectivity
curl -v https://displays.example.com/api/public/events

# Check network interface
ip addr show
ping -c 4 8.8.8.8
```

**Solutions**:

1. **Wi-Fi disconnected**:
   ```bash
   # Check Wi-Fi status
   iwconfig
   
   # Reconnect to Wi-Fi
   sudo raspi-config nonint do_wifi_ssid_passphrase "<SSID>" "<password>"
   ```

2. **Ethernet not configured**:
   ```bash
   # Check Ethernet interface
   ip link show eth0
   
   # Bring up interface if down
   sudo ip link set eth0 up
   ```

3. **DNS issues**:
   ```bash
   # Test with Google DNS
   sudo nano /etc/resolv.conf
   # Add: nameserver 8.8.8.8
   ```

4. **Firewall blocking**:
   ```bash
   # Check if firewall is active
   sudo ufw status
   
   # Ensure outbound HTTPS allowed
   sudo ufw allow out 443/tcp
   ```

### SSL Certificate Errors

**Symptoms**: Logs show "certificate verify failed" or "SSL handshake error".

**Solutions**:
```bash
# Update CA certificates
sudo apt update
sudo apt install -y ca-certificates
sudo update-ca-certificates

# Restart container
docker compose -f /opt/signage/docker-compose.yml restart
```

---

## Event Data Issues

### Events Not Updating

**Symptoms**: Same events shown for extended period, timestamps in footer not changing.

**Diagnostic Steps**:
```bash
# Check fetch logs
docker compose -f /opt/signage/docker-compose.yml logs signage | grep -i fetch

# Verify fetch interval
docker compose -f /opt/signage/docker-compose.yml exec signage printenv FETCH_INTERVAL_S

# Check last fetch time
curl http://localhost:3000/status | jq .lastSuccessfulFetch
```

**Solutions**:

1. **Fetch interval too long**:
   ```bash
   # Reduce FETCH_INTERVAL_S in .env
   nano /opt/signage/.env
   docker compose restart
   ```

2. **Container not auto-refreshing**:
   ```bash
   # Force restart to trigger immediate fetch
   docker compose -f /opt/signage/docker-compose.yml restart signage
   ```

### No Events Displayed

**Symptoms**: "No Upcoming Events" message shown.

**Diagnostic Steps**:
```bash
# Check raw API response
curl https://displays.example.com/api/public/events

# If using venue slug, check venue-specific endpoint
curl https://displays.example.com/api/public/venues/your-slug/events

# Verify events in controller admin UI
```

**Solutions**:

1. **No events marked public**:
   - Log into CoreGeek Displays admin
   - Set `visiblePublic: true` on events
   - Wait for next fetch cycle

2. **Wrong venue slug**:
   ```bash
   # Verify venue slug in .env
   grep VENUE_SLUG /opt/signage/.env
   
   # List available venues
   curl https://displays.example.com/api/public/venues
   ```

3. **Events in the past**:
   - Check `startDatetime` and `endDatetime` on events
   - Events may be filtered out if already ended

### Images Not Loading

**Symptoms**: Event cards show placeholder icons instead of images.

**Diagnostic Steps**:
```bash
# Check event data for imageUrl
curl http://localhost:3000/status | jq '.events[0].imageUrl'

# Test image URL directly
curl -I https://displays.example.com/uploads/example.png
```

**Solutions**:

1. **Media URL hydration issue**:
   ```bash
   # Verify CONTROLLER_BASE_URL
   grep CONTROLLER_BASE_URL /opt/signage/.env
   
   # Check hydration logic in logs
   docker compose logs signage | grep -i media
   ```

2. **CORS or access issues**:
   - Ensure `/api/public/uploads/*` endpoint is accessible
   - Test from browser: `https://displays.example.com/uploads/test.png`

---

## Performance Problems

### Slow Rendering / Lag

**Symptoms**: Display stutters, animations choppy, page loads slowly.

**Diagnostic Steps**:
```bash
# Check CPU temperature
vcgencmd measure_temp

# Check memory usage
free -h

# Check CPU load
uptime

# Monitor container resources
docker stats coregeek-signage
```

**Solutions**:

1. **Overheating**:
   ```bash
   # Check temperature (should be < 80°C)
   vcgencmd measure_temp
   
   # Add heatsink or fan to Raspberry Pi
   # Ensure adequate ventilation
   ```

2. **Insufficient memory**:
   ```bash
   # Reduce MAX_EVENTS_DISPLAY in .env
   nano /opt/signage/.env
   # Set MAX_EVENTS_DISPLAY=4
   
   # Increase container memory limit in docker-compose.yml
   ```

3. **Too many events**:
   - Reduce `MAX_EVENTS_DISPLAY` to 4-6
   - Increase `DISPLAY_ROTATION_S` to reduce rotation frequency

4. **4K display on Pi 4**:
   - Lower display resolution to 1080p
   - Or upgrade to Raspberry Pi 5

### High Network Usage

**Symptoms**: Bandwidth exhaustion, slow other devices on network.

**Solutions**:
```bash
# Increase fetch interval
nano /opt/signage/.env
# Set FETCH_INTERVAL_S=300 (5 minutes)

# Restart container
docker compose restart
```

---

## System Issues

### SD Card Full

**Symptoms**: Container won't start, logs show "No space left on device".

**Diagnostic Steps**:
```bash
# Check disk usage
df -h

# Find large files
sudo du -sh /var/* | sort -h

# Check Docker disk usage
docker system df
```

**Solutions**:
```bash
# Clean Docker cache
docker system prune -a

# Clean old logs
sudo journalctl --vacuum-time=7d

# Limit log sizes in docker-compose.yml (already configured)
```

### System Won't Boot

**Symptoms**: Pi doesn't complete boot process.

**Solutions**:

1. **SD card corruption**:
   - Remove SD card, back up data
   - Run fsck on another computer
   - Reflash OS if necessary

2. **Power supply insufficient**:
   - Use official Raspberry Pi power supply (5V 3A for Pi 4)
   - Check for low voltage warnings: `dmesg | grep voltage`

3. **Boot partition full**:
   - Mount SD card on another computer
   - Clean `/boot` partition

### Time Sync Issues

**Symptoms**: Event times displayed incorrectly, SSL certificate errors.

**Solutions**:
```bash
# Check current time
date

# Enable and restart time sync
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# Set correct timezone
sudo raspi-config nonint do_change_timezone America/Chicago

# Force immediate sync
sudo systemctl restart systemd-timesyncd
sleep 5
date
```

---

## Getting Help

If none of these solutions resolve your issue:

1. **Collect diagnostic information**:
   ```bash
   # Save to file for support
   {
     echo "=== System Info ==="
     uname -a
     cat /etc/os-release
     
     echo -e "\n=== Docker Status ==="
     docker compose -f /opt/signage/docker-compose.yml ps
     
     echo -e "\n=== Container Logs ==="
     docker compose -f /opt/signage/docker-compose.yml logs --tail=50 signage
     
     echo -e "\n=== Kiosk Status ==="
     sudo systemctl status chromium-kiosk
     
     echo -e "\n=== Network ==="
     ip addr show
     
     echo -e "\n=== Environment ==="
     docker compose -f /opt/signage/docker-compose.yml config
   } > ~/signage-diagnostics.txt
   ```

2. **Open GitHub issue**: [github.com/0x0meow/cgd-pi/issues](https://github.com/0x0meow/cgd-pi/issues)
3. **Include**: Diagnostics file, description of issue, steps to reproduce
4. **Reference**: [docs/server-api-events.md](../coregeek-displays/docs/server-api-events.md) Section 8.8

---

## Preventative Maintenance

To avoid issues:

- **Weekly**: Check `docker compose logs` for errors
- **Monthly**: Update OS (`sudo apt update && sudo apt full-upgrade`)
- **Quarterly**: Clean Docker cache (`docker system prune`)
- **Annually**: Replace SD card (SD cards degrade over time)
