# Raspberry Pi Deployment Checklist

Use this checklist when deploying a new signage player to ensure all steps are completed correctly.

## Pre-Deployment

- [ ] Raspberry Pi 4/5 hardware acquired (4GB+ RAM)
- [ ] MicroSD card flashed with Raspberry Pi OS (64-bit)
- [ ] Network connectivity tested (Ethernet preferred)
- [ ] Monitor connected via HDMI and powered on
- [ ] CoreGeek Displays controller URL and venue slug identified

## Initial Setup (Section 8.2)

- [ ] SSH access configured and tested
- [ ] `pi` user password changed
- [ ] Hostname set: `sudo raspi-config nonint do_hostname cg-signage-<location>`
- [ ] Timezone configured: `sudo raspi-config nonint do_change_timezone <zone>`
- [ ] System updated: `sudo apt update && sudo apt full-upgrade -y`
- [ ] Reboot completed

## Software Installation (Section 8.3)

- [ ] Docker installed: `curl -fsSL https://get.docker.com | sh`
- [ ] User added to docker group: `sudo usermod -aG docker pi`
- [ ] Docker enabled at boot: `sudo systemctl enable docker`
- [ ] Chromium browser installed: `sudo apt install -y chromium-browser unclutter`
- [ ] System rebooted to apply group membership

## Application Deployment (Section 8.4-8.6)

- [ ] Deployment directory created: `sudo mkdir -p /opt/signage`
- [ ] Repository cloned or release downloaded to `/opt/signage`
- [ ] `.env` file created from `.env.example`
- [ ] Environment variables configured:
  - [ ] `CONTROLLER_BASE_URL` set
  - [ ] `VENUE_SLUG` set (or left empty for all events)
  - [ ] `FETCH_INTERVAL_S` configured
  - [ ] Other settings reviewed
- [ ] Docker image built: `docker buildx build --platform linux/arm64 -t coregeek-signage:latest .`
- [ ] Docker compose started: `docker compose up -d`
- [ ] Container health verified: `docker compose ps` and `curl http://localhost:3000/healthz`

## Systemd Services (Section 8.6-8.7)

- [ ] Signage service installed: `sudo cp deployment/signage.service /etc/systemd/system/`
- [ ] Signage service enabled: `sudo systemctl enable signage.service`
- [ ] Signage service started: `sudo systemctl start signage.service`
- [ ] Kiosk script installed: `sudo cp deployment/start-kiosk.sh /home/pi/`
- [ ] Kiosk script made executable: `sudo chmod +x /home/pi/start-kiosk.sh`
- [ ] Kiosk service installed: `sudo cp deployment/chromium-kiosk.service /etc/systemd/system/`
- [ ] Kiosk service enabled: `sudo systemctl enable chromium-kiosk.service`
- [ ] Auto-login configured: `sudo raspi-config nonint do_boot_behaviour B4`
- [ ] Final reboot: `sudo reboot`

## Post-Deployment Verification

- [ ] Display shows signage after boot (within 2 minutes)
- [ ] Events are visible and properly formatted
- [ ] Images load correctly
- [ ] No error messages visible
- [ ] Check health endpoint: `curl http://localhost:3000/healthz`
- [ ] Verify logs: `docker compose -f /opt/signage/docker-compose.yml logs`
- [ ] Test offline resilience (disconnect network briefly)
- [ ] Confirm events auto-refresh after `FETCH_INTERVAL_S`

## Production Hardening (Section 8.8)

- [ ] SSH key authentication configured (password auth disabled)
- [ ] Firewall rules configured (if applicable)
- [ ] Remote monitoring/logging configured
- [ ] Scheduled reboots configured (optional): `sudo crontab -e`
- [ ] Backup/restore procedure documented
- [ ] Update schedule established

## Documentation

- [ ] Deployment notes recorded (hostname, IP, location, venue)
- [ ] Contact information for venue/IT documented
- [ ] Escalation procedures defined
- [ ] Monitoring dashboard configured (if applicable)

## Sign-Off

- **Deployed by**: _________________
- **Date**: _________________
- **Location**: _________________
- **Hostname**: _________________
- **IP Address**: _________________
- **Venue Slug**: _________________
- **Notes**: _________________
