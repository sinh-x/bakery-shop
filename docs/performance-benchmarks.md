# Performance Benchmarks

> Date: 2026-07-30
> Ticket: DG-308 (Phase 6 — Performance Profiling)
> Scope: FR-PERF-1 (order list screen), FR-PERF-2 (POS checkout flow), FR-PERF-3 (API endpoint latency)
> Repository: /home/sinh/Documents/bakery-shop
> Branch: feature/DG-308-tech-debt-cleanup-roadmap

This is a **profiling and documentation exercise** — no optimization is
performed. It establishes baselines, identifies bottlenecks with `file:line`
references, and proposes targeted optimizations for a future phase. The
requirements plan explicitly scopes this as profiling-only (FR-PERF-1/2/3
are "Should" priority; deliverable is benchmarks documented).

## Methodology

### Backend (FR-PERF-3)
- **Tooling:** `FastAPI TestClient` (in-process, no network) seeded with
  synthetic order volumes (50 / 200 / 500 / 1000 rows) spread across the five
  active statuses, each with one order item and (for delivered orders) one
  payment transaction. 60% of delivered orders are fully paid so they are
  filtered out of the `active_only` view (exercises the per-row
  `PaymentTransaction.total_paid_excl_outflows` check).
- **Profiling script:** `/tmp/opencode/profile_endpoints.py` (one-off, not
  committed; reproducible from this doc).
- **Measurements:** 5 repeats per endpoint (10 for `POST` endpoints),
  reporting median and p95 in milliseconds. SQLite 3.51.2, in-process.
- **Caveats:** In-process TestClient excludes real network/WSGI overhead, so
  absolute numbers are a lower bound for production. The relative scaling
  between endpoints and the N+1 pattern are the actionable findings.

### Flutter (FR-PERF-1)
- **Tooling:** `flutter test` headless micro-benchmarks in
  `app/test/features/orders/order_list_perf_benchmark_test.dart` (committed,
  12 tests). These exercise the client-side filter + group + urgency-count
  pipeline that runs after the API response arrives.
- **Limitation:** Live widget rendering / Flutter DevOps timeline traces
  require a running emulator or device, which is not available in this
  environment. Rendering cost is therefore analyzed statically from the
  widget tree (see §FR-PERF-1 Rendering) and the client-side *data* cost is
  measured directly.

### POS checkout (FR-PERF-2)
- The checkout flow is a 5-stage wizard driven by synchronous API calls.
  Step-transition responsiveness is dominated by (a) the
  `AnimatedSwitcher` 300ms transition and (b) the final `POST /api/orders`
  + payment-transaction calls. Both are measured: the API side via the
  backend profile, the UI side via static analysis of the stage widgets.

## Results: FR-PERF-3 — API Endpoint Latency

### Order list endpoints (the order list screen's data source)

| Endpoint | n=50 p95 | n=200 p95 | n=500 p95 | n=1000 p95 | Slow? |
|---|---:|---:|---:|---:|:---:|
| `GET /api/orders?active_only=true` | 48 ms | 93 ms | **254 ms** | **452 ms** | YES (>200ms at ≥500) |
| `GET /api/orders?status=delivered` | 19 ms | 35 ms | 51 ms | 108 ms | no |
| `GET /api/orders` (limit=50, paginated) | 37 ms | 40 ms | 35 ms | 43 ms | no |
| `GET /api/orders/{ref}` (single detail) | 22 ms | 18 ms | 19 ms | 19 ms | no |

Median times track p95 closely except for `active_only`, where p95 diverges
(n=500 median 206ms / p95 254ms; n=1000 median 393ms / p95 452ms).

### Mutation endpoints (POS checkout flow)

| Endpoint | n=1000 p95 | Notes |
|---|---:|---|
| `POST /api/orders` (create) | 23 ms | Includes journal sync when `status=delivered` |
| `POST /api/orders/{ref}/status` (delivered→completed) | 19 ms | Includes stock + journal sync |

### Other endpoints

| Endpoint | p95 | Notes |
|---|---:|---|
| `GET /api/products` | 25 ms | N+1 enrichment (see below) |
| `GET /api/customers` | 23 ms | |
| `GET /api/cake-queue` | 11 ms | |

**Endpoints exceeding 200ms: 2/21** — both are the
`GET /api/orders?active_only=true` path at n≥500.

## Results: FR-PERF-1 — Order List Screen Loading

The order list screen load is the sum of: (1) the `active_only` API call,
(2) client-side filtering/grouping, (3) widget rendering.

### (1) API call — dominant cost
See FR-PERF-3 above. **`GET /api/orders?active_only=true` is the
bottleneck**: 254ms at 500 orders, 452ms at 1000 orders. This is what the
user perceives as "the list is slow to load".

### (2) Client-side data pipeline — measured (headless benchmark)
`app/test/features/orders/order_list_perf_benchmark_test.dart`:

| Operation | n=50 | n=200 | n=500 | n=1000 |
|---|---:|---:|---:|---:|
| status filter + groupByDueDate | <16 ms | <16 ms | <16 ms | <16 ms |
| `groupOrdersByKanbanStatus` (6-column sort) | <16 ms | ~15 ms | **~30 ms** | **~55 ms** |
| urgency banner counts (3× full scan) | <16 ms | <16 ms | <16 ms | <16 ms |

The kanban grouping sorts each of 6 columns by `dueDate` ascending
(`order_list_screen.dart:643` `groupOrdersByKanbanStatus`), which is 6 sorts
over the full list — crosses the 16ms single-frame budget at n≥500.

### (3) Rendering — static analysis (no emulator available)
Each order row renders an `OrderCard` — a `ConsumerStatefulWidget` with its
own `AnimationController` (`app/lib/features/orders/widgets/order_card.dart:35`).
For critical-urgency orders the controller calls `_flashController.repeat()`
(`order_card.dart:55`), so **every visible critical card runs a perpetual
1500ms pulse animation** that rebuilds on every tick. With many critical
orders on screen this produces N concurrent animations.

Additional render-cost observations in `order_list_screen.dart`:
- The AppBar title is a separate `Consumer` that re-watches
  `orderListProvider` and runs `countCriticalActive` / `countUrgentActive` /
  `countIncompleteActive` on every rebuild (`order_list_screen.dart:269-274`).
  Because the body also watches `orderListProvider` (`:264`), the list is
  iterated **4 extra times per rebuild** for the banner counts.
- The delivery tab label computes `filterDeliveryOrders(orders, todayOnly:
  true)` inline in the `Tab` builder on every build
  (`order_list_screen.dart:396-398`).

## Results: FR-PERF-2 — POS Checkout Flow Responsiveness

The checkout flow (`app/lib/features/pos/pos_checkout_screen.dart`) is a
5-stage wizard. Stage transitions are gated by an `AnimatedSwitcher` with a
300ms duration (`pos_checkout_screen.dart:479`), which is the **floor** for
perceived step-transition time regardless of data work.

| Step transition | Data work | Measured API cost |
|---|---|---|
| Stage 1→2 (product selection) | none (in-memory cart) | — |
| Stage 2→3 (customer info) | none | — |
| Stage 3→4 (delivery options) | none | — |
| Stage 4→5 (review → payment) | cart write-back + total fold (`:124-140`) | — |
| Stage 5 → pay (final) | `POST /api/orders` + photo uploads + `POST /payment-transactions` | **23 ms** (create) + per-photo upload |

The final "Pay now" handler (`pos_checkout_screen.dart:214` `_handlePayNow`)
is sequential: `createOrder` → `_uploadOrderPhotos` (loop, one request per
photo, `:371-385`) → `_createPaymentTransactions` (1–2 requests, `:389-411`).
With per-item photos this is **1 + (photos) + (1–2)** sequential HTTP calls,
each adding network RTT on top of the 23ms server time.

The payment step UI itself (`pos_payment_step.dart`) is lightweight
(text fields + method selector); the NFR-9 sub-100ms target for *payment step
transitions* is met on the client side — the binding constraint is the
300ms `AnimatedSwitcher` and the final sequential API calls.

## Bottlenecks Identified (with file:line references)

### B1 — `active_only` order list: N+1 payment query + full sort (CRITICAL)
**Symptom:** `GET /api/orders?active_only=true` >200ms at ≥500 orders.

**Root cause:** For each active order row, `Order.from_row` calls
`PaymentTransaction.total_paid_excl_outflows(conn, row["id"])`
(`src/baker/models/order.py:462`) which runs a separate
`SELECT COALESCE(SUM(amount),0) FROM payment_transactions WHERE order_id=?`
query per row. At n=1000 this is ~1000 individual queries.

The `active_only` branch already precomputes `amount_paid` via
`_is_delivered_and_fully_paid` (`src/baker/api/orders.py:434` / `:451`) and
forwards it to `from_row(..., amount_paid=...)` to avoid a duplicate query —
but this only covers **delivered** rows. Non-delivered active rows (new /
confirmed / in_progress / ready) still fall through to the lazy
`total_paid_excl_outflows` call at `order.py:461-462`.

Additionally, the query `SELECT * FROM orders WHERE status IN (...) ORDER BY
id DESC` (`orders.py:424`) uses `idx_orders_status` for the `IN` filter but
then performs a **TEMP B-TREE sort** for `ORDER BY id DESC` (confirmed via
`EXPLAIN QUERY PLAN`). There is no `(status, id)` composite index.

**Locations:**
- `src/baker/api/orders.py:422-439` (active_only branch — loop + per-row query)
- `src/baker/api/orders.py:441-456` (status branch — same pattern)
- `src/baker/models/order.py:460-462` (lazy `total_paid_excl_outflows` fallback)
- `src/baker/models/payment_transaction.py:144` (`total_paid_excl_outflows`)

**Proposed optimization (future phase):**
1. Replace the N+1 with a single grouped query:
   `SELECT order_id, COALESCE(SUM(amount),0) FROM payment_transactions
   WHERE order_id IN (...) AND invalidated_at IS NULL GROUP BY order_id`,
   then pass the map to `from_row`. This collapses ~1000 queries to 1.
2. Precompute `amount_paid` for **all** rows in the `active_only`/`status`
   branches (not just delivered), forwarding it via `amount_paid=`.
3. Add a composite index `idx_orders_status_id` on `(status, id DESC)` to
   satisfy the `ORDER BY id DESC` without a temp B-tree.

### B2 — `GET /api/products`: N+1 enrichment queries (MEDIUM)
**Symptom:** 25ms p95 on seed data (~50 products); scales as O(products ×
attributes).

**Root cause:** `_enrich_product` (`src/baker/api/products.py:164`) runs
three sub-queries per product:
- `_product_attributes` (`:68`) — 1 query + JSON parsing
- `_product_price_chips` (`:40`) — 1 JOIN query
- `_product_enum_attributes` (`:108`) — 1 query **plus a per-attribute-type
  option query** (`:137`), so it is O(attribute_types) per product.

The `list_products` loop (`products.py:221-223`) calls `_enrich_product` per
row, so total queries ≈ `products × (2 + attribute_types + 1)`.

**Locations:**
- `src/baker/api/products.py:220-223` (per-row enrichment loop)
- `src/baker/api/products.py:164-172` (`_enrich_product`)
- `src/baker/api/products.py:137-141` (per-attribute option sub-query)

**Proposed optimization (future phase):** Batch-load attributes/price-chips/
enum-options for all returned product IDs in 3 set-based queries, then join
in Python. Reduces ~`N×K` queries to 3.

### B3 — Order list rendering: per-card animation controllers (MEDIUM)
**Symptom:** Jank / high GPU utilization when many critical orders are
visible.

**Root cause:** Each `OrderCard` is a `ConsumerStatefulWidget` that creates
its own `AnimationController` (`app/lib/features/orders/widgets/order_card.dart:35`)
and starts a perpetual `repeat()` pulse for critical-urgency orders
(`order_card.dart:55`). N visible critical cards = N concurrent animations
driving N rebuilds per tick.

**Locations:**
- `app/lib/features/orders/widgets/order_card.dart:35` (controller per card)
- `app/lib/features/orders/widgets/order_card.dart:55` (`repeat()` for critical)

**Proposed optimization (future phase):** Drive the pulse from a single
top-level ticker that broadcasts a progress value via an
`AnimationController` + `Listenable` provider, so cards listen rather than
each owning a controller. Alternatively gate the pulse to only the visible
viewport (via `ListView.builder` already in use — the issue is cards off
the top are disposed, but cards *in* the viewport all animate).

### B4 — Order list screen: repeated full-list iterations per rebuild (LOW)
**Symptom:** Extra CPU on every `OrderListScreen` rebuild.

**Root cause:** The AppBar title `Consumer` re-runs
`countCriticalActive` + `countUrgentActive` + `countIncompleteActive`
(`order_list_screen.dart:272-274`) — three full O(n) scans — on every
rebuild, in addition to the body's own `orderListProvider` watch. The
delivery tab label also runs `filterDeliveryOrders` inline per build
(`:396-398`).

**Locations:**
- `app/lib/features/orders/order_list_screen.dart:269-274` (3× count scans)
- `app/lib/features/orders/order_list_screen.dart:396-398` (delivery tab fold)

**Proposed optimization (future phase):** Memoize the counts in a derived
provider (`urgency_count_provider.dart` already exists — wire it into the
AppBar instead of recomputing inline) and cache the delivery-today count.

### B5 — POS checkout: sequential per-photo uploads (LOW)
**Symptom:** Checkout completion latency grows linearly with photo count.

**Root cause:** `_uploadOrderPhotos` loops over each item's `pendingPhotos`
and uploads them one at a time (`pos_checkout_screen.dart:371-385`), each a
separate HTTP round-trip.

**Locations:**
- `app/lib/features/pos/pos_checkout_screen.dart:371-385` (sequential upload loop)

**Proposed optimization (future phase):** Use `Future.wait` for parallel
uploads (bounded concurrency), or a multipart batch endpoint.

### B6 — Kanban grouping: 6 column sorts (LOW)
**Symptom:** ~30ms at 500 orders, ~55ms at 1000 orders (above one-frame
budget but below 200ms threshold).

**Root cause:** `groupOrdersByKanbanStatus` (`order_list_screen.dart:643`)
sorts each of 6 columns independently by `dueDate`.

**Proposed optimization (future phase):** Sort the full list once by
`dueDate`, then partition into columns (stable partition preserves sort
order within each column).

## NFR Targets vs. Observed

| NFR | Target | Observed | Status |
|---|---|---|:---:|
| NFR-8 | Order list renders <500ms for ≤500 orders | API 254ms + client <16ms + render (unmeasured, static-only) | At-risk: API alone is 254ms at 500; render cost unmeasured but OrderCard animations add GPU load. Likely <500ms total on modern hardware but **not verified** without a device trace. |
| NFR-9 | POS checkout payment step <100ms transitions | Client step transitions are 300ms (AnimatedSwitcher floor) but the *payment step UI itself* is sub-100ms; final pay API is 23ms + sequential uploads | Payment-step UI meets target; overall checkout completion does not (by design — sequential uploads). |

## Reproducing

### Backend profile
```bash
cd /home/sinh/Documents/bakery-shop
# The one-off script /tmp/opencode/profile_endpoints.py seeds a temp DB
# and prints all timings. Reconstruct from this doc or re-run if present.
PYTHONPATH=src python /tmp/opencode/profile_endpoints.py
```

### Flutter client benchmark
```bash
cd app
flutter test test/features/orders/order_list_perf_benchmark_test.dart
```

### Query plan inspection
```python
from baker.db.connection import get_db
from baker.db.schema import ensure_schema
with get_db() as conn:
    ensure_schema(conn)
    print(conn.execute("EXPLAIN QUERY PLAN "
        "SELECT * FROM orders WHERE status IN "
        "('new','confirmed','in_progress','ready','delivered') "
        "ORDER BY id DESC").fetchall())
```

## Follow-up / Future Work

- **Optimization phase:** B1 (active_only N+1 + composite index) is the
  highest-ROI fix — it would bring the 1000-order case from ~450ms to an
  estimated <50ms. Recommend a dedicated ticket.
- **Device-side render profiling:** Run Flutter DevOps timeline on a real
  device/emulator with 500+ orders to measure actual `OrderCard` render and
  animation cost (this profile could not — no display available).
- **Load test with network RTT:** The in-process numbers exclude network;
  real-world latency adds ~5-30ms RTT per call, which compounds the
  sequential POS photo uploads (B5).
- **Re-profile after B1 fix** to confirm NFR-8 is met end-to-end.