# DG-148 Phase 1 AppBar Inventory

Date: 2026-05-20
Branch: `feature/pos-appbar-menu-stock-filter`

## Scope

- Target: `app/lib/features/**`
- Rule baseline: max 3 visible AppBar actions (1 overflow + up to 2 direct local actions)
- Excludes: dialog action rows and non-AppBar action areas

## Screens exceeding direct-action cap

1. `app/lib/features/pos/pos_screen.dart`
   - Current visible actions: refresh, stock reconciliation, reconciliation history, order history, stock screen
   - Local direct candidate: refresh
   - Shared/secondary actions to preserve in overflow (Phase 2):
     - `/stock/reconciliation`
     - `/stock/reconciliation/history`
     - `/orders/history`
     - `/stock`

2. `app/lib/features/orders/order_list_screen.dart`
   - Current visible actions: refresh, order history, view toggle, settings
   - Local direct candidates: refresh, view toggle
   - Shared/secondary actions to preserve in overflow (Phase 2):
     - `/orders/history`
     - `/settings`

3. `app/lib/features/products/product_catalog_screen.dart`
   - Current visible actions: refresh, manage categories, settings, browse catalog photos
   - Local direct candidate: refresh
   - Shared/secondary actions to preserve in overflow (Phase 2):
     - `/categories/manage`
     - `/settings`
     - `/products/browse`

4. `app/lib/features/products/catalog_browse_screen.dart`
   - Current visible actions (selection mode): select all, share, download, cancel
   - Local direct candidates: select all, cancel
   - Shared/secondary actions to preserve in overflow (Phase 2):
     - `_onBulkShare`
     - `_onBulkDownload`

## Inventory notes

- Repeated overflow conversion patterns appear in at least three screens (`pos`, `orders`, `products`).
- A lightweight shared helper is justified in Phase 2 if action wiring remains repetitive after first conversion.
- Existing mixed-label hotspots identified for Phase 2 normalization:
  - `app/lib/features/pos/pos_screen.dart` had inline `Kho hàng` tooltip (moved to VN constant in this phase).
  - `app/lib/features/orders/order_list_screen.dart` view-mode tooltips are inline (`Kanban`, `Danh sách`).

## Label foundation added in Phase 1

Added VN constants in `app/lib/shared/widgets/vietnamese_labels.dart` for overflow menu labels and future POS stock switch label:

- `VN.moreActions`
- `VN.openSettings`
- `VN.openStock`
- `VN.openOrderHistory`
- `VN.openStockReconciliation`
- `VN.openStockReconciliationHistory`
- `VN.openCategoryManagement`
- `VN.openCatalogBrowse`
- `VN.switchToKanbanView`
- `VN.switchToListView`
- `VN.showOutOfStockProducts`
