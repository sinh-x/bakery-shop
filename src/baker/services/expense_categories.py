"""Shared expense-category aggregation helpers (DG-386 review Mn3, cycle 5).

The "resolve category/subcategory from event data + normalize legacy
subcategory-in-category rows + accumulate totals/sub_totals/uncategorized"
block was implemented three times (``api/reports/__init__.py`` expense
summary, ``services/cashflow.py`` supplier breakdown, and the
``expense-by-category`` CLI). This module provides a single
:func:`aggregate_categories` helper that all three call sites use so the
normalization and accumulation logic lives in one place.

The helper is intentionally pure: callers resolve the
``(category, subcategory, amount)`` triple for each row themselves
(because that resolution differs — expense events vs. settlement id
lookups vs. per-row DB queries), then hand the triples to
:func:`aggregate_categories` which applies the legacy normalization and
accumulates ``totals`` / ``sub_totals`` / ``uncategorized``.
"""

from __future__ import annotations

from typing import Iterable


def aggregate_categories(
    triples: Iterable[tuple[str | None, str | None, float]],
    parent_of: dict[str, str],
) -> tuple[dict[str, float], dict[str, dict[str, float]], float]:
    """Accumulate category/subcategory totals with legacy normalization.

    Iterates ``(category, subcategory, amount)`` triples and produces
    ``(totals, sub_totals, uncategorized)`` where:

    - ``totals[parent]`` — total for the parent category, including all
      subcategory amounts.
    - ``sub_totals[parent][subcategory]`` — subtotal for a subcategory
      under a parent.
    - ``uncategorized`` — sum of amounts whose category could not be
      resolved.

    Legacy normalization: when ``category`` is itself a subcategory name
    (present in ``parent_of``), it is normalized back to the parent so
    the amount lands in the right parent bucket and is recorded as a
    subcategory subtotal under that parent. This matches the original
    inline behavior at ``report.py:806-813`` /
    ``api/reports/__init__.py:764-781`` / ``cashflow.py:312-329``.

    A ``None`` (or empty) ``category`` routes the amount to
    ``uncategorized``. A non-empty ``subcategory`` is recorded under its
    parent only when ``category`` is not a legacy subcategory name (the
    legacy case already records the category-as-subcategory name).
    """
    totals: dict[str, float] = {}
    sub_totals: dict[str, dict[str, float]] = {}
    uncategorized = 0.0

    for category, subcategory, amount in triples:
        if not category:
            uncategorized += amount
            continue

        if category in parent_of:
            # Legacy normalization: the category field is actually a
            # subcategory name — normalize back to the parent so it lands
            # in the right bucket (matches report.py:806-813).
            parent = parent_of[category]
            sub_totals.setdefault(parent, {})
            sub_totals[parent][category] = (
                sub_totals[parent].get(category, 0.0) + amount
            )
            totals[parent] = totals.get(parent, 0.0) + amount
        else:
            totals[category] = totals.get(category, 0.0) + amount
            if subcategory:
                sub_totals.setdefault(category, {})
                sub_totals[category][subcategory] = (
                    sub_totals[category].get(subcategory, 0.0) + amount
                )

    return totals, sub_totals, uncategorized