#!/usr/bin/env bash
# Build release APK and install on a connected Android device.
# Usage: ./tool/deploy.sh [device-name]
#   device-name  Optional substring to match against adb device serial/model.
#                If omitted, installs on all connected devices.
set -euo pipefail

cd "$(dirname "$0")/../app"

DEVICE_FILTER="${1:-}"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

# --- Build ---
echo "Building release APK..."
flutter build apk --release

if [ ! -f "$APK_PATH" ]; then
  echo "ERROR: APK not found at $APK_PATH"
  exit 1
fi

echo "APK ready: $APK_PATH"

# --- Detect devices ---
DEVICES=$(adb devices | tail -n +2 | grep -w 'device' | awk '{print $1}')

if [ -z "$DEVICES" ]; then
  echo "ERROR: No connected devices found."
  exit 1
fi

# --- Install ---
INSTALLED=0
for SERIAL in $DEVICES; do
  if [ -n "$DEVICE_FILTER" ]; then
    # Match filter against serial or device model
    MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null || echo "")
    if [[ "$SERIAL" != *"$DEVICE_FILTER"* && "$MODEL" != *"$DEVICE_FILTER"* ]]; then
      continue
    fi
  fi

  echo "Installing on $SERIAL..."
  adb -s "$SERIAL" install -r "$APK_PATH"
  INSTALLED=$((INSTALLED + 1))
done

if [ "$INSTALLED" -eq 0 ]; then
  echo "ERROR: No device matched filter '$DEVICE_FILTER'."
  echo "Connected devices:"
  adb devices -l | tail -n +2
  exit 1
fi

echo "Done. Installed on $INSTALLED device(s)."
