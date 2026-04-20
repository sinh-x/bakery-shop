#!/usr/bin/env bash
# Renew TLS certificates via tailscale cert and restart Caddy.
# Usage: ./scripts/renew-certs.sh [<domain>]
#   domain  Tailscale domain name (e.g. mymachine.tail1234.ts.net)
#           Falls back to $DOMAIN from .env if not provided.
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_env

# Resolve domain: CLI arg > DOMAIN from env/.env > BAKER_DOMAIN (legacy)
DOMAIN="${1:-${DOMAIN:-${BAKER_DOMAIN:-}}}"

if [ -z "$DOMAIN" ]; then
  echo "ERROR: No domain specified."
  echo "Usage: $0 <domain>"
  echo "  or set DOMAIN in .env (see config/docker.example)"
  exit 1
fi

CERT_DIR="${REPO_ROOT}/certs"
mkdir -p "$CERT_DIR"

# --- Generate certs via tailscale ---
echo "Requesting TLS certificate for $DOMAIN..."
tailscale cert --cert-file "${CERT_DIR}/${DOMAIN}.crt" --key-file "${CERT_DIR}/${DOMAIN}.key" "$DOMAIN"
echo "Certificates written to $CERT_DIR"

# --- Restart Caddy to pick up new certs ---
restart_caddy

echo "Done. Certificates renewed for $DOMAIN."
