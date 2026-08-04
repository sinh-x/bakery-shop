"""Migration v068: _migrate_v68_users_table (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

import os

def _migrate_v68_users_table(conn):
    """Create the ``users`` table and seed existing staff as users with random
    bcrypt-hashed passwords (DG-029 Phase 1, FR12/FR13).

    Each staff member in :data:`SEED_STAFF` is inserted as a user. Sinh (role
    "owner") becomes ``admin``; all others become ``staff``. A random password
    is generated for each user, bcrypt-hashed (cost factor 12), and the plain
    password is printed to stdout so the admin can distribute credentials.

    Starting DG-259 Phase 1, ``staff_id`` is set during user creation using
    case+diacritic-insensitive name matching against the ``staff`` table.
    Role overrides are applied per the approved seed mapping: Ân→admin,
    Ngân→staff, Phượng→admin, Sinh→admin, Tân→admin.

    Idempotent: re-running on a DB where users already exist skips seeding
    (INSERT OR IGNORE on the unique ``username``); printed passwords are only
    emitted on the first run when a row is actually inserted.
    """
    import secrets as _secrets

    from passlib.context import CryptContext

    from baker.config import BCRYPT_ROUNDS

    _pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto", bcrypt__rounds=BCRYPT_ROUNDS)

    _USER_ROLE_OVERRIDE = {
        "Ân": "admin",
        "Ngân": "staff",
        "Phượng": "admin",
        "Tân": "admin",
    }

    inserted: list[tuple[str, str, str]] = []  # (username, role, plain_password)

    for name, staff_role in SEED_STAFF:
        user_role = _USER_ROLE_OVERRIDE.get(name, _SEED_STAFF_ROLE_TO_USER_ROLE.get(staff_role, "staff"))
        # DG-029 follow-on: lowercase the system username (staff.name display
        # name is left unchanged — users.username is the login account name).
        # Python str.lower() is Unicode-aware and correct for Vietnamese
        # diacritics (Â→â, Ư→ư, Ầ→ầ, etc.).
        username = name.lower()
        existing = conn.execute(
            "SELECT id FROM users WHERE username = ?", (username,)
        ).fetchone()
        if existing:
            continue
        plain = _secrets.token_urlsafe(12)
        hashed = _pwd_ctx.hash(plain)
        cursor = conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES (?, ?, ?, 1)",
            (username, hashed, user_role),
        )
        # Look up staff_id by case+diacritic-insensitive name matching
        user_id = cursor.lastrowid
        staff_row = conn.execute(
            "SELECT id FROM staff WHERE name = ?", (name,)
        ).fetchone()
        if staff_row:
            conn.execute(
                "UPDATE users SET staff_id = ? WHERE id = ?",
                (int(staff_row[0]), user_id),
            )
        inserted.append((username, user_role, plain))

    if inserted:
        import sys

        # MJ-2 (DG-029 phase 5.6-c1): gate plaintext password printing behind
        # BAKER_SEED_QUIET so CI logs don't capture plaintext credentials.
        # When unset/empty the admin-distribution UX is preserved.
        seed_quiet = os.environ.get("BAKER_SEED_QUIET", "").strip().lower() in (
            "1", "true", "yes", "on",
        )
        if seed_quiet:
            print(
                "DG-029 users migration: seeded initial user accounts "
                f"({len(inserted)} users) — passwords suppressed (BAKER_SEED_QUIET=1)",
                file=sys.stdout,
            )
        else:
            print("=" * 60, file=sys.stdout)
            print("DG-029 users migration: seeded initial user accounts", file=sys.stdout)
            print("Distribute these temporary passwords to each user:", file=sys.stdout)
            print("-" * 60, file=sys.stdout)
            for username, role, plain in inserted:
                print(f"  {username} ({role}): {plain}", file=sys.stdout)
            print("=" * 60, file=sys.stdout)
