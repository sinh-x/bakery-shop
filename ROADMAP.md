# Bakery-Shop Roadmap

> Updated: 2026-03-18

## Released

| Version | Feature | Status |
|---------|---------|--------|
| v0.2.0 | Products Management + Photo Library + App Cleanup + FastAPI | ✅ Done |
| v0.2.1 | Nix packaging + NixOS auto-start module | ✅ Done |
| v0.2.2 | Product codes + Categories (CLI, API, Flutter) | ✅ Done |

## In Queue (v0.2.x)

| Version | Feature | Branch | Status |
|---------|---------|--------|--------|
| v0.2.3 | Category Management UI | `feature/category-management-ui` | ✅ Done (merged develop) |
| v0.2.4 | Product Catalog Gallery | `feature/product-catalog-gallery` | ⏳ Queued |
| v0.2.5 | Event Logging UI | `feature/event-logging-ui` | ⏳ Queued |

### v0.2.3 — Category Management UI

Full category CRUD from phone. Currently categories are CLI/API-only.

- Manage icon on Products screen → Category Management Screen
- Actions: add, edit, deactivate, reactivate
- API additions: `PATCH /api/categories/{id}`, `GET /api/categories?include_inactive=1`
- All text Vietnamese

**Inbox item:** `agent-teams/builder/inbox/2026-03-18-review-category-management-ui-requirement.md`

---

### v0.2.4 — Product Catalog Gallery

Photo portfolio per product, separate from the profile/display photo.

- New `product_catalog_photos` table (caption, tags, position)
- Storage: `photos/products/{id}/catalog/{photo_id}.jpg`
- API: list, upload, update, delete catalog photos
- Flutter: 2-column gallery grid, full-screen swipe viewer, add/edit/delete
- Users: owner builds portfolio, staff shows customers examples

**Inbox item:** `agent-teams/builder/inbox/2026-03-18-review-product-catalog-gallery-requirement.md`

---

### v0.2.5 — Event Logging UI

Replace Events "Coming Soon" tab with a live quick-log + history screen.

- API: POST/GET events (wraps existing `fetch_events()` query logic)
- Flutter: chip-based type selector (Sự cố, Ghi chú, etc.), multi-select tags, logged-by preference
- Event history: filterable by type, tag, date range, full-text search
- Source tracking: `source: 'app'` vs `source: 'cli'`

**Inbox item:** `agent-teams/builder/inbox/2026-03-18-review-event-logging-ui-requirement.md`

---

## Future (v0.3+)

| Version | Feature |
|---------|---------|
| v0.3.0 | Orders Management + Delivery Tracking (full vertical slice) |
| v0.3.x | Dashboard with real data |
| v0.4+ | Inventory, Staff management, Customer DB, Analytics |
| Later | Offline-first / cr-sqlite sync, Zalo integration |
