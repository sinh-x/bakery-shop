import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_browse_photo.freezed.dart';
part 'catalog_browse_photo.g.dart';

@freezed
sealed class CatalogBrowsePhoto with _$CatalogBrowsePhoto {
  const factory CatalogBrowsePhoto({
    required int id,
    @JsonKey(name: 'product_id') required int productId,
    @JsonKey(name: 'file_path') required String filePath,
    @Default('') String caption,
    @Default('') String tags,
    @Default(0) int position,
    @JsonKey(name: 'created_at') String? createdAt,
    @JsonKey(name: 'photo_hash') String? photoHash,
    @JsonKey(name: 'product_name') required String productName,
  }) = _CatalogBrowsePhoto;

  factory CatalogBrowsePhoto.fromJson(Map<String, dynamic> json) =>
      _$CatalogBrowsePhotoFromJson(json);
}
