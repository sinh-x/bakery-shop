# API Reference

> Date: 2026-07-29
> Ticket: DG-308 (Phase 5 — Documentation)
> Base URL: `https://lily.tail10c2c6.ts.net/api` (prod) · `http://127.0.0.1:2312/api` (dev)
> Auto-generated OpenAPI spec: `/docs` (FastAPI Swagger UI) and `/openapi.json`.

This document is the human-curated API reference covering endpoint purposes,
auth requirements, and request/response conventions. It supplements — does not
replace — the auto-generated OpenAPI spec. For the auth workflow see
`docs/authentication.md`; for the system overview see `docs/architecture.md`.

---

## 1. Conventions

### 1.1 Authentication

All endpoints except the public ones below require a JWT bearer token in the
`Authorization` header when `AUTH_REQUIRED=true` (production enforcement
mode). During the grace period (`AUTH_REQUIRED=false`, default) requests
pass through unauthenticated but a present JWT is still decoded and the
claims attached to the request state.

```
Authorization: Bearer <jwt>
```

- **Public (never require auth):** `GET /api/health`, `POST /api/auth/login`.
- **Admin-only:** endpoints marked **[ADMIN]** below require a JWT whose
  `role` claim is `admin` (enforced via the `Depends(RequireRole("admin"))`
  dependency). Staff-role tokens receive `403`.
- **Auth (any role):** endpoints marked **[AUTH]** accept either `admin` or
  `staff` role tokens when enforcement is on.

### 1.2 Roles

| Role | Access |
|------|--------|
| `admin` | All endpoints, user management, audit log, all create/update/delete operations. |
| `staff` | Daily operational endpoints (orders, events, checklist, POS, catalog reads, stock). Blocked from admin writes. |

### 1.3 Common headers

Sent by the Flutter client on every request for logging/analytics (optional,
server tolerates absence):

| Header | Purpose |
|--------|---------|
| `x-device-model` | Device model for request logs. |
| `x-app-version` | Client app version. |
| `x-os-version` | OS version. |

### 1.4 Error responses

Errors follow FastAPI conventions: `{"detail": "<message>"}`. The global
exception handler (`api/exception_handlers.py`) sanitizes unhandled
exceptions into a generic 500 with a correlation-safe message (no stack
trace leakage). Status codes in use:

| Code | Meaning |
|------|---------|
| 200 | Success (GET / PATCH / PUT success). |
| 201 | Created (POST success). |
| 401 | Missing/invalid/expired/revoked JWT (when `AUTH_REQUIRED=true`). |
| 403 | Valid JWT but insufficient role (staff hitting an admin endpoint). |
| 404 | Resource not found. |
| 409 | Conflict (duplicate value, e.g. config key already exists). |
| 422 | Validation error (bad chip, malformed body). |
| 423 | Account locked by brute-force lockout (login). |
| 429 | IP rate-limited (login). |
| 500 | Unhandled server error (sanitized message). |

### 1.5 IDs & refs

Orders are addressed by `order_ref` (unique human-readable reference) **or**
numeric `id` in URL path params (`{ref}` accepts either). Products,
customers, events, etc. use numeric `id`. Work items and blanks use numeric
ids scoped to their parent order.

---

## 2. Health & Auth

### 2.1 Health — `GET /api/health`  **[PUBLIC]**

Returns server status, version, build fingerprint, and accounting sync
health. Used by the Docker healthcheck and the Flutter app startup check.

**Response:**
```json
{
  "status": "ok",
  "version": "0.8.18",
  "fingerprint": "abc123",
  "journalSyncFailures": 0,
  "journalSyncFailureLogRows": [
    {"id": 1, "source_type": "payment_transaction", "source_id": 42,
     "error_message": "...", "created_at": "2026-07-29T10:00:00Z"}
  ]
}
```

### 2.2 Login — `POST /api/auth/login`  **[PUBLIC]**

Authenticates a user and returns a JWT. See `docs/authentication.md` §2 for
the full flow including brute-force lockout and rate limiting.

**Request:**
```json
{"username": "sinh", "password": "<plaintext>"}
```
**Response (200):**
```json
{"token": "<jwt>", "username": "sinh", "role": "admin"}
```
**Errors:** `401` invalid credentials / deactivated account; `423` locked;
`429` rate-limited. Password verified via bcrypt (cost 12). JWT is HS256,
7-day expiry, claims `{sub, role, exp, jti}`. A session row is recorded.

---

## 3. Orders

### 3.1 Orders — prefix `/api/orders`, tag `orders`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/orders` | AUTH | List orders (filterable by status, customer, due date, active_only). Delivered+fully-paid orders are filtered out of the default active view. |
| POST | `/api/orders` | AUTH | Create a new order. Resolves/creates a customer via `customer_resolver`; creates `order_items` + work items; attaches photos; can auto-decrement stock for trưng bày products when `status=delivered`. |
| GET | `/api/orders/{ref}/events` | AUTH | List events linked to an order (newest first). |
| GET | `/api/orders/{ref}/inventory-audit` | AUTH | Read immutable inventory decisions and existing reconciliation links, newest first. |
| GET | `/api/orders/{ref}` | AUTH | Order detail by `order_ref` or `id`. |
| POST | `/api/orders/{ref}/acknowledge` | AUTH | Mark an order as acknowledged (sets `acknowledged_at` if null). |
| PATCH | `/api/orders/{ref}` | AUTH | Update order fields (customer, delivery, items, notes). |
| POST | `/api/orders/{ref}/status` | AUTH | Transition order status. **Reason required when moving backward** (e.g. to `cancelled`). Triggers journal sync side effects (revenue/COGS on `delivered`, reversals on `cancelled`). |
| PATCH | `/api/orders/{ref}/payment-method` | AUTH | Update the payment method on the most recent payment transaction. |
| PATCH | `/api/orders/{ref}/payment` | AUTH | Record a payment (creates a new `payment_transactions` row if amount > 0). |

**Status machine:** `new` → `confirmed` → `in_progress` → `ready` → `delivered` (or `cancelled`). Item statuses cascade with the order; extras/gifts auto-transition to match (F5).

#### Inventory audit — `GET /api/orders/{ref}/inventory-audit` **[AUTH]**

Returns read-only, append-only inventory evidence for the order addressed by
`order_ref` or numeric `id`. Every authenticated staff role that can view the
order may use this endpoint; there is no admin-only gate and no audit mutation
route.

Query parameters:

| Parameter | Contract |
|-----------|----------|
| `limit` | Optional integer, default `100`, range `1..500`. Values above `500` are rejected with `422`. |
| `offset` | Optional nonnegative integer, default `0`. |

Entries are ordered deterministically by `createdAt DESC`, then `id DESC`.
A known order without audit history returns an empty envelope; an unknown order
returns `404`.

**Response (200):**
```json
{
  "items": [
    {
      "id": 42,
      "operationId": "182f85f3-a304-4bbb-beca-337860641cf7",
      "orderId": 17,
      "orderRef": "ORD-017",
      "trigger": "status_action",
      "action": "inventory_deduct",
      "statusBefore": "new",
      "statusAfter": "confirmed",
      "actor": {
        "identifier": "cashier",
        "username": "cashier",
        "staffId": 3,
        "staffName": "Thu ngân",
        "role": "staff"
      },
      "createdAt": "2026-09-04T03:00:00Z",
      "outcome": "applied",
      "reasonCode": "eligible_display_item",
      "detail": null,
      "item": {
        "orderItemId": 91,
        "productId": 31,
        "productCode": "TB-31",
        "productName": "Bánh trưng bày",
        "isGift": false,
        "isDisplay": true,
        "source": "Tại tiệm - POS",
        "requestedQuantity": 2,
        "priceChipId": 9,
        "priceChipLabel": "Miếng lớn",
        "useInventoryPresent": true,
        "useInventoryValue": true,
        "resolvedBucket": "price_chip",
        "resolvedPriceChipId": 9,
        "resolvedPriceChipLabel": "Miếng lớn",
        "resolvedUnitPrice": 45000
      },
      "requestedDelta": -2,
      "appliedDelta": -2,
      "before": {"fifoAvailable": 5, "negative": 0, "net": 5},
      "after": {"fifoAvailable": 3, "negative": 0, "net": 3},
      "stockMovementId": 701,
      "negativeMovementId": null,
      "relatedEntryId": null,
      "reconciliationSessionId": 12,
      "reconciliationSessionIds": [12],
      "reconciliationLineIds": [33],
      "reconciliationSaleRowIds": [44]
    }
  ],
  "total": 1,
  "hasMore": false,
  "limit": 100,
  "offset": 0
}
```

Missing inventory snapshots and reconciliation relationships are represented by
explicit `null` values and empty identifier lists. Failure `detail` values are
bounded and sanitized; they do not expose stack traces or raw confidential
request values.

### 3.2 Work items — prefix `/api/orders`, tag `work-items`

Per-order line tasks that feed the cake queue.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/orders/{ref}/items` | AUTH | List work items for an order. |
| POST | `/api/orders/{ref}/items` | AUTH | Add a work item to an order. |
| PATCH | `/api/orders/{ref}/items/{item_id}` | AUTH | Update a work item. |
| DELETE | `/api/orders/{ref}/items/{item_id}` | AUTH | Remove a work item. |
| POST | `/api/orders/{ref}/items/{item_id}/blanks` | AUTH | Assign cake blanks (phôi bánh) to a work item. |
| PATCH | `/api/orders/{ref}/items/{item_id}/blanks/{blank_item_id}` | AUTH | Update a blank assignment. |
| DELETE | `/api/orders/{ref}/items/{item_id}/blanks/{blank_item_id}` | AUTH | Remove a blank assignment. |
| POST | `/api/orders/{ref}/items/{item_id}/status` | AUTH | Transition a work item's status (reason required for backward moves). |

Work item status maps to order status (`pending`/`confirmed`/`working`/`ready`/`delivered`/`cancelled`).

### 3.3 Cake queue — prefix `/api/work-items`, tag `cake-queue`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/work-items` | AUTH | Production queue across all non-delivered orders. Filter by status (default `pending`+`working`; `?include_ready=true` adds `ready`; `?status=all` excludes only `delivered`). Sorted by due date ascending (urgent first). |

### 3.4 Order photos — prefix `/api/orders`, tag `order-photos`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/orders/{ref}/photos` | AUTH | List photos attached to an order (ordered by position). |
| POST | `/api/orders/{ref}/photos` | AUTH | Attach a photo (dedups by hash+work_item). |
| PATCH | `/api/orders/{ref}/photos/{photo_id}` | AUTH | Update tags or position. |
| DELETE | `/api/orders/{ref}/photos/{photo_id}` | AUTH | Detach a photo (DB record only; hash file is kept on disk). |

### 3.5 Payment transactions — prefix `/api/orders`, tag `payment-transactions`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/orders/{ref}/transactions` | AUTH | List payment transactions for an order. |
| POST | `/api/orders/{ref}/transactions` | AUTH | Create a payment transaction (`type`: deposit/payment/full_payment/refund/tien_rut; `method`: cash/card/transfer). Triggers `journal_sync/payment`. |
| PATCH | `/api/orders/{ref}/transactions/{txn_id}` | AUTH | Update a transaction. |
| DELETE | `/api/orders/{ref}/transactions/{txn_id}` | AUTH | Delete a transaction. |
| POST | `/api/orders/{ref}/transactions/{txn_id}/invalidate` | AUTH | Soft-delete a transaction (`invalidated_at`/`invalidated_by`) + reverse its journal entry. |
| POST | `/api/orders/{ref}/transactions/{txn_id}/restore` | AUTH | Restore an invalidated transaction + recreate its journal entry. |

### 3.6 Receipts — prefix `/api/orders`, tag `receipts`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/orders/{ref}/receipt` | AUTH | Render a printer-ready receipt image (576×1024 label or roll format per `paper_mode`). |

### 3.7 Printing — prefix `/api/orders`, tag `printing`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/orders/print/paper-mode` | AUTH | Effective printer paper mode (`label`/`roll`). |
| PUT | `/api/orders/print/paper-mode` | AUTH | Set the runtime paper-mode override (persists to `app_config`). |
| POST | `/api/orders/{ref}/print` | AUTH | Print an order's work ticket/receipt to the USB or IPP printer. |
| GET | `/api/orders/{ref}/print-log` | AUTH | Print history for an order. |
| GET | `/api/orders/print/status` | AUTH | Check USB printer accessibility + effective paper mode. |

---

## 4. Customers

Prefix `/api/customers`, tag `customers`.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/customers` | AUTH | List customers with partial search by name/phone. |
| GET | `/api/customers/duplicates` | ADMIN | Find duplicate customers. |
| POST | `/api/customers` | AUTH | Create a customer; returns list of other customers sharing the phone. |
| GET | `/api/customers/{customer_id}` | AUTH | Customer detail (includes `yearSummary`). |
| PATCH | `/api/customers/{customer_id}` | AUTH | Update name and/or phone. |
| DELETE | `/api/customers/{customer_id}` | ADMIN | Delete a customer. |
| GET | `/api/customers/{customer_id}/orders` | AUTH | Order history for a customer. |
| POST | `/api/customers/{customer_id}/merge` | ADMIN | Merge customers. |

---

## 5. Products & Catalog

### 5.1 Products — prefix `/api/products`, tag `products`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/products` | AUTH | List products. |
| GET | `/api/products/code/{code}` | AUTH | Get a product by code. |
| GET | `/api/products/{product_id}` | AUTH | Product detail. |
| POST | `/api/products` | ADMIN | Create a product. |
| PATCH | `/api/products/{product_id}` | ADMIN | Update a product. |
| DELETE | `/api/products/{product_id}` | ADMIN | Soft-delete a product (`active=0`). |
| POST | `/api/products/{product_id}/photo` | AUTH | Upload a product photo. |
| GET | `/api/products/{product_id}/photo` | AUTH | Get a product photo. |
| GET | `/api/products/{product_id}/cost` | AUTH | Current + historical cost (from `cost_history`). |
| POST | `/api/products/{product_id}/cost` | AUTH | Create/update cost (idempotent on `effective_from`). |

### 5.2 Catalog photos — prefix `/api/products`, tag `catalog`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/products/{product_id}/catalog` | AUTH | List a product's gallery photos (ordered by position). |
| POST | `/api/products/{product_id}/catalog` | AUTH | Add a catalog photo. |
| GET | `/api/products/{product_id}/catalog/{photo_id}/photo` | AUTH | Fetch a catalog photo by id (serves via hash). |
| PATCH | `/api/products/{product_id}/catalog/{photo_id}` | AUTH | Replace catalog_photo_tags for a photo. |
| DELETE | `/api/products/{product_id}/catalog/{photo_id}` | AUTH | Delete a catalog photo (DB record only). |
| POST | `/api/products/{product_id}/catalog/{photo_id}/promote` | AUTH | Promote a catalog photo to the product's main photo. |
| GET | `/api/catalog/photos` | AUTH | List all catalog photos. |

### 5.3 Categories — prefix `/api/categories`, tag `categories`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/categories` | AUTH | List categories (`include_inactive=1` includes hidden). |
| POST | `/api/categories` | ADMIN | Create a category. |
| PATCH | `/api/categories/reorder` | ADMIN | Reorder categories. |
| PATCH | `/api/categories/{category_id}` | ADMIN | Update a category (name, code_prefix, active). |

### 5.4 Product attributes — prefix `/api`, tag `product-attributes`

System-level attribute types (e.g. `cash_amount`, `cash_fee`, `trung_bay`, `tang_kem`, `rut_tien`, `nhan_banh`).

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/product-attributes` | AUTH | List active attribute types (optional category filter). |
| POST | `/api/product-attributes` | ADMIN | Create an attribute type. |
| PATCH | `/api/product-attributes/{attribute_type}` | ADMIN | Update an attribute type. |
| DELETE | `/api/product-attributes/{attribute_type}` | ADMIN | Soft-delete an attribute type (`active=0`). |
| GET | `/api/products/{product_id}/attributes` | AUTH | Get per-product attribute values. |
| POST | `/api/products/{product_id}/attributes` | ADMIN | Set/update a per-product attribute value. |
| DELETE | `/api/products/{product_id}/attributes/{attribute_type}` | ADMIN | Remove a per-product attribute value (reverts to default). |

### 5.5 Product attribute options — prefix `/api`, tag `product-attribute-options`

Enum options for an attribute (e.g. fillings for `nhan_banh`).

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/product-attributes/{attribute_type}/options` | AUTH | List options (ordered by sort_order then id). |
| POST | `/api/product-attributes/{attribute_type}/options` | ADMIN | Create an option. |
| PATCH | `/api/product-attribute-options/{option_id}` | ADMIN | Update an option (`value_vi`, `sort_order`, `active`). |
| DELETE | `/api/product-attribute-options/{option_id}` | ADMIN | Soft-delete an option (`active=0`). |
| POST | `/api/product-attributes/{attribute_type}/options/reorder` | ADMIN | Reorder options. |

### 5.6 Product price chips — prefix `/api`, tag `product-price-chips`

Preset pricing tiers per product (e.g. 16/18/20/22 cm sizes).

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/products/{product_id}/price-chips` | AUTH | List price chips. |
| POST | `/api/products/{product_id}/price-chips` | ADMIN | Create a price chip. |
| PATCH | `/api/products/{product_id}/price-chips/{chip_id}` | ADMIN | Update a price chip. |
| DELETE | `/api/products/{product_id}/price-chips/{chip_id}` | ADMIN | Delete a price chip. |

---

## 6. Stock & Inventory

### 6.1 Stock — prefix `/api`, tag `stock`

Chip-aware stock per product (trưng bày / display products).

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/products/{product_id}/stock` | AUTH | Current stock quantity for a product. |
| POST | `/api/products/{product_id}/stock/restock` | AUTH | Increase stock (restock a lot). |
| POST | `/api/products/{product_id}/stock/waste` | AUTH | Decrease stock (waste/spoilage). |
| POST | `/api/products/{product_id}/stock/adjust` | AUTH | Set exact stock quantity (adjustment). |
| GET | `/api/stock/overview` | AUTH | All trưng bày products with current stock + configured price chips. |

### 6.2 Blanks — prefix `/api`, tag `blanks`

Cake base (phôi bánh) stock and BOM management.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/blanks` | AUTH | List blanks (optional category filter). |
| POST | `/api/blanks` | AUTH | Create a blank. |
| PATCH | `/api/blanks/{blank_id}` | AUTH | Update a blank. |
| DELETE | `/api/blanks/{blank_id}` | AUTH | Delete a blank. |
| GET | `/api/price-chips/{chip_id}/blanks` | AUTH | BOM mappings for a price chip. |
| POST | `/api/price-chips/{chip_id}/blanks` | AUTH | Add a BOM mapping. |
| PATCH | `/api/price-chips/{chip_id}/blanks/{bom_id}` | AUTH | Update a BOM mapping. |
| DELETE | `/api/price-chips/{chip_id}/blanks/{bom_id}` | AUTH | Delete a BOM mapping. |
| GET | `/api/blanks/stock` | AUTH | Net stock per blank across all lots. |
| POST | `/api/blanks/stock` | AUTH | Record a blank stock change (production + / usage −). |
| GET | `/api/blanks/demand` | AUTH | Demand from pending orders vs. stock per blank. |
| GET | `/api/blanks/{blank_id}/stock-log` | AUTH | Chronological stock-change audit log for a blank. |
| GET | `/api/blanks/{blank_id}/products` | AUTH | Reverse lookup: products/work items linked to a blank. |

---

## 7. Events

Prefix `/api/events`, tag `events`. General events (notes, equipment issues, expenses, incidents).

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| POST | `/api/events` | AUTH | Create an event. |
| GET | `/api/events` | AUTH | List events. |
| GET | `/api/events/{event_id}` | AUTH | Event detail. |
| PATCH | `/api/events/{event_id}` | AUTH | Update an event (summary, type, tags, logged_by, data). |
| DELETE | `/api/events/{event_id}` | AUTH | Soft-delete an event. |
| GET | `/api/events/{event_id}/history` | AUTH | Event change history (audit trail). |
| GET | `/api/events/{event_id}/photos` | AUTH | List photos attached to an event. |
| POST | `/api/events/{event_id}/photos` | AUTH | Attach a photo to an event. |
| DELETE | `/api/events/{event_id}/photos/{photo_id}` | AUTH | Detach a photo from an event. |

### Expenses — prefix `/api/expenses`, tag `expenses`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/expenses/debts` | AUTH | List outstanding debts. |
| POST | `/api/expenses/{event_id}/settle` | AUTH | Settle an expense event. |

### Expense categories — prefix `/api/expense-categories`, tag `expense-categories`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/expense-categories` | AUTH | Category tree (parent + children) for dropdown population. |

---

## 8. Accounting

Prefix `/api/accounts`, tag `accounts`. Double-entry ledger.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/accounts` | AUTH | Hierarchical chart of accounts. |
| GET | `/api/accounts/journal` | AUTH | Current balance per account (computed from `journal_lines`). |
| GET | `/api/accounts/balances` | AUTH | Account balances. |
| POST | `/api/accounts/journal/lock` | AUTH | Lock journal entries in a `[since, until]` range. |
| POST | `/api/accounts/owner-capital` | AUTH | Record owner capital injection (debit Asset, credit Owner's Equity). |
| POST | `/api/accounts/owner-draw` | AUTH | Record owner draw (debit Owner's Equity, credit Asset). |
| POST | `/api/accounts/staff-reimburse` | AUTH | Staff reimbursement (debit Staff Advances sub-account, credit Asset). |
| GET | `/api/accounts/validate` | AUTH | Run ledger integrity checks (double-entry, COGS, waste, cost history). |

See `docs/accounting-journal-reference.md` for every debit/credit mapping
and `docs/accounting-health-monitoring.md` for the health model.

---

## 9. Reconciliation

Prefix `/api/reconciliations`, tag `reconciliations`. End-of-day reconciliation.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/reconciliations/draft` | AUTH | Current reconciliation draft. |
| POST | `/api/reconciliations/submit` | AUTH | Submit a reconciliation session (can finalize orders to `delivered`). |
| GET | `/api/reconciliations/history` | AUTH | List past reconciliation sessions. |
| GET | `/api/reconciliations/history/{session_id}` | AUTH | Detail of a past session. |

---

## 10. Checklist

Prefix `/api/checklist`, tag `checklist`. Opening/closing shift checklists.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/checklist/templates` | AUTH | List checklist templates (optional shift filter). |
| POST | `/api/checklist/templates` | ADMIN | Create a template. |
| PUT | `/api/checklist/templates/{template_id}` | ADMIN | Update a template. |
| DELETE | `/api/checklist/templates/{template_id}` | ADMIN | Delete a template. |
| GET | `/api/checklist/daily` | AUTH | Today's checklist (auto-creates if absent). |
| POST | `/api/checklist/daily/{entry_id}/toggle` | AUTH | Toggle a checklist item complete/incomplete. |
| GET | `/api/checklist/history` | AUTH | Checklist history. |

---

## 11. Knowledge Base

Prefix `/api/knowledge`, tag `knowledge`.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| POST | `/api/knowledge` | AUTH | Create a knowledge entry. |
| GET | `/api/knowledge` | AUTH | List entries. |
| GET | `/api/knowledge/{entry_id}` | AUTH | Entry detail. |
| PATCH | `/api/knowledge/{entry_id}` | AUTH | Update an entry (title, content, type, tags). |
| DELETE | `/api/knowledge/{entry_id}` | AUTH | Delete an entry (cascade-deletes photos via FK). |
| POST | `/api/knowledge/{entry_id}/pin` | AUTH | Pin an entry to the top. |
| DELETE | `/api/knowledge/{entry_id}/pin` | AUTH | Unpin an entry. |
| POST | `/api/knowledge/{entry_id}/photos` | AUTH | Attach a photo. |
| GET | `/api/knowledge/{entry_id}/photos` | AUTH | List attached photos. |
| DELETE | `/api/knowledge/{entry_id}/photos/{photo_id}` | AUTH | Detach a photo (junction only; original kept). |

---

## 12. Photos

Prefix `/api/photos`, tag `photos`. Flat hash-based storage with SHA-256 dedup.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| POST | `/api/photos` | AUTH | Upload a photo (SHA-256 hash, dedup, flat storage). Returns the hash. |
| GET | `/api/photos/{photo_hash}.jpg` | AUTH | Fetch a photo by hash. |

---

## 13. Staff & Users

### 13.1 Staff — prefix `/api/staff`, tag `staff`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/staff` | AUTH | List active staff. |

### 13.2 Users — prefix `/api/users`, tag `users`

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/users/me/staff-binding` | AUTH | Current user's linked staff record. |
| PUT | `/api/users/me/staff-binding` | ADMIN | Set the staff binding for the current user. |

---

## 14. Audit Log

Prefix `/api/audit-log`, tag `audit-log`. Admin write-operation traceability.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/audit-log` | ADMIN | List admin audit log entries (FR23). |

---

## 15. Config

Prefix `/api/config`, tag `config`. General key/value config + server settings.

| Method | Path | Auth | Summary |
|--------|------|------|---------|
| GET | `/api/config` | AUTH | Server config (timezone, etc.) for client display sync. |
| GET | `/api/config/delivery_critical_threshold_minutes` | AUTH | Effective delivery critical threshold (minutes). |
| PUT | `/api/config/delivery_critical_threshold_minutes` | AUTH | Set the threshold (DB override, 1–10080). |
| GET | `/api/config/{config_key}` | AUTH | List config values for a key. |
| POST | `/api/config/{config_key}` | ADMIN | Create a config value. |
| GET | `/api/config/{config_key}/usage` | AUTH | Usage info for a config key. |
| PUT | `/api/config/{config_key}` | ADMIN | Update a config value (by old_value). |
| DELETE | `/api/config/{config_key}` | ADMIN | Delete a config value. |