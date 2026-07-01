"""UTC timestamp utility for the baker package.

Provides a single source of truth for UTC timestamp generation so that all
code paths produce ISO-8601 UTC strings with a trailing ``Z`` suffix
(e.g., ``2026-06-30T08:06:00Z``).

Traceability: DG-202 FR3, NFR2.
"""

from __future__ import annotations

from datetime import datetime, timezone


def now_utc() -> str:
    """Return the current UTC time as an ISO-8601 string with a ``Z`` suffix.

    Format: ``YYYY-MM-DDTHH:MM:SSZ`` (no microseconds, no offset).

    This replaces ad-hoc ``datetime.now().strftime()`` and
    ``datetime.now().isoformat()`` calls throughout the codebase.
    """
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")