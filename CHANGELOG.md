# Changelog

## [0.7.2+83] — 2026-07-11
- chore(release): add CHANGELOG 0.7.2+82 entry, sync uv.lock version

## [0.7.2+82] — 2026-07-11

> **Release summary:** This release bundles all features from v0.7.0 through v0.7.2+82 (approximately 108 commits), including 4-stage unified order creation pipeline (DG-211, DG-214, DG-218), order edit/create wizard UI parity (DG-217, DG-220), customer picker improvements (DG-222), cart attribute sync (DG-221), journal backfill prevention (DG-226), customer link repair (DG-227), missing revenue repair (DG-229), expense debt management, Tailscale MagicDNS HTTPS dev server (DG-219), and COGS audit/business-health metrics (DG-208, DG-209). See the entries below for the full delta.
- feat(DG-229): repair missing revenue — fix all query, create missing entries, check-revenue-gaps command, --since date filtering
- feat(DG-227): customer link repair — name fallback, update endpoint fix, migration v66
- feat(DG-226): journal backfill prevention — audit log, proactive detection, missing source_type/source_id params
- feat(DG-225): POS fixes — useInventory persistence, trailing newline, health check retry
- feat(DG-224): POS order creation — extract _createOrderInternal, guard debugPrint
- feat(DG-223): POS review findings resolution (4/4)
- feat(DG-222): customer picker — inline list, adaptive fetch/mode, selection states, VN labels
- feat(DG-221): POS cart attribute sync — lossless cart↔wizard isBirthday, age, rut_tien, cash_fee
- feat(DG-220): order edit UI parity — single-state customer model, stage-widget decomposition
- feat(DG-219): Tailscale MagicDNS HTTPS dev server via central drgnfly-caddy gateway
- feat(DG-218): POS unified order creation — 4-stage pipeline, dedicated payment step, gift logic dedup
- feat(DG-217): order wizard — swipe navigation, stage gating, post-submit navigation, VN labels
- feat(DG-216): delivery options polish — layout/UX, shipping fee config, due date/time picker
- feat(DG-215): Facebook source labels — align with backend values, Stage 2 customer info polish
- feat(DG-214): order wizard UI — tien_rut fixes, cash amount defaults, state management
- feat(DG-213): VN label policy + const lint warnings resolution
- feat(DG-211): 4-stage unified order creation pipeline — OrderWizardData, PageView, error handling
- feat(delivery): phone input formatter, delivery_phone NULL handling
- feat(expense-debt): debt expense creation, settlement API, Flutter UI, vendor autocomplete
- feat(reports): COGS ratio in income statement, business-health metrics with severity classification
- chore(release): bump patch version to 0.7.2+82 [skip ci]

## [0.7.0+79] — 2026-07-06

> **Release summary:** This release bundles all features from v0.6.1 through v0.6.13 (approximately 178 commits across 18 milestone features), including double-entry accounting (DG-175, DG-189–199), customer management (DG-182, DG-204–206), negative inventory flow (DG-200), UTC timestamp standardization (DG-202), printing module (DG-186), expense events (DG-185), printer paper mode (DG-183), and COGS audit/cost_history (DG-208). See the entries below for the full delta.
- feat(DG-208): core COGS formula fix, cost_history CRUD, COGS audit + backfill commands
- feat(DG-209): 4 new business-health metric categories with severity classification
- feat(reports): COGS ratio in income statement with regression tests
- feat(DG-209): pre/post-migration DB validation procedure
- chore(release): bump version 0.6.13+78 → 0.7.0+79

## [0.6.13+78] — 2026-07-05
- feat(inventory): DG-200 negative inventory POS flow (negative_balance table, allow_negative FIFO, surplus inflow netting, accounting entries, Flutter stock/reconciliation negative display, integration tests)
- chore(release): bump patch version to 0.6.13+78

## [0.6.12+77] — 2026-07-04
- feat(time): DG-202 UTC timestamp standardization (now_utc() utility, v55 migration, Z-suffix round-trip, timezone endpoint, Flutter date formatting)
- feat(customers): DG-204 customer generation from orders (phone normalization, name dedup, v57 migration)
- feat(customers): DG-205 multi-phone support + customer management foundation (v58 customer_phones table, Flutter multi-phone UI, order-customer phone matching, name dedup v59)
- feat(orders): DG-206 customer search + card in order create/edit/detail flows (CustomerProfileCard, PhoneCountBadge, diacritic-insensitive search_name, customer_year_summary)
- feat(customers): DG-182 Flutter UI for customer management + detail screens with search in order flows
- feat(accounting): DG-175 double-entry accounting (chart of accounts, journal auto-gen hooks, Flutter accounting UI, COGS journal entries, cost_history, cost_at_sale)
- feat(accounting): DG-189 accounting validation module (6 new validation checks, CLI reports, Flutter review remediation)
- feat(accounting): DG-190 delivered-order revenue updates + repair-order-revenue CLI (pipeline visibility, refund handling)
- feat(accounting): DG-191 bus shipping revenue (COA held account 2200, payment journal split, backfill v49, Flutter VN labels)
- feat(accounting): DG-192 transaction_date on journal entries (model + Flutter data layer, report/API/lock filters, backfill + live-sync)
- feat(accounting): DG-196 PaymentTransaction invalidation (v53 migration, invalidate/restore endpoints, Flutter UI, downstream exclusion)
- feat(accounting): DG-198 tien_rut routing to account 2400 Tien Rut Held (deposit-revenue integrity checks, guardrail, backfill)
- feat(accounting): DG-199 journal sync remediation + production verification docs (v54 migration, rollback procedure)
- feat(printing): DG-186 CUPS/IPP printer module (IPP client, BAKER_PRINT_IPP_URL env, NixOS CUPS module)
- feat(events): DG-185 expense auto-staff, payer confirmation, audit log (v43 event_history, soft-delete, loggedBy attribution)
- feat(printer): DG-183 printer paper mode (PAPER_MODE env, Flutter settings dropdown, conditional TSPL GAP)
- feat(print): DG-184 receipt print trailing space & tear indicator for roll paper
- fix(tests): DG-207 rewrite event_test timezone assertions
- chore(release): bump patch version to 0.6.12+77

## [0.6.11+73] — 2026-06-19
- feat(expenses): staff dropdown + paid_by role separation (WAL checkpoint, paid_by_name validation, Flutter UI)
- feat(auto-refresh): DG-181 AutoRefreshMixin for data-list screens (ExpenseScreen, EventListScreen, shared mixin)
- chore(release): bump patch version to 0.6.11+73

## [0.6.10+72] — 2026-06-17
- feat(expenses): DG-176 payment source (payment_source validation + filter, Flutter UI form/history/filter, reimbursed support)
- chore(release): bump patch version to 0.6.10+72

## [0.6.9+71] — 2026-06-12
- refactor(orders): extract rut_tien widgets from order_detail_screen and expandable_item_card
- chore(release): bump patch version to 0.6.9+71

## [0.6.8+70] — 2026-05-25
- feat(deps): DG-172 replace 5 KGP-warning plugins with patched forks (pin git deps to commit SHAs)
- feat(orders): DG-066 per-order incident linking with photo attachments
- chore(release): bump patch version to 0.6.8+70

## [0.6.7+69] — 2026-05-24
- feat(expenses): operation expenses note (Chi phi list filters, editable timestamps, local-day filtering, staff chip filters)
- chore(release): bump patch version to 0.6.7+69

## [0.6.6+68] — 2026-05-23
- feat(orders): phu_kien accessory draft support + integrate phu_kien extras in create/edit, bind gifts to phu_kien catalog products
- feat(settings): deprecate legacy extras management
- chore(release): bump patch version to 0.6.6+68

## [0.6.5+67] — 2026-05-22
- feat(orders): customer-facing public order code (persistence, generation, edit rules, receipt surfaces, Flutter UI)
- feat(receipts): remove non-customer pickup label, apply DG-164 receipt feedback
- chore(release): bump patch version to 0.6.5+67

## [0.6.4+66] — 2026-05-22
- feat(app): DG-165 flutter kotlin warnings remediation (upgrade warning-related plugins, preserve Android share flows)
- chore(release): bump patch version to 0.6.4+66

## [0.6.3+65] — 2026-05-22
- feat(deps): DG-162 flutter SDK dependency alignment (nix flutter + CI pin, lockfile alignment, docs)
- chore(release): bump patch version to 0.6.3+65

## [0.6.2+64] — 2026-05-22
- feat(orders): default trung bay inventory off (require explicit useInventory opt-in, preserve FIFO regression behavior)
- chore(release): bump patch version to 0.6.2+64

## [0.6.1+63] — 2026-05-21
- feat(pos): POS sales workflow UX (checkout edit/payment state refinement, local finalization guard, receipt print skip flow, regression verification)
- feat(orders): order status error messaging (backend status-rejection diagnostics, improved 422 failure messaging)
- feat(orders): POS order history UI (persist quick-sale dueDate, backend due-date history query)
- feat(pos): POS appbar menu stock filter (inventory crowded appbars, overflow action menus, stock visibility switch, VN menu labels)
- ci: auto bump patch version after develop CI (wait for develop CI before patch bump)
- chore(release): bump patch version to 0.6.1+63

## [0.6.0] — 2026-05-17
- feat(reconciliation): DG-121 reconciliation screen improvements (auto-create sales rows, product filtering, sale editor reorder)
- feat(stock): reconciliation chip stock filter (hide zero-stock chips, remove price shortcuts, category grouping cleanup)
- feat(linting): DG-120 coding standards audit (12 lint rules activated, const suppression audit, widget extraction)
- feat(orders): active order visibility (active_only API parameter, Kanban grouping for column correctness)
- feat(stock): POS stock collapsible categories (reusable category grouping sections, order extras to product-backed accessories)
- feat(stock): DG-144 improve reconciliation UX (icon regression coverage, mutable Flutter web asset revalidation)
- feat(stock): DG-112 inventory choice (useInventory toggle, FIFO consumption gating for Trung bay items, idempotent deduction + restore on cancel)
- feat(refactor): DG-120 refactor bundle (split reconciliation/order providers, domain import split, widget extraction)
- feat(products): promote catalog photo as canonical product photo (API fallback, Flutter refresh state)
- feat(products): DG-143 product reactivation + category visibility (inactive data path, reactivation UI, edit-sheet visibility switch)
- feat(app): DG-156 server code-fingerprint mismatch warning (backend fingerprint metadata, Flutter comparison state, all-route warning strip)
- chore(release): bump version to 0.6.0

## [0.5.5+58] — 2026-04-22
- chore(release): bump version to 0.5.5+57

## [0.5.4+54] — 2026-04-21
- feat(DG-094): phase F9 — category-grouped layout in TagChipSelector (headers on own row)
- feat(DG-094): label_outline button on browse grid thumbnails (direct tag edit from Duyệt ảnh mẫu)
- feat(DG-094): fix refetch storm, multi-row filter bar, Xoá lọc, CatalogTagChips, quick-tag overlay
- feat(DG-094): add traceback logging to catalog photo upload

## [0.5.3+52] — 2026-04-21
- feat(DG-094): add cross-product catalog photo browse with tag filtering (CatalogBrowseScreen, catalog_photo_tags table, v28 migration)

## [0.5.3+51] — 2026-04-21
- fix(DG-089): order list shows wrong payment status for fully-paid orders

## [0.5.2+50] — 2026-04-20
- feat(DG-088): add mark-as-printed and unmark-printed to order detail screen

## [0.5.2+49] — 2026-04-20
- chore(release): bump version to 0.5.2+48

## [0.4.0+42] — 2026-04-19
- feat(deploy): add recover-lily.sh for backup restore and redeploy

## [0.4.0+41] — 2026-04-16
- fix(DG-073): flutter analyze --no-fatal-warnings

## [0.4.0+40] — 2026-04-16
- fix(DG-073): flutter analyze --allow-warnings in CI

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
