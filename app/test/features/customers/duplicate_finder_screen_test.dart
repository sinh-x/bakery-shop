import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/duplicate_finder_screen.dart';
import 'package:bakery_app/features/customers/widgets/duplicate_batch_merge_dialog.dart';
import 'package:bakery_app/features/customers/widgets/duplicate_merge_dialog.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDuplicateService extends CustomerService {
  _FakeDuplicateService({
    this.groups = const [],
    this.mergeThrows = false,
    this.batchMergeThrows = false,
  }) : super(Dio());

  List<DuplicateGroup> groups;
  int mergeCallCount = 0;
  int? lastTargetId;
  int? lastSourceId;
  bool mergeThrows;
  int batchMergeCallCount = 0;
  int? lastBatchTargetId;
  List<int>? lastBatchSourceIds;
  bool batchMergeThrows;

  @override
  Future<DuplicateGroupsResult> listDuplicates() async {
    return DuplicateGroupsResult(groups: List.of(groups));
  }

  @override
  Future<MergeResult> mergeCustomers({
    required int targetId,
    required int sourceId,
  }) async {
    mergeCallCount += 1;
    lastTargetId = targetId;
    lastSourceId = sourceId;
    if (mergeThrows) throw Exception('boom');
    // Simulate the backend removing the merged group.
    groups = groups
        .where((g) => g.customers.every((c) => c.id != sourceId))
        .where((g) => g.customers.length >= 2)
        .toList();
    return MergeResult(
      ok: true,
      targetId: targetId,
      sourceId: sourceId,
      customer: Customer(id: targetId, name: 'kept', phone: '09'),
      movedOrders: 2,
      addedPhones: 1,
      recomputedYears: const [2025, 2026],
    );
  }

  @override
  Future<BatchMergeResult> batchMergeCustomers({
    required int targetId,
    required List<int> sourceCustomerIds,
  }) async {
    batchMergeCallCount += 1;
    lastBatchTargetId = targetId;
    lastBatchSourceIds = List<int>.of(sourceCustomerIds);
    if (batchMergeThrows) throw Exception('boom');
    // Simulate the backend removing all sources from groups.
    final removed = sourceCustomerIds.toSet();
    groups = groups
        .map((g) => DuplicateGroup(
              key: g.key,
              kind: g.kind,
              customers: g.customers
                  .where((c) => !removed.contains(c.id))
                  .toList(),
            ))
        .where((g) => g.customers.length >= 2)
        .toList();
    return BatchMergeResult(
      ok: true,
      targetId: targetId,
      sourceIds: sourceCustomerIds,
      customer: Customer(id: targetId, name: 'kept', phone: '09'),
      merged: const [],
      totalMovedOrders: 6,
      totalAddedPhones: 2,
      recomputedYears: const [2025, 2026],
    );
  }
}

DuplicateGroup _phoneGroup() => const DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
      ],
    );

DuplicateGroup _nameGroup() => const DuplicateGroup(
      key: 'nguyen van a',
      kind: 'name',
      customers: [
        DuplicateCustomerEntry(id: 3, name: 'Nguyễn Văn A', phone: '', orderCount: 0),
        DuplicateCustomerEntry(id: 4, name: 'Nguyễn Văn Á', phone: '091', orderCount: 1),
      ],
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  CustomerService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const DuplicateFinderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Finds only [Text] widgets (not [EditableText]) displaying [text].
/// Use in filter tests where the search query would also appear in the
/// search field's [EditableText], causing `find.text` to match twice.
Finder _findLabel(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.data == text);

/// Two-tap selection flow used by the merge tests: tap [keep] then [mergeFrom]
/// to set the keep/merge-from roles, then tap the merge button to open the
/// confirmation dialog. Mirrors the DG-252 review M3 selection model.
Future<void> _selectTwoAndTapMerge(
  WidgetTester tester, {
  required String keep,
  required String mergeFrom,
}) async {
  await tester.tap(find.text(keep));
  await tester.pumpAndSettle();
  await tester.tap(find.text(mergeFrom));
  await tester.pumpAndSettle();
  await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'renders empty state when no duplicates (FR7/AC4)',
      (tester) async {
    await _pumpScreen(tester, _FakeDuplicateService(groups: const []));
    expect(find.text(CustomersLabels.duplicateFinderTitle), findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsOneWidget);
  });

  testWidgets(
      'lists candidate groups with both records and their order counts (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    // Phone group kind label + key + both members + order counts.
    expect(find.text(CustomersLabels.duplicateFinderGroupPhoneLabel),
        findsOneWidget);
    expect(find.text('0901234567'), findsWidgets);
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('Sinh A'), findsOneWidget);
    expect(find.textContaining('5 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);
    expect(find.textContaining('2 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);
    // Name group.
    expect(find.text(CustomersLabels.duplicateFinderGroupNameLabel),
        findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Nguyễn Văn Á'), findsOneWidget);
    // No merge button is shown until the admin selects two members per group
    // (DG-252 review M3 — two-tap selection model).
    expect(find.text(CustomersLabels.duplicateFinderMergeButton), findsNothing);
    // Each group shows the two-tap selection hint instead.
    expect(
      find.text(CustomersLabels.duplicateFinderPickTwoHint(2, 0)),
      findsNWidgets(2),
    );
  });

  testWidgets(
      'selecting two members in a group reveals the merge button (DG-252 review M3)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_phoneGroup()]);
    await _pumpScreen(tester, service);

    // Initially no merge button — only the hint.
    expect(find.text(CustomersLabels.duplicateFinderMergeButton), findsNothing);

    // Tap first member → keep role label appears.
    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeIntoLabel),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderPickTwoHint(2, 1)),
        findsOneWidget);

    // Tap second member → merge-from role label + merge button appears.
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeFromLabel),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);
  });

  testWidgets(
      'groups of three members have a merge path via two-tap selection (DG-252 review M3)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '0901234567', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(groups: [triple]);
    await _pumpScreen(tester, service);

    // No merge button initially; the hint adapts to the 3-member count.
    expect(find.text(CustomersLabels.duplicateFinderMergeButton), findsNothing);
    expect(find.text(CustomersLabels.duplicateFinderPickTwoHint(3, 0)),
        findsOneWidget);

    // Select two of the three members to enable merging.
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);

    // Confirm the merge: keep=Sinh B (id 3, first tap), mergeFrom=Sinh A (id 2).
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.mergeCallCount, 1);
    expect(service.lastTargetId, 3);
    expect(service.lastSourceId, 2);
  });

  testWidgets(
      'tapping merge opens confirmation dialog showing both records order counts (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_phoneGroup()]);
    await _pumpScreen(tester, service);

    await _selectTwoAndTapMerge(tester, keep: 'Sinh', mergeFrom: 'Sinh A');

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(CustomersLabels.duplicateFinderMergeDialogTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(CustomersLabels.duplicateFinderMergeDialogBody),
      ),
      findsOneWidget,
    );
    // Dialog shows keep/merge-from labels and both order counts.
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(CustomersLabels.duplicateFinderMergeIntoLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(CustomersLabels.duplicateFinderMergeFromLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
            '5 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
            '2 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
      ),
      findsOneWidget,
    );
    // Confirm + cancel actions present.
    expect(find.text(CustomersLabels.duplicateFinderMergeConfirm),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeCancel),
        findsOneWidget);
  });

  testWidgets(
      'confirming merge calls service with keep=first/mergeFrom=last and refreshes (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_phoneGroup()]);
    await _pumpScreen(tester, service);

    await _selectTwoAndTapMerge(tester, keep: 'Sinh', mergeFrom: 'Sinh A');
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.mergeCallCount, 1);
    expect(service.lastTargetId, 1);
    expect(service.lastSourceId, 2);
    // The merged group disappeared after refresh.
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeSuccess),
        findsOneWidget);
  });

  testWidgets(
      'cancelling the merge dialog does not call merge (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_phoneGroup()]);
    await _pumpScreen(tester, service);

    await _selectTwoAndTapMerge(tester, keep: 'Sinh', mergeFrom: 'Sinh A');
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeCancel));
    await tester.pumpAndSettle();

    expect(service.mergeCallCount, 0);
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsNothing);
  });

  testWidgets(
      'merge failure shows failure snackbar and does not crash (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup()],
      mergeThrows: true,
    );
    await _pumpScreen(tester, service);

    await _selectTwoAndTapMerge(tester, keep: 'Sinh', mergeFrom: 'Sinh A');
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.mergeCallCount, 1);
    expect(find.text(CustomersLabels.duplicateFinderMergeFailed),
        findsOneWidget);
    // Group remains after failure (refresh still runs).
    expect(find.text('Sinh'), findsOneWidget);
  });

  testWidgets(
      'refresh button re-fetches groups (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(groups: const []);
    await _pumpScreen(tester, service);
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsOneWidget);

    service.groups = [_phoneGroup()];
    await tester.tap(find.byTooltip(CustomersLabels.duplicateFinderRefresh));
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
  });

  testWidgets('DuplicateMergeDialog renders both records with order counts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: ctx,
                    builder: (_) => const DuplicateMergeDialog(
                      keep: DuplicateCustomerEntry(
                          id: 1, name: 'Sinh', phone: '090', orderCount: 7),
                      mergeFrom: DuplicateCustomerEntry(
                          id: 2, name: 'An', phone: '091', orderCount: 3),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateFinderMergeDialogTitle),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeIntoLabel),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeFromLabel),
        findsOneWidget);
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
    expect(find.textContaining('7 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);
    expect(find.textContaining('3 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);
  });

  testWidgets(
      'DuplicateMergeDialog swap affordance inverts keep/merge-from direction (DG-252 review M3)',
      (tester) async {
    MergeChoice? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<MergeChoice>(
                      context: ctx,
                      builder: (_) => const DuplicateMergeDialog(
                        keep: DuplicateCustomerEntry(
                            id: 1, name: 'Sinh', phone: '090', orderCount: 7),
                        mergeFrom: DuplicateCustomerEntry(
                            id: 2, name: 'An', phone: '091', orderCount: 3),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Initial direction: keep=Sinh (id 1), mergeFrom=An (id 2).
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);

    // Tap the swap affordance.
    await tester.tap(find.byTooltip(CustomersLabels.duplicateFinderSwapDirection));
    await tester.pumpAndSettle();

    // Confirm and capture the returned choice.
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeConfirm));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.keep.id, 2, reason: 'swap inverts keep → mergeFrom');
    expect(result!.mergeFrom.id, 1, reason: 'swap inverts mergeFrom → keep');
  });

  testWidgets(
      'confirming merge after swap applies the swapped direction to the service (DG-252 review M3)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_phoneGroup()]);
    await _pumpScreen(tester, service);

    await _selectTwoAndTapMerge(tester, keep: 'Sinh', mergeFrom: 'Sinh A');
    await tester.tap(find.byTooltip(CustomersLabels.duplicateFinderSwapDirection));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.mergeCallCount, 1);
    expect(service.lastTargetId, 2,
        reason: 'after swap the original mergeFrom (id 2) becomes the keep target');
    expect(service.lastSourceId, 1,
        reason: 'after swap the original keep (id 1) becomes the merge source');
  });

  // ---------------------------------------------------------------------------
  // DG-369 Phase 3 — batch merge (3+ members) FR5/FR6/AC3/AC4/AC6
  // ---------------------------------------------------------------------------

  testWidgets(
      'selecting 3+ members in a group reveals the merge button with primary + sources labelled (FR5/AC3)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '0901234567', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(groups: [triple]);
    await _pumpScreen(tester, service);

    // Tap three members: first = primary, next two = sources.
    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeIntoLabel),
        findsOneWidget);
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();

    // 3 selected → merge button appears; two 'Gộp vào' source labels.
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeIntoLabel),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeFromLabel),
        findsNWidgets(2));
  });

  testWidgets(
      'tapping a selected member deselects it (FR5)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '0901234567', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(groups: [triple]);
    await _pumpScreen(tester, service);

    // Select three.
    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);

    // Deselect one source — merge button still present (2 selected).
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeFromLabel),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);

    // Deselect the other source — only primary remains; no merge button.
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsNothing);
  });

  testWidgets(
      '3+ member selection opens batch confirmation dialog listing primary + all sources with names, phones, order counts (FR6/AC4)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '090', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(groups: [triple]);
    await _pumpScreen(tester, service);

    // Select three: Sinh=primary, Sinh A + Sinh B=sources.
    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    // Batch dialog title + body.
    expect(
      find.descendant(
        of: dialog,
        matching:
            find.text(CustomersLabels.duplicateFinderBatchMergeDialogTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching:
            find.text(CustomersLabels.duplicateFinderBatchMergeDialogBody),
      ),
      findsOneWidget,
    );
    // Primary label + primary name + order count.
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(CustomersLabels.duplicateFinderBatchMergePrimaryLabel),
      ),
      findsOneWidget,
    );
    expect(find.descendant(of: dialog, matching: find.text('Sinh')),
        findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
            '5 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
      ),
      findsOneWidget,
    );
    // Sources section label + two source labels with names + order counts.
    expect(
      find.descendant(
        of: dialog,
        matching:
            find.text(CustomersLabels.duplicateFinderBatchMergeSourcesLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(CustomersLabels.duplicateFinderMergeFromLabel),
      ),
      findsNWidgets(2),
    );
    expect(find.descendant(of: dialog, matching: find.text('Sinh A')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Sinh B')),
        findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
            '2 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.textContaining(
            '1 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
      ),
      findsOneWidget,
    );
    // Confirm + cancel actions present.
    expect(find.text(CustomersLabels.duplicateFinderBatchMergeConfirm),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderBatchMergeCancel),
        findsOneWidget);
  });

  testWidgets(
      'confirming batch merge calls batchMergeCustomers with primary + source ids and refreshes (FR5/AC6)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '0901234567', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(groups: [triple]);
    await _pumpScreen(tester, service);

    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
    await tester.tap(
        find.text(CustomersLabels.duplicateFinderBatchMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.batchMergeCallCount, 1);
    expect(service.lastBatchTargetId, 1);
    expect(service.lastBatchSourceIds, [2, 3]);
    // After batch merge the group shrinks below 2 → empty state.
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderBatchMergeSuccess),
        findsOneWidget);
  });

  testWidgets(
      'cancelling the batch merge dialog does not call batchMerge (FR6/AC4)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '0901234567', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(groups: [triple]);
    await _pumpScreen(tester, service);

    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
    await tester.tap(
        find.text(CustomersLabels.duplicateFinderBatchMergeCancel));
    await tester.pumpAndSettle();

    expect(service.batchMergeCallCount, 0);
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsNothing);
  });

  testWidgets(
      'batch merge failure shows failure snackbar and does not crash (FR5/AC6)',
      (tester) async {
    const triple = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(id: 2, name: 'Sinh A', phone: '0901234567', orderCount: 2),
        DuplicateCustomerEntry(id: 3, name: 'Sinh B', phone: '0901234567', orderCount: 1),
      ],
    );
    final service = _FakeDuplicateService(
      groups: [triple],
      batchMergeThrows: true,
    );
    await _pumpScreen(tester, service);

    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
    await tester.tap(
        find.text(CustomersLabels.duplicateFinderBatchMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.batchMergeCallCount, 1);
    expect(find.text(CustomersLabels.duplicateFinderBatchMergeFailed),
        findsOneWidget);
    // Group remains after failure (refresh still runs).
    expect(find.text('Sinh'), findsOneWidget);
  });

  testWidgets('DuplicateBatchMergeDialog renders primary + all sources',
      (tester) async {
    BatchMergeChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<BatchMergeChoice>(
                    context: ctx,
                    builder: (_) => const DuplicateBatchMergeDialog(
                      primary: DuplicateCustomerEntry(
                          id: 1, name: 'Sinh', phone: '090', orderCount: 7),
                      sources: [
                        DuplicateCustomerEntry(
                            id: 2, name: 'An', phone: '091', orderCount: 3),
                        DuplicateCustomerEntry(
                            id: 3, name: 'Bình', phone: '092', orderCount: 1),
                      ],
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateFinderBatchMergeDialogTitle),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderBatchMergePrimaryLabel),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderBatchMergeSourcesLabel),
        findsOneWidget);
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
    expect(find.text('Bình'), findsOneWidget);
    expect(find.textContaining('7 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);
    expect(find.textContaining('3 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);
    expect(find.textContaining('1 ${CustomersLabels.duplicateFinderOrderCountSuffix}'),
        findsOneWidget);

    // Confirm returns primary + sources.
    await tester.tap(
        find.text(CustomersLabels.duplicateFinderBatchMergeConfirm));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.primary.id, 1);
    expect(result!.sources.map((s) => s.id).toList(), [2, 3]);
  });

  testWidgets('DuplicateBatchMergeDialog cancel returns null', (tester) async {
    BatchMergeChoice? result = (
      primary: const DuplicateCustomerEntry(
          id: 1, name: 'x', phone: '', orderCount: 0),
      sources: const <DuplicateCustomerEntry>[],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showDialog<BatchMergeChoice>(
                    context: ctx,
                    builder: (_) => const DuplicateBatchMergeDialog(
                      primary: DuplicateCustomerEntry(
                          id: 1, name: 'Sinh', phone: '090', orderCount: 7),
                      sources: [
                        DuplicateCustomerEntry(
                            id: 2, name: 'An', phone: '091', orderCount: 3),
                      ],
                    ),
                  );
                  result = r;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.text(CustomersLabels.duplicateFinderBatchMergeCancel));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  // ---------------------------------------------------------------------------
  // DG-372 Phase 4.3 — duplicate finder filter tests
  // (FR1–FR6/AC1–AC6/NFR2)
  // ---------------------------------------------------------------------------

  testWidgets(
      'search field renders at the top with a search icon and hint text (FR1/AC1/NFR2)',
      (tester) async {
    await _pumpScreen(tester, _FakeDuplicateService(groups: [_phoneGroup()]));

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);
    expect(find.descendant(of: searchField, matching: find.byIcon(Icons.search)),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderSearchHint),
        findsOneWidget);
    // AppBar title is still present above the search field.
    expect(find.text(CustomersLabels.duplicateFinderTitle), findsOneWidget);
    // No clear button is shown when the search field is empty.
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets(
      'typing a name filters groups client-side; non-matching groups are hidden (FR2/AC2)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    // Both groups visible initially.
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);

    // Type a query matching only the phone group members.
    await tester.enterText(find.byType(TextField), 'Sinh');
    await tester.pumpAndSettle();

    // Phone group still visible; name group hidden. Use `_findLabel` so the
    // search field's [EditableText] (which also contains "Sinh") is excluded.
    expect(_findLabel('Sinh'), findsOneWidget);
    expect(find.text('Sinh A'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);
    expect(find.text('Nguyễn Văn Á'), findsNothing);
  });

  testWidgets(
      'filter matches by phone as well as name (FR3/AC2)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    await tester.enterText(find.byType(TextField), '091');
    await tester.pumpAndSettle();

    // Only the name group has a member with phone '091'.
    expect(find.text('Nguyễn Văn Á'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Sinh'), findsNothing);
  });

  testWidgets(
      'filter matching is diacritic-insensitive on names (FR3/AC2)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_nameGroup()]);
    await _pumpScreen(tester, service);

    // Query without diacritics matches accented names.
    await tester.enterText(find.byType(TextField), 'nguyen');
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Nguyễn Văn Á'), findsOneWidget);

    // Clear and query with diacritics still matches.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nguyễn');
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Nguyễn Văn Á'), findsOneWidget);
  });

  testWidgets(
      'a partial match shows the entire group including non-matching members (FR4/AC2)',
      (tester) async {
    // Group where only one member's name matches the query.
    const group = DuplicateGroup(
      key: '0901234567',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(
            id: 1, name: 'Sinh', phone: '0901234567', orderCount: 5),
        DuplicateCustomerEntry(
            id: 2, name: 'An', phone: '0901234567', orderCount: 2),
      ],
    );
    final service = _FakeDuplicateService(groups: [group]);
    await _pumpScreen(tester, service);

    await tester.enterText(find.byType(TextField), 'Sinh');
    await tester.pumpAndSettle();

    // Both members of the matching group are shown, not just the match.
    // Use `_findLabel` because the query "Sinh" also appears in the search
    // field's [EditableText].
    expect(_findLabel('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
  });

  testWidgets(
      'clear button (X icon) resets the filter and shows all groups again (FR5/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    // Apply a filter that hides the name group.
    await tester.enterText(find.byType(TextField), 'Sinh');
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsNothing);
    // Clear button is now visible because the field is non-empty.
    expect(find.byIcon(Icons.clear), findsOneWidget);

    // Tap the clear button.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    // All groups are shown again.
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    // Clear button is hidden again once the field is empty.
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets(
      'clearing the text (empty query) also restores all groups (FR5/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    await tester.enterText(find.byType(TextField), 'Sinh');
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsNothing);

    // Clear the text by entering an empty string.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
  });

  testWidgets(
      'no-results message is shown when the filter matches no groups, distinct from the empty state (FR6/AC3)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateFinderSearchNoResults),
        findsOneWidget);
    // The "no duplicates exist" empty state must NOT be shown here.
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsNothing);
    // No group member text is shown.
    expect(find.text('Sinh'), findsNothing);
    expect(find.text('Nguyễn Văn A'), findsNothing);
  });

  testWidgets(
      'empty-groups state (no duplicates at all) does not show the no-results message (FR6)',
      (tester) async {
    await _pumpScreen(tester, _FakeDuplicateService(groups: const []));
    expect(find.text(CustomersLabels.duplicateFinderEmpty), findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderSearchNoResults),
        findsNothing);
  });

  testWidgets(
      'clearing the filter preserves selection state for a still-present group (FR7/AC5)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    // Select two members in the phone group (index 0).
    await tester.tap(find.text('Sinh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinh A'));
    await tester.pumpAndSettle();
    // Merge button visible → selection active.
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);

    // Apply a filter that still matches the phone group (index 0 unchanged).
    await tester.enterText(find.byType(TextField), 'Sinh');
    await tester.pumpAndSettle();
    // Selection persists: merge button still visible for the matching group.
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);

    // Clear the filter; the phone group remains at index 0, so its tile
    // state (selection) is preserved.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text(CustomersLabels.duplicateFinderMergeButton),
        findsOneWidget);
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('Sinh A'), findsOneWidget);
  });

  testWidgets(
      'merge flow works identically with a filter active (FR7/AC6)',
      (tester) async {
    final service = _FakeDuplicateService(
      groups: [_phoneGroup(), _nameGroup()],
    );
    await _pumpScreen(tester, service);

    // Activate a filter matching the phone group.
    await tester.enterText(find.byType(TextField), '0901234567');
    await tester.pumpAndSettle();
    // Only the phone group is visible.
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsNothing);

    // Select two members and merge.
    await _selectTwoAndTapMerge(tester, keep: 'Sinh', mergeFrom: 'Sinh A');
    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeConfirm));
    await tester.pumpAndSettle();

    expect(service.mergeCallCount, 1);
    expect(service.lastTargetId, 1);
    expect(service.lastSourceId, 2);
    // The phone group is gone after merge. The filter ('0901234567') is still
    // active, so the "no results" message shows (not the empty-groups state).
    expect(find.text(CustomersLabels.duplicateFinderSearchNoResults),
        findsOneWidget);
    expect(find.text(CustomersLabels.duplicateFinderMergeSuccess),
        findsOneWidget);
  });

  testWidgets(
      'filter handles many groups without perceptible lag (NFR1 — smoke test)',
      (tester) async {
    // Build 50 groups and filter to a single matching one.
    final groups = List<DuplicateGroup>.generate(50, (i) => DuplicateGroup(
      key: 'phone-$i',
      kind: 'phone',
      customers: [
        DuplicateCustomerEntry(
            id: i * 2, name: 'User $i', phone: '0$i', orderCount: 0),
        DuplicateCustomerEntry(
            id: i * 2 + 1, name: 'User ${i}b', phone: '0$i', orderCount: 0),
      ],
    ));
    final service = _FakeDuplicateService(groups: groups);
    await _pumpScreen(tester, service);

    // Filter to a single group by a unique name fragment.
    await tester.enterText(find.byType(TextField), 'User 42');
    await tester.pumpAndSettle();

    // Use `_findLabel` because the query also appears in the search field.
    expect(_findLabel('User 42'), findsOneWidget);
    expect(find.text('User 42b'), findsOneWidget);
    // The no-results path is NOT taken.
    expect(find.text(CustomersLabels.duplicateFinderSearchNoResults),
        findsNothing);
  });
}