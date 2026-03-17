// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'staff.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Staff _$StaffFromJson(Map<String, dynamic> json) => _Staff(
  id: json['id'] as String,
  name: json['name'] as String,
  role: json['role'] as String? ?? '',
  phone: json['phone'] as String? ?? '',
  active: json['active'] as bool? ?? true,
);

Map<String, dynamic> _$StaffToJson(_Staff instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'role': instance.role,
  'phone': instance.phone,
  'active': instance.active,
};
