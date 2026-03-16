import 'package:freezed_annotation/freezed_annotation.dart';

part 'event.freezed.dart';
part 'event.g.dart';

@freezed
sealed class BakeryEvent with _$BakeryEvent {
  const factory BakeryEvent({
    required String id,
    required DateTime timestamp,
    @Default('note') String type,
    required String summary,
    @Default('') String loggedBy,
  }) = _BakeryEvent;

  factory BakeryEvent.fromJson(Map<String, dynamic> json) =>
      _$BakeryEventFromJson(json);
}
