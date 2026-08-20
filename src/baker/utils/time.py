"""UTC timestamp utility for the baker package.

Provides a single source of truth for UTC timestamp generation so that all
code paths produce ISO-8601 UTC strings with a trailing ``Z`` suffix
(e.g., ``2026-06-30T08:06:00Z``).

Traceability: DG-202 FR3, NFR2.
"""

from __future__ import annotations

import re
from datetime import datetime, timezone

from baker.config import TIMEZONE


_TZ_RE = re.compile(r"(Z|[+-]\d{2}:?\d{2})$")


def now_utc() -> str:
    """Return the current UTC time as an ISO-8601 string with a ``Z`` suffix.

    Format: ``YYYY-MM-DDTHH:MM:SSZ`` (no microseconds, no offset).

    This replaces ad-hoc ``datetime.now().strftime()`` and
    ``datetime.now().isoformat()`` calls throughout the codebase.
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def utc_to_local(ts_str: str | None) -> str:
    """Convert a UTC ISO-8601 timestamp string to local time for display.

    Accepts ``YYYY-MM-DDTHH:MM:SSZ`` / ``YYYY-MM-DDTHH:MM:SS`` (full
    timestamp) or ``YYYY-MM-DD`` (date-only, backward compat).
    Returns ``HH:MM DD/MM/YYYY`` for full timestamps or ``DD/MM/YYYY``
    for date-only strings, in the configured ``TIMEZONE``.
    Returns empty string for None/empty input.
    """
    if not ts_str:
        return ""
    try:
        if "T" not in ts_str and ":" not in ts_str:
            dt = datetime.strptime(ts_str, "%Y-%m-%d")
            return dt.strftime("%d/%m/%Y")
        dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        local_dt = dt.astimezone(TIMEZONE)
        return local_dt.strftime("%H:%M %d/%m/%Y")
    except (ValueError, TypeError):
        return ts_str


class InvalidEffectiveFrom(ValueError):
    """Raised when an ``effective_from`` string cannot be parsed.

    Callers map this to their own error type (e.g. ``HTTPException``,
    ``click.BadParameter``). The original input is available on the
    ``input`` attribute for message formatting.
    """

    def __init__(self, message: str, *, input: str | None = None) -> None:
        super().__init__(message)
        self.input = input


def parse_effective_from(date_str: str | None) -> datetime:
    """Parse an ``effective_from`` string into a UTC-naive ``datetime``.

    Accepts ``YYYY-MM-DD`` (treated as start-of-day) or a full ISO-8601
    string (trailing ``Z`` accepted). Returns ``None``-equivalent for
    empty/``None`` input by calling :class:`InvalidEffectiveFrom` only on
    malformed values — callers should call :func:`now_utc` themselves when
    the input is empty.

    Args:
        date_str: ``YYYY-MM-DD`` or ISO-8601 timestamp, or ``None``/empty.

    Returns:
        Parsed ``datetime`` (naive, in the source's timezone).

    Raises:
        InvalidEffectiveFrom: When the string cannot be parsed as either
            ``YYYY-MM-DD`` or ISO-8601.

    Traceability: DG-208 review finding CQ-1 — shared parser extracted from
    the duplicated ``_normalize_effective_from`` helpers in the API and CLI.
    """
    if date_str is None or date_str == "":
        return None  # type: ignore[return-value]
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        pass
    try:
        return datetime.fromisoformat(date_str.replace("Z", "+00:00"))
    except ValueError as exc:
        raise InvalidEffectiveFrom(
            f"effective_from phải có dạng YYYY-MM-DD (nhận được '{date_str}')",
            input=date_str,
        ) from exc


def format_effective_from(date_str: str | None) -> str:
    """Parse and format ``effective_from`` into the comparable UTC form.

    Returns :func:`now_utc` for empty/``None`` input (the documented
    "effective now" behaviour). For non-empty input the parsed datetime is
    rendered as ``YYYY-MM-DDTHH:MM:SSZ``.

    Raises :class:`InvalidEffectiveFrom` on malformed input — callers
    should catch and convert to their preferred error type.
    """
    if date_str is None or date_str == "":
        return now_utc()
    parsed = parse_effective_from(date_str)
    return parsed.strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_timestamp(raw: str | None, *, empty_error: str | None = None) -> str | None:
    """Normalize an ISO-8601 timestamp to UTC ``Z``-suffixed form.

    Accepts bare timestamps (treated as UTC), ``Z``-suffixed, or offset
    timestamps (e.g. ``+07:00``) and returns ``YYYY-MM-DDTHH:MM:SSZ`` (no
    fractional seconds) or with fractional seconds preserved when present.

    Inputs MUST be a full ISO-8601 datetime: a ``T`` separator and a
    complete time component (``HH:MM:SS``). Date-only (``"2026-07-01"``)
    and short-time (``"2026-07-01T09:15"``) inputs are rejected so the
    canonical ``YYYY-MM-DDTHH:MM:SSZ`` invariant is preserved
    (review-auto cycle 1 CQ-2).

    Args:
        raw: The raw timestamp string, or ``None``/empty.
        empty_error: Optional detail message used when ``raw`` is empty
            (``None`` → returns ``None`` silently; non-``None`` raises
            :class:`ValueError`). When ``raw`` is ``None``, returns ``None``.

    Returns:
        The normalized UTC ``Z``-suffixed timestamp, or ``None`` when
        ``raw`` is ``None``.

    Raises:
        ValueError: When ``raw`` is an empty/whitespace string and
            ``empty_error`` is provided, when the value cannot be
            parsed as ISO-8601, or when it is not a full datetime
            (missing ``T`` separator or seconds component). Callers
            map these to their preferred error type (e.g.
            :class:`fastapi.HTTPException`).

    Traceability: DG-202 FR1, DG-415 FR3/NFR1 — shared helper extracted
        from the duplicated ``_normalize_timestamp`` in ``events.py`` so the
        payment-transaction API can reuse the same normalization semantics.
    """
    if raw is None:
        return None
    value = raw.strip()
    if not value:
        if empty_error is not None:
            raise ValueError(empty_error)
        return None
    # review-auto cycle 1 CQ-2: reject date-only / short-time inputs so the
    # canonical ``YYYY-MM-DDTHH:MM:SSZ`` invariant is preserved. Require a
    # ``T`` separator and a complete ``HH:MM:SS`` time component.
    if "T" not in value:
        raise ValueError("timestamp phải có dạng YYYY-MM-DDTHH:MM:SSZ")
    time_part = re.split(r"[Z+\-]", value.split("T", 1)[1], maxsplit=1)[0]
    if len(time_part.split(":")) < 3:
        raise ValueError("timestamp phải có đủ giây (HH:MM:SS)")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("timestamp không đúng định dạng ISO") from exc
    # Bare (no timezone) and Z/offset timestamps are all normalized through
    # the parsed datetime object so the output is always canonical
    # ``YYYY-MM-DDTHH:MM:SSZ`` (no string concat that could leave short
    # components). Treat bare timestamps as UTC (DG-202 FR1).
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    utc_dt = parsed.astimezone(timezone.utc)
    if utc_dt.microsecond:
        return utc_dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{utc_dt.microsecond:06d}Z"
    return utc_dt.strftime("%Y-%m-%dT%H:%M:%SZ")