import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class StaffMember {
  final int id;
  final String name;
  final String role;
  final bool active;

  StaffMember({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as int,
        name: json['name'] as String,
        role: json['role'] as String? ?? '',
        active: json['active'] == 1 || json['active'] == true,
      );
}

class StaffService {
  final Dio _dio;

  StaffService(this._dio);

  Future<List<StaffMember>> listStaff() async {
    final response = await _dio.get('/api/staff');
    final list = response.data as List;
    return list
        .map((json) => StaffMember.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final staffServiceProvider = Provider<StaffService>((ref) {
  final dio = ref.watch(dioProvider);
  return StaffService(dio);
});
