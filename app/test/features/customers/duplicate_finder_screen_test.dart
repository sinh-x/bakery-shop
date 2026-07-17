import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/duplicate_finder_screen.dart';
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
  }) : super(Dio());

  List<DuplicateGroup> groups;
  int mergeCallCount = 0;
  int? lastTargetId;
  int? lastSourceId;
  bool mergeThrows;

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
      recomputedYears: 1,
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
    // Two merge buttons (one per 2-member group).
    expect(find.text(CustomersLabels.duplicateFinderMergeButton), findsNWidgets(2));
  });

  testWidgets(
      'tapping merge opens confirmation dialog showing both records order counts (FR7/AC4)',
      (tester) async {
    final service = _FakeDuplicateService(groups: [_phoneGroup()]);
    await _pumpScreen(tester, service);

    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();

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

    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text(CustomersLabels.duplicateFinderMergeButton));
    await tester.pumpAndSettle();
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
      MaterialApp(
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
}