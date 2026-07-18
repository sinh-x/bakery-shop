import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/user_service.dart';

class StaffBindingNotifier extends AsyncNotifier<StaffBinding> {
  @override
  Future<StaffBinding> build() async {
    final service = ref.read(userServiceProvider);
    return service.getStaffBinding();
  }

  Future<void> updateBinding(int? staffId) async {
    final service = ref.read(userServiceProvider);
    state = await AsyncValue.guard(() => service.updateStaffBinding(staffId));
  }
}

final staffBindingProvider =
    AsyncNotifierProvider<StaffBindingNotifier, StaffBinding>(
  StaffBindingNotifier.new,
);
