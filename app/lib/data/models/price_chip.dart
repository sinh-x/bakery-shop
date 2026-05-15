import 'package:freezed_annotation/freezed_annotation.dart';

part 'price_chip.freezed.dart';
part 'price_chip.g.dart';

@freezed
sealed class PriceChip with _$PriceChip {
  const factory PriceChip({
    required int id,
    required String label,
    required double price,
    @Default(0) int position,
    @JsonKey(name: 'stock_qty') int? stockQty,
  }) = _PriceChip;

  factory PriceChip.fromJson(Map<String, dynamic> json) => _$PriceChipFromJson(json);
}
