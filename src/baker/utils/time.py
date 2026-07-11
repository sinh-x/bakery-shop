"""UTC timestamp utility for the baker package.

Provides a single source of truth for UTC timestamp generation so that all
code paths produce ISO-8601 UTC strings with a trailing ``Z`` suffix
(e.g., ``2026-06-30T08:06:00Z``).

Traceability: DG-202 FR3, NFR2.
"""

from __future__ import annotations

from datetime import datetime, timezone

from baker.config import TIMEZONE


def now_utc() -> str:
    """Return the current UTC time as an ISO-8601 string with a ``Z`` suffix.

    Format: ``YYYY-MM-DDTHH:MM:SSZ`` (no microseconds, no offset).

    This replaces ad-hoc ``datetime.now().strftime()`` and
    ``datetime.now().isoformat()`` calls throughout the codebase.
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def utc_to_local(ts_str: str | None) -> str:
    """Convert a UTC ISO-8601 timestamp string to local time for display.

    Accepts ``YYYY-MM-DDTHH:MM:SSZ`` or ``YYYY-MM-DDTHH:MM:SS``.
    Returns ``HH:MM DD/MM/YYYY`` in the configured ``TIMEZONE``.
    Returns empty string for None/empty input.
    """
    if not ts_str:
        return ""
    try:
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