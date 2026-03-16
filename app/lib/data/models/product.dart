import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

@freezed
sealed class Product with _$Product {
  const factory Product({
    required String id,
    required String name,
    @Default('cake') String category,
    @Default(0) double basePrice,
    @Default('') String unit,
    @Default(true) bool active,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);
}
