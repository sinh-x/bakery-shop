// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CustomerPhone _$CustomerPhoneFromJson(Map<String, dynamic> json) =>
    _CustomerPhone(
      phone: json['phone'] as String,
      isPrimary: json['isPrimary'] as bool? ?? false,
    );

Map<String, dynamic> _$CustomerPhoneToJson(_CustomerPhone instance) =>
    <String, dynamic>{'phone': instance.phone, 'isPrimary': instance.isPrimary};

_CustomerYearSummary _$CustomerYearSummaryFromJson(Map<String, dynamic> json) =>
    _CustomerYearSummary(
      year: (json['year'] as num).toInt(),
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      totalVolume: (json['totalVolume'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$CustomerYearSummaryToJson(
  _CustomerYearSummary instance,
) => <String, dynamic>{
  'year': instance.year,
  'orderCount': instance.orderCount,
  'totalVolume': instance.totalVolume,
};

_Customer _$CustomerFromJson(Map<String, dynamic> json) => _Customer(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  phone: json['phone'] as String? ?? '',
  phones:
      (json['phones'] as List<dynamic>?)
          ?.map((e) => CustomerPhone.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <CustomerPhone>[],
  createdAt: parseApiDateTime(json['createdAt'] as String?),
  updatedAt: parseApiDateTime(json['updatedAt'] as String?),
  yearSummary: json['yearSummary'] == null
      ? null
      : CustomerYearSummary.fromJson(
          json['yearSummary'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$CustomerToJson(_Customer instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'phone': instance.phone,
  'phones': instance.phones,
  'createdAt': timestampToJson(instance.createdAt),
  'updatedAt': timestampToJson(instance.updatedAt),
  'yearSummary': instance.yearSummary,
};
