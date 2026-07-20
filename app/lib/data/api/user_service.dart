import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class StaffBinding {
  final int? staffId;
  final String? staffName;

  StaffBinding({this.staffId, this.staffName});

  factory StaffBinding.fromJson(Map<String, dynamic> json) => StaffBinding(
        staffId: json['staff_id'] as int?,
        staffName: json['staff_name'] as String?,
      );
}

class UserService {
  final Dio _dio;

  UserService(this._dio);

  Future<StaffBinding> getStaffBinding() async {
    final response = await _dio.get('/api/users/me/staff-binding');
    return StaffBinding.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffBinding> updateStaffBinding(int? staffId) async {
    final response = await _dio.put(
      '/api/users/me/staff-binding',
      data: {'staff_id': staffId},
    );
    return StaffBinding.fromJson(response.data as Map<String, dynamic>);
  }
}

final userServiceProvider = Provider<UserService>((ref) {
  final dio = ref.watch(dioProvider);
  return UserService(dio);
});
