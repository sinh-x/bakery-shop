# Code Quality Audit Report: Bakery Shop Flutter App

> Date: 2026-08-17 (re-audit, live counts)
> Scope: God file audit of non-generated Dart files under `app/lib/`
> Files scanned: 475 non-generated `.dart` files (81,256 total lines)
> Severity thresholds: High >500, Medium 400–500, Low 300–399 (fixed — see §Severity Thresholds)
> Reproducibility: All counts below are reproducible by re-running the commands in §Audit Method against the current working tree. The codebase is the source of truth.

## Summary

| Severity | Count | Total Lines | % of All Lines |
|----------|-------|-------------|----------------|
| High (>500) | 18 | 14,459 | 17.8% |
| Medium (400–500) | 15 | 6,603 | 8.1% |
| Low (300–399) | 42 | 14,445 | 17.8% |
| **Audited (≥300)** | **75** | **35,507** | **43.7%** |

> 75 of 475 files (15.8%) are at least 300 lines. 18 files exceed 500 lines and are High severity. The top offender is `app/lib/features/products/product_form_screen.dart` at 1,774 lines.

> [!NOTE] **Live re-audit (DG-416 Phase 2, 2026-08-17)**
> Counts in this report are reproducible via the commands in §Audit Method. See ticket DG-416 and the Phase 1 re-audit artifact `agent-teams/builder/artifacts/2026-08-17-dg416-audit-counts.md`.

## God Files: High Severity (>500 lines)

| # | File | Lines | Severity |
|---|------|-------|----------|
| 1 | `app/lib/features/products/product_form_screen.dart` | 1,774 | High |
| 2 | `app/lib/shared/widgets/vietnamese_labels.dart` | 1,686 | High |
| 3 | `app/lib/features/orders/order_list_screen.dart` | 981 | High |
| 4 | `app/lib/features/stock/widgets/reconciliation_product_card.dart` | 881 | High |
| 5 | `app/lib/features/cash_drawer/cash_drawer_screen.dart` | 877 | High |
| 6 | `app/lib/features/orders/order_edit/widgets/work_item_edit_card.dart` | 801 | High |
| 7 | `app/lib/data/api/reconciliation_models.dart` | 781 | High |
| 8 | `app/lib/features/orders/widgets/cake_detail_body.dart` | 729 | High |
| 9 | `app/lib/features/pos/widgets/pos_product_grid.dart` | 652 | High |
| 10 | `app/lib/features/cash_drawer/widgets/cash_drawer_action_dialogs.dart` | 651 | High |
| 11 | `app/lib/features/stock/widgets/reconciliation_sell_waste_modal.dart` | 646 | High |
| 12 | `app/lib/features/orders/widgets/order_card.dart` | 646 | High |
| 13 | `app/lib/features/orders/widgets/order_photo_section.dart` | 620 | High |
| 14 | `app/lib/features/cash_drawer/widgets/cash_drawer_transaction_list.dart` | 569 | High |
| 15 | `app/lib/features/orders/widgets/expandable_item_card.dart` | 563 | High |
| 16 | `app/lib/features/orders/order_edit_screen.dart` | 562 | High |
| 17 | `app/lib/data/api/cash_drawer_service.dart` | 531 | High |
| 18 | `app/lib/features/customers/customer_form.dart` | 509 | High |

> Line counts above are `wc -l` output captured on 2026-08-17 against `feature/DG-416-update-standards-docs`. Re-run the High-band command in §Audit Method to verify; each row should match `wc -l <path>` exactly.

## God Files: Medium Severity (400–500 lines)

| # | File | Lines | Severity |
|---|------|-------|----------|
| 1 | `app/lib/features/settings/address_library_screen.dart` | 488 | Medium |
| 2 | `app/lib/features/orders/cake_queue_screen.dart` | 469 | Medium |
| 3 | `app/lib/features/products/widgets/catalog_photo_viewer.dart` | 468 | Medium |
| 4 | `app/lib/features/knowledge/knowledge_form_screen.dart` | 466 | Medium |
| 5 | `app/lib/features/orders/order_detail_screen.dart` | 464 | Medium |
| 6 | `app/lib/features/products/product_catalog_screen.dart` | 457 | Medium |
| 7 | `app/lib/features/knowledge/knowledge_detail_screen.dart` | 454 | Medium |
| 8 | `app/lib/features/events/event_form_screen.dart` | 434 | Medium |
| 9 | `app/lib/features/expenses/expense_form_screen.dart` | 433 | Medium |
| 10 | `app/lib/features/expenses/expense_screen.dart` | 428 | Medium |
| 11 | `app/lib/features/categories/category_form.dart` | 423 | Medium |
| 12 | `app/lib/features/templates/widgets/template_picker_modal.dart` | 406 | Medium |
| 13 | `app/lib/features/expenses/widgets/expense_filter_card.dart` | 406 | Medium |
| 14 | `app/lib/features/blanks/blank_detail_screen.dart` | 405 | Medium |
| 15 | `app/lib/shared/widgets/printer_picker_dialog.dart` | 402 | Medium |

## God Files: Low Severity (300–399 lines)

| # | File | Lines | Severity |
|---|------|-------|----------|
| 1 | `app/lib/features/pos/widgets/pos_checkout_payment_controller.dart` | 399 | Low |
| 2 | `app/lib/features/orders/widgets/address_autocomplete_field.dart` | 392 | Low |
| 3 | `app/lib/features/events/widgets/event_history_list.dart` | 388 | Low |
| 4 | `app/lib/features/products/catalog_browse_screen.dart` | 386 | Low |
| 5 | `app/lib/data/api/customer_service.dart` | 385 | Low |
| 6 | `app/lib/features/orders/widgets/order_delivery_section.dart` | 384 | Low |
| 7 | `app/lib/features/settings/settings_screen.dart` | 380 | Low |
| 8 | `app/lib/features/checklist/checklist_config_screen.dart` | 380 | Low |
| 9 | `app/lib/features/checklist/checklist_history_screen.dart` | 376 | Low |
| 10 | `app/lib/features/stock/widgets/reconciliation_shared_widgets.dart` | 374 | Low |
| 11 | `app/lib/features/knowledge/knowledge_list_screen.dart` | 373 | Low |
| 12 | `app/lib/features/orders/order_history_screen.dart` | 371 | Low |
| 13 | `app/lib/features/settings/widgets/catalog_tags_dialogs.dart` | 365 | Low |
| 14 | `app/lib/features/events/widgets/event_log_form.dart` | 359 | Low |
| 15 | `app/lib/features/pos/widgets/pos_payment_step.dart` | 357 | Low |
| 16 | `app/lib/features/pos/pos_screen.dart` | 353 | Low |
| 17 | `app/lib/features/stock/widgets/stock_action_sheet.dart` | 348 | Low |
| 18 | `app/lib/features/expenses/widgets/expense_form_card.dart` | 346 | Low |
| 19 | `app/lib/features/customers/widgets/customer_search_field.dart` | 338 | Low |
| 20 | `app/lib/features/customers/customer_detail_screen.dart` | 338 | Low |
| 21 | `app/lib/features/checklist/checklist_screen.dart` | 338 | Low |
| 22 | `app/lib/data/services/printer_service.dart` | 338 | Low |
| 23 | `app/lib/data/api/order_service.dart` | 337 | Low |
| 24 | `app/lib/features/knowledge/widgets/knowledge_photo_gallery.dart` | 334 | Low |
| 25 | `app/lib/shared/labels/orders.dart` | 332 | Low |
| 26 | `app/lib/features/pos/pos_checkout_screen.dart` | 332 | Low |
| 27 | `app/lib/features/orders/widgets/delivery_order_card.dart` | 331 | Low |
| 28 | `app/lib/features/orders/widgets/order_detail/order_record_payment_sheet.dart` | 327 | Low |
| 29 | `app/lib/features/orders/order_edit/widgets/edit_extras_section.dart` | 327 | Low |
| 30 | `app/lib/features/dashboard/management_dashboard_screen.dart` | 324 | Low |
| 31 | `app/lib/shared/labels/shared.dart` | 323 | Low |
| 32 | `app/lib/features/today_sales/widgets/cashflow_summary_section.dart` | 323 | Low |
| 33 | `app/lib/features/orders/widgets/order_submission_mixin.dart` | 318 | Low |
| 34 | `app/lib/shared/utils/delivery_helpers.dart` | 314 | Low |
| 35 | `app/lib/providers/order/order_create_state_provider.dart` | 314 | Low |
| 36 | `app/lib/providers/products_provider.dart` | 313 | Low |
| 37 | `app/lib/features/templates/widgets/template_editor_screen.dart` | 308 | Low |
| 38 | `app/lib/data/providers/reconciliation_notifier.dart` | 308 | Low |
| 39 | `app/lib/features/cash_drawer/widgets/cash_drawer_breakdown_card.dart` | 307 | Low |
| 40 | `app/lib/features/products/widgets/catalog_browse_sections.dart` | 304 | Low |
| 41 | `app/lib/features/orders/widgets/product_picker_page.dart` | 301 | Low |
| 42 | `app/lib/features/orders/widgets/stage3_delivery_options_screen.dart` | 300 | Low |

## Follow-up Tickets

| Ticket | Description |
|--------|-------------|
| DG-404 | Refactor setState violations in ConsumerState/ConsumerStatefulWidget contexts |
| DG-408 | Extract inner widget classes from files triggering the ≥3 private inner widget extraction rule (35 extraction targets) |
| DG-417 | Relocate misplaced providers (cross-dependency violation: `reconciliation_notifier.dart` imports app-layer providers) |
| DG-418 | Migrate remaining inline strings to shared Vietnamese label modules (60 strict import lines remaining) |

## Severity Thresholds

The severity bands are fixed and must not be changed without an explicit standards update:

| Band | Line range (inclusive) |
|------|------------------------|
| High | > 500 |
| Medium | 400 – 500 |
| Low | 300 – 399 |

Files below 300 lines are not audited. Generated files (`*.g.dart`, `*.freezed.dart`) are excluded from all counts.

## Audit Method (Reproducible)

All commands run from the repo root `/home/sinh/Documents/bakery-shop`. Generated files (`*.g.dart`, `*.freezed.dart`) are excluded. Re-running these commands in the same working tree yields the counts reported above (75 / 18 / 15 / 42). See `agent-teams/builder/artifacts/2026-08-17-dg416-audit-counts.md` for the full Phase 1 re-audit artifact.

### F1 — Total non-generated Dart files

```bash
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' | wc -l
# → 475
```

### F2 — Files ≥300 lines with severity split

```bash
# Total ≥300
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 >= 300 && $2 != "total"' | wc -l
# → 75

# High (>500)
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 > 500 && $2 != "total"' | wc -l
# → 18

# Medium (400–500 inclusive)
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 >= 400 && $1 <= 500 && $2 != "total"' | wc -l
# → 15

# Low (300–399)
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 >= 300 && $1 < 400 && $2 != "total"' | wc -l
# → 42

# Full sorted list (≥300 lines) — use to populate/verify the High/Medium/Low tables
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 >= 300 && $2 != "total" {print $1"\t"$2}' | sort -rn
```

### Severity band totals (lines)

```bash
# Total lines across all audited (≥300) files
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 >= 300 && $2 != "total" {sum+=$1} END {print sum}'
# → 35507

# Per-band line totals: change the awk condition to match each band
#   High:   $1 > 500                          → 14459
#   Medium: $1 >= 400 && $1 <= 500            →  6603
#   Low:    $1 >= 300 && $1 < 400             → 14445
```

### Reproducing the High-severity table

To verify any row in §"God Files: High Severity", run:

```bash
wc -l <path-from-table>
```

The output line count must match the value in the table exactly. The 18 High-band files are the complete set returned by:

```bash
find app/lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec wc -l {} + \
  | awk '$1 > 500 && $2 != "total" {print $1"\t"$2}' | sort -rn
```

### Stability

Each command above was re-run twice during the Phase 1 re-audit (deployment d-a1f0b4) and again during Phase 2 verification (deployment d-f1a731); counts were stable across all runs. The counts are reproducible within the same working tree.