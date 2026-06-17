import 'package:freezed_annotation/freezed_annotation.dart';

part 'event_photo.freezed.dart';
part 'event_photo.g.dart';

@freezed
sealed class EventPhoto with _$EventPhoto {
  const factory EventPhoto({
    required int id,
    @JsonKey(name: 'event_id') required int eventId,
    @JsonKey(name: 'photo_id') required int photoId,
    @JsonKey(name: 'photo_hash') required String photoHash,
    @Default('') String tags,
    @Default(0) int position,
    @JsonKey(name: 'created_at') String? createdAt,
  }) = _EventPhoto;

  factory EventPhoto.fromJson(Map<String, dynamic> json) =>
      _$EventPhotoFromJson(json);
}
