#!/usr/bin/env bash
# Shared functions for scripts/.
# Usage: source "$(dirname "$0")/lib.sh"

# Resolve repo root (idempotent if already set)
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# --- Load .env if present (same vars Docker Compose reads) ---
# Shell environment takes precedence over .env, matching Docker Compose behavior.
load_env() {
  local env_file="${REPO_ROOT}/.env"
  if [[ -f "$env_file" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$key" ]] && continue
      key=$(echo "$key" | xargs)
      # Only set if not already in environment (shell env wins)
      if [[ -z "${!key+x}" ]]; then
        export "$key=$value"
      fi
    done < "$env_file"
  fi
}

# --- Build Flutter web (release) and sync to web-build/ ---
compute_build_fingerprint() {
  local git_sha
  git_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    printf '%s-dirty\n' "$git_sha"
    return
  fi

  printf '%s\n' "$git_sha"
}

build_flutter_web() {
  local fingerprint="${1:-${BAKER_BUILD_FINGERPRINT:-$(compute_build_fingerprint)}}"

  echo "--- Building Flutter web (release) ---"
  nix develop "${REPO_ROOT}/.#flutter" --command bash -c \
    "cd '${REPO_ROOT}/app' && flutter build web --release --dart-define=BAKER_BUILD_FINGERPRINT=${fingerprint}"

  local build_output="${REPO_ROOT}/app/build/web"
  if [[ ! -d "$build_output" ]]; then
    echo "ERROR: Flutter web build output not found at $build_output"
    exit 1
  fi

  local dest="${REPO_ROOT}/web-build"
  echo "Syncing build to $dest..."
  mkdir -p "$dest"
  rsync -a --delete "$build_output/" "$dest/"
  echo "Web build ready."
}

# --- Restart Caddy Docker container ---
restart_caddy() {
  echo "--- Restarting Caddy ---"
  (cd "$REPO_ROOT" && docker compose --profile prod restart caddy)
  echo "Caddy restarted."
}

# --- Execute command on remote host via SSH ---
# Usage: remote_exec "hostname" "command string"
remote_exec() {
  local host="$1"
  local cmd="$2"
  ssh "$host" "$cmd"
}

# --- Check health endpoint with retry loop ---
# Usage: check_health [host] [port] [max_attempts] [delay_seconds]
# Returns 0 on success, 1 on failure
check_health() {
  local host="${1:-localhost}"
  local port="${2:-2108}"
  local max_attempts="${3:-10}"
  local delay="${4:-3}"

  local attempt=1
  while [ "$attempt" -le "$max_attempts" ]; do
    local response
    response=$(curl -sf --max-time 5 "http://${host}:${port}/api/health" 2>/dev/null)
    if [ -n "$response" ]; then
      local status
      status=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)
      if [ "$status" = "ok" ]; then
        echo "Health check passed: $response"
        return 0
      fi
    fi
    echo "Attempt $attempt/$max_attempts: health check not ready yet..."
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  echo "ERROR: Health check failed after $max_attempts attempts"
  return 1
}

# --- Log deployment to history file on remote host ---
# Usage: log_deploy "hostname" "version" "commit" "status" "user"
log_deploy() {
  local host="$1"
  local version="$2"
  local commit="$3"
  local status="$4"
  local user="${5:-$(whoami)}"
  local timestamp
  timestamp=$(date -Iseconds)
  local log_line="{\"timestamp\":\"$timestamp\",\"version\":\"$version\",\"commit\":\"$commit\",\"status\":\"$status\",\"user\":\"$user\"}"

  remote_exec "$host" "mkdir -p /home/sinh/bakery-shop/deploy-history && echo '$log_line' >> /home/sinh/bakery-shop/deploy-history/deploy-history.log"
}
