#!/usr/bin/env bash
# Reads app_name.conf and updates all platform-specific app name references.
# Usage: ./scripts/update_app_name.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

# Load config
source "$APP_DIR/app_name.conf"

echo "Updating app name to: $APP_NAME"

# Android
sed -i "s|android:label=\"[^\"]*\"|android:label=\"$APP_NAME\"|" \
  "$APP_DIR/android/app/src/main/AndroidManifest.xml"

# iOS
# CFBundleDisplayName
sed -i "/<key>CFBundleDisplayName<\/key>/{n;s|<string>[^<]*</string>|<string>$APP_NAME</string>|}" \
  "$APP_DIR/ios/Runner/Info.plist"
# CFBundleName
sed -i "/<key>CFBundleName<\/key>/{n;s|<string>[^<]*</string>|<string>$APP_NAME</string>|}" \
  "$APP_DIR/ios/Runner/Info.plist"

# Web - index.html
sed -i "s|<title>[^<]*</title>|<title>$APP_NAME</title>|" \
  "$APP_DIR/web/index.html"
sed -i "s|apple-mobile-web-app-title\" content=\"[^\"]*\"|apple-mobile-web-app-title\" content=\"$APP_NAME\"|" \
  "$APP_DIR/web/index.html"
sed -i "s|name=\"description\" content=\"[^\"]*\"|name=\"description\" content=\"$APP_DESCRIPTION\"|" \
  "$APP_DIR/web/index.html"

# Web - manifest.json
sed -i "s|\"name\": \"[^\"]*\"|\"name\": \"$APP_NAME\"|" \
  "$APP_DIR/web/manifest.json"
sed -i "s|\"short_name\": \"[^\"]*\"|\"short_name\": \"$APP_SHORT_NAME\"|" \
  "$APP_DIR/web/manifest.json"
sed -i "s|\"description\": \"[^\"]*\"|\"description\": \"$APP_DESCRIPTION\"|" \
  "$APP_DIR/web/manifest.json"

# Windows
sed -i "s|window.Create(L\"[^\"]*\"|window.Create(L\"$APP_NAME\"|" \
  "$APP_DIR/windows/runner/main.cpp"
sed -i "s|\"FileDescription\", \"[^\"]*\"|\"FileDescription\", \"$APP_NAME\"|" \
  "$APP_DIR/windows/runner/Runner.rc"
sed -i "s|\"ProductName\", \"[^\"]*\"|\"ProductName\", \"$APP_NAME\"|" \
  "$APP_DIR/windows/runner/Runner.rc"

# Dart - VN.appName
sed -i "s|static const appName = '[^']*';|static const appName = '$APP_NAME';|" \
  "$APP_DIR/lib/shared/widgets/vietnamese_labels.dart"

echo "Done. Updated all platform configs to: $APP_NAME"
