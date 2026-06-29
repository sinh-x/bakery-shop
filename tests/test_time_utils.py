"""Round-trip tests for `baker.utils.time` timestamp utilities (DG-174 Phase 5).

Covers AC9 (all tests pass) and AC10 (timestamp round-trip correctness):
- `now_iso()` always emits the configured timezone offset suffix.
- `normalize_timestamp()` handles bare, UTC `Z`, and already-offset values.
- `tz_offset()` reflects the configured timezone.
- `GET /api/config` exposes timezone + offset to clients.
- Full API round-trip: create event, read it back, verify the stored timestamp
  carries `+07:00` and round-trips back to the original local time.
"""

from __future__ import annotations

import importlib

import pytest

from baker import config
from baker.utils import time as time_utils


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _set_timezone(monkeypatch: pytest.MonkeyPatch, tz_name: str) -> None:
    """Reconfigure `baker.config` (and refresh `baker.utils.time`) to a TZ."""
    monkeypatch.setenv("BAKER_TIMEZONE", tz_name)
    config.reload()
    importlib.reload(time_utils)


# ---------------------------------------------------------------------------
# now_iso
# ---------------------------------------------------------------------------


class TestNowIso:
    def test_returns_plus_07_00_suffix(self):
        ts = time_utils.now_iso()
        assert ts.endswith("+07:00"), f"expected +07:00 suffix, got {ts!r}"
        assert len(ts) == 25, f"expected YYYY-MM-DDTHH:MM:SS+07:00 (25 chars), got {ts!r}"

    def test_format_is_iso8601(self):
        ts = time_utils.now_iso()
        # YYYY-MM-DDTHH:MM:SS+07:00
        assert ts[4] == "-" and ts[7] == "-" and ts[10] == "T"
        assert ts[13] == ":" and ts[16] == ":" and ts[19] == "+"

    def test_asia_bangkok_produces_plus_07_00(self, monkeypatch):
        _set_timezone(monkeypatch, "Asia/Bangkok")
        try:
            ts = time_utils.now_iso()
            assert ts.endswith("+07:00"), f"Asia/Bangkok should be +07:00, got {ts!r}"
        finally:
            # Restore default timezone for downstream tests.
            monkeypatch.delenv("BAKER_TIMEZONE", raising=False)
            config.reload()
            importlib.reload(time_utils)


# ---------------------------------------------------------------------------
# tz_offset
# ---------------------------------------------------------------------------


class TestTzOffset:
    def test_default_offset_is_plus_07_00(self):
        assert time_utils.tz_offset() == "+07:00"

    def test_asia_bangkok_offset(self, monkeypatch):
        _set_timezone(monkeypatch, "Asia/Bangkok")
        try:
            assert time_utils.tz_offset() == "+07:00"
        finally:
            monkeypatch.delenv("BAKER_TIMEZONE", raising=False)
            config.reload()
            importlib.reload(time_utils)

    def test_utc_offset(self, monkeypatch):
        _set_timezone(monkeypatch, "UTC")
        try:
            assert time_utils.tz_offset() == "+00:00"
        finally:
            monkeypatch.delenv("BAKER_TIMEZONE", raising=False)
            config.reload()
            importlib.reload(time_utils)


# ---------------------------------------------------------------------------
# normalize_timestamp
# ---------------------------------------------------------------------------


class TestNormalizeTimestamp:
    def test_bare_timestamp_appends_offset(self):
        out = time_utils.normalize_timestamp("2026-06-29T12:55:02")
        assert out == "2026-06-29T12:55:02+07:00", f"bare ts should gain +07:00, got {out!r}"

    def test_z_suffix_converts_to_local_plus_offset(self):
        # UTC 05:55:00 -> local 12:55:00+07:00
        out = time_utils.normalize_timestamp("2026-06-29T05:55:00Z")
        assert out == "2026-06-29T12:55:00+07:00", f"Z ts should convert to local, got {out!r}"

    def test_z_suffix_with_milliseconds_converts(self):
        out = time_utils.normalize_timestamp("2026-06-29T05:55:00.000Z")
        assert out == "2026-06-29T12:55:00+07:00", f"Z ms ts should convert, got {out!r}"

    def test_already_correct_offset_is_noop(self):
        out = time_utils.normalize_timestamp("2026-06-29T12:55:02+07:00")
        assert out == "2026-06-29T12:55:02+07:00", f"already-offset ts should be no-op, got {out!r}"

    def test_other_offset_converts_to_configured(self):
        # -05:00 10:00 -> UTC 15:00 -> local 22:00+07:00
        out = time_utils.normalize_timestamp("2026-05-23T10:00:00-05:00")
        assert out == "2026-05-23T22:00:00+07:00", f"foreign offset should convert, got {out!r}"

    def test_plus_00_00_converts_to_local(self):
        out = time_utils.normalize_timestamp("2026-06-29T05:55:00+00:00")
        assert out == "2026-06-29T12:55:00+07:00", f"+00:00 should convert to local, got {out!r}"

    def test_empty_string_raises(self):
        with pytest.raises(ValueError):
            time_utils.normalize_timestamp("")

    def test_whitespace_only_raises(self):
        with pytest.raises(ValueError):
            time_utils.normalize_timestamp("   ")

    def test_round_trip_bare_then_normalize_idempotent(self):
        """Normalizing an already-normalized timestamp must be a no-op."""
        once = time_utils.normalize_timestamp("2026-06-29T12:55:02")
        twice = time_utils.normalize_timestamp(once)
        assert once == twice, f"normalize should be idempotent, got {once!r} then {twice!r}"


# ---------------------------------------------------------------------------
# GET /api/config
# ---------------------------------------------------------------------------


class TestApiConfigTimezone:
    def test_config_returns_timezone_and_offset(self, api_client):
        resp = api_client.get("/api/config")
        assert resp.status_code == 200
        data = resp.json()
        assert data["timezone"] == "Asia/Ho_Chi_Minh"
        assert data["timezone_offset"] == "+07:00"


# ---------------------------------------------------------------------------
# Full API round-trip: create event -> read back -> verify +07:00 suffix
# ---------------------------------------------------------------------------


class TestEventTimestampRoundTrip:
    def test_create_event_without_timestamp_uses_plus_07_00_default(self, api_client):
        """When no timestamp is supplied, the DB DEFAULT emits +07:00."""
        resp = api_client.post("/api/events", json={"summary": "RT test no ts"})
        assert resp.status_code == 201
        ev = resp.json()
        ts = ev["timestamp"]
        assert ts is not None
        assert ts.endswith("+07:00"), f"auto timestamp should carry +07:00, got {ts!r}"

    def test_create_event_with_bare_timestamp_normalizes_to_plus_07_00(self, api_client):
        resp = api_client.post(
            "/api/events",
            json={"summary": "RT bare ts", "timestamp": "2026-06-29T12:55:02"},
        )
        assert resp.status_code == 201
        ev = resp.json()
        assert ev["timestamp"] == "2026-06-29T12:55:02+07:00"

    def test_create_event_with_z_timestamp_converts_to_local_plus_07_00(self, api_client):
        resp = api_client.post(
            "/api/events",
            json={"summary": "RT z ts", "timestamp": "2026-06-29T05:55:00Z"},
        )
        assert resp.status_code == 201
        ev = resp.json()
        assert ev["timestamp"] == "2026-06-29T12:55:00+07:00"

    def test_create_event_with_plus_07_00_preserved(self, api_client):
        resp = api_client.post(
            "/api/events",
            json={
                "summary": "RT offset ts",
                "timestamp": "2026-06-29T12:55:02+07:00",
            },
        )
        assert resp.status_code == 201
        ev = resp.json()
        assert ev["timestamp"] == "2026-06-29T12:55:02+07:00"

    def test_read_back_event_timestamp_carries_offset(self, api_client):
        """Create then GET by id — the read-back timestamp must keep +07:00."""
        create = api_client.post(
            "/api/events",
            json={"summary": "RT readback", "timestamp": "2026-06-29T09:30:00"},
        )
        assert create.status_code == 201
        event_id = create.json()["id"]
        stored_ts = create.json()["timestamp"]

        detail = api_client.get(f"/api/events/{event_id}")
        assert detail.status_code == 200
        assert detail.json()["timestamp"] == stored_ts
        assert detail.json()["timestamp"].endswith("+07:00")

    def test_list_events_timestamps_carry_offset(self, api_client):
        """Listing events must return +07:00-suffixed timestamps."""
        api_client.post(
            "/api/events",
            json={"summary": "RT list", "timestamp": "2026-06-29T08:00:00"},
        )
        resp = api_client.get("/api/events", params={"limit": 50})
        assert resp.status_code == 200
        events = resp.json()
        assert len(events) > 0
        for ev in events:
            ts = ev.get("timestamp")
            if ts:
                assert ts.endswith("+07:00"), f"list ts should carry +07:00, got {ts!r}"

    def test_round_trip_local_time_preserved(self, api_client):
        """AC10: created local time == displayed local time after round-trip.

        Send `12:55:02` (bare, local), the API normalizes to `12:55:02+07:00`,
        and reading it back must yield the same wall-clock local time.
        """
        local_input = "2026-06-29T12:55:02"
        resp = api_client.post(
            "/api/events",
            json={"summary": "RT local preserve", "timestamp": local_input},
        )
        assert resp.status_code == 201
        stored = resp.json()["timestamp"]
        # Stored value carries the offset.
        assert stored == f"{local_input}+07:00"
        # The local-time component (before the offset) must be unchanged.
        assert stored[: len(local_input)] == local_input