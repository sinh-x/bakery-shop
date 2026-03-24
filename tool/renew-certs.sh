#!/usr/bin/env bash
# Renew TLS certificates via tailscale cert and restart Caddy.
# Usage: ./tool/renew-certs.sh [<domain>]
#   domain  Tailscale domain name (e.g. mymachine.tail1234.ts.net)
#           Falls back to $BAKER_DOMAIN env var if not provided.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Resolve domain: argument takes priority over env var
DOMAIN="${1:-${BAKER_DOMAIN:-}}"

if [ -z "$DOMAIN" ]; then
  echo "ERROR: No domain specified."
  echo "Usage: $0 <domain>"
  echo "  or set the BAKER_DOMAIN environment variable."
  exit 1
fi

CERT_DIR="${REPO_ROOT}/certs"
mkdir -p "$CERT_DIR"

# --- Generate certs via tailscale ---
echo "Requesting TLS certificate for $DOMAIN..."
tailscale cert --cert-file "${CERT_DIR}/${DOMAIN}.crt" --key-file "${CERT_DIR}/${DOMAIN}.key" "$DOMAIN"
echo "Certificates written to $CERT_DIR"

# --- Restart Caddy to pick up new certs ---
echo "Restarting Caddy container..."
cd "$REPO_ROOT"
docker compose --profile prod restart caddy
echo "Caddy restarted."

echo "Done. Certificates renewed for $DOMAIN."
