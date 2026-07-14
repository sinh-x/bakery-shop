# Authentication & Access Control (DG-029)

> Status: Implemented on `feature/DG-029-bakery-auth-rbac` (PR #102 → `develop`), pending UAT.
> Requirements: `agent-teams/requirements/artifacts/2026-07-04-bakery-auth-rbac-v2.md` (ticket DG-029)
> Scope: JWT authentication, admin/staff RBAC, login rate limiting, brute-force lockout, CLI user/session management, audit logging, and Flutter auth UI.

This document describes the authentication workflow, the security controls applied, and the known limitations / enhancement opportunities. It is the developer reference for the auth subsystem.

---

## 1. Overview

Before DG-029, every API endpoint was public and "identity" was a free-text `logged_by` string; the only security boundary was the Tailscale VPN. DG-029 adds a real authentication and authorization layer while preserving a **grace period** so existing clients keep working during rollout.

Two roles exist:

| Role | Who | Access |
|------|-----|--------|
| `admin` | Sinh (owner) | All endpoints, user management, audit log |
| `staff` | Ân, Ngân, Phượng, Tân | Daily operational endpoints (orders, events, checklist, POS, catalog, stock reads); blocked from admin writes |

Usernames are stored **lowercase** (`sinh`, `ân`, `ngân`, `phượng`, `tân`).

---

## 2. Authentication Workflow

### 2.1 End-to-end flow

```
┌────────────┐  1. POST /api/auth/login {username, password}
│  Flutter   │ ───────────────────────────────────────────────►  ┌──────────────┐
│    app     │                                                    │  FastAPI     │
│            │  2. {token, username, role}  (JWT, 7-day expiry)   │  backend     │
│            │ ◄───────────────────────────────────────────────  │              │
│            │                                                    │              │
│  stores    │  3. every request: Authorization: Bearer <token>  │ AuthMiddle-  │
│  JWT in    │ ───────────────────────────────────────────────► │ ware decodes │
│  Shared-   │                                                    │ + role check │
│  Prefs     │  4. 401 → interceptor clears token → login screen  │              │
└────────────┘                                                    └──────────────┘
```

1. App launch → check SharedPreferences for a stored JWT.
2. No token (or expired) → **login screen**. Valid credentials → `POST /api/auth/login` → store token → navigate to the main shell.
3. Every API request carries `Authorization: Bearer <token>` via a Dio interceptor.
4. Server middleware decodes the JWT, checks the denylist, extracts the role, and enforces per-endpoint permissions. A `401` clears the token client-side and redirects to login.

### 2.2 Login endpoint — `POST /api/auth/login`

Source: `src/baker/api/auth.py` (`login`).

- Request: `{username, password}`; Response: `{token, username, role}`.
- Password verification uses **bcrypt (cost factor 12)** via `passlib`.
- On success, issues an **HS256 JWT** with claims `{sub, role, exp, jti}` and a **7-day expiry** (no refresh — user re-logs in).
- On success, records an active **session** row (`sessions` table) with IP + device headers.
- Failure responses:
  - `401` — invalid username/password, or deactivated account.
  - `423` (Locked) — account locked by brute-force lockout.
  - `429` (Too Many Requests) — IP rate-limited.

### 2.3 Auth middleware

Source: `src/baker/api/middleware.py` (`AuthMiddleware`).

- Registered as the outermost layer (after `LoggingMiddleware`, before CORS) in `src/baker/api/app.py`.
- **Public paths** (always allowed): `/api/health`, `/api/auth/login`.
- **Grace period** (`AUTH_REQUIRED=false`, default): all requests pass through. If a token *is* present it is still decoded and `request.state.auth_username` / `auth_role` are attached, so role-gated routes give correct feedback to updated clients.
- **Enforced** (`AUTH_REQUIRED=true`): a valid `Authorization: Bearer <token>` is required. The JWT is:
  1. decoded with `JWT_SECRET` (HS256) — expired → `401`, malformed → `401`;
  2. checked against the **denylist** (`jti` revoked via force-logout) → `401`;
  3. its `sub`/`role` attached to `request.state`;
  4. its session's `last_activity` refreshed (best-effort; a session-DB error never fails a valid request).
- **NFR3**: role is read from JWT claims — no per-request DB lookup for role.

### 2.4 Role-gated authorization — `RequireRole`

Source: `src/baker/api/auth.py` (`RequireRole`).

`RequireRole("admin")` is a FastAPI dependency that inspects `request.state.auth_role` and raises `403` when the role doesn't match. Applied to **write** endpoints across 9 routers:

| Router | Gated writes |
|--------|--------------|
| `config.py` | config value create/update/delete |
| `products.py` | product create/update |
| `categories.py` | category create/update |
| `checklist.py` | checklist **template** create/update/delete |
| `product_price_chips.py` | price-chip writes |
| `product_attributes.py` | attribute writes |
| `product_attribute_options.py` | attribute-option writes |
| `reconciliations.py` | stock reconciliation writes |
| `audit_log.py` | `GET /api/audit-log` (admin-only read) |

GET endpoints on these routers remain **staff-accessible**. Staff have full access to daily operational endpoints (orders, events, knowledge, photos, catalog, cake_queue, receipts, printing, stock reads, daily checklist, health).

Grace-period nuance: when `AUTH_REQUIRED=false` and no token is present, `RequireRole` returns the actor as `"anonymous"` (not an empty string) so audit rows remain attributable.

---

## 3. Security Controls Applied

### 3.1 Password storage
- **bcrypt, cost factor 12** (`passlib` `CryptContext`, `bcrypt__rounds=12`) — NFR4. Applied in both the login path and the CLI/seed paths.

### 3.2 JWT
- **HS256**, secret from `BAKER_JWT_SECRET` env var (**≥256-bit** expected) — NFR5.
- Claims: `sub` (username), `role`, `exp` (7 days), `jti` (unique ID for revocation).
- If `BAKER_JWT_SECRET` is unset, the app generates an **ephemeral** `secrets.token_urlsafe(32)` and logs a warning (tokens invalidated on restart).
- **Startup validation (Mn-5):** `create_app()` raises `RuntimeError` and refuses to start when `AUTH_REQUIRED=true` **and** the secret is ephemeral — preventing an enforcement-mode deploy that silently invalidates tokens on every restart. Grace-period mode keeps the warning-only behavior.

### 3.3 Login rate limiting (FR18 / NFR7)
- In-memory, per-IP sliding window: **3 failed attempts within 60s → HTTP 429 for 5 minutes**.
- Uses `time.monotonic()`; a successful login clears the counter. State resets on server restart (acceptable for bakery use).

### 3.4 Brute-force account lockout (FR19 / NFR8)
- **5 consecutive failed attempts for a username → HTTP 423 for 30 minutes.**
- In-memory counter for fast checks; the lock expiry is persisted to `users.locked_until` so it **survives restarts** and **auto-expires**. Admin can clear early via `baker user unlock <username>`.
- The lockout `UPDATE` is committed before the `423` is raised (the `get_db()` context manager rolls back on exception, which would otherwise undo the lock).

### 3.5 Session management & token revocation (FR20 / FR21)
- Each login writes a row to the `sessions` table (jti, username, role, client_ip, device_model, app_version, os_version, logged_in_at, last_activity, revoked_at).
- **Force-logout** adds the session's `jti` to an in-memory **denylist** checked by `AuthMiddleware` (immediate invalidation) and stamps `revoked_at`.
- CLI: `baker session list` / `logout <user>` / `logout-all`.

### 3.6 Audit logging (FR22 / FR23)
- `record_audit_log(conn, ...)` writes to the `audit_log` table **inside the caller's transaction** (atomic with the audited mutation). `old_value`/`new_value` are JSON-serialized snapshots.
- Recorded on admin writes to config, products, categories, and checklist templates.
- `GET /api/audit-log` (admin-only) returns paginated, filterable results (`username`, `entity_type`, `date_from`, `date_to`). Date-only `date_to` values are expanded to `T23:59:59Z` so same-day entries are included (Mn-1).
- Indexed on `created_at`, `username`, `entity_type` (NFR9).

### 3.7 Data-integrity controls
- `users.role` has a DB-level `CHECK(role IN ('admin','staff'))` (Mn-3; migration v71 rebuilds existing tables to add it).
- `users.username` is UNIQUE; usernames normalized to lowercase at seed, at CLI create/lookup, and via migration v72 for existing rows (Vietnamese-safe Python `.lower()` with a UNIQUE-collision skip guard).

### 3.8 Credential-exposure hardening
- CLI `set-password` uses an interactive hidden prompt (`click.prompt(hide_input=True, confirmation_prompt=True)`); the plaintext `--password` flag was **removed** (MJ-1) to avoid `ps`/`/proc`/shell-history exposure.
- `user create` / `set-password --random` and the v68 seeding support a `--quiet` flag / `BAKER_SEED_QUIET` env toggle to suppress plaintext password output in CI/scripted contexts (MJ-2, SEC-1).

### 3.9 Network boundary
- CORS restricted to the single trusted origin `https://lily.tail10c2c6.ts.net` (air-gapped Tailscale network). Device headers (`x-device-model`, `x-app-version`, `x-os-version`) are allowed for telemetry/session metadata.

---

## 4. Data Model & Migrations

| Migration | Table / change |
|-----------|----------------|
| v68 | `users` (id, username UNIQUE, password_hash, role CHECK(admin/staff), active, locked_until, created_at) + seed 5 staff as users |
| v69 | `audit_log` (id, username, action, entity_type, entity_id, old_value, new_value, created_at) + indexes |
| v70 | `sessions` (id, jti UNIQUE, username, role, client_ip, device_model, app_version, os_version, logged_in_at, last_activity, revoked_at) + indexes |
| v71 | Add DB-level `CHECK(role IN ('admin','staff'))` on existing `users` tables |
| v72 | Lowercase existing `users.username` values |

> Note: the plan originally referenced v62–v64, but those slots were already occupied by other features. The actual slots used are **v68–v72** (next free slots per the migration guardrail).

---

## 5. Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `BAKER_AUTH_REQUIRED` | `false` | `false` = grace period (public access); `true` = JWT enforced on all non-public paths |
| `BAKER_JWT_SECRET` | *(ephemeral if unset)* | HS256 signing secret; ≥256-bit expected. Required when `AUTH_REQUIRED=true` |
| `BAKER_SEED_QUIET` | *(unset)* | When truthy, suppresses plaintext password output during v68 user seeding |

Rollout order (per requirements §11): deploy the Flutter update first, then set `BAKER_JWT_SECRET` and flip `BAKER_AUTH_REQUIRED=true`.

---

## 6. CLI Reference

```
baker user create <username> --role <admin|staff> [--quiet]
baker user set-password <username> [--random] [--quiet]
baker user set-role <username> <admin|staff>
baker user list
baker user deactivate <username>
baker user unlock <username>

baker session list
baker session logout <username>
baker session logout-all
```

`create` and `set-password --random` print a generated password to stdout for distribution (unless `--quiet`).

---

## 7. Flutter Client

| File | Responsibility |
|------|----------------|
| `app/lib/features/auth/login_screen.dart` | Username/password form, error mapping (401/423/429), loading + obscure-password toggle |
| `app/lib/features/auth/auth_service.dart` | Calls `POST /api/auth/login` |
| `app/lib/features/auth/auth_provider.dart` | Auth state (Riverpod); exposes `isAdmin` and authenticated username from claims |
| `app/lib/features/auth/jwt_claims.dart` | JWT claim decoding |
| `app/lib/features/auth/token_storage.dart` | SharedPreferences token persistence |
| `app/lib/data/api/api_client.dart` | Dio `AuthInterceptor` — attaches Bearer header, redirects to login on 401 |
| `app/lib/app.dart` + `shared/router/app_router.dart` | Auth gate + redirect guards (unauth → `/login`; staff away from admin routes) |
| `app/lib/shared/widgets/admin_guard.dart` | `AdminOnly` widget gating admin UI; `AdminAccessScreen` fallback for staff deep-links |
| `app/lib/features/audit_log/` | Admin-only audit log screen (filter panel: user/date/entity-type; paginated "load more") |
| `app/lib/providers/events_provider.dart` | `loggedByProvider` replaced with authenticated identity (FR17) |

Admin-only screens hidden from staff: Settings technical tab, Checklist Config, Category Management, Stock Reconciliation, Audit Log.

---

## 8. Testing & Verification

Backend (run per-file; the full suite is slow on Pi-class hosts):

```bash
python -m pytest tests/test_auth.py tests/test_rbac.py tests/test_audit_log_api.py \
                 tests/test_user_session_cli.py tests/test_db_schema.py -v
python -m ruff check src tests --select E9,F63,F7,F82
docker compose --profile prod config
```

Flutter:

```bash
cd app && flutter analyze && dart analyze && flutter test --coverage
```

Last recorded results: backend auth suites green, Flutter 658 passed / 1 skipped, lint + compose-config clean. The full UAT scenario list (TS-1…TS-20, edge cases) is in `agent-teams/requirements/artifacts/2026-07-04-bakery-auth-rbac-v2-uat.md`; the builder UAT review is at `agent-teams/builder/artifacts/2026-07-13-dg029-bakery-auth-rbac-uat-review.md`.

---

## 9. Known Limitations & Potential Enhancements

These are intentional trade-offs or deferred items — candidates for follow-up tickets.

### 9.1 In-memory state (single-process assumption)
- **Rate-limit counters, lockout counters, and the token denylist are in-memory** and reset on restart / are not shared across workers.
- **Impact:** If the backend is ever scaled to multiple workers behind a load balancer, revoked tokens could still be accepted by a worker whose denylist doesn't have the `jti`, and rate limits would be per-worker.
- **Enhancement:** Back the denylist + rate-limit state with a shared store (SQLite table or Redis) if the deployment topology changes. Currently single-process on the Pi, so acceptable.

### 9.2 No token refresh
- **7-day expiry, no refresh** — the user must re-login when the token expires.
- **Enhancement:** Add a refresh-token flow if session length becomes a UX pain point.

### 9.3 Binary role model
- Only `admin` vs `staff`; no fine-grained per-endpoint permission matrix.
- **Enhancement:** Introduce a permissions/claims model (or per-endpoint scopes) if more granular access is needed (e.g., a "cashier" role limited to POS).

### 9.4 No self-service password reset
- Password resets require admin CLI intervention (`baker user set-password`).
- **Enhancement:** Optional self-service reset (would need an email/OTP channel — currently out of scope for the air-gapped setup).

### 9.5 Audit log coverage & retention
- Recording currently covers config, products, categories, and checklist templates; **staff** create/update was listed in FR22 but staff writes are CLI-managed, so API-side staff audit is limited.
- No retention/archival policy — `audit_log` grows unbounded.
- **Enhancement:** Extend audit recording to any remaining admin-mutating routes as they are added; add a retention/rollup job.

### 9.6 Grace-period audit attribution
- During `AUTH_REQUIRED=false`, unauthenticated admin writes are recorded as `"anonymous"`.
- **Enhancement:** Once enforcement is on, these should not occur; consider a dashboard warning if any `anonymous` audit rows appear after enforcement day.

### 9.7 JWT secret operational safety
- Startup now refuses `AUTH_REQUIRED=true` + ephemeral secret, but there is no active check that the configured secret meets the 256-bit length target.
- **Enhancement:** Add a startup length/entropy assertion for `BAKER_JWT_SECRET`.

### 9.8 CORS / device-header trust
- Device headers are client-supplied and used for session metadata only (not for security decisions) — this is correct, but worth keeping in mind if they ever influence authorization.

### 9.9 No Flutter session-management UI
- Session list / force-logout is CLI-only by design.
- **Enhancement:** Add an admin session screen if remote logout from the app becomes desirable.

---

## 10. Review History

Two automated review cycles were run against the branch:

- **Cycle 1** (`2026-07-14-review-bakery-auth-rbac.md`): 0 Critical, 2 Major, 5 Minor — all resolved (MJ-1 CLI password flag, MJ-2 quiet flags, Mn-1 date filter, Mn-2 imports, Mn-3 role CHECK, Mn-4 grace actor, Mn-5 startup validation), plus a Sinh-requested lowercase-username change.
- **Cycle 2** (`2026-07-14-review-bakery-auth-rbac-rereview.md`): found SEC-1 (a `BAKER_SEED_QUIET` indentation bug introduced by the cycle-1 fix) — resolved; final re-review clean (0 findings).

Full orchestration record: `agent-teams/builder/artifacts/2026-07-13-dg029-bakery-auth-rbac-orchestration-report.md`.
