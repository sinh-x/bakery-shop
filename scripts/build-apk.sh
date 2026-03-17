#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT/app"

echo "Building APKs..."
flutter build apk --release --split-per-abi

mkdir -p "$REPO_ROOT/releases"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$REPO_ROOT/releases/bakery-app-v0.2.0-arm64.apk"
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$REPO_ROOT/releases/bakery-app-v0.2.0-armv7.apk"

echo ""
echo "Done! APKs in releases/:"
ls -lh "$REPO_ROOT/releases/"*.apk
