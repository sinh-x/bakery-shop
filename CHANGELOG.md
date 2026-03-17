# Changelog

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
