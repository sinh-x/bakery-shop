# Bakery App — Phase 1A Prototype

Mobile UI prototype for Sinh's family bakery shop in Ninh Điêm. Built with Flutter + Material 3.

## Screens

- **Tổng quan (Dashboard)** — Today's order counts by status, next due orders, recent events
- **Đơn hàng (Orders)** — Kanban board with status columns; create, view, and update orders
- **Sản phẩm (Products)** — Product catalog by category with VND prices
- **Sự kiện (Events)** — Event log with quick-entry form (6 event types)

## Status

Phase 1A complete: all 11 screens built with mock data. APK built and ready for install testing.

## Build Requirements

Use the Nix flutter devshell (includes Android SDK):

```bash
cd ~/Documents/bakery-shop
nix develop .#flutter
```

## Build Commands

```bash
# Run on Linux desktop
bakery-run

# Build Android APK (universal)
bakery-build-apk

# Build split APKs by ABI (smaller files, recommended)
cd app && flutter build apk --release --split-per-abi

# Run tests
bakery-test

# Analyze code
bakery-analyze
```

## Deploy to Device

```bash
# Build release APK and install on all connected devices
./tool/deploy.sh

# Install only on a specific device (match by serial or model)
./tool/deploy.sh Samsung
```

Requires `adb` (included in the Nix flutter devshell) and a USB-connected Android device with developer mode enabled.

## APK Installation

Pre-built APKs are in `releases/`:

| File | ABI | Size | Use for |
|------|-----|------|---------|
| `bakery-app-v1.0.0-arm64.apk` | arm64-v8a | ~17MB | Modern Android phones (2016+) |
| `bakery-app-v1.0.0-armv7.apk` | armeabi-v7a | ~15MB | Older 32-bit Android phones |

**Minimum:** Android 7.0 (API 24)

To install: copy APK to phone, enable "Install from unknown sources", open the APK file.

## Tech Stack

- Flutter 3.41.2 / Dart 3.11.0
- Riverpod (state management)
- GoRouter (navigation)
- Freezed (data models)
- Material 3 + Vietnamese labels
