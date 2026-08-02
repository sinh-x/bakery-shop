import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/staff_service.dart';
import '../staff_provider.dart';

/// All active staff for populating assignment dropdowns in the order edit
/// and detail screens (DG-329 Phase 1 / FR1 / AC1). Filters the cached
/// [staffListProvider] client-side so no extra API call is needed on each
/// dropdown open (matches the established `delivery_content.dart`
/// staff-filter pattern — NFR1). Deactivated staff are excluded.
final deliveryStaffForAssignmentProvider =
    FutureProvider<List<StaffMember>>((ref) async {
  final all = await ref.watch(staffListProvider.future);
  return all.where((s) => s.active).toList();
});