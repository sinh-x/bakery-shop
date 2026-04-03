# Changelog

## [0.3.1+38] — 2026-04-01
- fix: pass item_id to receipt API and print all main items

## [0.3.1+37] — 2026-03-31
- fix(dg-055): fix phone input cursor jump when dashes are auto-inserted

## [0.3.1+36] — 2026-03-30
- fix(backup): use nix-shell for sqlite3 availability on NixOS

## [0.3.1+35] — 2026-03-30
- fix(backup): replace python3 with sqlite3 CLI in wasabi-backup script

## [0.3.1+30] — 2026-03-29
- chore: update CHANGELOG and pubspec.lock

## [0.3.1+29] — 2026-03-29
- feat(deploy): add lily-setup script, fix deploy doc gaps

## [0.3.1+28] — 2026-03-29
- fix(receipts): format phone as xxxx-xxx-xxx on bus label

## [0.3.1+27] — 2026-03-29
- fix(receipts): thick-thin double line separator on bus label

## [0.3.1+26] — 2026-03-29
- fix(receipts): add section spacing between phone/address/notes on bus label

## [0.3.1+25] — 2026-03-29
- fix(receipts): anchor shop info to bottom, add specialty line, remove product list

## [0.3.1+24] — 2026-03-29
- fix(receipts): bigger fonts + product info on bus shipping label

## [0.3.1+23] — 2026-03-29
- fix(receipts): match bus label to 76x128mm label paper dimensions

## [0.3.1+22] — 2026-03-29
- fix(receipts): update shop address to 61 Hòn Khói

## [0.3.0+20] — 2026-03-28
- feat(print): add runtime Bluetooth permission handling for Android 12+

## [0.3.0+2] — 2026-03-28
- chore: update CHANGELOG for v0.3.0

## [0.3.0+1] — 2026-03-28
- feat(print): DG-037 Bluetooth thermal printer integration (Y41BT TSPL protocol)
- feat(print): auto-reconnect to last used printer
- feat(print): web browser print support via window.print()
- feat(receipts): increased font sizes for thermal print readability
- refactor: replaced PDF share with direct image share
- chore: version bump to 0.3.0

## [0.2.2+18] — 2026-03-28
- chore: bump build number to 17

## [0.2.2+16] — 2026-03-26
- feat(checklist): DG-028 daily opening/closing checklist for staff procedures

## [0.2.2+15] — 2026-03-25
- feat(orders): DG-030 edit order feature parity with create order

## [0.2.2+14] — 2026-03-24
- chore: add CLAUDE.md placeholder and ignore certs/ directory

## [0.2.2+13] — 2026-03-24
- chore: ignore web-build output directory

## [0.2.2+12] — 2026-03-24
- feat(settings): DG-019 — staff picker, version display, auto-fill created_by, settings accessible from all screens

## [0.2.2+11] — 2026-03-24
- fix: read VERSION dynamically from package metadata

## [0.2.2+10] — 2026-03-24
- chore: update CHANGELOG and pubspec.lock for v0.2.2+9

## [0.2.2+9] — 2026-03-24
- feat(logging): DG-018 — server logging system + deploy.sh --debug flag

## [0.2.2+8] — 2026-03-19
- docs: update CHANGELOG for v0.2.2+7 deploy script

## [0.2.2+7] — 2026-03-18
- feat(tool): add deploy.sh for APK build and install to device

## [0.2.2+6] — 2026-03-18
- docs: mark v0.2.5 event logging UI as done in ROADMAP

## [0.2.2+5] — 2026-03-18
- docs: mark v0.2.4 product catalog gallery as done in ROADMAP

## [0.2.2+4] — 2026-03-18
- docs: mark v0.2.3 category management UI as done in ROADMAP

## [0.2.2+3] — 2026-03-18
- docs: add ROADMAP + unreleased v0.2.3-v0.2.5 to CHANGELOG

## [Unreleased — v0.2.x]

### Planned (approved, in implementation queue)

- **v0.2.3 — Category Management UI** (`feature/category-management-ui`)
  - Flutter: manage icon on Products screen → Category Management Screen (add / edit / deactivate / reactivate)
  - API: `PATCH /api/categories/{id}`, `GET /api/categories?include_inactive=1`

- **v0.2.4 — Product Catalog Gallery** (`feature/product-catalog-gallery`)
  - DB: new `product_catalog_photos` table (id, product_id, file_path, caption, tags, position)
  - API: `GET/POST /api/products/{id}/catalog`, `PATCH/DELETE /api/products/{id}/catalog/{photo_id}`
  - Flutter: gallery grid tab on product detail, full-screen viewer, add/edit/delete photo flows

- **v0.2.5 — Event Logging UI** (`feature/event-logging-ui`)
  - Replace Events "Coming Soon" tab with quick-log form + filterable event history
  - API: `POST /api/events`, `GET /api/events` (with filters), `GET /api/events/{id}`
  - Flutter: chip-based type/tag selector, logged-by preference, event history list

---

## [0.2.2] — 2026-03-18

### Added
- Product codes (`product_code`) — human-readable codes for every product (e.g. `BMI-01`, `BKS-16`, `BNG-S06`)
- Categories table — 5 seeded categories (bánh mì, bánh kem, bánh ngọt, cookie, khác), user-manageable via CLI and API
- API: `GET /api/products?code=` filter, `GET /api/products/code/{code}` lookup, `GET /api/categories`, `POST /api/categories`
- CLI: `baker product list` shows Code column, `baker product edit` accepts code as identifier, `baker category` commands
- Flutter: product card shows code badge, product form has code field, catalog tabs load from API categories
- Variant products seeded: bánh kem 16/18/20/22cm × thường/cao/tầng (12 variants) + bánh su kem sets (5 variants)
- Test suite expanded to 113 tests including unit tests for code generation

## [0.2.1+12] — 2026-03-17
- chore: bump patch version 0.2.0 → 0.2.1

## [0.2.1] — 2026-03-17
- chore: bump patch version — Nix packaging + NixOS auto-start module complete

## [0.2.0+10] — 2026-03-17
- feat(nix): phase 4 - regression check — nix develop and nix develop .#flutter verified working

## [0.2.0+9] — 2026-03-17
- fix(api): NameError PHOTOS_DIR in get_photo — missed bare reference

## [0.2.0+8] — 2026-03-17
- fix(nix): replace StateDirectory with ExecStartPre mkdir for arbitrary dataDir

## [0.2.0+7] — 2026-03-17
- chore(changelog): add prepare-commit-msg hook + backfill history

## [0.2.0+6] — 2026-03-17
- feat(config): universal --config flag on CLI group

## [0.2.0+5] — 2026-03-17
- feat(config): YAML config at ~/.config/doangia/bakery/baker.yaml

## [0.2.0+4] — 2026-03-17
- chore: ignore nix build result symlink

## [0.2.0+3] — 2026-03-17
- chore(version): auto-bump hook + versioning strategy

## [0.2.0+2] — 2026-03-17
- chore: add build number versioning to branch strategy

## [0.2.0+1] — 2026-03-17
- chore: add git-flow branch strategy

## [0.2.0] — 2026-03-17
- feat(nix): NixOS module for baker service + nixosModules.default export
- feat(nix): add packages.baker output to flake
- feat(build): APK build script, Android network permissions, Nix flutter shell
- fix(app): photo not persisting after save on product screens
- fix(app): strip trailing slash from API base URL to prevent double-slash 404
- feat(release): APK v0.2.0 with products management
- feat(test): integration tests for API ↔ CLI round-trip
- feat(app): Flutter settings screen with API URL config
- feat(app): Flutter product screens with create, edit, and photo picker
- feat(app): Flutter API client with dio and product service
- feat(api): pytest API tests for product endpoints and photo upload
- feat(db): migration v3 with photo_path and 23 product seeds
- feat(api): photo upload/serve with resize
- feat(api): product CRUD API routes
- feat(api): FastAPI skeleton with CORS and health endpoint
- feat(app): Vietnamese audit and app name config
- feat(app): app cleanup and coming soon placeholders
- feat: staff tracking and people tagging for events
- feat: initial baker CLI for bakery shop management
