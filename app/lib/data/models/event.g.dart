// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BakeryEvent _$BakeryEventFromJson(Map<String, dynamic> json) => _BakeryEvent(
  id: (json['id'] as num).toInt(),
  timestamp: parseApiDateTimeRequired(json['timestamp'] as String),
  type: json['type'] as String? ?? 'note',
  summary: json['summary'] as String,
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  loggedBy: json['logged_by'] as String? ?? '',
  source: json['source'] as String? ?? 'app',
  data: json['data'] as Map<String, dynamic>? ?? const <String, dynamic>{},
  orderId: (json['order_id'] as num?)?.toInt(),
);

Map<String, dynamic> _$BakeryEventToJson(_BakeryEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'timestamp': _timestampToJson(instance.timestamp),
      'type': instance.type,
      'summary': instance.summary,
      'tags': instance.tags,
      'logged_by': instance.loggedBy,
      'source': instance.source,
      'data': instance.data,
      'order_id': instance.orderId,
    };
