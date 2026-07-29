# Database Schema Reference

> Date: 2026-07-29
> Ticket: DG-308 (Phase 5 — Documentation)
> Source of truth: `src/baker/db/schema.py` (88 incremental migrations)
> SQLite runtime requirement: ≥ 3.35.0 (v80 uses `ALTER TABLE ... DROP COLUMN`).

This is the standalone reference for the bakery-shop database schema. It
covers table relationships, the double-entry accounting model, indexes, and
seed data. For migration application/rollback procedures see
`docs/migration-rollback.md`; for the overall system see
`docs/architecture.md`.

---

## 1. Migration System

### 1.1 How migrations run

`schema.py:ensure_schema(conn)` is the single entry point:

1. Reads `MAX(version)` from `schema_version` (treats a missing table as v0).
2. Iterates `sorted(MIGRATIONS.keys())` and applies each version greater than
   the current one:
   - `conn.executescript(MIGRATIONS[version]["sql"])` — DDL statements.
   - If `"seed"` is present, inserts each tuple into the target table via
     `INSERT OR IGNORE`.
   - If `"callable"` is present, invokes the Python migration function (for
     data backfills and complex logic that cannot be expressed as static SQL).
   - Inserts a row into `schema_version (version, description)`.
3. Commits once after all pending migrations.

Migrations are **forward-only and incremental** — there is no automatic
down-migration. The `MIGRATIONS` dict (line 4589) maps `int → {description,
sql, [callable], [seed]}`. Current max schema version: **88**.

### 1.2 Migration history (v1–v88)

| V | Description |
|---|---|
| 1 | Initial schema (events, orders, inventory, products, schema_version) |
| 2 | Staff tracking and event people |
| 3 | Product `photo_path` column and seed 23 products |
| 4 | Product codes and `categories` table |
| 5 | Update product categories to new slugs |
| 6 | Seed cake variants (16/18/20/22cm × thường/cao/tầng) and su kem sets |
| 7 | `product_catalog_photos` table for gallery feature |
| 8 | `photos` table (flat hash storage), categories icon+position, product FK |
| 9 | Rename event type 'incident' to 'equipment' |
| 10 | Add `amount_paid` to orders (dropped in v80) |
| 11 | `order_photos` table for decoration references and chat screenshots |
| 12 | `order_items` and `payment_transactions` tables with data migration |
| 13 | Per-item birthday/age fields and `order_photos.work_item_id` FK |
| 14 | `app_config` table for general config (order sources etc), `source` on orders |
| 15 | `server_logs` and `log_triggers` tables for API logging |
| 16 | Seed staff table (5 members) and `created_by` on orders |
| 17 | Fix staff names to use Vietnamese diacritics |
| 18 | `checklist_templates` and `checklist_entries` tables with seed data |
| 19 | `order_history` audit table for tracking all order changes |
| 20 | Add `shipping_fee` to orders, `is_extra`/`is_gift` to order_items, seed shipping presets and extras |
| 21 | `work_ticket_printed_at` on orders for tracking work ticket print state |
| 22 | `knowledge_entries` and `knowledge_entry_photos` tables |
| 23 | Product attribute system: `product_attributes`, `product_attribute_values`, `order_items.attributes`, seed cash attributes for banh_kem |
| 24 | Add `rut_tien` per-product toggle; seed banh_kem products with rut_tien=true |
| 25 | Rename `rut_tien` transaction type to `tien_rut` in payment_transactions |
| 26 | Add `trung_bay`/`tang_kem` attributes; create `product_stock` and `stock_movements` tables |
| 27 | Create `catalog_photo_tags` junction table and seed 20 catalog tag entries |
| 28 | Rebuild `catalog_photo_tags` with `ON DELETE CASCADE`; re-seed vocabulary (fixes v27 typos) |
| 29 | Add pin support to knowledge entries |
| 30 | `product_price_chips` table for preset pricing |
| 31 | Enum attributes: `product_attribute_options`; seed nhan_banh options (5 fillings) |
| 32 | Print tracking: `print_log` table and `work_ticket_printed_by` column |
| 33 | `reconciliation_sessions` and `reconciliation_lines` tables |
| 34 | `reconciliation_sale_rows` table (grouped reconciliation sale rows) |
| 35 | Add per-line waste reason to reconciliation lines |
| 36 | Chip-aware inventory: `stock_lots`, `inventory_items`, option columns, `product_stock` migration |
| 37 | Consolidate stock lots by normalized selling price buckets |
| 38 | Migrate order_extra app config rows into product-backed `phu_kien` accessories |
| 39 | Add `public_order_code` column and per-due-date uniqueness index |
| 40 | Add `order_id` nullable FK to events for order incident linking |
| 41 | Create `event_photos` junction table linking events to photo attachments |
| 42 | Backfill `payment_source` for existing expense events |
| 43 | `event_history` audit table, soft-delete columns on events, backfill expense staff_name |
| 44 | Double-entry accounting: `accounts`, `journal_entries`, `journal_lines`, chart of accounts seed, backfill historical entries |
| 45 | Cost data foundation: `cost_history`, `order_items.cost_at_sale`, backfill delivered order_items with baseline costs |
| 46 | One-time fix: backfill journal entry for old-format expense event #25 |
| 47 | One-time fix: delete/re-create stale `order_cogs` entries (old cost resolver) |
| 48 | One-time fix: re-route Nguyên liệu/Bao bì expense entries to debit Inventory (1300) |
| 49 | Bus shipping accounting backfill: fix revenue entries, hold+release entries for delivered bus orders |
| 50 | Add `transaction_date` column + index to `journal_entries` (DG-192 Phase 4.1) |
| 51 | Re-backfill `journal_entries.transaction_date` from source record dates |
| 52 | Reclassify staff advance accounts (1400 asset) to staff payables (2300 liability) |
| 53 | Add `invalidated_at`/`invalidated_by` soft-delete to `payment_transactions` |
| 54 | Ensure account 2400 (Tien Rut Held) exists in chart of accounts |
| 55 | UTC timestamp standardization — append Z, convert +07:00 to UTC Z |
| 56 | Customer management: `customers` table, `customer_id` FK on orders, auto-match by phone |
| 57 | Generate customer records from existing orders (earliest-order-wins, idempotent) |
| 58 | Customer multi-phone: `customer_phones` table + migrate primary phone |
| 59 | Deduplicate customers with same case-insensitive name (merge orders) |
| 60 | `customer_year_summary` table for order count + total volume per year |
| 61 | Add `search_name` to customers for diacritic-insensitive search |
| 62 | Negative inventory: `negative_balance` tracking oversold qty per (product_id, price_chip_id) |
| 63 | Repair zero-cost order_items (unit_price anchor) and missing order_cogs journal entries |
| 64 | Add `delivery_phone` column to orders |
| 65 | Create `journal_sync_failure_log` table for per-source audit records |
| 66 | Repair unlinked orders — link NULL customer_id orders (idempotent) |
| 67 | Add `acknowledged_at` to orders for order acknowledgment tracking |
| 68 | Auth RBAC: `users` table for JWT auth + seed existing staff as users |
| 69 | Auth RBAC: `audit_log` table for recording admin write operations |
| 70 | Auth RBAC: `sessions` table for active session tracking |
| 71 | Auth RBAC: DB-level `CHECK(role IN ('admin','staff'))` on users |
| 72 | Auth RBAC: lowercase existing `users.username` values |
| 73 | Chart of accounts: ensure account 2500 (Accounts Payable) exists |
| 74 | Backfill remaining NULL customer_id orders (idempotent, with pre/post counts) |
| 75 | Backfill primary `customer_phones` row for customers with zero phone rows |
| 76 | Chart of accounts: bank sub-accounts 1210/1220/1290 |
| 77 | Add `staff_id` to users/sessions, UNIQUE index, back-link existing users to staff |
| 78 | Add `staff_name` to events for display-name attribution |
| 79 | Add `created_staff_name`/`work_ticket_printed_staff_name` to orders |
| 80 | Drop redundant `amount_paid` from orders (live-computed from payment_transactions) |
| 81 | Blanks foundation: `blanks`, `product_blank_bom`, `blank_stock`, `blank_stock_log` |
| 82 | Add `blank_id` nullable FK to order_items + index |
| 83 | Replace `order_items.blank_id` with `order_item_blanks` junction table |
| 84 | Add `assigned_price` to order_items for trưng bày markup audit |
| 85 | Seed account 1600 (Fixed Assets) for investing-activity cash flows |
| 86 | Expense subcategories: `expense_categories` table + seed + account codes 5110-5140, 5210-5230 |
| 87 | Add `latitude`/`longitude`/`google_maps_url`/`delivery_time_slot` to orders (delivery GPS) |
| 88 | Add composite indexes on `orders(status, due_date)` and `orders(customer_id, created_at)` |

---

## 2. Tables (52 total)

Tables grouped by domain. Arrows show foreign-key relationships.

### 2.1 Orders & work items

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `orders` | The core order record. Status machine: `new`→`confirmed`→`in_progress`→`ready`→`delivered` (or `cancelled`). Holds `order_ref` (unique), `public_order_code` (per-due-date unique), customer/delivery fields, shipping, GPS, acknowledgement, print tracking, display-name attribution. | `customer_id → customers.id`; `created_by → staff.id`; `order_items`, `payment_transactions`, `order_photos`, `order_history`, `events(order_id)` |
| `order_items` | Per-line items in an order (cakes, extras, gifts). Has `is_extra`, `is_gift`, `price_chip_id`, `attributes` (JSON), `cost_at_sale`, `assigned_price`. Status cascade follows the order. | `order_id → orders.id`; `price_chip_id → product_price_chips.id`; `order_item_blanks` |
| `order_item_blanks` | Junction linking a work item to physical cake blanks (phôi bánh). Replaced the v82 `blank_id` column. | `order_item_id → order_items.id`; `blank_id → blanks.id` (UNIQUE per pair) |
| `order_history` | Audit trail of all order changes (status, field updates). | `order_id → orders.id` |
| `order_photos` | Photos attached to an order (decoration references, chat screenshots). | `order_id → orders.id`; `photo_id → photos.id`; `work_item_id → order_items.id` |

### 2.2 Customers

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `customers` | Customer master record. Has `name`, `search_name` (diacritic-insensitive), `phone` (legacy primary), `notes`. | `orders(customer_id)`; `customer_phones`; `customer_year_summary` |
| `customer_phones` | Multi-phone support. One customer can have several phone numbers; one is primary. | `customer_id → customers.id` |
| `customer_year_summary` | Aggregated order count + total volume per customer per year. | `customer_id → customers.id` |

### 2.3 Products, catalog & attributes

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `products` | Product master. `name`, `code` (unique), `category`, `base_price`, `cost`, `photo_path`, `active`. | `categories`; `product_price_chips`; `product_attributes/values`; `product_catalog_photos`; `product_blank_bom` |
| `categories` | Product categories with `code_prefix`, `icon`, `position`, `active`. | `products(category)` |
| `product_price_chips` | Preset pricing tiers per product (e.g. 16/18/20/22 cm). | `product_id → products.id`; `order_items(price_chip_id)`; `stock_lots`; `product_blank_bom` |
| `product_attributes` | System-level attribute types (e.g. `cash_amount`, `cash_fee`, `trung_bay`, `tang_kem`, `rut_tien`, `nhan_banh`). | `product_attribute_options`; `product_attribute_values` |
| `product_attribute_options` | Enum options for an attribute (e.g. 5 fillings for `nhan_banh`). Soft-deletable via `active`. | `attribute_type → product_attributes.attribute_type` |
| `product_attribute_values` | Per-product attribute value overrides. | `product_id`; `attribute_type` |
| `product_catalog_photos` | Gallery photos per product (ordered by `position`). | `product_id → products.id`; `photo_id → photos.id`; `catalog_photo_tags` |
| `product_stock` | Legacy per-product stock summary (pre-chip). Superseded by chip-aware tables in v36. | `product_id` |
| `cost_history` | Time-phased product cost history with `effective_from`. | `product_id → products.id` |

### 2.4 Inventory (chip-aware FIFO)

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `inventory` | Legacy ingredient-level inventory (name, category, quantity, unit, cost_per_unit). From v1. | — |
| `inventory_items` | Per-lot inventory item instances with status (`in_stock`/`consumed`/`wasted`). | `lot_id → stock_lots.id` |
| `stock_lots` | FIFO lots per `(product_id, price_chip_id)` with `restocked_at` (FIFO ordering via `idx_stock_lots_fifo`). | `product_id`; `price_chip_id` |
| `stock_movements` | Movement log per `(product_id, price_chip_id, created_at)`. | `product_id`; `price_chip_id` |
| `negative_balance` | Tracks oversold quantity per `(product_id, price_chip_id)` (UNIQUE). | `product_id`; `price_chip_id` |

### 2.5 Blanks (cake bases)

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `blanks` | Cake base / phôi master (name, category). | `product_blank_bom`; `blank_stock`; `order_item_blanks` |
| `product_blank_bom` | Bill of materials: how many blanks of a given price chip make a product. | `blank_id → blanks.id`; `price_chip_id → product_price_chips.id` |
| `blank_stock` | Net stock per blank across production/usage lots. | `blank_id → blanks.id` |
| `blank_stock_log` | Chronological audit log of blank stock changes. | `blank_id → blanks.id` |

### 2.6 Payments & accounting

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `payment_transactions` | Payment records per order (`type`: deposit/payment/full_payment/refund/tien_rut; `method`: cash/card/transfer). Soft-deletable via `invalidated_at`/`invalidated_by`. | `order_id → orders.id`; `journal_entries(source_type='payment_transaction')` |
| `accounts` | Chart of accounts (code, name, type, parent_code). Seeded by `SEED_CHART_OF_ACCOUNTS`. | `journal_lines.account_id` |
| `journal_entries` | Double-entry header (`source_type`, `source_id`, `transaction_date`, `description`). | `journal_lines(entry_id)` |
| `journal_lines` | Debit/credit lines per journal entry (`account_id`, `debit`, `credit`). | `entry_id → journal_entries.id`; `account_id → accounts.id` |
| `journal_sync_failure_log` | Per-source audit records when `journal_sync` fails (error not raised, recorded). | `source_type`, `source_id` |
| `expense_categories` | Expense subcategory tree (parent + children) for dropdown population. | `parent_id → expense_categories.id` |

### 2.7 Events

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `events` | General events (notes, equipment issues, expenses, incidents). `type`, `summary`, `data` (JSON), `tags`, soft-deletable. | `event_people`; `event_photos`; `event_history`; `orders(order_id)` |
| `event_people` | Staff linked to an event with a role. | `event_id → events.id`; `staff_id → staff.id` |
| `event_photos` | Photos attached to an event. | `event_id → events.id`; `photo_id → photos.id` |
| `event_history` | Audit trail of event changes. | `event_id → events.id` |

### 2.8 Photos

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `photos` | Flat hash-based photo storage (SHA-256 dedup). File on disk under `photos/`. | referenced by `order_photos`, `product_catalog_photos`, `knowledge_entry_photos`, `event_photos` |

### 2.9 Staff & auth

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `staff` | Staff master (name, role, phone, active). Seeded with 5 members. | `event_people`; `orders(created_by)`; `users(staff_id)` |
| `users` | JWT auth users. `username` (lowercase), `password_hash` (bcrypt), `role` (`admin`/`staff`, DB CHECK), `staff_id` (UNIQUE partial). | `staff_id → staff.id`; `sessions`; `audit_log` |
| `sessions` | Active JWT session tracking (jti, IP, device headers, revoked_at). | `username → users.username` |
| `audit_log` | Records admin write operations for RBAC traceability. | `username → users.username` |

### 2.10 Operations

| Table | Purpose | Key relationships |
|-------|---------|--------------------|
| `checklist_templates` | Opening/closing checklist templates (per shift). Seeded. | `checklist_entries` |
| `checklist_entries` | Daily checklist instances (UNIQUE per template+date). | `template_id → checklist_templates.id` |
| `reconciliation_sessions` | End-of-day reconciliation sessions. | `reconciliation_lines`; `reconciliation_sale_rows` |
| `reconciliation_lines` | Per-product reconciliation lines with waste reason. | `session_id → reconciliation_sessions.id`; `price_chip_id` |
| `reconciliation_sale_rows` | Grouped sale rows for a reconciliation session. | `session_id → reconciliation_sessions.id` |
| `knowledge_entries` | Knowledge base entries (title, content, type, tags, pinned). | `knowledge_entry_photos` |
| `knowledge_entry_photos` | Photos attached to a knowledge entry. | `entry_id → knowledge_entries.id`; `photo_id → photos.id` |
| `catalog_photo_tags` | Junction tagging catalog photos with vocabulary keys (UNIQUE per photo+tag). | `photo_id → product_catalog_photos.id` |
| `print_log` | Print job tracking (work tickets, receipts). | `order_id → orders.id` |

### 2.11 Infrastructure

| Table | Purpose |
|-------|---------|
| `schema_version` | Tracks applied migration versions + timestamps + descriptions. |
| `app_config` | General key/value config (order sources, delivery threshold, paper mode, catalog tag vocabulary). UNIQUE on (config_key, config_value). |
| `server_logs` | API request logs written by `LoggingMiddleware`. |
| `log_triggers` | DB trigger metadata for the logging system. |

---

## 3. Double-Entry Accounting Model

### 3.1 Chart of accounts

Seeded by `SEED_CHART_OF_ACCOUNTS` (`schema.py:1618`) plus runtime additions
(v54 account 2400, v73 account 2500, v76 bank sub-accounts 1210/1220/1290,
v85 account 1600). Full reference in `docs/accounting-journal-reference.md`.

| Code | Name (VN) | Type | Parent |
|------|-----------|------|--------|
| 1000 | Tài sản | asset | — |
| 1100 | Tiền mặt (Cash on Hand) | asset | 1000 |
| 1200 | Tài khoản ngân hàng (Bank Account) | asset | 1000 |
| 1210 | TK Phượng VCB | asset | 1200 |
| 1220 | TK Ân VCB | asset | 1200 |
| 1290 | TK ngân hàng chưa phân bổ | asset | 1200 |
| 1300 | Hàng tồn kho (Inventory) | asset | 1000 |
| 1500 | Phải thu khách hàng (Accounts Receivable) | asset | 1000 |
| 1600 | Tài sản cố định (Fixed Assets) | asset | 1000 |
| 2000 | Nợ phải trả | liability | — |
| 2100 | Tiền khách đặt cọc (Customer Deposits) | liability | 2000 |
| 2200 | Tiền ship bus giữ hộ (Bus Shipping Held) | liability | 2000 |
| 2300 | Phải trả nhân viên (Staff Payables) | liability | 2000 |
| 2400 | Tiền rút tạm giữ (Tien Rut Held) | liability | 2000 |
| 2500 | Phải trả người bán (Accounts Payable) | liability | 2000 |
| 3000 | Vốn chủ sở hữu | equity | — |
| 3100 | Vốn chủ sở hữu (Owner's Equity) | equity | 3000 |
| 4000 | Doanh thu | income | — |
| 4100 | Doanh thu bán hàng (Order Revenue) | income | 4000 |
| 5000 | Chi phí | expense | — |
| 5100 | Nguyên liệu (Ingredients) | expense | 5000 |
| 5110 | Trứng (Eggs) | expense | 5100 |
| 5120 | Kem (Cream) | expense | 5100 |
| 5130 | Bột (Flour) | expense | 5100 |
| 5140 | Phụ gia khác (Other Additives) | expense | 5100 |
| 5200 | Bao bì (Packaging) | expense | 5000 |
| 5210 | Hộp & đế (Boxes & Bases) | expense | 5200 |
| 5220 | Phụ kiện (Accessories) | expense | 5200 |
| 5230 | Bọc nilon (Plastic Wrap) | expense | 5200 |
| 5300 | Vận chuyển (Delivery/Shipping) | expense | 5000 |
| 5400 | Điện/nước (Utilities) | expense | 5000 |
| 5500 | Dụng cụ (Tools) | expense | 5000 |
| 5600 | Sửa chữa (Equipment Maintenance) | expense | 5000 |
| 5700 | Lương/phụ cấp (Staff Salary) | expense | 5000 |
| 5800 | Khác (Other Expenses) | expense | 5000 |
| 5900 | Giá vốn hàng bán (COGS) | expense | 5000 |
| 5910 | Chi phí khuyến mãi (Promotional Expense) | expense | 5000 |

### 3.2 Entry structure

Every business action that moves value creates one `journal_entries` row and
two or more `journal_lines` rows. Each line has an `account_id`, a `debit`
and a `credit` (exactly one is non-zero), and the sum of debits must equal
the sum of credits for the entry (double-entry invariant, verified by
`accounts/validate`).

`journal_entries.source_type` + `source_id` link the entry back to its
originating record:

| `source_type` | `source_id` | Writer |
|----------------|-------------|--------|
| `payment_transaction` | `payment_transactions.id` | `journal_sync/payment.py` |
| `expense_event` | `events.id` | `journal_sync/expense.py` |
| `order_revenue` / `order_cogs` / `order_gift_cogs` | `orders.id` | `journal_sync/order.py` |
| `reconciliation_waste` | `reconciliation_lines.id` | `journal_sync/waste.py` |

### 3.3 Asset account selection

The "Asset" account on the credit side of inflows / debit side of outflows is
resolved from the payment transaction's `method`:

| `method` | Asset account |
|----------|---------------|
| `cash` | 1100 (Cash on Hand) |
| `card` | 1100 (Cash on Hand) |
| `transfer` | 1200 (Bank Account) → sub-account (1210/1220) when routed |

Unknown method defaults to 1100. See `docs/accounting-journal-reference.md`
for every debit/credit mapping per business action.

### 3.4 Integrity & failure handling

- `journal_sync` failures are **recorded, not raised**: the failing source is
  written to `journal_sync_failure_log` and the live `journal_sync_failures`
  counter (proxied via PEP-562 `__getattr__` on the package `__init__`) is
  incremented. This guarantees an accounting error never blocks an
  operational write.
- `GET /api/accounts/validate` runs full ledger integrity checks (double-entry
  balance, COGS coverage, waste, cost history) and reports any drift.
- `GET /api/health` exposes the `journalSyncFailures` counter and the last 50
  failure log rows.

---

## 4. Indexes

### 4.1 Composite indexes

| Index | Table(columns) | Notes |
|-------|----------------|-------|
| `idx_event_people_staff` | event_people(staff_id) | |
| `idx_event_people_event` | event_people(event_id) | |
| `idx_events_logged_by` | events(logged_by) | |
| `idx_server_logs_ref` | server_logs(ref_type, ref_id) | |
| `idx_checklist_entries_unique` | checklist_entries(template_id, checklist_date) | UNIQUE |
| `idx_stock_lots_product_chip` | stock_lots(product_id, price_chip_id) | |
| `idx_stock_lots_fifo` | stock_lots(product_id, price_chip_id, restocked_at ASC) | FIFO ordering |
| `idx_inventory_items_lot_status` | inventory_items(lot_id, status, created_at) | |
| `idx_catalog_photo_tags_unique` | catalog_photo_tags(photo_id, tag_key) | UNIQUE |
| `idx_orders_due_date_public_order_code_unique` | orders(due_date, public_order_code) | UNIQUE |
| `idx_journal_entries_source` | journal_entries(source_type, source_id) | |
| `idx_stock_movements_product_chip_created` | stock_movements(product_id, price_chip_id, created_at) | |
| `idx_order_items_price_chip` | order_items(price_chip_id) | |
| `idx_reconciliation_lines_price_chip` | reconciliation_lines(price_chip_id) | |
| `idx_failure_log_type_id` | journal_sync_failure_log(source_type, source_id) | |
| `idx_negative_balance_product_chip` | negative_balance(product_id, price_chip_id) | UNIQUE |
| `idx_cost_history_product_effective` | cost_history(product_id, effective_from) | |
| `idx_product_blank_bom_price_chip` | product_blank_bom(price_chip_id) | |
| `idx_order_item_blanks_item_blank_unique` | order_item_blanks(order_item_id, blank_id) | UNIQUE |
| `idx_orders_status_due_date` | orders(status, due_date) | v88 |
| `idx_orders_customer_id_created_at` | orders(customer_id, created_at) | v88 |
| `idx_journal_entries_transaction_date` | journal_entries(transaction_date) | |

### 4.2 Notable UNIQUE indexes

- `idx_products_code` — products(code)
- `idx_app_config_key_value` — app_config(config_key, config_value) UNIQUE
- `idx_users_staff_id` — users(staff_id) WHERE staff_id IS NOT NULL (partial UNIQUE)
- `uq_expense_categories_name_parent` — expense_categories(name, parent_id) UNIQUE

Single-column indexes exist on most FK columns and common filter columns
(events.type/timestamp/tags, orders.status/due_date, photos.hash,
payment_transactions.order_id, journal_lines.entry_id/account_id,
customers.name/phone/search_name, audit_log.created_at/username/entity_type,
sessions.username/jti/revoked_at, …).

---

## 5. Seed Data

| Seed constant | V | Target | Content |
|---------------|---|--------|---------|
| `SEED_PRODUCTS` | 3 | products | 23 bakery products (breads, cakes, pastries, cookies) |
| `SEED_CATEGORIES` | 4 | categories | Category slugs |
| `SEED_CAKE_VARIANTS` | 6 | product_price_chips | 16/18/20/22cm × thường/cao/tầng price tiers |
| `SEED_SU_KEM_SETS` | 6 | product_price_chips | Su kem set pricing |
| `SEED_ORDER_SOURCES` | 14 | app_config | Order source config values |
| `SEED_STAFF` | 16 | staff | 5 staff members |
| `SEED_CHECKLIST_OPENING` | 18 | checklist_templates | Opening checklist templates |
| `SEED_CHECKLIST_CLOSING` | 18 | checklist_templates | Closing checklist templates |
| `SEED_SHIPPING_AND_EXTRAS` | 20 | app_config | Shipping presets + extras |
| `SEED_PRODUCT_ATTRIBUTES` | 23 | product_attributes | cash_amount, cash_fee for banh_kem |
| `SEED_CATALOG_TAGS` | 27/28 | app_config | 20 catalog tag vocabulary entries |
| `SEED_NHAN_BANH_OPTIONS` | 31 | product_attribute_options | 5 fillings for banh_kem (Sầu riêng default) |
| `SEED_CHART_OF_ACCOUNTS` | 44 | accounts | Double-entry chart of accounts |
| `SEED_EXPENSE_CATEGORIES` | 86 | expense_categories | Expense subcategories + account codes |

Runtime seed accounts added by callables: 2400 (v54), 2500 (v73),
1210/1220/1290 (v76), 1600 (v85). All seeds use `INSERT OR IGNORE` so they
are idempotent across re-runs.