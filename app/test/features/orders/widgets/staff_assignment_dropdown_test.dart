import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/features/orders/widgets/order_edit/staff_assignment_dropdown.dart';
import 'package:bakery_app/data/providers/staff_provider.dart';

class _FakeStaffListNotifier extends StaffListNotifier {
  final List<StaffMember> staff;
  _FakeStaffListNotifier(this.staff);

  @override
  Future<List<StaffMember>> build() async => staff;
}

Widget _buildApp(List<StaffMember> staff, {String? assignedStaffId}) {
  return ProviderScope(
    overrides: [
      staffListProvider.overrideWith(() => _FakeStaffListNotifier(staff)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: StaffAssignmentDropdown(
          assignedStaffId: assignedStaffId,
          onChanged: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  // DG-329 Phase 2 / FR3 / AC2: the assignment dropdown label for an inactive
  // (deactivated) staff member shows the real name with the "(đã ngưng)"
  // suffix; a missing (deleted) staff record shows only the "NV #<id>"
  // fallback — never the misleading "NV #<id> (đã ngưng)" combo.
  group('StaffAssignmentDropdown inactive/missing staff label (DG-329 P2)',
      () {
    testWidgets('active staff render their real name', (tester) async {
      final staff = <StaffMember>[
        StaffMember(id: 1, name: 'An', role: 'giao-hang', active: true),
        StaffMember(id: 2, name: 'Bình', role: 'giao-hang', active: true),
      ];
      await tester.pumpWidget(_buildApp(staff, assignedStaffId: '1'));
      await tester.pumpAndSettle();

      expect(find.text('An'), findsWidgets);
      expect(find.textContaining('đã ngưng'), findsNothing);
    });

    testWidgets('deactivated assigned staff show "Name (đã ngưng)"',
        (tester) async {
      final staff = <StaffMember>[
        StaffMember(id: 1, name: 'An', role: 'giao-hang', active: true),
        StaffMember(id: 2, name: 'Bình', role: 'giao-hang', active: false),
      ];
      await tester.pumpWidget(_buildApp(staff, assignedStaffId: '2'));
      await tester.pumpAndSettle();

      // The synthesized dropdown item shows the real name + "(đã ngưng)" as
      // the currently selected value.
      expect(find.text('Bình (đã ngưng)'), findsOneWidget);
    });

    testWidgets(
        'missing (deleted) assigned staff show "NV #<id>" without '
        '"(đã ngưng)"', (tester) async {
      final staff = <StaffMember>[
        StaffMember(id: 1, name: 'An', role: 'giao-hang', active: true),
      ];
      // Assigned to staff id 999 which does not exist in the list at all.
      await tester.pumpWidget(_buildApp(staff, assignedStaffId: '999'));
      await tester.pumpAndSettle();

      expect(find.text('NV #999'), findsOneWidget);
      // Crucially, NOT the misleading "NV #999 (đã ngưng)" combo.
      expect(find.text('NV #999 (đã ngưng)'), findsNothing);
    });
  });

  // deliveryStaffForAssignmentProvider filters to active staff only — verify
  // the dropdown's active list excludes inactive staff while the synthesized
  // item still renders for the currently-assigned inactive id.
  testWidgets(
      'dropdown list excludes inactive staff but synthesizes item for the '
      'assigned inactive id', (tester) async {
    final staff = <StaffMember>[
      StaffMember(id: 1, name: 'An', role: 'giao-hang', active: true),
      StaffMember(id: 2, name: 'Bình', role: 'giao-hang', active: false),
    ];
    await tester.pumpWidget(_buildApp(staff, assignedStaffId: '2'));
    await tester.pumpAndSettle();

    // Open the dropdown to inspect the items.
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();

    // "An" (active) appears as a selectable option.
    expect(find.text('An'), findsWidgets);
    // "Bình" (inactive) does NOT appear as a standalone option, only as the
    // synthesized "Bình (đã ngưng)" item.
    expect(find.text('Bình'), findsNothing);
  });
}