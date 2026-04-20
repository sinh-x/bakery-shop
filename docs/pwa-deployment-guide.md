# PWA Deployment Guide — iOS Access via Safari

> **Feature branch:** `feature/pwa-ios-access`
> **Ticket:** DG-020

## Prerequisites

- Bakery server on Tailnet (Tailscale installed)
- Target iPhones on Tailnet with Tailscale app
- Docker running on the server
- Nix flutter devshell available (`nix develop .#flutter`)

## Step 1: Build Flutter Web

```bash
cd ~/Documents/bakery-shop
./scripts/deploy-web.sh
```

Builds the Flutter web app in the nix flutter devshell and copies output to `web-build/`.

## Step 2: Quick Local Preview (optional, no API)

```bash
cd web-build && python3 -m http.server 8080
```

Open `http://localhost:8080` in a browser. The UI loads but API calls return 404 (no backend). This only verifies the web build renders correctly.

To test with the actual API locally, run `baker serve` in another terminal and set the API URL in the app's settings to `http://localhost:2108`.

## Step 3: Generate HTTPS Certificates

On the bakery server:

```bash
# Find your Tailscale hostname
tailscale status | head -5

# Generate certs
./scripts/renew-certs.sh your-hostname.tail12345.ts.net
```

This writes cert files to `certs/` and restarts Caddy.

## Step 4: Deploy with Docker

```bash
# First time only: set up .env with your Tailscale domain
cp config/docker.example .env
# Edit DOMAIN in .env if the default doesn't match your hostname

docker compose --profile prod up -d
```

This starts:
- `baker-prod` on port 2108 (unchanged — Android APK uses this)
- `caddy` on port 443 (HTTPS — serves web app + proxies `/api/` to baker)

## Step 5: Test on iPhone

1. Make sure the iPhone is connected to Tailscale
2. Open Safari: `https://your-hostname.tail12345.ts.net/`
3. Verify: app loads, no certificate warnings
4. Tap **Share** → **Add to Home Screen**
5. Open from home screen — launches in standalone mode (no Safari bar)

### What to check during testing

- [ ] Products/categories screens render
- [ ] Order creation works end-to-end
- [ ] Photo upload works (camera + photo library)
- [ ] App launches in standalone mode from home screen icon
- [ ] Android APK still works on `http://your-hostname:2108` (unchanged)

## Troubleshooting

```bash
# Check Caddy logs
docker compose --profile prod logs caddy

# Check baker logs
docker compose --profile prod logs baker-prod

# Validate Caddyfile syntax
docker run --rm -v $(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile

# Rebuild web app after code changes
./scripts/deploy-web.sh --restart-caddy
```

## Certificate Renewal

Tailscale certs auto-renew but Caddy needs to pick up new files:

```bash
./scripts/renew-certs.sh your-hostname.tail12345.ts.net
```

Run periodically (e.g., monthly) or set up a cron/systemd timer.

## Architecture

```
┌──────────────────────────────────────────────────┐
│ Docker network                                   │
│                                                  │
│  ┌─────────┐:2108   ┌──────────────────┐        │
│  │ baker   │◄───────│ caddy            │        │
│  │ (API)   │        │ :443 (HTTPS)     │◄─── iPhones via Tailscale (PWA)
│  │         │        │ /     → web app  │        │
│  │         │        │ /api/ → baker    │        │
│  └────┬────┘        └──────────────────┘        │
│       │:2108 (exposed)                           │
└───────┼──────────────────────────────────────────┘
        │
        ◄─── Android APK via Tailscale (existing, unchanged)
```

- **Android (APK):** `http://<hostname>:2108/api/...` → baker directly
- **iPhone (PWA):** `https://<hostname>.ts.net/api/...` → Caddy :443 → baker :2108
