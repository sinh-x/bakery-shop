# Code Quality Audit Report: Bakery Shop Flutter App

> Date: 2026-05-09
> Scope: God file audit of non-generated Dart files under `app/lib/`
> Files scanned: 120 non-generated `.dart` files (30,479 total lines)
> Severity thresholds: High >500, Medium 300-500, Low 200-300

## Summary

| Severity | Count | Total Lines | % of All Lines |
|----------|-------|-------------|----------------|
| High (>500) | 16 | 16,873 | 55.4% |
| Medium (300-500) | 22 | 8,277 | 27.2% |
| Low (200-300) | 8 | 2,039 | 6.7% |
| **Audited** | **46** | **27,189** | **89.2%** |

> 46 of 120 files (38.3%) are at least 200 lines. 16 files exceed 500 lines and are High severity.

## God Files: High Severity (>500 lines)

| # | File | Lines | Widget Classes | Top-Level Funcs | Severity | Recommendation |
|---|------|-------|----------------|-----------------|----------|----------------|
| 1 | `features/orders/order_detail_screen.dart` | 2,557 | 18 | 2 | High | Break into per-section screens or extract inner widget classes to `widgets/`. Create `payment_section.dart`, `work_item_section.dart`, `print_dialogs.dart`, `info_section.dart`. |
| 2 | `features/products/product_form_screen.dart` | 1,831 | 5 | 0 | High | Extract form sections (basic info, attributes, catalog integration, pricing) into `product_form/widgets/`. Split enum attribute handling into dedicated widget. |
| 3 | `features/orders/order_edit_screen.dart` | 1,389 | 6 | 0 | High | Extract work-item section and extras management into dedicated widgets. Separate form validation logic to a service/provider. |
| 4 | `features/stock/stock_reconciliation_screen.dart` | 1,024 | 8 | 0 | High | Extract reconciliation row widget, diff display, and count input components. Move scan-row logic into per-row widgets. |
| 5 | `features/orders/cake_detail_screen.dart` | 943 | 4 | 1 | High | Split into info section, packing section, and attribute display. Extract attribute list into reusable widget. |
| 6 | `features/orders/order_create_screen.dart` | 938 | 3 | 0 | High | Extract customer form section, item picker section, extras section. Widget count is 3 — triggering extraction threshold. |
| 7 | `shared/widgets/vietnamese_labels.dart` | 790 | 0 | 6 | High | Split by domain: `labels/orders.dart`, `labels/products.dart`, `labels/shared.dart`, `labels/checklist.dart`, `labels/events.dart`. Phase migration per §FR-6. |
| 8 | `features/orders/order_list_screen.dart` | 744 | 5 | 0 | High | Extract filter bar, search bar, list tile widget, empty state, and loading indicator to separate files. |
| 9 | `data/providers/reconciliation_provider.dart` | 651 | 0 | 2 | High | Split manual state class into freezed model. Extract reconciliation math helpers to `reconciliation_math.dart`. |
| 10 | `features/settings/settings_screen.dart` | 618 | 5 | 0 | High | Extract each settings section to its own widget file under `settings/widgets/`. |
| 11 | `features/orders/cake_queue_screen.dart` | 618 | 4 | 0 | High | Extract queue list tile, time slot picker, and summary bar widgets. |
| 12 | `features/orders/widgets/expandable_item_card.dart` | 616 | 2 | 0 | High | Split into expandable card shell, collapsed content widget, and expanded content widget. |
| 13 | `features/orders/widgets/order_photo_section.dart` | 592 | 4 | 0 | High | Extract photo tile, photo viewer sheet, upload button, and empty state into sub-widgets. |
| 14 | `features/products/catalog_browse_screen.dart` | 563 | 3 | 0 | High | Extract photo grid, filter bar, bulk operations bar. Widget count triggers extraction rule. |
| 15 | `providers/order_providers.dart` | 530 | 0 | 1 | High | Separate draft model classes to `data/models/`. Split providers by concern: order CRUD vs. draft management. |
| 16 | `data/api/reconciliation_service.dart` | 519 | 0 | 0 | High | Split scan reconciliation into smaller endpoint handlers. Extract date-range helper methods. |

## God Files: Medium Severity (300-500 lines)

| # | File | Lines | Widget Classes | Top-Level Funcs | Severity | Recommendation |
|---|------|-------|----------------|-----------------|----------|----------------|
| 1 | `shared/router/app_router.dart` | 496 | 4 | 0 | Medium | Split into route definitions per feature module. Extract redirect guards to separate file. |
| 2 | `features/orders/widgets/order_card.dart` | 467 | 1 | 0 | Medium | Extract status badge, price row, and action buttons into sub-widgets. |
| 3 | `features/pos/pos_checkout_screen.dart` | 465 | 2 | 1 | Medium | Extract cart item list, payment method selector, and summary bar. |
| 4 | `features/knowledge/knowledge_detail_screen.dart` | 460 | 2 | 0 | Medium | Extract photo gallery integration and metadata display sections. |
| 5 | `features/products/widgets/catalog_photo_viewer.dart` | 443 | 3 | 0 | Medium | Widget count triggers extraction. Extract zoom controls, tag editor, share button to sub-widgets. |
| 6 | `features/pos/widgets/pos_product_grid.dart` | 435 | 2 | 2 | Medium | Extract grid item widget and category tabs. Move category filter logic to provider. |
| 7 | `features/knowledge/knowledge_form_screen.dart` | 434 | 1 | 0 | Medium | Extract form sections: metadata fields, content editor, photo picker, tag editor. |
| 8 | `features/dashboard/dashboard_screen.dart` | 401 | 6 | 0 | Medium | 6 inner widgets → extraction required. Create `dashboard/widgets/` and move stat cards. |
| 9 | `shared/widgets/printer_picker_dialog.dart` | 392 | 1 | 0 | Medium | Extract printer list tile, connection status indicator, test print button. |
| 10 | `features/events/widgets/event_history_list.dart` | 392 | 2 | 2 | Medium | Extract event tile, filter controls, export button to sub-widgets. |
| 11 | `features/stock/stock_screen.dart` | 385 | 2 | 2 | Medium | Extract ingredient list tile, filter bar, stock level indicator widgets. |
| 12 | `features/checklist/checklist_config_screen.dart` | 374 | 2 | 0 | Medium | Extract template editor, entry list manager, import/export controls. |
| 13 | `features/checklist/checklist_history_screen.dart` | 371 | 5 | 0 | Medium | 5 inner widgets → extraction required. Extract history card, date filter, status badge. |
| 14 | `features/events/event_form_screen.dart` | 333 | 1 | 0 | Medium | Extract form fields: datetime picker, recurrence config, description editor. |
| 15 | `features/knowledge/widgets/knowledge_photo_gallery.dart` | 330 | 3 | 0 | Medium | Widget count triggers extraction. Extract photo tile, lightbox overlay, upload button. |
| 16 | `data/services/printer_service.dart` | 328 | 0 | 1 | Medium | Split connection management from print job formatting. Extract receipt template builder. |
| 17 | `features/knowledge/knowledge_list_screen.dart` | 322 | 2 | 0 | Medium | Extract search bar, list tile, filter chips, empty state widgets. |
| 18 | `features/categories/category_form.dart` | 319 | 2 | 0 | Medium | Extract name field, color picker, icon selector, parent category picker. |
| 19 | `features/stock/widgets/stock_action_sheet.dart` | 310 | 1 | 0 | Medium | Extract action type selector, quantity input, reason field, confirm button. |
| 20 | `features/checklist/checklist_screen.dart` | 304 | 4 | 0 | Medium | 4 inner widgets → extraction required. Extract entry card, progress bar, action buttons. |
| 21 | `features/categories/category_management_screen.dart` | 303 | 5 | 1 | Medium | 5 inner widgets → extraction required. Extract category tree, drag handle, edit sheet. |
| 22 | `features/pos/pos_screen.dart` | 300 | 1 | 0 | Medium | At screen threshold limit. Extract category sidebar, search bar, cart panel sections. |

## God Files: Low Severity (200-300 lines)

| # | File | Lines | Widget Classes | Top-Level Funcs | Severity | Recommendation |
|---|------|-------|----------------|-----------------|----------|----------------|
| 1 | `features/events/widgets/event_log_form.dart` | 295 | 1 | 0 | Low | Extract outcome selector, timestamp picker, notes field. |
| 2 | `features/products/product_catalog_screen.dart` | 255 | 2 | 0 | Low | Extract catalog card, filter toolbar, import button widgets. |
| 3 | `features/orders/receipt_preview_screen.dart` | 255 | 1 | 0 | Low | Extract receipt content widget, print action bar, share button. |
| 4 | `features/products/widgets/catalog_tag_edit_sheet.dart` | 250 | 2 | 1 | Low | Extract tag color picker, name field, preview chip widgets. |
| 5 | `features/orders/widgets/product_picker_page.dart` | 250 | 1 | 0 | Low | Extract search bar, product chip, quantity stepper widgets. |
| 6 | `features/stock/stock_reconciliation_history_screen.dart` | 235 | 4 | 0 | Low | 4 inner widgets → extraction recommended. Extract history card, diff summary, date filter. |
| 7 | `data/api/product_service.dart` | 224 | 0 | 0 | Low | Split catalog queries from product CRUD. Extract DTO mapping helpers. |
| 8 | `data/api/order_service.dart` | 205 | 0 | 0 | Low | Split order CRUD from list/search/filter endpoints. Extract query param builder. |

## Follow-up Tickets

| Ticket | Description |
|--------|-------------|
| DG-135 | Refactor 16 High-severity oversized files (>500 lines) |
| DG-136 | Extract widget classes from files triggering ≥3 extraction rule |
| DG-137 | Apply const constructor suppression across codebase |
| DG-138 | Deferred const audit — suppress or fix const issues |
