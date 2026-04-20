import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_photo.freezed.dart';
part 'catalog_photo.g.dart';

@freezed
sealed class CatalogPhoto with _$CatalogPhoto {
  const factory CatalogPhoto({
    required int id,
    @JsonKey(name: 'product_id') required int productId,
    @JsonKey(name: 'file_path') required String filePath,
    @Default('') String caption,
    @Default('') String tags,
    @Default(0) int position,
    @JsonKey(name: 'created_at') String? createdAt,
    @JsonKey(name: 'photo_hash') String? photoHash,
  }) = _CatalogPhoto;

  factory CatalogPhoto.fromJson(Map<String, dynamic> json) =>
      _$CatalogPhotoFromJson(json);
}
