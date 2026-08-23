# Bakery Shop Flutter Coding Standards

> Date: 2026-05-09
> Scope: Coding standards covering file sizing, widget composition, provider placement, state management, label organization, testing, and linting
> Based on: Code Quality Audit (475 files, 81,256 lines)
> Flutter SDK: 3.44.0 (repo-standard devshell)
> Riverpod: ^3.1.0
> Review cadence: Annual or on major Flutter/Riverpod version bump

## Quick Reference

| Rule | Threshold / Directive |
|------|----------------------|
| Screen max lines | 300 |
| Widget max lines | 300 |
| Provider max lines | 400 |
| Service max lines | 300 |
| Widget extraction trigger | ≥3 private inner widget classes in a file |
| Data-layer providers | `lib/data/providers/` |
| App-layer providers | `lib/providers/` |
| Async state | `AsyncNotifier` |
| Sync state | `Notifier` |
| `setState` in ConsumerWidget | Prohibited |
| Form drafts | Typed context; authenticated-session retention; isolated operation state |
| VN labels | Domain files under `lib/shared/labels/` |
| Test naming | `<component>_test.dart` |
| Widget test pattern | `pumpWidget` with provider overrides |
| Lint rules | 12 rules activated (see §7) |

## Compliance Checklist

- [ ] §1 File Sizing — all files checked against thresholds
- [ ] §2 Widget Composition — inner classes ≥3 extracted to `widgets/`
- [ ] §3 Provider Placement — providers placed in correct directory
- [ ] §4 State Management — AsyncNotifier/Notifier used, no setState in ConsumerWidget
- [ ] §4 Contextual Form Drafts — typed keys, lifecycle clears, operation isolation, and retained-scope tests verified
- [ ] §5 Label Organization — labels split by domain, no monolithic VN class additions
- [ ] §6 Testing — tests follow naming, pattern, and coverage rules
- [x] §7 Linting — 12 rules enabled, no new analyzer errors

---

## §1 File Sizing

### Thresholds

| File Type | Max Lines | Location | Evidence from Audit |
|-----------|-----------|----------|---------------------|
| Screen | 300 | `lib/features/<feature>/` | 18 High-severity files >500 lines; `product_form_screen.dart` at 1,774 lines |
| Widget | 300 | `lib/features/<feature>/widgets/` | Raised from 200 to 300 per DG-332; aligns widget threshold with Screen/Service (300). Largest widgets: `reconciliation_product_card.dart` at 881 lines, `cake_detail_body.dart` at 729 lines. Audit baseline files ≥300 lines = 75 (18 High >500 + 15 Medium 400-500 + 42 Low 300-399) |
| Provider | 400 | `lib/data/providers/` or `lib/providers/` | `reconciliation_models.dart` at 781 lines; `cash_drawer_service.dart` at 531 lines |
| Service | 300 | `lib/data/api/` | `reconciliation_models.dart` at 781; `cash_drawer_service.dart` at 531 |

### Exception Process

When a file must exceed its threshold:
1. Add a comment at the top of the file:
   ```dart
   // EXEMPT: <max>-line threshold exceeded because <reason>. Reviewed <date>.
   ```
2. The reason must cite a concrete blocker (e.g., "form contains 12 enum attribute types requiring per-type widget logic").
3. Exemptions are not permanent — re-evaluate on each feature change to the file.
4. Exempt files still trigger the widget extraction rule (§2) when they contain ≥3 private inner widget classes.

### Pre-existing Oversized Files (Baseline)

The audit identified 75 files ≥300 lines under the updated widget threshold (18 High-severity >500 lines + 15 Medium 400-500 lines + 42 Low 300-399 lines). The 18 High-severity files (>500 lines) remain the priority refactoring targets. Individual refactoring will be tracked as separate DG tickets. New files must comply from creation — the baseline does not grandfather future additions.

---

## §2 Widget Composition

### Extraction Rule

**When a single `.dart` file contains ≥3 private inner widget classes, those classes must be extracted into separate files under the feature's `widgets/` subdirectory.**

| Trigger | Action | Rationale |
|---------|--------|-----------|
| 1 inner widget class | Keep inline — acceptable | No action needed |
| 2 inner widget classes | Keep inline — review | Consider extraction if either exceeds 80 lines |
| 3+ inner widget classes | **Extract to `widgets/`** | Required. Testability, reuse, and review scannability |

### Extraction Pattern

Given `lib/features/orders/order_create_screen.dart` containing private classes `_CustomerFormSection`, `_ItemPickerSection`, `_ExtrasSection`:

1. Create files:
   - `lib/features/orders/widgets/customer_form_section.dart`
   - `lib/features/orders/widgets/item_picker_section.dart`
   - `lib/features/orders/widgets/extras_section.dart`
2. Each extracted widget file must be standalone — all imports self-contained.
3. The parent screen file imports from `widgets/` using relative paths.

### Pre-existing Extraction Targets (Audit)

Files currently triggering the ≥3 rule (live audit, 2026-08-17):

| File | Inner Classes | Severity |
|------|---------------|----------|
| `features/blanks/blank_detail_screen.dart` | 9 | Medium |
| `features/stock/widgets/reconciliation_product_card.dart` | 8 | High |
| `features/cash_drawer/cash_drawer_screen.dart` | 7 | High |
| `features/today_sales/widgets/cashflow_summary_section.dart` | 6 | Low |
| `features/today_sales/widgets/expense_summary_section.dart` | 5 | n/a |
| `features/today_sales/widgets/day_tab_body.dart` | 5 | n/a |
| `features/products/product_form_screen.dart` | 5 | High |
| `features/orders/order_list_screen.dart` | 5 | High |
| `features/customers/customer_list_screen.dart` | 5 | n/a |
| `features/categories/category_management_screen.dart` | 5 | n/a |
| `features/today_sales/widgets/product_breakdown_section.dart` | 4 | n/a |
| `features/settings/widgets/catalog_tags_dialogs.dart` | 4 | Low |
| `features/settings/address_library_screen.dart` | 4 | Medium |
| `features/products/widgets/catalog_photo_viewer.dart` | 4 | Medium |
| `features/products/product_catalog_screen.dart` | 4 | Medium |
| `features/orders/widgets/order_photo_section.dart` | 4 | High |
| `features/expenses/debt_list_screen.dart` | 4 | n/a |
| `features/events/widgets/event_form_photo_section.dart` | 4 | n/a |
| `features/customers/customer_form.dart` | 4 | High |
| `features/checklist/checklist_screen.dart` | 4 | Low |
| `features/checklist/checklist_history_screen.dart` | 4 | Low |
| `features/cash_drawer/widgets/cash_drawer_history_list.dart` | 4 | n/a |
| `features/auth/login_screen.dart` | 4 | n/a |
| `features/audit_log/audit_log_screen.dart` | 4 | n/a |
| `features/today_sales/widgets/today_order_list.dart` | 3 | n/a |
| `features/templates/widgets/template_picker_modal.dart` | 3 | Medium |
| `features/settings/widgets/settings_sections.dart` | 3 | n/a |
| `features/settings/missing_links_screen.dart` | 3 | n/a |
| `features/orders/order_history_screen.dart` | 3 | Low |
| `features/knowledge/widgets/knowledge_photo_gallery.dart` | 3 | Low |
| `features/events/widgets/quick_log_photo_picker.dart` | 3 | n/a |
| `features/dashboard/management_dashboard_screen.dart` | 3 | Low |
| `features/categories/category_form.dart` | 3 | Medium |
| `features/blanks/bom_mapping_screen.dart` | 3 | n/a |
| `features/auth/widgets/password_change_form.dart` | 3 | n/a |

---

## §3 Provider Placement

### Directory Map

| Directory | Purpose | Examples |
|-----------|---------|----------|
| `lib/data/providers/` | Data-layer providers: API calls, model reconciliation, CRUD operations | `reconciliation_provider.dart`, `knowledge_provider.dart`, `checklist_provider.dart`, `cake_queue_provider.dart` |
| `lib/providers/` | App-layer providers: UI state, navigation, draft management, form state, printer status | `order_providers.dart`, `pos_provider.dart`, `config_provider.dart`, `products_provider.dart`, `events_provider.dart`, `catalog_provider.dart` |

### Placement Decision Table

| Does the provider... | Directory |
|----------------------|-----------|
| Consume an API service and transform server data? | `lib/data/providers/` |
| Manage draft/local-only state not persisted to server? | `lib/providers/` |
| Track UI-only state (selected tab, expanded section, filter)? | `lib/providers/` |
| Map server models to domain models? | `lib/data/providers/` |
| Control navigation state or go_router redirect logic? | `lib/providers/` |
| Hold form-in-progress state before submit? | `lib/providers/` |

### Cross-Directory Dependencies

- Data-layer providers (`lib/data/providers/`) may be consumed by app-layer providers (`lib/providers/`) — this is expected and correct.
- App-layer providers must NOT be consumed by data-layer providers — data-layer must remain pure and independent of UI concerns.
- Both directories share the same Riverpod `ProviderContainer` — no directory creates a separate scope.

### Live Findings (audit 2026-08-17)

**Provider counts by location:**
| Location | Files |
|----------|-------|
| `lib/providers/` | 35 |
| `lib/data/providers/` | 15 |
| `lib/features/**/providers/` | 3 |

**Cross-dependency violation (1 file, 2 imports):**

`app/lib/data/providers/reconciliation_notifier.dart` imports two app-layer providers, violating the data-layer↔app-layer boundary above:

| Line | Import |
|------|--------|
| 4 | `import '../../providers/events_provider.dart';` |
| 5 | `import '../../providers/products_provider.dart';` |

This is the sole confirmed data-layer→app-layer cross-dependency in the tree. Reproduce:

```bash
grep -nE "import.*'../../providers/(events_provider|products_provider)\.dart'" \
  app/lib/data/providers/reconciliation_notifier.dart
# → 4:import '../../providers/events_provider.dart';
# → 5:import '../../providers/products_provider.dart';
```

**Misplaced providers — reproducible classification rule:**

"21 misplaced" (stated in the prior requirements baseline) was not objectively reproducible: the §3 decision table permits app-layer providers to consume data-layer services, so service-backed providers in `lib/providers/` are not misplaced by that fact alone. The reproducible rule below counts only clear data-layer↔app-layer violations and does not reproduce 21.

**Reproducible rule:** A `lib/providers/` file is *misplaced* iff it is **pure service-backed** (references a `Service` or `Repository` and exposes zero UI-controller signals: no `TabController`/`ScrollController`/`TextEditingController`/`AnimationController`/`FocusNode`/`GlobalKey` and no UI-state fields). Such a file belongs in `lib/data/providers/`.

Applying this rule to the live tree:

| Misplaced file (lib/providers/ → lib/data/providers/) | Service/Repository ref | UI-controller signals |
|--------------------------------------------------------|-----------------------|------------------------|
| `printer_provider.dart` | yes | none |
| `events_provider.dart` | yes | none |
| `photo_upload_provider.dart` | yes | none |
| `cash_drawer_provider.dart` | yes | none |

**Reproducible misplaced-provider count: 4.**

Non-provider helper files in `lib/data/providers/` (`reconciliation_math.dart`, `reconciliation_state.dart`) are excluded — they are not providers and therefore not "misplaced". No `lib/data/providers/` file exposes UI-state signals.

Reproduce:

```bash
find app/lib/providers        -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' | wc -l  # → 35
find app/lib/data/providers  -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' | wc -l  # → 15
find app/lib/features        -type f -path '*/providers/*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' | wc -l  # → 3
```

The misplaced-provider classification is intentionally narrower than the prior "21" figure: it counts only clear, decision-table-supported data-layer↔app-layer violations (see §11 risk note). Downstream relocation is tracked by DG-417.

---

## §4 State Management

### Riverpod Notifier Rules

| State Type | Use | Example |
|------------|-----|---------|
| **Async** (loading/data/error) | `AsyncNotifier<T>` | Order list fetching, reconciliation draft loading, product search |
| **Sync** (immediate, no loading phase) | `Notifier<T>` | Selected tab index, filter toggle, expanded section ID, form field value |

### Prohibited Pattern

`setState()` inside `ConsumerWidget` or `ConsumerStatefulWidget` is prohibited for **mutable local state**. Use Riverpod `Notifier` or `AsyncNotifier` instead.

```dart
// ❌ PROHIBITED
class _MyScreenState extends ConsumerState<MyScreen> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => setState(() => _counter++),
      child: Text('$_counter'),
    );
  }
}
```

```dart
// ✅ CORRECT
class CounterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

// In screen:
final counterProvider = NotifierProvider<CounterNotifier, int>(CounterNotifier.new);
```

### Acceptable setState Usage

`setState()` is acceptable only in:
1. **Animation controllers** (`AnimationController` lifecycle — `addListener` + `setState` for repaints).
2. **Text editing controllers** (`TextEditingController` listener callbacks — but prefer `flutter_hooks` `useTextEditingController` where feasible).
3. **Third-party widget integration** where the widget API requires `StatefulWidget` (e.g., `GoogleMap`, `WebView`).

In all three cases, the `setState` scope must be confined to the single widget's local animation/text state. Business logic state must still use Riverpod.

### Live Status (audit 2026-08-19, post-DG-404 migration)

| Metric | Count |
|--------|-------|
| Files containing `setState(` | 19 |
| Total `setState()` call sites | 43 |
| Files using `setState(` inside `ConsumerState`/`ConsumerStatefulWidget` (prohibited-context subset) | 7 |
| Of those 7, files whose `setState` body contains business-logic signals (counter / list / bool / selected / expanded / filter / isLoading) — the **prohibited** subset | 0 |

**Prohibited vs acceptable distinction (live):**

- **Prohibited (0 files):** `setState` inside `ConsumerState`/`ConsumerStatefulWidget` that mutates business-logic state (counters, lists, booleans, selection, expansion, filter, loading flags). The prohibited subset is now **zero** — DG-404 is complete; all 76 prohibited files from the pre-migration baseline have been migrated to Riverpod `Notifier`/`AsyncNotifier`.
- **Acceptable (7 of the 7 prohibited-context files):** All 7 remaining `ConsumerState`/`ConsumerStatefulWidget` `setState` usages are classified as acceptable/out-of-scope per the rule above (animation/text/third-party or comment-only). Breakdown:
  - 5 comment-only (no real call): `orders/widgets/address_autocomplete_field.dart`, `orders/widgets/google_maps_modal.dart`, `orders/order_list_screen.dart`, `pos/pos_checkout_screen.dart`, `today_sales/today_sales_screen.dart`.
  - 1 acceptable-use: `pos/widgets/pos_payment_step.dart` (2 `setState` inside `TextEditingController` listeners).
  - 1 mixed: `orders/widgets/order_photo_section.dart` (its only `setState` is in the plain-`StatefulWidget` `OrderPhotoViewer`, not in a `ConsumerState`).
- **Outside `ConsumerState`/`ConsumerStatefulWidget` (12 files of the 19):** `setState` in plain `StatefulWidget`s not consumed via Riverpod — acceptable by the rule above, scoped to local widget state.

Reproduce:

```bash
# Files using setState
grep -rlE "setState\(" app/lib --include='*.dart' 2>/dev/null \
  | grep -v '.g.dart' | grep -v '.freezed.dart' | wc -l
# → 19

# Total setState call sites
grep -rE "setState\(" app/lib --include='*.dart' 2>/dev/null \
  | grep -v '.g.dart' | grep -v '.freezed.dart' | wc -l
# → 43

# Files using setState inside ConsumerState/ConsumerStatefulWidget
grep -rlE "ConsumerState|ConsumerStatefulWidget" app/lib --include='*.dart' 2>/dev/null \
  | grep -v '.g.dart' | grep -v '.freezed.dart' \
  | xargs grep -lE "setState\(" 2>/dev/null | wc -l
# → 7
```

The prohibited subset is **0**: every remaining `setState` call site in `ConsumerState`/`ConsumerStatefulWidget` has been manually classified as acceptable-use (animation/text/third-party) or comment-only per the rule above. All real `setState` call sites now live in plain `StatefulWidget`s (out of scope per the Non-Goals) or acceptable-use cases. DG-404 migration is complete.

### Contextual Form Drafts

Form state moved from a widget into Riverpod must preserve form lifecycle semantics; moving it into an application-scope provider must not turn unrelated forms into one shared draft. The exhaustive DG-423 classification of all 98 fixed-baseline providers and 19 added lifecycle symbols is maintained in the [form draft lifecycle migration matrix](form-draft-lifecycle-migration-matrix.md).

#### Identity And Lifetime

- Every retained draft has a typed context identity containing the form type and `create`, `edit`, or `action` mode, plus every stable identity that distinguishes the form: entity ID, product ID, option ID, and normalized-price/variant ID where applicable.
- Create and edit modes never share a key. Different entities, products, options, or normalized prices never share a key, even when their widgets reuse the same Riverpod family or route.
- Drafts are in-memory only and live for the current authenticated application session. They are not written to disk and must add no API request.
- A context has at most one registry entry. Reopening a context restores that entry; it must not append a duplicate or initialize from another context.
- Initialize from declared defaults or server entity data only when the exact context has no retained draft. Deferred seeding must not overwrite a dirty draft or expose another context's state on the first frame.

Use the shared `FormDraftContext` identity and session registry rather than ad hoc strings or one global mutable form provider. An intentional exception must document its key, retention boundary, reset events, security rationale where relevant, and tests in the migration matrix.

The integrated implementation uses `formDraftSessionProvider` as the in-memory registry and `formDraftSessionEpochProvider` to reset already-live providers on every authenticated-session clear, including when the registry is empty. Async success paths use `clearDraftIfUnchanged` when a newer same-context draft may replace the submitted snapshot. Order flows construct identities through `OrderDraftContexts`, and transient order busy/error state is isolated by `orderFormOperationProvider` rather than retained with draft fields.

#### Retain And Clear Rules

| Event | Required result |
|---|---|
| Cancel, system back, route back, or swipe dismissal | Retain the dirty draft for the exact context; do not interpret navigation as discard. |
| Reopen same context in same authenticated session | Restore all draft values, selections, identity, and draft-owned photos. |
| Open another context | Show only that context's retained draft or declared defaults/server data. |
| Submit fails | Clear transient busy state and retain retryable draft data plus the contextual error. |
| Submit succeeds | Clear transient operation state and remove exactly the submitted context's draft. |
| User requests clear draft | Show the shared Vietnamese action only when dirty; clear exactly one context only after confirmation. Cancelling confirmation retains it. |
| Logout, forced session end, or HTTP 401 | Clear every authenticated-session draft. |
| App-process restart | Drafts are naturally absent because storage is memory-only. |

Sensitive credentials are an explicit exception: password values must not be retained as session drafts and must clear on close, success, logout, and 401. Their loading and error state still follows the operation-isolation rules below.

#### Operation State

Draft data and transient operation state are separate lifecycle concepts. `loading`, `saving`, `submitting`, validation/API errors, and duplicate-submission latches must be scoped to the matching context/operation and must not be retained as unfinished field data.

- A pending operation may disable only its context.
- Dismissing and reopening while a request is pending must not expose another context's busy/error state.
- Failure clears busy state and preserves retryable draft values.
- Success clears busy/error state and the submitted draft, even if the originating widget was dismissed before completion.
- Two mounted contexts and reused family keys must remain independent.

#### Nullable Fields And Photos

Nullable `copyWith` parameters must distinguish "not supplied" from "explicitly clear to null". Use an explicit clear flag, sentinel, or another typed mechanism; `field: value ?? this.field` is invalid when null is a meaningful user action. Tests must cover both preserving an omitted value and clearing a populated value, including expense subcategory, product photo, catalog-tag category, and reconciliation payment method.

Photos follow the same context rules as other draft data:

- Pending/local photos and persisted-photo selections must never cross form contexts.
- If a flow retains draft-owned photos, restore them only for the exact context and clear them on success, confirmed discard, logout, or restart.
- If security, platform lifetime, or file-handle validity requires a form not to retain pending photos, document that intentional exception and its user-visible behavior in the migration matrix and add a focused test. Silent photo loss is not the default.

#### Test Expectations

Provider and widget tests must reuse one `ProviderContainer`/`ProviderScope` across sequential opens; constructing a fresh scope for each open cannot detect application-scope leaks. Each audited draft family requires coverage for:

1. Same-context cancel/back/swipe dismissal and reopen.
2. Create versus edit and entity/product/option/normalized-price isolation.
3. Successful submit, failed submit/retry, confirmed discard, cancelled discard, logout/401, and process-restart semantics.
4. Dismiss-in-flight and two concurrently mounted contexts, including Riverpod family-key reuse.
5. Explicit nullable clearing through state and submitted request.
6. Draft-owned photo isolation/retention or an approved tested exception.
7. Public notifier methods and each operation error path, followed by `flutter analyze`, `dart analyze`, and `flutter test --coverage`.

---

## §5 Label Organization

### Domain Split

The migration from the former monolithic `lib/shared/widgets/vietnamese_labels.dart` (1,686 lines, 30+ domain sections, single `VN` class) is **complete**. The monolithic file has been removed; Vietnamese labels now live in per-domain files under `lib/shared/labels/`, with cross-domain helper maps and lookup functions in `lib/shared/utils.dart`. There is no monolithic `VN` class and no `vietnamese_labels.dart` in the tree.

| File | Domain | Example Labels |
|------|--------|----------------|
| `lib/shared/labels/shared.dart` | Navigation, common actions, error messages, generic UI | `appName`, `cancel`, `save`, `delete`, `confirm` |
| `lib/shared/labels/orders.dart` | Order statuses, actions, form fields, detail, photos, cake queue, cake detail | `statusNew`, `createOrder`, `orderDetail`, `payment` |
| `lib/shared/labels/products.dart` | Product categories, form, catalog gallery, product code, display flags | `productCategories`, `addProduct`, `catalogGallery` |
| `lib/shared/labels/events.dart` | Event types, tags, form, history filters | `eventTypes`, `eventTags`, `eventForm` |
| `lib/shared/labels/checklist.dart` | Checklist templates, entries, print dialog | `checklistTemplate`, `checklistEntry` |
| `lib/shared/labels/customers.dart` | Customer-domain copy | customer form/action labels |
| `lib/shared/labels/accounting.dart` | Accounting-domain copy | accounting labels |
| `lib/shared/labels/expenses.dart` | Expenses-domain copy | `paymentSourcePhuongVCB`, `paymentSourceAnVCB` |
| `lib/shared/labels/stock.dart` | Stock-domain copy | stock labels |
| `lib/shared/labels/cash_drawer.dart` | Cash-drawer-domain copy | cash drawer labels |
| `lib/shared/labels/audit_log.dart` | Audit log-domain copy | audit log labels |
| `lib/shared/labels/auth.dart` | Auth-domain copy | auth labels |
| `lib/shared/labels/templates.dart` | Message-template picker (DG-375) | template picker labels |
| `lib/shared/labels/address_labels.dart` | Address autocomplete (DG-385) | address autocomplete labels |
| `lib/shared/labels/technical_settings.dart` | Pre-login technical settings (DG-367) | technical settings labels |
| `lib/shared/labels/blanks.dart` | Blank/placeholder actions | `actionCancel` |

`lib/shared/utils.dart` provides cross-domain lookup helpers (`categoryMap`, `statusMap`, `validTransitions`, `statusActionLabel`, `txnTypeLabel`, `paymentMethodLabel`, `paymentTargetAccounts`, `workItemStatusMap`, etc.) that map domain slugs to the corresponding domain label.

### Label Rule

- New labels go in the appropriate domain file under `lib/shared/labels/`. Never re-introduce a monolithic `VN` class or `vietnamese_labels.dart`.
- When a consumer imports a label, import only the domain file(s) it needs — not a barrel file.
- Shared/common labels that span multiple domains go in `shared.dart`.
- If a label's domain is unclear, default to the feature that most frequently consumes it.
- Cross-domain string-keyed lookups (mapping a backend slug to a VN label) belong in `lib/shared/utils.dart`, importing from the domain label files.

### Import Pattern

```dart
// Domain label files (current state)
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
// Usage: OrdersLabels.createOrder, SharedLabels.cancel

// Cross-domain lookup helpers
import 'package:bakery_app/shared/utils.dart';
// Usage: statusActionLabel('confirmed'), categoryMap['banh_mi']
```

### Migration Status (complete as of DG-418 follow-up)

The VN labels migration is complete:

- The monolithic `lib/shared/widgets/vietnamese_labels.dart` and the `VN` class are removed.
- All user-facing copy lives in `lib/shared/labels/*.dart` (per-domain) plus helper maps/functions in `lib/shared/utils.dart`.
- No `vietnamese_labels` import statements remain in `app/lib`.

Reproduce:

```bash
# Strict import-line count (must be 0)
grep -rE "import.*vietnamese_labels" app/lib --include='*.dart' 2>/dev/null \
  | grep -v '.g.dart' | grep -v '.freezed.dart' | wc -l
# → 0

# Files referencing vietnamese_labels anywhere (must be 0)
grep -rlE "vietnamese_labels" app/lib --include='*.dart' 2>/dev/null \
  | grep -v '.g.dart' | grep -v '.freezed.dart' | wc -l
# → 0

# Monolithic file must be absent
test ! -e app/lib/shared/widgets/vietnamese_labels.dart && echo "absent" || echo "present"
# → absent
```

New labels must continue to go in domain files under `lib/shared/labels/` — never add to a monolithic `VN` class. Cross-cutting lookups go in `lib/shared/utils.dart`.

---

## §6 Testing

### File Naming

| Artifact Under Test | Test File |
|---------------------|-----------|
| Screen `lib/features/orders/order_detail_screen.dart` | `test/features/orders/order_detail_screen_test.dart` |
| Widget `lib/features/orders/widgets/order_card.dart` | `test/features/orders/widgets/order_card_test.dart` |
| Provider `lib/data/providers/reconciliation_provider.dart` | `test/features/stock/reconciliation_provider_test.dart` or `test/data/providers/reconciliation_provider_test.dart` |
| Service `lib/data/api/order_service.dart` | `test/data/api/order_service_test.dart` |
| Utility `lib/shared/utils/vnd_units.dart` | `test/shared/utils/vnd_units_test.dart` |

### Widget Test Pattern

Use `pumpWidget` with a `ProviderScope` wrapping the widget under test. Override providers with fake/mock implementations:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders product list when data loads', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderServiceProvider.overrideWithValue(FakeOrderService()),
        ],
        child: const MaterialApp(home: OrderListScreen()),
      ),
    );

    expect(find.text('Đơn hàng'), findsOneWidget);
  });
}
```

For navigation-aware screens that use `GoRouter`, wrap with a `MaterialApp.router`:

```dart
GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const OrderDetailScreen(orderId: 1)),
    ],
  );
}

await tester.pumpWidget(
  ProviderScope(
    overrides: [...],
    child: MaterialApp.router(routerConfig: buildRouter()),
  ),
);
```

### Per-Feature Coverage Expectations

| Artifact | Minimum Tests |
|----------|---------------|
| Screen | 1 widget test (renders without error + core interaction) |
| Provider (Notifier/AsyncNotifier) | 1 test per public method + 1 test per error path |
| Service | 1 test per endpoint method (mock Dio) |
| Shared widget | 1 widget test per interactive state (if >1 state) |

Coverage is per-feature, not per-file. A feature with 3 screens and 2 providers needs minimum 5 tests (3 screen + 2 provider).

---

## §7 Linting

### Enabled Rules

All 12 rules below are already enabled in `app/analysis_options.yaml` (Phase 3 complete). No further enablement work is required.

| # | Rule | Category | Rationale |
|---|------|----------|-----------|
| 1 | `prefer_const_constructors` | Performance | Enables compile-time constant widget instantiation. Reduces rebuilds. |
| 2 | `prefer_const_literals_to_create_immutables` | Performance | Extends const optimization to list/map/set literals. |
| 3 | `avoid_print` | Code quality | Prevents debug `print()` leaks into production. Use `debugPrint` or structured logging. |
| 4 | `prefer_single_quotes` | Style | Consistent string quoting across the codebase. |
| 5 | `use_key_in_widget_constructors` | Correctness | Ensures widget keys for efficient diffing in lists. Prevents state-loss bugs on reorder. |
| 6 | `unnecessary_lambdas` | Performance | Replaces tear-off closures with direct method references. |
| 7 | `avoid_unnecessary_containers` | Performance | Eliminates redundant `Container` wrappers that add no layout/sizing. |
| 8 | `prefer_const_declarations` | Performance | Forces const on top-level/static declarations that never change. |
| 9 | `sort_child_properties_last` | Style | Consistent widget property ordering: child/children after all other properties. |
| 10 | `require_trailing_commas` | Style | Enforces trailing commas on multi-line parameter lists. Enables cleaner diffs and formatter output. |
| 11 | `always_declare_return_types` | Correctness | Explicit return types on methods/functions. Prevents accidental `dynamic` inference. |
| 12 | `avoid_types_on_closure_parameters` | Style | Leverages type inference in closures. Reduces noise in callback parameters. |

### Application Status (Complete)

1. All 12 rules are enabled in `app/analysis_options.yaml` (Phase 3 complete).
2. New code must comply with all enabled rules — no new `// ignore:` comments for new code.
3. Verify: `dart analyze` returns zero errors.

---

## Version Reference

- Flutter SDK: 3.44.0 (run all Flutter/Dart commands via `nix develop .#flutter`)
- Dart SDK: 3.12.0 (from the same pinned Flutter toolchain)
- Do not edit `flake.nix` or repo Flutter pin values directly to change Flutter/Dart versions; file a ticket for requirements or builder review first.
- Riverpod: ^3.1.0 (as of `pubspec.yaml`)
- flutter_lints: ^5.0.0 (via `analysis_options.yaml` include)
- Review cadence: Annual or on major Flutter/Riverpod SDK version bump
