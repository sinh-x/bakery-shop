import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';
part 'event.g.dart';

@freezed
sealed class BakeryEvent with _$BakeryEvent {
  const factory BakeryEvent({
    required int id,
    required DateTime timestamp,
    @Default('note') String type,
    required String summary,
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'logged_by') @Default('') String loggedBy,
    @Default('app') String source,
    @Default(<String, dynamic>{}) Map<String, dynamic> data,
  }) = _BakeryEvent;

  factory BakeryEvent.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);
    final rawTimestamp = normalized['timestamp'];
    if (rawTimestamp is String) {
      normalized['timestamp'] = _normalizeApiTimestamp(rawTimestamp);
    }
    return _$BakeryEventFromJson(normalized);
  }
}

String _normalizeApiTimestamp(String value) {
  final hasExplicitTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  if (!hasExplicitTimezone) {
    return '${value}Z';
  }
  return value;
}
