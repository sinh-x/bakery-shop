import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

@freezed
sealed class Product with _$Product {
  const factory Product({
    required int id,
    required String name,
    @Default('bread') String category,
    @Default(0) @JsonKey(name: 'base_price') double basePrice,
    @Default(0) double cost,
    @Default('') @JsonKey(name: 'recipe_notes') String recipeNotes,
    @Default(1) int active,
    @Default('') @JsonKey(name: 'photo_path') String photoPath,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);
}
