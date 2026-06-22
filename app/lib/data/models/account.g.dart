// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Account _$AccountFromJson(Map<String, dynamic> json) => _Account(
  id: json['id'] as String,
  code: json['code'] as String,
  name: json['name'] as String,
  type: json['type'] as String,
  parentId: json['parentId'] as String?,
  isActive: json['isActive'] as bool? ?? true,
  createdAt: json['createdAt'] as String?,
  children:
      (json['children'] as List<dynamic>?)
          ?.map((e) => Account.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Account>[],
);

Map<String, dynamic> _$AccountToJson(_Account instance) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'name': instance.name,
  'type': instance.type,
  'parentId': instance.parentId,
  'isActive': instance.isActive,
  'createdAt': instance.createdAt,
  'children': instance.children,
};
