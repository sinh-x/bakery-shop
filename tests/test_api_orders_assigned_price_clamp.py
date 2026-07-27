"""Backend safety-net tests for the trưng bày markup price floor (DG-296
FR3/AC3 review-remediation).

The frontend clamps ``unitPrice`` to ``assignedPrice`` at every entry point
(POS chip picker, wizard Stage 1 editor, cart write-back). These tests verify
the backend defense-in-depth: when a client bypasses the frontend clamp and
submits ``unitPrice < assignedPrice``, the ``OrderItemIn`` /
``WorkItemCreate`` / ``WorkItemUpdate`` pydantic validators clamp
``unitPrice`` upward to ``assignedPrice`` so the stored row can never violate
the markup invariant. A warning is logged (not asserted here) so the
violation remains observable in production logs.

Evidence that motivated this remediation: order M52-T (#1708) in production
stored ``order_item #5206`` with ``unit_price=150,000`` and
``assigned_price=200,000`` — exactly the below-floor state these tests prove
can no longer happen.
"""

import pytest

from baker.api.orders import OrderItemIn

pytestmark = pytest.mark.critical


def test_order_item_in_clamps_unit_price_up_to_assigned_price():
    """FR3/AC3 backend safety net: ``unitPrice < assignedPrice`` is clamped
    upward to ``assignedPrice`` so the stored selling price cannot fall below
    the COGS anchor (matches the M52-T / order_item #5206 remediation)."""
    item = OrderItemIn(
        productName="Bánh kem trưng bày",
        quantity=1,
        unitPrice=150000.0,
        assignedPrice=200000.0,
    )
    assert item.unitPrice == 200000.0
    assert item.assignedPrice == 200000.0


def test_order_item_in_preserves_marked_up_unit_price():
    """Regression guard: a legitimate markup (``unitPrice > assignedPrice``)
    is preserved unchanged — the clamp only fires below the floor."""
    item = OrderItemIn(
        productName="Bánh kem trưng bày",
        quantity=1,
        unitPrice=350000.0,
        assignedPrice=300000.0,
    )
    assert item.unitPrice == 350000.0
    assert item.assignedPrice == 300000.0


def test_order_item_in_no_assigned_price_unchanged():
    """FR8 backward compatibility: items without ``assignedPrice`` keep the
    historical ``unitPrice`` (no clamp, no anchor)."""
    item = OrderItemIn(
        productName="Bánh mì",
        quantity=1,
        unitPrice=50000.0,
        assignedPrice=None,
    )
    assert item.unitPrice == 50000.0
    assert item.assignedPrice is None


def test_order_item_in_equal_prices_no_clamp():
    """Edge case: ``unitPrice == assignedPrice`` is not below floor — no
    clamp, no warning."""
    item = OrderItemIn(
        productName="Bánh kem trưng bày",
        quantity=1,
        unitPrice=200000.0,
        assignedPrice=200000.0,
    )
    assert item.unitPrice == 200000.0


def test_work_item_create_clamps_unit_price_up_to_assigned_price():
    """FR3/AC3 backend safety net at the work-item create path."""
    from baker.api.work_items import WorkItemCreate

    item = WorkItemCreate(
        productName="Bánh kem trưng bày",
        quantity=1,
        unitPrice=130000.0,
        assignedPrice=200000.0,
    )
    assert item.unitPrice == 200000.0
    assert item.assignedPrice == 200000.0


def test_work_item_update_clamps_unit_price_up_to_assigned_price():
    """FR3/AC3 backend safety net at the work-item update path: when both
    fields are supplied in the same PATCH, ``unitPrice`` is clamped upward."""
    from baker.api.work_items import WorkItemUpdate

    update = WorkItemUpdate(
        unitPrice=180000.0,
        assignedPrice=200000.0,
    )
    assert update.unitPrice == 200000.0
    assert update.assignedPrice == 200000.0
