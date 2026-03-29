# Lily Deployment Guide

Deploying baker to lily using Docker Compose with HTTPS via Caddy.

**Target:** lily server (NixOS + Docker + Tailscale)
**Last updated:** 2026-03-29 (revised)

---

## 1. Prerequisites

### Required

- [ ] Docker installed and running on lily
  ```bash
  docker --version
  docker compose version
  ```
- [ ] Tailscale set up on lily with a registered hostname (e.g., `lily.tail1234.ts.net`)
- [ ] Tailscale HTTPS certs generated (certs expire ~90 days — you'll need to re-run this periodically):
  ```bash
  tailscale cert --cert-file=certs/lily.tail1234.ts.net.crt --key-file=certs/lily.tail1234.ts.net.key lily.tail1234.ts.net
  ```
- [ ] USB printer (optional): if using thermal printing, verify `/dev/usb/lp0` exists on lily. The docker-compose mounts this device — skip if no printer.
- [ ] Rustic backup tools installed (for automated backups):
  ```bash
  # Install rustic
  curl -L https://github.com/rustic-rs/rustic/releases/latest/download/rustic-linux-x86_64.gz | sudo tee /usr/local/bin/rustic > /dev/null
  sudo chmod +x /usr/local/bin/rustic

  # Install rclone (if not present)
  # Follow: https://rclone.org/install/
  ```

### Optional (for building web on lily)

- [ ] Flutter SDK (for building the web app on lily)
  ```bash
  # From NixOS flake
  nix develop ~/Documents/bakery-shop/.#flutter --command flutter --version
  ```

---

## 2. Clone the Repository

On lily, clone the bakery-shop repo:

```bash
# SSH to lily first
ssh lily

# Clone (or copy from USB if offline)
git clone https://github.com/sinh/bakery-shop.git /srv/bakery-shop
cd /srv/bakery-shop

# Checkout the production branch
git checkout main   # or feature branch for testing
```

**Alternative: Copy from USB drive**

```bash
# Mount USB and copy
sudo mount /dev/sda1 /mnt
sudo cp -r /mnt/bakery-shop /srv/
sudo chown -R $USER:$USER /srv/bakery-shop
cd /srv/bakery-shop
```

---

## 3. Configure Environment

### 3.1 Create `.env` file

```bash
cd /srv/bakery-shop
cp config/docker.example .env
nano .env
```

Set your Tailscale domain:
```
DOMAIN=lily.tail1234.ts.net
```

### 3.2 Set Up Tailscale Certs

```bash
# Create certs directory
mkdir -p certs

# Generate certificates (run on lily with Tailscale running)
tailscale cert --cert-file=certs/${DOMAIN}.crt --key-file=certs/${DOMAIN}.key ${DOMAIN}

# Verify
ls -la certs/
```

### 3.3 Create Prod Data Directory

```bash
mkdir -p prod/data
```

If restoring from a backup:
```bash
# Copy existing baker.db and photos from backup
cp /path/to/backup/baker.db prod/data/
cp -r /path/to/backup/photos prod/data/  # if exists
```

---

## 4. Build Docker Image

```bash
cd /srv/bakery-shop

# Build the baker-server image
docker compose build baker-prod

# Verify the image was created
docker images | grep baker-server
```

---

## 5. Deploy Web Build

> **Important:** `web-build/` is gitignored and won't exist after a fresh clone. You MUST complete this section before starting containers (§6), or Caddy will fail to serve the web app.

### Option A: Build on Lily (requires Flutter)

```bash
cd /srv/bakery-shop

# Build Flutter web using Nix
nix develop ~/Documents/bakery-shop/.#flutter --command bash -c "cd app && flutter build web --release"

# Copy to web-build directory
rm -rf web-build
cp -r app/build/web web-build
```

### Option B: Copy Pre-built from Dev Machine

On your development machine:
```bash
cd ~/Documents/bakery-shop

# Build web
nix develop .#flutter --command bash -c "cd app && flutter build web --release"

# Copy to USB or transfer via network
scp -r app/build/web lily:/srv/bakery-shop/web-build
```

Verify:
```bash
ls -la /srv/bakery-shop/web-build/index.html
```

---

## 6. Start Containers

```bash
cd /srv/bakery-shop

# Start with prod profile (baker-prod + Caddy)
docker compose --profile prod up -d

# Check status
docker compose ps

# View logs
docker compose logs --tail=50
```

Expected output:
```
NAME          IMAGE          STATUS
baker-prod    baker-server   Up (healthy)
caddy         caddy:2-alpine Up
```

---

## 7. Verify Deployment

### 7.1 Check Health Endpoint

```bash
# From lily directly
curl http://localhost:2108/api/health

# From external (via Tailscale)
curl https://lily.tail1234.ts.net/api/health
```

Expected response:
```json
{"status":"ok","schema_version":7}
```

### 7.2 Check Web App

Open in browser:
```
https://lily.tail1234.ts.net/
```

You should see the bakery app. The API calls will be proxied to baker-prod via Caddy.

### 7.3 Verify Data Persistence

```bash
# Check data directory
ls -la /srv/bakery-shop/prod/data/

# Should contain: baker.db, photos/, logs/
```

---

## 8. Automated Backup Setup

The backup infrastructure uses rustic to backup to Wasabi S3. The backup script is at `scripts/wasabi-backup.sh`.

### 8.1 Prerequisites for Backup

```bash
# 1. Verify rclone remote "wasabi-sinh" is configured
rclone config show wasabi-sinh
# If not configured, run: rclone config  (create an S3-compatible remote named wasabi-sinh)

# 2. Create rustic config directory
mkdir -p ~/.config/rustic

# 3. Copy rustic config and add repository section
#    The backup script uses profile "baker-prod", so the file MUST be named baker-prod.toml
cp /srv/bakery-shop/config/rustic/baker.toml ~/.config/rustic/baker-prod.toml

# 4. Add the [repository] section to the config
#    IMPORTANT: The password must match the one used on the dev machine.
#    Using a different password means you can't read existing snapshots.
#    Get the password from the dev machine: grep password ~/.config/rustic/baker.toml
cat >> ~/.config/rustic/baker-prod.toml << 'EOF'

[repository]
repository = "rclone:wasabi-sinh:baker-backup/dev2"
password = "<paste the password from dev machine here>"
EOF

chmod 600 ~/.config/rustic/baker-prod.toml
```

### 8.2 Test Backup Manually

> **Important:** Always set `DATA_DIR` explicitly. The script's default fallback is the dev machine path (`/home/sinh/Documents/bakery-shop/prod/data`) and will back up nothing useful on lily.

```bash
cd /srv/bakery-shop

# Run backup script — DATA_DIR is required on lily
DATA_DIR=/srv/bakery-shop/prod/data ./scripts/wasabi-backup.sh

# Check rustic snapshots
rustic -P baker-prod snapshots
```

### 8.3 Set Up Systemd Timer (Alternative to NixOS module)

If lily is not using NixOS or you prefer standalone systemd units:

```bash
# Create systemd service file
sudo tee /etc/systemd/system/baker-backup.service << 'EOF'
[Unit]
Description=Baker Backup to Wasabi
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/srv/bakery-shop/scripts/wasabi-backup.sh
Environment=DATA_DIR=/srv/bakery-shop/prod/data
User=root
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# Create systemd timer
sudo tee /etc/systemd/system/baker-backup.timer << 'EOF'
[Unit]
Description=Baker Backup Timer - Every 6 hours

[Timer]
OnCalendar=*-*-* 00/6:00:00
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now baker-backup.timer

# Check status
systemctl status baker-backup.timer
systemctl list-timers --all | grep baker
```

### 8.4 NixOS Backup Module (if using NixOS)

If lily uses NixOS, add the backup module to the flake.

> **Note:** `nix/backup.nix` is a function factory that takes `{ self }:` before the standard module args. You must call it with the flake's `self` reference.

```nix
# In your NixOS configuration
{ inputs, ... }:
{
  imports = [
    (import /srv/bakery-shop/nix/backup.nix { self = inputs.self; })
  ];

  services.baker-backup = {
    enable = true;
    dataDir = "/srv/bakery-shop/prod/data";
    user = "root";
    scriptPath = /srv/bakery-shop/scripts/wasabi-backup.sh;
  };
}
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake /srv/bakery-shop#
```

---

## 9. Common Tasks

### Restart Containers

```bash
docker compose --profile prod restart
```

### Update to New Version

```bash
cd /srv/bakery-shop

# Pull latest code
git pull

# Rebuild image
docker compose --profile prod build baker-prod

# Restart
docker compose --profile prod up -d
```

### View Logs

```bash
# All services
docker compose --profile prod logs -f

# Specific service
docker compose --profile prod logs -f baker-prod
docker compose --profile prod logs -f caddy
```

### Stop Containers

```bash
docker compose --profile prod down
```

---

## 10. Troubleshooting

### Caddy not starting

```bash
# Check Caddyfile syntax
docker compose --profile prod config

# View Caddy logs
docker compose --profile prod logs caddy

# Common issue: DOMAIN not set
# Verify .env exists and contains DOMAIN=lily.tail1234.ts.net
cat .env
```

### Baker health check failing

```bash
# Check baker logs
docker compose --profile prod logs baker-prod

# Manually test
docker compose --profile prod exec baker-prod python -c "import urllib.request; urllib.request.urlopen('http://localhost:2108/api/health')"

# Check if port is correct
docker compose --profile prod exec baker-prod ss -tlnp | grep 2108
```

### Web app not loading

```bash
# Verify web-build exists
ls -la web-build/index.html

# Check Caddy is serving correct path
docker compose --profile prod exec caddy cat /etc/caddy/Caddyfile

# Check file permissions
docker compose --profile prod exec caddy ls -la /srv/web/
```

### Backup failing

```bash
# Test rclone connectivity
rclone ls wasabi-sinh:baker-backup/dev2

# Test rustic manually
rustic -P baker-prod snapshots

# Check backup script syntax
bash -n scripts/wasabi-backup.sh
```

---

## 11. Restore from Backup

### 11.1 List Available Snapshots

```bash
rustic -P baker-prod snapshots
```

### 11.2 Restore a Snapshot

```bash
# Stop containers first
cd /srv/bakery-shop
docker compose --profile prod down

# Restore latest snapshot to a temporary directory
mkdir -p /tmp/baker-restore
rustic -P baker-prod restore latest /tmp/baker-restore

# The restored files are under the staging path structure
# Copy baker.db back to prod data
cp /tmp/baker-restore/tmp/baker-backup-staging/baker.db prod/data/baker.db

# Restore photos if they exist
if [ -d /tmp/baker-restore/tmp/baker-backup-staging/photos ]; then
  cp -r /tmp/baker-restore/tmp/baker-backup-staging/photos prod/data/
fi

# Restart containers
docker compose --profile prod up -d

# Verify
curl http://localhost:2108/api/health

# Cleanup
rm -rf /tmp/baker-restore
```

### 11.3 Restore a Specific Snapshot

```bash
# Pick a snapshot ID from the list
rustic -P baker-prod snapshots

# Restore by ID
rustic -P baker-prod restore <snapshot-id> /tmp/baker-restore
```

---

## 12. Tailscale Cert Renewal

Tailscale certs expire after ~90 days. Caddy mounts them read-only, so there is no auto-renewal. You must re-generate manually:

```bash
cd /srv/bakery-shop
tailscale cert --cert-file=certs/${DOMAIN}.crt --key-file=certs/${DOMAIN}.key ${DOMAIN}

# Restart Caddy to pick up new certs
docker compose --profile prod restart caddy
```

Consider setting a calendar reminder every 2 months.

---

## 13. Security Notes

- **Rustic password**: Stored in `~/.config/rustic/baker-key` — keep this file secure
- **Tailscale certs**: Stored in `certs/` directory — don't commit to git
- **.env file**: Contains `DOMAIN` — don't commit to git (already in .gitignore)
- **Docker socket**: Don't expose the Docker socket to containers

---

## 14. Quick Reference

| Command | Purpose |
|---------|---------|
| `docker compose --profile prod up -d` | Start all prod services |
| `docker compose --profile prod restart` | Restart all prod services |
| `docker compose --profile prod logs -f` | Follow logs |
| `docker compose --profile prod down` | Stop all services |
| `curl https://${DOMAIN}/api/health` | Test health endpoint |
| `DATA_DIR=/srv/bakery-shop/prod/data ./scripts/wasabi-backup.sh` | Run manual backup |
| `rustic -P baker-prod snapshots` | List backup snapshots |
| `systemctl status baker-backup.timer` | Check backup timer status |
