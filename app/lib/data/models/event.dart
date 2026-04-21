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
    int? orderId,
  }) = _BakeryEvent;

  factory BakeryEvent.fromJson(Map<String, dynamic> json) =>
      _$BakeryEventFromJson(json);
}
