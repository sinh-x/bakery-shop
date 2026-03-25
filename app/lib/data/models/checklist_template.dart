import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_template.freezed.dart';
part 'checklist_template.g.dart';

@freezed
sealed class ChecklistTemplate with _$ChecklistTemplate {
  const factory ChecklistTemplate({
    required int id,
    required String name,
    @Default('opening') String period,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @Default(true) bool active,
    @JsonKey(name: 'created_at') String? createdAt,
  }) = _ChecklistTemplate;

  factory ChecklistTemplate.fromJson(Map<String, dynamic> json) =>
      _$ChecklistTemplateFromJson(json);
}
