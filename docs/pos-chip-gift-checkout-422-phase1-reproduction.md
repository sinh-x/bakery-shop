# Phase 1 Reproduction Evidence: POS chip + gift checkout HTTP 422

Date: 2026-05-08
Branch: feature/pos-chip-gift-checkout-422
Ticket: DG-117

## Scope

- Reproduced the HTTP 422 path for POS checkout with a price-chip item plus a gift item.
- Captured exact request payload and server response detail.
- Verified likely root-cause path in backend validation/stock consumption.

## Reproduction Setup

Environment used for reproducible evidence:

- Local isolated API runtime via `TestClient` and temp SQLite DB (mirrors API behavior).
- Product `id=1` marked as `trung_bay=true`.
- Price chip created for product 1:
  - label: `POS-Nho`
  - price: `12000`
- Stock restocked for that chip option: quantity `1`.

## Checkout Payload Used

```json
{
  "customerName": "Khach POS",
  "source": "Tại tiệm - POS",
  "deliveryType": "pickup",
  "status": "delivered",
  "paymentMethod": "cash",
  "items": [
    {
      "productId": "1",
      "productName": "Bánh kem (POS-Nho)",
      "quantity": 2,
      "unitPrice": 12000,
      "priceChipId": 1
    },
    {
      "productName": "Dao nhua",
      "quantity": 1,
      "unitPrice": 1000,
      "isGift": true
    }
  ]
}
```

## Observed Response

- HTTP status: `422`
- Response body:

```json
{
  "detail": "Không đủ tồn kho"
}
```

## API/Code Path Evidence

- POS payload generation sends paid items with `productId` and `priceChipId`, and gift items with `isGift=true` and no `productId`:
  - `app/lib/features/pos/pos_checkout_screen.dart`
- Order create with `status=delivered` calls stock decrement:
  - `src/baker/api/orders.py` (`create_order` -> `_auto_decrement_stock`)
- Chip validation and chip-specific FIFO consumption path:
  - `src/baker/api/inventory_fifo.py`
  - `consume_fifo_items(...)` raises HTTP 422 detail `"Không đủ tồn kho"` when remaining quantity is insufficient.

## Root-Cause Hypothesis (Phase 2 input)

- The reproduced 422 is expected behavior when chip-specific available stock is lower than requested paid quantity.
- This specific response indicates inventory insufficiency, not request schema breakage and not gift-item stock decrement.
- Likely issue for user experience is that POS currently surfaces raw exception text (`Lỗi: $e`) instead of clean backend detail.

## Guardrails Confirmed During Investigation

- No `/api/orders` request-field removals or renames were made.
- No timeout changes were made (`Dio` timeout behavior untouched).
- No UI error behavior changes were implemented in this phase.
