"""Timestamp utility module.

Provides timezone-aware timestamp generation and normalization so the rest of
the codebase avoids ad-hoc `datetime.now().strftime()` calls. The timezone is
configured via `baker.config.TIMEZONE` (read from `BAKER_TIMEZONE` env var,
defaulting to `Asia/Ho_Chi_Minh`).
"""

from __future__ import annotations

from datetime import datetime, timezone

from baker import config

__all__ = ["now_iso", "tz_offset", "normalize_timestamp"]

_TZ_SUFFIX_RE = __import__("re").compile(r"(Z|[+-]\d{2}:?\d{2})$")


def _localize(value: datetime) -> datetime:
    """Attach the configured timezone to a naive datetime, or convert an
    aware datetime into the configured timezone."""
    if value.tzinfo is None:
        return value.replace(tzinfo=config.TIMEZONE)
    return value.astimezone(config.TIMEZONE)


def tz_offset() -> str:
    """Return the current UTC offset string for the configured timezone.

    Example: `+07:00` for `Asia/Ho_Chi_Minh` / `Asia/Bangkok`.
    """
    offset = config.TIMEZONE.utcoffset(datetime.now(timezone.utc))
    if offset is None:
        return "+00:00"
    total_seconds = int(offset.total_seconds())
    sign = "+" if total_seconds >= 0 else "-"
    total_seconds = abs(total_seconds)
    hours, remainder = divmod(total_seconds, 3600)
    minutes = remainder // 60
    return f"{sign}{hours:02d}:{minutes:02d}"


def now_iso() -> str:
    """Return the current time as `YYYY-MM-DDTHH:MM:SS+HH:MM` in the
    configured timezone."""
    now = datetime.now(timezone.utc).astimezone(config.TIMEZONE)
    return now.strftime("%Y-%m-%dT%H:%M:%S") + tz_offset()


def normalize_timestamp(ts: str) -> str:
    """Normalize a timestamp string to the configured timezone offset.

    - Bare timestamps (no offset): assume they are local time in the configured
      timezone and append the offset.
    - UTC `Z` timestamps: convert to local time then append the offset.
    - Timestamps already carrying an offset: convert to the configured timezone
      and re-emit with the configured offset.
    """
    value = ts.strip()
    if not value:
        raise ValueError("timestamp không được để trống")

    match = _TZ_SUFFIX_RE.search(value)
    offset = tz_offset()

    if match is None:
        # Bare timestamp — treat as local time in configured timezone.
        parsed = datetime.fromisoformat(value).replace(tzinfo=config.TIMEZONE)
    else:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        parsed = parsed.astimezone(config.TIMEZONE)

    return parsed.strftime("%Y-%m-%dT%H:%M:%S") + offset