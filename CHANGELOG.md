# Changelog

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
