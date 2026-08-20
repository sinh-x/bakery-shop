# Architecture Overview

> Date: 2026-07-29
> Ticket: DG-308 (Phase 5 — Documentation)
> Scope: High-level architecture covering system components, data flow, and deployment topology.

This document is the developer reference for the bakery-shop system's overall
architecture. It complements the domain-specific docs already in `docs/`
(`authentication.md`, `accounting-journal-reference.md`,
`accounting-health-monitoring.md`, `dev-verification-workflow.md`,
`migration-rollback.md`, `prod-workflow.md`, `release-workflow.md`,
`flutter-coding-standards.md`, `code-quality-audit.md`).

---

## 1. System Components

The bakery-shop is a two-tier system: a **Python FastAPI backend** (`baker`)
that owns all business logic and persistence, plus a **Flutter client**
that consumes the API. The backend is the single source of truth; the Flutter
app is a thin presentation layer.

```
                         ┌──────────────────────────────────────────┐
                         │                 Clients                  │
                         │  ┌──────────┐   ┌──────────┐            │
   Tailscale tailnet ───►│  │ Flutter  │   │ Flutter  │  (web)     │
   (lily.tail10c2c6.     │  │ Android/ │   │   Web    │            │
    ts.net)              │  │  iOS app │   │ (PWA)   │            │
                         │  └────┬─────┘   └────┬─────┘            │
                         └───────┼──────────────┼──────────────────┘
                                 │ HTTPS        │
                         ┌───────▼──────────────▼──────────────────┐
                         │            Caddy 2 (TLS)               │
                         │  certs/  ·  /api/* → reverse_proxy     │
                         │  /  → Flutter web-build (SPA fallback) │
                         └───────┬────────────────────────────────┘
                                 │ HTTP (container network)
                         ┌───────▼────────────────────────────────┐
                         │            baker-prod                 │
                         │  FastAPI (uvicorn)   port 2108        │
                         │  ┌──────────────────────────────────┐ │
                         │  │ Middleware: Logging · Auth · CORS│ │
                         │  │ Routers (~26) grouped by domain   │ │
                         │  │ Services layer (journal_sync,     │ │
                         │  │  inventory_fifo, customer_resolver│ │
                         │  │  order_stock, cost_resolver,      │ │
                         │  │  accounting_validation)           │ │
                         │  │ DB layer: connection · schema ·   │ │
                         │  │  queries                          │ │
                         │  └─────────────┬────────────────────┘ │
                         │                │ sqlite3 (WAL mode)    │
                         │                ▼                       │
                         │      /var/lib/baker/baker.db            │
                         │      /var/lib/baker/photos/ (hashes)   │
                         └────────────────────────────────────────┘
                                 │ (optional) USB / IPP
                                 ▼
                          Thermal label printer
                          (/dev/usb/lp0 or CUPS IPP)
```

### 1.1 Backend (`src/baker/`)

The `baker` Python package is the entire backend. Layers, from outer to inner:

| Layer | Path | Responsibility |
|-------|------|----------------|
| **API / HTTP** | `src/baker/api/` | FastAPI routers, request/response models, middleware, exception handlers. Thin handlers — they validate input, call services/queries, and serialize output. ~26 router files grouped by domain (`orders`, `products`, `customers`, `events`, `accounts`, `reconciliations`, `checklist`, `knowledge`, `blanks`, `stock`, `printing`, `receipts`, `auth`, `users`, `audit_log`, …). |
| **Services** | `src/baker/services/` | Business logic that is reused across handlers or shared with the CLI. `journal_sync/` (double-entry accounting sync, split by domain), `inventory_fifo.py` (chip-aware FIFO lots), `customer_resolver.py` (customer resolution chain), `order_stock.py` (stock decrement on order), `cost_resolver.py` (product cost lookup), `accounting_validation.py` (ledger integrity checks). |
| **DB** | `src/baker/db/` | `connection.py` (context-managed `sqlite3` with WAL + foreign keys + 5s timeout), `schema.py` (88 incremental migrations + seed data), `queries.py` (reusable query helpers). |
| **Commands / CLI** | `src/baker/commands/` | Administrative repair and maintenance commands (`repair.py`, etc.) invoked via the `baker` CLI (`cli.py`). |
| **Config** | `src/baker/config.py` | YAML + env-var config loader. Loaded once on import; `reload()` switches configs. Holds `DB_PATH`, `JWT_SECRET`, `AUTH_REQUIRED`, `TIMEZONE`, `DELIVERY_CRITICAL_THRESHOLD_MINUTES`, printer settings, etc. |
| **Utils / Formatters / Models** | `src/baker/utils/`, `formatters/`, `models/` | Shared helpers (time, db), output formatters, pydantic request/response models. |
| **Integrations** | `ipp_client.py`, `usb_printer.py`, `triggers.py` | Thermal printer drivers (USB `/dev/usb/lp0` or CUPS IPP), DB log triggers. |

#### Application bootstrap

`src/baker/api/app.py:create_app()` wires everything:

1. Refuses to start if `AUTH_REQUIRED=true` and `BAKER_JWT_SECRET` is ephemeral (DG-029 Mn-5) — prevents silent token invalidation on restart.
2. Creates the `FastAPI` app, sets up logging.
3. Registers a global exception handler (`exception_handlers.global_exception_handler`).
4. Adds middleware in order (outermost to innermost): `LoggingMiddleware` → `AuthMiddleware` → `CORSMiddleware`.
5. Registers ~26 routers covering all domains.
6. Registers a shutdown hook that runs `checkpoint_wal()` to flush the WAL journal into the main DB file before exit.

### 1.2 Middleware pipeline

Requests pass through three middleware layers (added in reverse order so the
first-added is outermost):

1. **`LoggingMiddleware`** (`api/middleware.py`) — logs every request to file
   and the `server_logs` table with metadata (method, path, status, duration,
   client IP, device headers, ref context). Runs first so it sees the final
   response status.
2. **`AuthMiddleware`** (`api/middleware.py`) — JWT validation. Behavior is
   gated by the `AUTH_REQUIRED` config flag:
   - `false` (default, grace period): requests pass through; a present JWT is
     decoded and `request.state.auth_username`/`auth_role` are attached.
   - `true`: rejects `401` for missing/invalid/expired tokens or revoked `jti`.
   - Always-public paths: `/api/health`, `/api/auth/login`.
   See `docs/authentication.md` for the full auth workflow.
3. **`CORSMiddleware`** — allows only the Tailscale web origin
   (`https://lily.tail10c2c6.ts.net`).

### 1.3 Flutter client (`app/`)

The Flutter app is a Riverpod-based single-page-style client:

| Directory | Role |
|-----------|------|
| `app/lib/main.dart` | Entry point. |
| `app/lib/app.dart` | Root `MaterialApp.router` + provider scope. |
| `app/lib/features/` | Feature screens grouped by domain (`orders/`, `products/`, `customers/`, `events/`, `checklist/`, `knowledge/`, `stock/`, `reconciliation/`, `settings/`, …). Each feature holds its screens, widgets, and local state. |
| `app/lib/providers/` | Riverpod providers grouped by domain (`order/`, `product/`, `customer/`, `auth/`, `shared/`, …). Feature-specific providers stay close to their screens; shared providers live in `shared/`. |
| `app/lib/data/` | API client (Dio), data models, repositories. A Dio interceptor attaches the stored JWT to every request and redirects to login on `401`. |
| `app/lib/shared/` | Cross-cutting widgets, labels (per-domain `labels/` files: `orders.dart`, `shared.dart`, `customers.dart`, `products.dart`, plus `utils.dart`), router (`router/app_router.dart` modularized into per-feature route modules), and common utilities. |

User-facing text is centralized in Vietnamese label modules under
`app/lib/shared/labels/` (see `docs/flutter-coding-standards.md` for the VN
label policy). The client targets Android, iOS, and Web (PWA served by Caddy).

---

## 2. Data Flow

### 2.1 Request lifecycle

```
Flutter (Dio) ──Bearer JWT──► Caddy (:443, TLS)
                                   │ /api/* reverse_proxy
                                   ▼
                              baker-prod (:2108)
                                   │
              LoggingMiddleware ──► AuthMiddleware ──► CORSMiddleware
                                   │
                                   ▼
                       FastAPI router (domain)
                                   │
                  ┌────────────────┼─────────────────┐
                  ▼                ▼                  ▼
            services.*        db.queries         db.schema
          (business logic)   (query helpers)    (migrations/seed)
                                   │
                                   ▼
                       sqlite3 (WAL, foreign_keys=ON)
                                   │
                                   ▼
                          /var/lib/baker/baker.db
```

- **Reads** go straight from router → `db.queries` / inline SQL → SQLite.
- **Writes** that touch accounting or inventory pass through the relevant
  service (`journal_sync`, `inventory_fifo`, `order_stock`,
  `customer_resolver`, `cost_resolver`) so the double-entry ledger and stock
  lots stay consistent with the operational tables.
- **Admin writes** additionally call `record_audit_log` (via the
  `Depends(RequireRole("admin"))` dependency) so every admin mutation is
  recorded in the `audit_log` table.

### 2.2 Order lifecycle (canonical flow)

The order domain is the system's backbone. Status transitions and the side
effects each triggers:

| Transition | Side effects |
|------------|--------------|
| create (`new`) | `order_items` + `work_items` created; `customers` resolved/linked via `customer_resolver`; photos attached via `order_photos`; work ticket printable. |
| `new` → `confirmed` | Main items cascade to `confirmed`; stock auto-decremented for `trưng bày` (display) products; order journal sync scheduled. |
| → `delivered` | Revenue conversion journal entry (debit Asset / credit 4100 Revenue); COGS journal entry (debit 5900 COGS / credit 1300 Inventory) using `cost_resolver`; item statuses cascade to `delivered`; reconciliation can finalize. |
| → `cancelled` (backward) | Reason required; reverse journal entries generated by `_sync_cancelled_order_journal`; item statuses cascade to `cancelled`. |
| payment recorded | `payment_transactions` row → `_sync_payment_journal` creates a journal entry (debit Asset / credit 2100 Customer Deposits, with bus-shipping split to 2200 when applicable). |
| payment invalidated | Soft-delete on `payment_transactions` + reverse journal entry; `restore` reverses the invalidation. |

Work items (per-order line tasks) follow a parallel status machine
(`pending`/`confirmed`/`working`/`ready`/`delivered`/`cancelled`) and feed the
**cake queue** view (`api/cake_queue.py`) used by production staff. Blank
(phôi bánh) assignments link work items to physical cake bases via the
`order_item_blanks` junction (v83).

### 2.3 Double-entry accounting

The ledger is a standard double-entry model. Every business action that moves
value produces a balanced `journal_entries` row with two or more
`journal_lines` (debit/credit) referencing the chart of accounts seeded in
`SEED_CHART_OF_ACCOUNTS` (`schema.py:1618`). The `journal_sync/` package is
the single writer:

| Module | Syncs |
|--------|-------|
| `journal_sync/expense.py` | Expense events → journal entries. |
| `journal_sync/payment.py` | Payment transactions → journal entries (deposits, refunds, bus-shipping splits). |
| `journal_sync/order.py` | Order revenue + COGS + gift promotional expense on delivery; reversals on cancellation. |
| `journal_sync/waste.py` | Reconciliation waste lines → inventory write-down journal entries. |
| `journal_sync/_common.py` | Shared helpers, the live `journal_sync_failures` counter, and retry/failure logging to `journal_sync_failure_log`. |

Failures are recorded (not raised) so an accounting error never blocks an
operational write; the `journalSyncFailures` counter is exposed on
`/api/health` and `accounts/validate` runs integrity checks (double-entry
balance, COGS coverage, waste, cost history). See
`docs/accounting-journal-reference.md` for every debit/credit mapping and
`docs/accounting-health-monitoring.md` for the health model.

### 2.4 Inventory & FIFO

Inventory is **chip-aware**: a product can have multiple price chips
(`product_price_chips`) and stock is tracked per `(product_id, price_chip_id)`
bucket in `stock_lots` and `inventory_items` (v36). FIFO consumption
(`services/inventory_fifo.py`) consumes the oldest restocked lot first via
the `idx_stock_lots_fifo` index. Oversold quantities are tracked in
`negative_balance` (v62). Blanks (cake bases) have a parallel stock model
(`blanks`, `blank_stock`, `blank_stock_log`, `product_blank_bom`) introduced
in v81.

### 2.5 Customer resolution

Customer identity is resolved by `services/customer_resolver.py` using a
chain (DG-205 / DG-227 / DG-252):

1. Match by normalized phone against `customer_phones` (any row), with
   earliest-order-wins tiebreak.
2. Fall back to the legacy `customers.phone` column for pre-v58 databases.
3. Fall back to diacritic-insensitive name lookup via `customers.search_name`.
4. If nothing matches and the order is named/phone-bearing, auto-create a
   customer; otherwise link to the shared "Khách lẻ" (walk-in) customer.

The resolver is pure (takes a connection, returns an id) so it is reused by
both API handlers and repair commands without going through FastAPI.

---

## 3. Deployment Topology

### 3.1 Environments

`docker-compose.yml` defines two profiles:

| Profile | Services | Purpose |
|---------|----------|---------|
| `prod` | `baker-prod` + `caddy` | Production. `baker-prod` on `:2108`; Caddy on `:443` terminates TLS (certs from `certs/`), serves the Flutter web build from `web-build/`, and reverse-proxies `/api/*` to `baker-prod:2108`. Data volume: `./prod/data` → `/var/lib/baker`. |
| `dev` | `baker-dev` + `caddy-dev` | Local dev front-end on the host. `baker-dev` on `:2312`; `caddy-dev` serves plain HTTP on `127.0.0.1:2380` (TLS terminated by the central drgnfly-caddy gateway). Data volume: `./data` → `/var/lib/baker`. |

Validate the prod topology with:
```bash
docker compose --profile prod config
```

### 3.2 Container image

`Dockerfile` is a two-stage build on `python:3.12-slim`:

1. **Builder** — installs `gcc`, copies `pyproject.toml` + `src/`, runs
   `pip install --prefix=/install ".[web]"`.
2. **Runtime** — copies the install prefix, creates a non-root `baker` user
   (`UID`/`GID` build args), sets `BAKER_DATA_DIR=/var/lib/baker`,
   `BAKER_HOST=0.0.0.0`, `BAKER_PORT=2108`, and uses
   `docker-entrypoint.sh` as the entrypoint.

### 3.3 Network & security boundaries

- The deployment runs on a **Tailscale tailnet** (air-gapped). The only trusted
  web origin is `https://lily.tail10c2c6.ts.net` (CORS allowlist).
- Caddy terminates TLS with on-disk certs in `certs/`. The Caddy→baker hop is
  plain HTTP on the container network.
- Printer access: the container mounts `/dev/usb/lp0` (host GID `lp` = 20) for
  USB thermal printers, or uses `BAKER_PRINT_IPP_URL` for CUPS IPP over the
  tailnet (WireGuard provides transport encryption).
- Auth: JWT (HS256, 7-day expiry). `AUTH_REQUIRED=false` keeps the grace
  period (public access); flip to `true` once all clients send tokens. The
  server refuses to start if `AUTH_REQUIRED=true` and the JWT secret is
  ephemeral (see §1.1).

### 3.4 Data & persistence

- **SQLite** (single file at `$BAKER_DATA_DIR/baker.db`, WAL journal mode,
  `foreign_keys=ON`, 5s busy timeout) is the only datastore. Schema is
  migrated incrementally by `db/schema.py:ensure_schema()` up to version 88.
  See `docs/database-schema.md` for the schema reference and
  `docs/migration-rollback.md` for rollback procedures.
- **Photos** are stored flat by SHA-256 hash under `$BAKER_DATA_DIR/photos/`
  with dedup; DB rows in `photos` reference the hash. Catalog and order
  photos link via junction tables.
- **Logs** go to files under `$BAKER_LOG_DIR` and to the `server_logs` table
  (populated by `LoggingMiddleware` + DB triggers in `log_triggers`).

### 3.5 CI/CD

`.github/workflows/ci.yml` runs:
- **Python**: lint (`ruff`), tests (`pytest`), coverage enforcement
  (`--cov-fail-under=70`), security scan (Bandit + pip-audit).
- **Flutter**: `flutter analyze`, `dart analyze`, `flutter test --coverage`,
  blocking `flutter pub outdated`.
- **Docker**: `docker build .` with a 10-minute timeout.

Releases follow `docs/release-workflow.md` and `docs/pre-release-checklist.md`;
post-merge verification follows `docs/post-merge-verification-checklist.md`.

### 3.6 Nix & local dev

`flake.nix` provides a Nix dev shell. `.envrc` enables direnv. The SQLite
runtime requirement (≥ 3.35.0) is documented in the repo `CLAUDE.md` — the
v80 migration uses `ALTER TABLE ... DROP COLUMN`, only supported on 3.35.0+.

---

## 4. Key Design Principles

- **Backend is the source of truth.** The Flutter client never writes
  business rules; it only renders API responses and sends validated input.
- **Thin routers, fat services.** API handlers validate and serialize;
  reusable logic lives in `services/`. The `journal_sync/` split (v4.4,
  FR-ARCH-2) and `customer_resolver.py` extraction (FR-ARCH-1) are the
  established patterns.
- **Incremental, forward-only migrations.** `schema.py` applies migrations
  v1→v88 in order; there is no automatic down-migration (see
  `docs/migration-rollback.md` for the manual rollback procedure).
- **Accounting never blocks operations.** `journal_sync` failures are
  recorded in `journal_sync_failure_log` and surfaced on `/api/health` rather
  than raising, so an accounting error cannot block an order/payment write.
- **Grace-period auth.** The system runs unauthenticated during rollout but
  is wired for JWT/RBAC; flipping `AUTH_REQUIRED=true` enforces it
  everywhere at once.
- **Chip-aware inventory.** Stock and COGS are tracked per price-chip bucket,
  not just per product, so multi-tier pricing (e.g. 16/18/20/22 cm cakes)
  has accurate per-tier cost and quantity.

---

## 5. Further Reading

| Topic | Document |
|-------|----------|
| Authentication & RBAC | `docs/authentication.md` |
| Double-entry journal mappings | `docs/accounting-journal-reference.md` |
| Accounting health monitoring | `docs/accounting-health-monitoring.md` |
| Event ledger map | `docs/dg245-event-ledger-map.md` |
| Database schema reference | `docs/database-schema.md` |
| API reference | `docs/api.md` |
| Migration rollback | `docs/migration-rollback.md` |
| Production workflow | `docs/prod-workflow.md` |
| Release workflow | `docs/release-workflow.md` |
| Pre-release checklist | `docs/pre-release-checklist.md` |
| Post-merge verification | `docs/post-merge-verification-checklist.md` |
| Dev verification workflow | `docs/dev-verification-workflow.md` |
| Production repair guide | `docs/production-repair-guide.md` |
| PWA deployment guide | `docs/pwa-deployment-guide.md` |
| Flutter coding standards | `docs/flutter-coding-standards.md` |
| Code quality audit | `docs/code-quality-audit.md` |
| Lily deploy | `docs/lily-deploy.md` |