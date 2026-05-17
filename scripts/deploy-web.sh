#!/usr/bin/env bash
# Build Flutter web app and copy to web-build/ for Caddy to serve.
# Usage: ./scripts/deploy-web.sh [--restart-caddy]
#   --restart-caddy  Restart the Caddy Docker container after copying build output
set -euo pipefail

source "$(dirname "$0")/lib.sh"
load_env

BUILD_FINGERPRINT="$(compute_build_fingerprint)"
echo "Build fingerprint: $BUILD_FINGERPRINT"

RESTART_CADDY=0

for arg in "$@"; do
  case "$arg" in
    --restart-caddy) RESTART_CADDY=1 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--restart-caddy]"
      exit 1
      ;;
  esac
done

build_flutter_web "$BUILD_FINGERPRINT"

if [ "$RESTART_CADDY" -eq 1 ]; then
  restart_caddy
fi

echo "Done."
