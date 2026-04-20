import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_tag.freezed.dart';
part 'catalog_tag.g.dart';

@freezed
sealed class CatalogTagDef with _$CatalogTagDef {
  const factory CatalogTagDef({
    required String category,
    required String key,
    required String label,
    int? color,
  }) = _CatalogTagDef;

  /// Parses 'category:key:label' format from config_value strings.
  factory CatalogTagDef.parse(String configValue) {
    final parts = configValue.split(':');
    if (parts.length < 3) {
      throw FormatException('Invalid catalog_tag config value: $configValue');
    }
    return CatalogTagDef(
      category: parts[0],
      key: parts[1],
      label: parts[2],
    );
  }

  factory CatalogTagDef.fromJson(Map<String, dynamic> json) =>
      _$CatalogTagDefFromJson(json);
}
