import 'package:bakery_app/features/orders/widgets/date_filter_chips.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpChips(
    WidgetTester tester, {
    required DateFilterOption selected,
    required ValueChanged<DateFilterOption> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DateFilterChips(selected: selected, onChanged: onChanged),
        ),
      ),
    );
  }

  group('DateFilterChips — FR1 (four exclusive options)', () {
    testWidgets('renders exactly four FilterChips', (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      expect(find.byType(FilterChip), findsNWidgets(4));
    });

    testWidgets('renders chips in the fixed option order today/tomorrow/combined/all',
        (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      // Verify labels in expected order.
      final labels = chips
          .map((c) => (c.label as Text).data)
          .toList();
      expect(labels, [
        VN.filterToday,
        OrdersLabels.dateFilterTomorrow,
        OrdersLabels.dateFilterTodayTomorrow,
        VN.filterAll,
      ]);
    });
  });

  group('DateFilterChips — NF3 (VN labels centralized)', () {
    testWidgets('today chip shows VN.filterToday label', (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      expect(find.text(VN.filterToday), findsOneWidget);
    });

    testWidgets('tomorrow chip shows OrdersLabels.dateFilterTomorrow label',
        (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      expect(find.text(OrdersLabels.dateFilterTomorrow), findsOneWidget);
    });

    testWidgets('today+tomorrow chip shows OrdersLabels.dateFilterTodayTomorrow label',
        (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      expect(find.text(OrdersLabels.dateFilterTodayTomorrow), findsOneWidget);
    });

    testWidgets('all chip shows VN.filterAll label', (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      expect(find.text(VN.filterAll), findsOneWidget);
    });
  });

  group('DateFilterChips — selection state (FR1 exclusive)', () {
    testWidgets('only the selected option is marked selected', (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.today, onChanged: (_) {});
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      final labels = chips.map((c) => (c.label as Text).data).toList();
      final selectedIdx = labels.indexOf(VN.filterToday);
      for (var i = 0; i < chips.length; i++) {
        expect(chips[i].selected, i == selectedIdx,
            reason: 'chip $i (${labels[i]}) selected state wrong');
      }
    });

    testWidgets('switching selection marks only the new option selected',
        (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.tomorrow, onChanged: (_) {});
      var chips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      final labels = chips.map((c) => (c.label as Text).data).toList();
      expect(chips[labels.indexOf(OrdersLabels.dateFilterTomorrow)].selected, true);
      expect(chips[labels.indexOf(VN.filterToday)].selected, false);
    });

    testWidgets('all-selected state: only the all chip is selected',
        (tester) async {
      await pumpChips(tester,
          selected: DateFilterOption.all, onChanged: (_) {});
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      final labels = chips.map((c) => (c.label as Text).data).toList();
      final allIdx = labels.indexOf(VN.filterAll);
      for (var i = 0; i < chips.length; i++) {
        expect(chips[i].selected, i == allIdx);
      }
    });
  });

  group('DateFilterChips — onChanged callback (FR1)', () {
    testWidgets('tapping today chip fires onChanged with DateFilterOption.today',
        (tester) async {
      DateFilterOption? picked;
      await pumpChips(tester,
          selected: DateFilterOption.all,
          onChanged: (o) => picked = o);
      await tester.tap(find.text(VN.filterToday));
      await tester.pump();
      expect(picked, DateFilterOption.today);
    });

    testWidgets('tapping tomorrow chip fires onChanged with tomorrow',
        (tester) async {
      DateFilterOption? picked;
      await pumpChips(tester,
          selected: DateFilterOption.all,
          onChanged: (o) => picked = o);
      await tester.tap(find.text(OrdersLabels.dateFilterTomorrow));
      await tester.pump();
      expect(picked, DateFilterOption.tomorrow);
    });

    testWidgets('tapping today+tomorrow chip fires onChanged with todayTomorrow',
        (tester) async {
      DateFilterOption? picked;
      await pumpChips(tester,
          selected: DateFilterOption.all,
          onChanged: (o) => picked = o);
      await tester.tap(find.text(OrdersLabels.dateFilterTodayTomorrow));
      await tester.pump();
      expect(picked, DateFilterOption.todayTomorrow);
    });

    testWidgets('tapping all chip fires onChanged with all (clears filter)',
        (tester) async {
      DateFilterOption? picked;
      await pumpChips(tester,
          selected: DateFilterOption.today,
          onChanged: (o) => picked = o);
      await tester.tap(find.text(VN.filterAll));
      await tester.pump();
      expect(picked, DateFilterOption.all);
    });

    testWidgets('tapping the already-selected chip still fires onChanged',
        (tester) async {
      DateFilterOption? picked;
      await pumpChips(tester,
          selected: DateFilterOption.today,
          onChanged: (o) => picked = o);
      await tester.tap(find.text(VN.filterToday));
      await tester.pump();
      expect(picked, DateFilterOption.today);
    });
  });
}