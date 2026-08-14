"""Shared date-bound and date-validation helpers for the reporting API.

Extracted from ``baker.api.reports`` (DG-386 review Mn1, cycle 5) so the
date helpers are reusable across the per-domain report router modules.
Behavior is identical to the prior inline implementation — only the
module location changed.
"""

import calendar
from datetime import datetime, timedelta
from typing import Optional

from fastapi import HTTPException

from baker.utils.time import now_utc

# POS source label — orders with empty due_date are matched by created_at.
_POS_SOURCE = "Tại tiệm - POS"

# Reconciliation source label — same fallback scope as POS for NULL due_date
# (DG-384 Phase 2: include reconciliation orders in today-summary date filter).
_RECONCILIATION_SOURCE = "reconciliation"

# Sources that fall back to created_at when due_date is NULL/empty.
_FALLBACK_SOURCES = (_POS_SOURCE, _RECONCILIATION_SOURCE)


def _day_bounds(date_str: str) -> tuple[str, str]:
    """Return (start, next_day_start) timestamps for string-range filtering."""
    day = datetime.strptime(date_str, "%Y-%m-%d")
    next_day = day + timedelta(days=1)
    return (
        f"{date_str}T00:00:00",
        next_day.strftime("%Y-%m-%dT00:00:00"),
    )


def _period_bounds(period: str, date_str: str) -> tuple[str, str, str, str]:
    """Return (start_date, end_date, start_ts, next_day_ts) for a period.

    - ``day``: the single day containing ``date_str`` (start == end ==
      ``date_str``). Mirrors [_day_bounds] so the day tab can reuse the
      period endpoints without a separate code path.
    - ``week``: Monday–Sunday of the week containing ``date_str``
      (Monday-anchored, per FR1).
    - ``month``: 1st day through last day of the month containing
      ``date_str``.

    The ``start_ts`` / ``next_day_ts`` pair mirrors ``_day_bounds`` so the
    same ``>= start_ts AND < next_day_ts`` journal-entry filter works for
    multi-day ranges.
    """
    ref = datetime.strptime(date_str, "%Y-%m-%d")
    if period == "day":
        start = ref
        end = ref
    elif period == "week":
        # weekday(): Mon=0 .. Sun=6 — subtract to reach this week's Monday.
        start = ref - timedelta(days=ref.weekday())
        end = start + timedelta(days=6)
    elif period == "month":
        start = ref.replace(day=1)
        last_day = calendar.monthrange(ref.year, ref.month)[1]
        end = ref.replace(day=last_day)
    else:
        raise HTTPException(
            status_code=422,
            detail="period phải là 'day', 'week' hoặc 'month'",
        )
    start_str = start.strftime("%Y-%m-%d")
    end_str = end.strftime("%Y-%m-%d")
    next_day = end + timedelta(days=1)
    return (
        start_str,
        end_str,
        f"{start_str}T00:00:00",
        next_day.strftime("%Y-%m-%dT00:00:00"),
    )


def _resolve_date_param(date: Optional[str]) -> str:
    """Resolve the optional ``date`` query parameter to a YYYY-MM-DD string.

    Defaults to today's UTC date when ``date`` is ``None``. Raises a 422
    with the canonical Vietnamese error message when the supplied value
    is not a valid ``YYYY-MM-DD`` calendar date.
    """
    if date is None:
        return now_utc()[:10]
    try:
        datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(
            status_code=422,
            detail="date phải có định dạng YYYY-MM-DD",
        )
    return date