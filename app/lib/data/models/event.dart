import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';
part 'event.g.dart';

@freezed
sealed class BakeryEvent with _$BakeryEvent {
  const factory BakeryEvent({
    required int id,
    @JsonKey(fromJson: _timestampFromJson)
    required DateTime timestamp,
    @Default('note') String type,
    required String summary,
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'logged_by') @Default('') String loggedBy,
    @Default('app') String source,
    @Default(<String, dynamic>{}) Map<String, dynamic> data,
    @JsonKey(name: 'order_id') int? orderId,
  }) = _BakeryEvent;

  factory BakeryEvent.fromJson(Map<String, dynamic> json) =>
      _$BakeryEventFromJson(json);
}

DateTime _timestampFromJson(String value) {
  return DateTime.parse(_normalizeApiTimestamp(value));
}

String _normalizeApiTimestamp(String value) {
  final hasExplicitTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  if (!hasExplicitTimezone) {
    return '$value+07:00';
  }
  return value;
}
