#!/usr/bin/env bash
# Shared functions for tool/ scripts.
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
build_flutter_web() {
  echo "--- Building Flutter web (release) ---"
  nix develop "${REPO_ROOT}/.#flutter" --command bash -c \
    "cd '${REPO_ROOT}/app' && flutter build web --release"

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
