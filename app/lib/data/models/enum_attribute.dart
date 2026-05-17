import 'package:freezed_annotation/freezed_annotation.dart';

part 'enum_attribute.freezed.dart';
part 'enum_attribute.g.dart';

@freezed
sealed class EnumOption with _$EnumOption {
  const factory EnumOption({
    required int id,
    @JsonKey(name: 'value_vi') required String valueVi,
    @Default(0) @JsonKey(name: 'sort_order') int sortOrder,
    @Default(1) int active,
    @Default(false) @JsonKey(name: 'is_default') bool isDefault,
  }) = _EnumOption;

  factory EnumOption.fromJson(Map<String, dynamic> json) =>
      _$EnumOptionFromJson(json);
}

@freezed
sealed class EnumAttribute with _$EnumAttribute {
  const factory EnumAttribute({
    @JsonKey(name: 'attribute_type') required String attributeType,
    @JsonKey(name: 'label_vi') required String labelVi,
    @JsonKey(name: 'default_option_id') int? defaultOptionId,
    @Default([]) List<EnumOption> options,
  }) = _EnumAttribute;

  factory EnumAttribute.fromJson(Map<String, dynamic> json) =>
      _$EnumAttributeFromJson(json);
}
