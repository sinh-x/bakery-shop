import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_photo.freezed.dart';
part 'order_photo.g.dart';

@freezed
sealed class OrderPhoto with _$OrderPhoto {
  const factory OrderPhoto({
    required int id,
    @JsonKey(name: 'order_id') required int orderId,
    @JsonKey(name: 'photo_hash') required String photoHash,
    @Default('') String tags,
    @Default(0) int position,
    @JsonKey(name: 'created_at') String? createdAt,
  }) = _OrderPhoto;

  factory OrderPhoto.fromJson(Map<String, dynamic> json) =>
      _$OrderPhotoFromJson(json);
}
