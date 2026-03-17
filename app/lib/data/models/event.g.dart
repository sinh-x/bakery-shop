// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BakeryEvent _$BakeryEventFromJson(Map<String, dynamic> json) => _BakeryEvent(
  id: json['id'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  type: json['type'] as String? ?? 'note',
  summary: json['summary'] as String,
  loggedBy: json['loggedBy'] as String? ?? '',
);

Map<String, dynamic> _$BakeryEventToJson(_BakeryEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'timestamp': instance.timestamp.toIso8601String(),
      'type': instance.type,
      'summary': instance.summary,
      'loggedBy': instance.loggedBy,
    };
