import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/staff_service.dart';

class StaffListNotifier extends AsyncNotifier<List<StaffMember>> {
  @override
  Future<List<StaffMember>> build() async {
    final service = ref.read(staffServiceProvider);
    return service.listStaff();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final service = ref.read(staffServiceProvider);
      return service.listStaff();
    });
  }
}

final staffListProvider =
    AsyncNotifierProvider<StaffListNotifier, List<StaffMember>>(
  StaffListNotifier.new,
);
