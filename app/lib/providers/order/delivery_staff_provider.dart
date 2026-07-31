import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/staff_service.dart';
import '../staff_provider.dart';

/// Active delivery-role staff (role "giao-hang") for populating assignment
/// dropdowns in the order edit and detail screens (DG-304 Phase 5 / FR8/FR9 /
/// AC6/FR10). Filters the cached [staffListProvider] client-side so no extra
/// API call is needed on each dropdown open (matches the established
/// `delivery_content.dart` staff-filter pattern — NFR1/NFR2). Deactivated
/// staff are excluded (FR10).
final deliveryStaffForAssignmentProvider =
    FutureProvider<List<StaffMember>>((ref) async {
  final all = await ref.watch(staffListProvider.future);
  return all.where((s) => s.role == 'giao-hang' && s.active).toList();
});