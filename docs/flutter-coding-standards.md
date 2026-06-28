# Bakery Shop Flutter Coding Standards

> Date: 2026-05-09
> Scope: Coding standards covering file sizing, widget composition, provider placement, state management, label organization, testing, and linting
> Based on: Code Quality Audit (120 files, 30,479 lines)
> Flutter SDK: 3.44.0 (repo-standard devshell)
> Riverpod: ^3.1.0
> Review cadence: Annual or on major Flutter/Riverpod version bump

## Quick Reference

| Rule | Threshold / Directive |
|------|----------------------|
| Screen max lines | 300 |
| Widget max lines | 200 |
| Provider max lines | 400 |
| Service max lines | 300 |
| Widget extraction trigger | ≥3 private inner widget classes in a file |
| Data-layer providers | `lib/data/providers/` |
| App-layer providers | `lib/providers/` |
| Async state | `AsyncNotifier` |
| Sync state | `Notifier` |
| `setState` in ConsumerWidget | Prohibited |
| VN labels | Domain files under `lib/shared/labels/` |
| Date/Time formatting | Use `lib/shared/utils/date_formatting.dart`; no direct `DateFormat` or `padLeft` |
| Test naming | `<component>_test.dart` |
| Widget test pattern | `pumpWidget` with provider overrides |
| Lint rules | 12 rules activated (see §7) |

## Compliance Checklist

- [ ] §1 File Sizing — all files checked against thresholds
- [ ] §2 Widget Composition — inner classes ≥3 extracted to `widgets/`
- [ ] §3 Provider Placement — providers placed in correct directory
- [ ] §4 State Management — AsyncNotifier/Notifier used, no setState in ConsumerWidget
- [ ] §5 Label Organization — labels split by domain, no monolithic VN class additions
- [ ] §6 Testing — tests follow naming, pattern, and coverage rules
- [ ] §7 Linting — 12 rules enabled, no new analyzer errors

---

## §1 File Sizing

### Thresholds

| File Type | Max Lines | Location | Evidence from Audit |
|-----------|-----------|----------|---------------------|
| Screen | 300 | `lib/features/<feature>/` | 16 High-severity files >500 lines; `order_detail_screen.dart` at 2,557 lines |
| Widget | 200 | `lib/features/<feature>/widgets/` | `expandable_item_card.dart` at 616 lines; `order_photo_section.dart` at 592 |
| Provider | 400 | `lib/data/providers/` or `lib/providers/` | `reconciliation_provider.dart` at 651; `order_providers.dart` at 530 |
| Service | 300 | `lib/data/api/` | `reconciliation_service.dart` at 519; `printer_service.dart` at 328 |

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

The audit identified 46 files ≥200 lines. The 16 High-severity files (>500 lines) are the priority refactoring targets. Individual refactoring will be tracked as separate DG tickets. New files must comply from creation — the baseline does not grandfather future additions.

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

Files currently triggering the ≥3 rule:

| File | Inner Classes | Severity |
|------|---------------|----------|
| `order_detail_screen.dart` | 18 | High |
| `stock_reconciliation_screen.dart` | 8 | High |
| `order_edit_screen.dart` | 6 | High |
| `order_list_screen.dart` | 5 | High |
| `settings_screen.dart` | 5 | High |
| `dashboard_screen.dart` | 6 | Medium |
| `checklist_history_screen.dart` | 5 | Medium |
| `category_management_screen.dart` | 5 | Medium |
| `checklist_screen.dart` | 4 | Medium |
| `catalog_browse_screen.dart` | 3 | High |
| `catalog_photo_viewer.dart` | 3 | Medium |
| `knowledge_photo_gallery.dart` | 3 | Medium |

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

---

## §5 Label Organization

### Domain Split

The monolithic `lib/shared/widgets/vietnamese_labels.dart` (790 lines, 511 entries, 30+ domain sections) must be split into domain files under `lib/shared/labels/`.

| File | Sections Migrated | Example Labels |
|------|-------------------|----------------|
| `lib/shared/labels/shared.dart` | Navigation, common actions, error messages, generic UI | `appName`, `cancel`, `save`, `delete`, `confirm` |
| `lib/shared/labels/orders.dart` | Order statuses, actions, form fields, detail, photos, cake queue, cake detail | `statusNew`, `createOrder`, `orderDetail`, `payment` |
| `lib/shared/labels/products.dart` | Product categories, form, catalog gallery, product code, display flags | `productCategories`, `addProduct`, `catalogGallery` |
| `lib/shared/labels/events.dart` | Event types, tags, form, history filters | `eventTypes`, `eventTags`, `eventForm` |
| `lib/shared/labels/checklist.dart` | Checklist templates, entries, print dialog | `checklistTemplate`, `checklistEntry` |

### Migration Rule

- New labels go in the appropriate domain file — never add to the `VN` class.
- When a consumer imports a label, import only the domain file(s) it needs — not a barrel file.
- Shared/common labels that span multiple domains go in `shared.dart`.
- If a label's domain is unclear, default to the feature that most frequently consumes it.

### Import Pattern

```dart
// Before (monolithic)
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
// Usage: VN.createOrder

// After (domain-split)
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
// Usage: OrdersLabels.createOrder, SharedLabels.cancel
```

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

### Rules to Enable

These rules are documented for Phase 2. Phase 3 will apply them to `analysis_options.yaml` with `// ignore_for_file:` suppression for pre-existing violations.

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

### Application Strategy (Phase 3)

1. Enable all 12 rules in `analysis_options.yaml`.
2. Run `dart analyze` to catalog violations.
3. For pre-existing violations (not related to current in-progress work), add `// ignore_for_file:` at the top of each violating file.
4. New code must comply with all enabled rules — no new `// ignore:` comments for new code.
5. Verify: `dart analyze` returns zero errors.

---

## §8 Date/Time Formatting

### Shared Utility Requirement

All DateTime display in screen widgets MUST use the shared utility functions from `lib/shared/utils/date_formatting.dart`. Direct use of `DateFormat.format()`, `DateFormat` constructors, or manual `padLeft` for date/time strings is prohibited in screen and widget code.

### Available Functions

| Function | Purpose | Example Output |
|----------|---------|---------------|
| `formatDisplay(dynamic value, String timezone)` | Full datetime for display (VN timezone) | `28/06/2026 14:30` |
| `formatDisplayDate(dynamic value, String timezone)` | Date only | `28/06/2026` |
| `formatDisplayTime(dynamic value, String timezone)` | Time only | `14:30` |
| `formatDisplayShort(dynamic value, String timezone)` | Short datetime | `28/06 14:30` |
| `parseApiDateTime(String? value, String timezone)` | Parse API string to DateTime in target timezone | `DateTime` object |

### Correct Usage

```dart
import 'package:bakery_app/shared/utils/date_formatting.dart';

// In screen widget
Text(formatDisplay(order.createdAt, timezone));
Text(formatDisplayDate(order.dueDate, timezone));
Text(formatDisplayTime(event.startTime, timezone));
```

### Anti-patterns

```dart
// ❌ PROHIBITED — direct DateFormat usage
import 'package:intl/intl.dart';
DateFormat('dd/MM/yyyy HH:mm').format(date);
DateFormat('yyyy-MM-dd').parse(str);

// ❌ PROHIBITED — manual padLeft for DateTime formatting
'${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'

// ❌ PROHIBITED — DateFormat with explicit format strings in widgets
final formatter = DateFormat('dd/MM/yyyy');
Text(formatter.format(order.createdAt));
```

### Exception

Services, providers, and data-layer code that parse API responses or serialize data before sending to the server may use `DateFormat` for the `yyyy-MM-dd HH:mm:ss` API format if the shared utility does not cover the exact serialization need. Screen widgets must never use `DateFormat` directly.

---

## Version Reference

- Flutter SDK: 3.44.0 (run all Flutter/Dart commands via `nix develop .#flutter`)
- Dart SDK: 3.12.0 (from the same pinned Flutter toolchain)
- Do not edit `flake.nix` or repo Flutter pin values directly to change Flutter/Dart versions; file a ticket for requirements or builder review first.
- Riverpod: ^3.1.0 (as of `pubspec.yaml`)
- flutter_lints: ^5.0.0 (via `analysis_options.yaml` include)
- Review cadence: Annual or on major Flutter/Riverpod SDK version bump
