"""UTC timestamp round-trip tests (DG-202 Phase 6 / AC8).

Verifies the "store UTC, display local" contract end-to-end:

1. A local wall-clock time (e.g. 12:00 +07:00) is converted to UTC
   (05:00Z) and submitted to the API.
2. The API stores it with a trailing ``Z`` suffix (no offset, no bare
   timestamp).
3. Reading the record back returns the UTC ``Z``-suffixed value.
4. Applying the configured server timezone (``baker.config.TIMEZONE``)
   converts the stored UTC instant back to the original local wall-clock
   time.

Also covers:
- ``now_utc()`` always emits a ``Z`` suffix (FR3).
- Date-only columns (``due_date``, ``checklist_date``,
  ``reconciliation_date``) are NOT touched by the UTC standardization and
  carry no ``Z`` suffix (FR8 / AC9).
- Backward compatibility: a bare timestamp submitted to the events API is
  treated as UTC and gets a ``Z`` suffix appended (NFR4).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from baker.config import TIMEZONE
from baker.utils.time import now_utc


# --- now_utc() (FR3) ------------------------------------------------------


def test_now_utc_returns_z_suffix():
    """``now_utc()`` always produces a trailing ``Z`` (FR3)."""
    ts = now_utc()
    assert ts.endswith("Z")
    # No offset suffix other than the trailing Z.
    assert "+" not in ts
    # Format is YYYY-MM-DDTHH:MM:SSZ (no microseconds).
    assert len(ts) == len("2026-06-30T08:06:00Z")


def test_now_utc_is_utc():
    """``now_utc()`` matches the current UTC time within a small tolerance."""
    before = datetime.now(timezone.utc)
    ts = now_utc()
    after = datetime.now(timezone.utc)
    parsed = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    assert before - timedelta(seconds=5) <= parsed <= after + timedelta(seconds=5)


def test_now_utc_is_idempotent_in_format():
    """Two calls return the same fixed-width format (NFR2 — negligible overhead)."""
    a = now_utc()
    b = now_utc()
    assert len(a) == len(b)


# --- Round-trip: local -> UTC Z -> stored -> read -> local display (AC8) --


def test_utc_z_roundtrip_preserves_local_wall_clock(api_client):
    """AC8: a local instant stored as UTC ``Z`` reads back as the same local
    wall-clock time once the server timezone offset is applied.

    Local 12:00 (+07:00) -> UTC 05:00Z -> stored -> read 05:00Z -> +07:00 -> 12:00.
    """
    local_hour = 12
    local_minute = 30
    # Convert the local instant to UTC.
    local = datetime(2026, 6, 30, local_hour, local_minute, tzinfo=TIMEZONE)
    utc = local.astimezone(timezone.utc)
    utc_z = utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    assert utc_z == "2026-06-30T05:30:00Z"

    # Submit the UTC Z-suffixed timestamp to the API.
    resp = api_client.post("/api/events", json={
        "summary": "Round-trip event",
        "type": "note",
        "timestamp": utc_z,
    })
    assert resp.status_code == 201
    stored = resp.json()["timestamp"]
    # Stored value must be UTC Z-suffixed (FR1).
    assert stored == utc_z
    assert stored.endswith("Z")

    # Read it back via GET.
    listed = api_client.get("/api/events", params={"search": "Round-trip event"})
    assert listed.status_code == 200
    row = listed.json()[0]
    assert row["timestamp"] == utc_z

    # Convert the stored UTC instant back to the server's local wall-clock
    # time — this is what the Flutter client does for display (FR5/AC4).
    parsed_utc = datetime.strptime(row["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(
        tzinfo=timezone.utc
    )
    displayed = parsed_utc.astimezone(TIMEZONE)
    assert displayed.hour == local_hour
    assert displayed.minute == local_minute
    assert displayed.tzinfo is not None


def test_bare_timestamp_treated_as_utc_and_z_suffixed(api_client):
    """NFR4: a bare timestamp submitted to the API is treated as UTC and gets a
    ``Z`` suffix appended on store (backward-compatible)."""
    bare = "2026-05-23T19:57:00"
    resp = api_client.post("/api/events", json={
        "summary": "Bare input event",
        "type": "note",
        "timestamp": bare,
    })
    assert resp.status_code == 201
    assert resp.json()["timestamp"] == f"{bare}Z"


def test_event_created_without_timestamp_gets_utc_z_default(api_client):
    """FR1: when no timestamp is supplied, the server stores the current UTC
    time with a ``Z`` suffix."""
    resp = api_client.post("/api/events", json={"summary": "Default ts event"})
    assert resp.status_code == 201
    ts = resp.json()["timestamp"]
    assert ts.endswith("Z")
    # Must parse as a valid UTC instant.
    datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")


# --- Date-only columns remain unchanged (FR8 / AC9) -----------------------


def test_due_date_has_no_z_suffix(api_client):
    """FR8/AC9: ``due_date`` is a date-only column and must not receive a ``Z``
    suffix or any timezone conversion."""
    resp = api_client.post("/api/orders", json={
        "customerName": "Date-only check",
        "dueDate": "2026-03-20",
        "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 200000, "productId": "BKS-16"}],
    })
    assert resp.status_code == 201
    body = resp.json()
    assert body["dueDate"] == "2026-03-20"
    assert "Z" not in body["dueDate"]


def test_reconciliation_date_has_no_z_suffix(api_client):
    """FR8/AC9: ``reconciliation_date`` is date-only and carries no ``Z``."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO reconciliation_sessions "
            "(id, reconciliation_date, staff_name) "
            "VALUES (999001, '2026-03-25', 'sinh')"
        )
        conn.commit()
        row = conn.execute(
            "SELECT reconciliation_date FROM reconciliation_sessions WHERE id=999001"
        ).fetchone()
        conn.execute("DELETE FROM reconciliation_sessions WHERE id=999001")
        conn.commit()
    assert row["reconciliation_date"] == "2026-03-25"
    assert "Z" not in row["reconciliation_date"]


def test_checklist_date_has_no_z_suffix(api_client):
    """FR8/AC9: ``checklist_date`` is date-only and carries no ``Z``."""
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute(
            "INSERT INTO checklist_entries (template_id, checklist_date, completed) "
            "VALUES (1, '2026-03-25', 0)"
        )
        conn.commit()
        row = conn.execute(
            "SELECT checklist_date FROM checklist_entries "
            "WHERE checklist_date='2026-03-25' LIMIT 1"
        ).fetchone()
        conn.execute("DELETE FROM checklist_entries WHERE checklist_date='2026-03-25'")
        conn.commit()
    assert row["checklist_date"] == "2026-03-25"
    assert "Z" not in row["checklist_date"]