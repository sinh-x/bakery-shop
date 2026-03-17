import 'package:freezed_annotation/freezed_annotation.dart';

part 'packing_item.freezed.dart';
part 'packing_item.g.dart';

@freezed
sealed class PackingItem with _$PackingItem {
  const factory PackingItem({
    required String name,
    @Default(false) bool isChecked,
  }) = _PackingItem;

  factory PackingItem.fromJson(Map<String, dynamic> json) =>
      _$PackingItemFromJson(json);
}
